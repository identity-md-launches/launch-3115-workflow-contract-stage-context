// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Squeeklings} from "../src/Squeeklings.sol";
import {SqueeklingsArt} from "../src/SqueeklingsArt.sol";
import {MockSqueekCore} from "./mocks/MockSqueekCore.sol";
import {Expedition, Loot, Slot, Rarity, Kind} from "../src/SqueekTypes.sol";

/// @notice Adversarial action sequences against the production contract, without storage overrides.
contract GameHandler is Test {
    Squeeklings public game;
    MockSqueekCore public currentCore;
    address public admin;
    address[3] public players;
    uint256[3] public returnsPerPet;
    uint256 public completed;
    uint256 public migrations;

    constructor(Squeeklings game_, MockSqueekCore core_, address admin_, address[3] memory players_) {
        game = game_;
        currentCore = core_;
        admin = admin_;
        players = players_;
    }

    function start(uint256 pick, uint8 route) external {
        uint256 id = pick % 3 + 1;
        if (game.expedition(id).away) return;
        vm.prank(game.ownerOf(id));
        game.embark(id, route % 3);
    }

    function finish(uint256 pick, uint16 workPattern) external {
        uint256 id = pick % 3 + 1;
        Expedition memory trip = game.expedition(id);
        if (!trip.away) return;
        uint32 oldPity = game.pet(id).pity;
        if (trip.epoch == game.coreEpoch()) {
            while (currentCore.settled() < trip.endRound) {
                uint64 r = currentCore.settled() + 1;
                uint64 work = r % 3 == 0 ? workPattern % 1001 : 0;
                currentCore.append(work, uint96(work) * 1e8, keccak256(abi.encode(r, workPattern)));
            }
            vm.warp(uint256(currentCore.genesis()) + uint256(currentCore.settled()) * currentCore.duration());
        }
        Loot memory result = game.returnHome(id);
        ++returnsPerPet[id - 1];
        ++completed;
        if (trip.epoch != game.coreEpoch()) {
            assertEq(result.itemId, 17);
            assertEq(result.pity, oldPity);
        } else if (result.rarity >= Rarity.Rare) {
            assertEq(result.pity, 0);
        } else {
            assertEq(result.pity, oldPity + 1);
        }
    }

    function move(uint256 pick, uint256 recipient) external {
        uint256 id = pick % 3 + 1;
        address from = game.ownerOf(id);
        address to = players[recipient % 3];
        bool away = game.expedition(id).away;
        vm.prank(from);
        (bool ok, bytes memory reason) =
            address(game).call(abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, id));
        if (away) {
            assertFalse(ok, "an away pet moved");
            assertEq(bytes4(reason), Squeeklings.PetAway.selector);
            assertEq(game.ownerOf(id), from);
        } else {
            assertTrue(ok);
            assertEq(game.ownerOf(id), to);
        }
    }

    function dress(uint256 pick, uint8 choice) external {
        uint256 id = pick % 3 + 1;
        uint8 item = choice % 17 + 1;
        address holder = game.ownerOf(id);
        if (game.itemBalanceOf(id, item) > 0) {
            vm.prank(holder);
            game.equip(id, item);
        } else {
            vm.prank(holder);
            game.unequip(id, choice % 4);
        }
    }

    function migrate(uint96 startingUnits) external {
        MockSqueekCore next = new MockSqueekCore(uint64(block.timestamp));
        // Leave room for subsequent settlements at uint96 bounds.
        next.setUnits(startingUnits / 2);
        uint256 oldAge = game.ageUnits();
        vm.prank(admin);
        game.setCore(address(next));
        assertEq(game.ageUnits(), oldAge);
        currentCore = next;
        ++migrations;
    }

    function tryDuplicateHatch(uint256 pick) external {
        address player = players[pick % 3];
        vm.prank(player);
        (bool ok, bytes memory reason) = address(game).call(abi.encodeCall(Squeeklings.hatch, ()));
        assertFalse(ok);
        assertEq(bytes4(reason), Squeeklings.AlreadyHatched.selector);
    }
}

contract StatefulTest is Test {
    Squeeklings internal game;
    GameHandler internal handler;
    address[3] internal players;

    function setUp() public {
        vm.warp(1_000_000);
        MockSqueekCore core = new MockSqueekCore(1_000_000);
        SqueeklingsArt art = new SqueeklingsArt();
        address admin = makeAddr("admin");
        game = new Squeeklings(address(core), address(art), admin);
        for (uint256 i; i < 3; ++i) {
            players[i] = makeAddr(string.concat("player", vm.toString(i)));
            vm.prank(players[i]);
            game.hatch();
        }
        handler = new GameHandler(game, core, admin, players);
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.start.selector;
        selectors[1] = handler.finish.selector;
        selectors[2] = handler.move.selector;
        selectors[3] = handler.dress.selector;
        selectors[4] = handler.migrate.selector;
        selectors[5] = handler.tryDuplicateHatch.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    function invariantExactlyOneInventoryItemPerCompletedTrip() public view {
        uint256 total;
        for (uint256 id = 1; id <= 3; ++id) {
            uint256[17] memory counts = game.inventory(id);
            uint256 count;
            for (uint256 i; i < 17; ++i) {
                count += counts[i];
            }
            assertEq(count, handler.returnsPerPet(id - 1));
            total += count;
        }
        assertEq(total, handler.completed());
    }

    function invariantEquippedItemsExistInTheirCorrectInventorySlots() public view {
        for (uint256 id = 1; id <= 3; ++id) {
            uint8[4] memory equipment = game.pet(id).equipped;
            for (uint8 slot; slot < 4; ++slot) {
                if (equipment[slot] == 0) continue;
                assertGt(game.itemBalanceOf(id, equipment[slot]), 0);
                (, Slot actualSlot,,) = game.itemInfo(equipment[slot]);
                assertEq(uint8(actualSlot), slot);
            }
        }
    }

    function invariantSupplyOwnershipEpochAndNoFunds() public view {
        assertEq(game.totalSupply(), 3);
        uint256 held;
        for (uint256 i; i < 3; ++i) {
            held += game.balanceOf(players[i]);
            assertTrue(game.hasHatched(players[i]));
        }
        assertEq(held, 3);
        assertEq(game.coreEpoch(), handler.migrations() + 1);
        assertEq(address(game).balance, 0);
    }
}
