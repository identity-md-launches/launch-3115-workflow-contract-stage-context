// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LootHarness} from "./mocks/Harnesses.sol";
import {SqueekLoot} from "../src/libraries/SqueekLoot.sol";
import {Loot, Kind, Rarity, Slot} from "../src/SqueekTypes.sol";

contract LootTest is Test {
    LootHarness internal lottery;

    function setUp() public {
        lottery = new LootHarness();
    }

    function testExactOddsForEveryTierDreamAndTrail() public view {
        for (uint8 route; route < 3; ++route) {
            uint96 blocks = route == 0 ? 39 : route == 1 ? 199 : 200;
            uint256[4] memory trail;
            uint256[4] memory dream;
            for (uint256 roll; roll < 100; ++roll) {
                Loot memory t = lottery.draw(bytes32(roll), route, 1, blocks, 499, 0);
                Loot memory d = lottery.draw(bytes32(roll), route, 0, 0, 0, 0);
                ++trail[uint8(t.rarity)];
                ++dream[uint8(d.rarity)];
                assertEq(uint256(t.kind), uint256(Kind.Trail));
                assertEq(uint256(d.kind), uint256(Kind.Dream));
            }
            assertEq(trail[0], route == 0 ? 100 : route == 1 ? 60 : 30);
            assertEq(trail[1], route == 0 ? 0 : route == 1 ? 40 : 45);
            assertEq(trail[2], route == 2 ? 25 : 0);
            assertEq(trail[3], 0);
            assertEq(dream[0], route == 0 ? 100 : route == 1 ? 60 : 20);
            assertEq(dream[1], trail[1]);
            assertEq(dream[2], trail[2]);
            assertEq(dream[3], route == 2 ? 10 : 0);
        }
    }

    function testLegendaryPrecedesPityAndFiveHundredIsInclusive() public view {
        Loot memory result = lottery.draw(bytes32(uint256(9)), 1, 500, 1, 500, 5);
        assertEq(uint256(result.rarity), uint256(Rarity.Legendary));
        assertEq(result.itemId, 8);
        assertEq(result.pity, 0);
        result = lottery.draw(bytes32(uint256(10)), 1, 500, 1, 500, 5);
        assertEq(uint256(result.rarity), uint256(Rarity.Rare));
        result = lottery.draw(bytes32(uint256(9)), 0, 499, 1, 499, 5);
        assertEq(uint256(result.rarity), uint256(Rarity.Common));
        assertEq(result.pity, 6);
        result = lottery.draw(bytes32(uint256(9)), 2, 0, 0, 0, 5);
        assertEq(result.itemId, 16);
    }

    function testBlockThresholdsAndExactRollBoundaries() public view {
        _rarity(59, 39, Rarity.Common);
        _rarity(99, 39, Rarity.Common);
        _rarity(59, 40, Rarity.Common);
        _rarity(60, 40, Rarity.Uncommon);
        _rarity(99, 199, Rarity.Uncommon);
        _rarity(29, 200, Rarity.Common);
        _rarity(30, 200, Rarity.Uncommon);
        _rarity(74, 200, Rarity.Uncommon);
        _rarity(75, 200, Rarity.Rare);
    }

    function _rarity(uint256 roll, uint96 blocks, Rarity expected) internal view {
        Loot memory result = lottery.draw(bytes32(roll), 0, 1, blocks, 1, 0);
        assertEq(uint256(result.rarity), uint256(expected));
    }

    function testFuzzPityAndTableMembership(
        bytes32 digest,
        uint8 routeRaw,
        uint32 pity,
        uint16 work,
        uint16 blocks,
        uint16 busiest
    ) public view {
        uint8 route = routeRaw % 3;
        Loot memory result = lottery.draw(digest, route, work, blocks, busiest, pity);
        (, Slot slot, Rarity rarity, Kind kind) = SqueekLoot.info(result.itemId);
        assertEq(uint256(rarity), uint256(result.rarity));
        assertEq(uint256(kind), uint256(result.kind));
        assertLe(uint256(slot), 3);
        if (result.rarity >= Rarity.Rare) assertEq(result.pity, 0);
        else assertEq(result.pity, pity == type(uint32).max ? pity : pity + 1);
        if (pity >= 5 && route != 0) assertGe(uint256(result.rarity), uint256(Rarity.Rare));
        if (result.rarity == Rarity.Legendary) {
            assertLt(uint256(digest) % 100, 10);
            assertTrue(work == 0 ? route == 2 : busiest >= 500);
        }
        if (work == 0) {
            assertGe(result.itemId, 9);
            assertLe(result.itemId, 16);
        } else {
            assertGe(result.itemId, 1);
            assertLe(result.itemId, 8);
        }
    }

    function testEveryItemIsReachableFromHashBytes() public view {
        bool[16] memory found;
        for (uint256 i; i < 1024; ++i) {
            Loot memory trail = lottery.draw(bytes32(i), 2, 500, 200, 500, 0);
            Loot memory dream = lottery.draw(bytes32(i), 2, 0, 0, 0, 0);
            found[trail.itemId - 1] = true;
            found[dream.itemId - 1] = true;
        }
        for (uint256 i; i < 16; ++i) {
            assertTrue(found[i]);
        }
        Loot memory fog = SqueekLoot.fog(23);
        assertEq(fog.itemId, 17);
        assertEq(fog.pity, 23);
        assertEq(uint256(fog.kind), uint256(Kind.Fog));
    }

    function testPitySaturatesInsteadOfBrickingThePet() public view {
        Loot memory result = lottery.draw(bytes32(uint256(99)), 0, 0, 0, 0, type(uint32).max);
        assertEq(result.pity, type(uint32).max);
        result = lottery.draw(bytes32(uint256(99)), 1, 0, 0, 0, type(uint32).max);
        assertEq(result.pity, 0);
        assertEq(uint256(result.rarity), uint256(Rarity.Rare));
    }
}
