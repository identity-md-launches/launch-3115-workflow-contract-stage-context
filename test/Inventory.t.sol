// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SqueekTestBase, Squeeklings, Expedition, Loot, Kind, Rarity, Slot} from "./TestBase.sol";
import {SqueekLoot} from "../src/libraries/SqueekLoot.sol";

contract InventoryTest is SqueekTestBase {
    function testExactItemCatalogueAndSlots() public view {
        string[17] memory names = [
            "Acorn",
            "Sunflower Seed",
            "Clover Sprig",
            "Leaf Scarf",
            "Copper Wheel",
            "Walnut Helmet",
            "Golden Wheel",
            "Zoomies Relic",
            "Moon Pebble",
            "Star Seed",
            "Nightcap",
            "Dream Scarf",
            "Cloud Bed",
            "Comet Crown",
            "Aurora Sky",
            "Wishing Star",
            "Compass"
        ];
        uint8[17] memory slots = [2, 2, 0, 1, 3, 0, 3, 1, 2, 2, 0, 1, 3, 0, 3, 1, 2];
        uint8[17] memory rarities = [0, 0, 0, 1, 1, 2, 2, 3, 0, 0, 0, 1, 1, 2, 2, 3, 1];
        for (uint8 i; i < 17; ++i) {
            (string memory name_, Slot slot, Rarity rarity, Kind kind) = game.itemInfo(i + 1);
            assertEq(name_, names[i]);
            assertEq(uint8(slot), slots[i]);
            assertEq(uint8(rarity), rarities[i]);
            assertEq(uint8(kind), i < 8 ? 0 : i < 16 ? 1 : 2);
        }
    }

    function testEquipUnequipAndInventoryStayWithTransferredPet() public {
        uint256 id = hatch(alice);
        for (uint8 item = 1; item <= 17; ++item) {
            game.giveItem(id, item);
        }
        vm.startPrank(alice);
        game.equip(id, 14);
        game.equip(id, 16);
        game.equip(id, 17);
        game.equip(id, 15);
        vm.stopPrank();
        assertEq(game.pet(id).equipped[0], 14);
        assertEq(game.pet(id).equipped[1], 16);
        assertEq(game.pet(id).equipped[2], 17);
        assertEq(game.pet(id).equipped[3], 15);
        vm.prank(alice);
        game.transferFrom(alice, bob, id);
        assertEq(inventoryTotal(id), 17);
        assertEq(game.pet(id).equipped[0], 14);
        vm.prank(alice);
        vm.expectRevert(Squeeklings.NotPetOwner.selector);
        game.unequip(id, 0);
        vm.startPrank(bob);
        game.unequip(id, 0);
        game.equip(id, 6);
        vm.stopPrank();
        assertEq(game.pet(id).equipped[0], 6);
        assertEq(game.itemBalanceOf(id, 14), 1);
        assertEq(game.itemBalanceOf(id, 6), 1);
        assertEq(inventoryTotal(id), 17);
    }

    function testAutoEquipDoesNotOverwriteExistingSlotOrConsumeItems() public {
        uint256 id = hatch(alice);
        for (uint8 item = 1; item <= 8; ++item) {
            game.giveItem(id, item);
        }
        vm.startPrank(alice);
        game.equip(id, 6);
        game.equip(id, 8);
        game.equip(id, 1);
        game.equip(id, 7);
        vm.stopPrank();
        Expedition memory trip = embark(id, 0);
        settleEmpty(trip.endRound);
        Loot memory result = game.returnHome(id);
        (, Slot slot,,) = game.itemInfo(result.itemId);
        assertEq(game.pet(id).equipped[uint8(slot)], slot == Slot.Head ? 6 : 1);
        assertEq(inventoryTotal(id), 9);
        assertEq(game.itemBalanceOf(id, result.itemId), 1);
    }

    function testAutoEquipEmptySlotAndOwnerCanManageWhileAway() public {
        uint256 id = hatch(alice);
        Expedition memory trip = embark(id, 0);
        settleEmpty(trip.endRound);
        Loot memory result = game.returnHome(id);
        (, Slot slot,,) = game.itemInfo(result.itemId);
        assertEq(game.pet(id).equipped[uint8(slot)], result.itemId);
        advance();
        embark(id, 0);
        vm.startPrank(alice);
        game.unequip(id, uint8(slot));
        assertEq(game.pet(id).equipped[uint8(slot)], 0);
        game.equip(id, result.itemId);
        vm.stopPrank();
        assertEq(game.pet(id).equipped[uint8(slot)], result.itemId);
        assertEq(inventoryTotal(id), 1);
    }

    function testInvalidItemsSlotsAndUnownedItemsAreRejected() public {
        uint256 id = hatch(alice);
        vm.startPrank(alice);
        vm.expectRevert(SqueekLoot.InvalidItem.selector);
        game.equip(id, 0);
        vm.expectRevert(SqueekLoot.InvalidItem.selector);
        game.equip(id, 18);
        vm.expectRevert(Squeeklings.ItemNotOwned.selector);
        game.equip(id, 8);
        vm.expectRevert(Squeeklings.InvalidSlot.selector);
        game.unequip(id, 4);
        vm.stopPrank();
        vm.expectRevert(SqueekLoot.InvalidItem.selector);
        game.itemBalanceOf(id, 18);
        assertEq(inventoryTotal(id), 0);
    }
}
