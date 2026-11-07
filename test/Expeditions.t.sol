// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SqueekTestBase, Squeeklings, Expedition, Loot, Kind, Rarity, Slot} from "./TestBase.sol";
import {ReaderHarness, LootHarness} from "./mocks/Harnesses.sol";
import {SqueekCoreReader as Reader} from "../src/libraries/SqueekCoreReader.sol";
import {Vm} from "forge-std/Vm.sol";

contract ExpeditionsTest is SqueekTestBase {
    function testRoutesStartNextRoundAndEndInclusively() public {
        uint256 id = hatch(alice);
        assertEq(game.currentRound(), 1);
        Expedition memory trip = embark(id, 0);
        assertEq(trip.startRound, 2);
        assertEq(trip.endRound, 7);
        assertEq(trip.epoch, 1);
        assertTrue(trip.away);
        assertEq(game.routeRounds(1), 18);
        assertEq(game.routeRounds(2), 36);
        vm.expectRevert(Squeeklings.InvalidRoute.selector);
        game.routeRounds(3);
        vm.prank(alice);
        vm.expectRevert(Squeeklings.PetAway.selector);
        game.embark(id, 1);
    }

    function testUnauthorizedAndInvalidEmbarkLeaveStateUntouched() public {
        uint256 id = hatch(alice);
        vm.prank(bob);
        vm.expectRevert(Squeeklings.NotPetOwner.selector);
        game.embark(id, 0);
        vm.prank(alice);
        vm.expectRevert(Squeeklings.InvalidRoute.selector);
        game.embark(id, 3);
        assertFalse(game.expedition(id).away);
    }

    function testAllTransferFormsBlockedUntilReturnEvenAfterSettlement() public {
        uint256 id = hatch(alice);
        vm.prank(alice);
        game.setApprovalForAll(bob, true);
        Expedition memory trip = embark(id, 0);
        vm.startPrank(bob);
        vm.expectRevert(Squeeklings.PetAway.selector);
        game.transferFrom(alice, bob, id);
        vm.expectRevert(Squeeklings.PetAway.selector);
        game.safeTransferFrom(alice, bob, id);
        vm.expectRevert(Squeeklings.PetAway.selector);
        game.safeTransferFrom(alice, bob, id, "");
        vm.stopPrank();
        settleEmpty(trip.endRound);
        vm.prank(alice);
        vm.expectRevert(Squeeklings.PetAway.selector);
        game.transferFrom(alice, bob, id);
        vm.prank(bob);
        game.returnHome(id);
        vm.prank(bob);
        game.transferFrom(alice, bob, id);
        assertEq(game.ownerOf(id), bob);
        assertEq(inventoryTotal(id), 1);
    }

    function testTimePassingDoesNotTurnUnknownWorkIntoDreamLoot() public {
        uint256 id = hatch(alice);
        Expedition memory trip = embark(id, 0);
        vm.warp(GENESIS + 1000 * ROUND_SECONDS);
        vm.expectRevert(abi.encodeWithSelector(Squeeklings.NotSettledYet.selector, trip.endRound, uint64(0)));
        game.returnHome(id);
        assertTrue(game.expedition(id).away);
        assertEq(inventoryTotal(id), 0);
        settleEmpty(trip.endRound - 1);
        vm.expectRevert(
            abi.encodeWithSelector(Squeeklings.NotSettledYet.selector, trip.endRound, trip.endRound - 1)
        );
        game.returnHome(id);
        settleEmpty(trip.endRound);
        Loot memory result = game.returnHome(id);
        assertEq(uint256(result.kind), uint256(Kind.Dream));
        assertGe(result.itemId, 9);
        assertLe(result.itemId, 11);
        assertEq(result.pity, 1);
        assertEq(inventoryTotal(id), 1);
        vm.expectRevert(Squeeklings.PetAtHome.selector);
        game.returnHome(id);
        assertEq(inventoryTotal(id), 1);
    }

    function testThirtySixActiveRoundsRequireThreePagesAndAllHashes() public {
        uint256 id = hatch(alice);
        Expedition memory trip = embark(id, 2);
        core.append(999, 900_000_000, keccak256("before trip"));
        bytes memory hashes;
        uint64 expectedWork;
        for (uint64 round = trip.startRound; round <= trip.endRound; ++round) {
            uint64 work = round == 20 ? 500 : round;
            bytes32 hash = keccak256(abi.encode("trip", round));
            core.append(work, 200_000_000, hash);
            hashes = bytes.concat(hashes, hash);
            expectedWork += work;
        }
        ReaderHarness reader = new ReaderHarness();
        (bool ok, Reader.History memory h) = reader.history(address(core), 1, 37);
        assertTrue(ok);
        assertEq(h.work, expectedWork);
        // floor(8.1) - floor(.9) = 8, not floor(7.2) = 7.
        assertEq(h.blocks, 8);
        assertEq(h.busiest, 500);
        assertEq(h.entropy, keccak256(hashes));
        core.append(5000, 1000e9, keccak256("after trip"));
        bytes32 digest = keccak256(abi.encode(h.entropy, game.pet(id).seed, id, trip.endRound));
        LootHarness lottery = new LootHarness();
        Loot memory expected = lottery.draw(digest, 2, h.work, h.blocks, h.busiest, 0);
        vm.recordLogs();
        vm.prank(bob);
        Loot memory result = game.returnHome(id);
        assertEq(result.itemId, expected.itemId);
        assertEq(uint256(result.rarity), uint256(expected.rarity));
        assertEq(uint256(result.kind), uint256(Kind.Trail));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory returned = logs[logs.length - 1];
        assertEq(returned.topics[1], bytes32(id));
        assertEq(address(uint160(uint256(returned.topics[2]))), alice);
        (,,, uint64 loggedWork, uint96 loggedBlocks, uint64 loggedBusiest, bytes32 entropy,) =
            abi.decode(returned.data, (uint8, Kind, Rarity, uint64, uint96, uint64, bytes32, uint32));
        assertEq(loggedWork, expectedWork);
        assertEq(loggedBlocks, 8);
        assertEq(loggedBusiest, 500);
        assertEq(entropy, keccak256(hashes));
    }

    function testSparseCursorAdvancesAcrossCertifiedEmptyGap() public {
        uint256 id = hatch(alice);
        Expedition memory trip = embark(id, 2);
        core.append(0, 0, bytes32(0));
        bytes memory hashes;
        for (uint64 r = 2; r <= trip.endRound; ++r) {
            bool active = r <= 17 || r >= 35;
            bytes32 hash = keccak256(abi.encode(r));
            core.append(active ? 1 : 0, active ? 1e9 : 0, hash);
            if (active) hashes = bytes.concat(hashes, hash);
        }
        assertEq(core.roundPage(1, 37, 16).certifiedThroughRound, 34);
        ReaderHarness reader = new ReaderHarness();
        (bool ok, Reader.History memory h) = reader.history(address(core), 1, 37);
        assertTrue(ok);
        assertEq(h.work, 19);
        assertEq(h.blocks, 19);
        assertEq(h.entropy, keccak256(hashes));
        core.setCertifyGaps(false);
        (ok, h) = reader.history(address(core), 1, 37);
        assertTrue(ok);
        assertEq(h.entropy, keccak256(hashes));
        game.returnHome(id);
        assertEq(inventoryTotal(id), 1);
    }

    function testMalformedHistoryDoesNotGiveLootOrLoseTheTrip() public {
        uint256 id = hatch(alice);
        Expedition memory trip = embark(id, 0);
        while (core.settled() < trip.endRound) core.append(1, 1e9, bytes32(uint256(core.settled())));
        for (uint8 fault = 1; fault <= 8; ++fault) {
            core.setBadPage(fault);
            vm.expectRevert(Squeeklings.InvalidHistory.selector);
            game.returnHome(id);
            assertTrue(game.expedition(id).away);
            assertEq(inventoryTotal(id), 0);
            assertEq(game.pet(id).pity, 0);
        }
        core.setBadPage(0);
        core.setFaults(false, false, true);
        vm.expectRevert(Squeeklings.InvalidHistory.selector);
        game.returnHome(id);
        core.setFaults(false, false, false);
        game.returnHome(id);
        assertEq(inventoryTotal(id), 1);
    }

    function testCorePauseDoesNotBlockReadingAlreadySettledTrips() public {
        uint256 id = hatch(alice);
        Expedition memory trip = embark(id, 1);
        settleEmpty(trip.endRound);
        core.setPaused(true);
        game.returnHome(id);
        assertEq(inventoryTotal(id), 1);
    }

    function testExactlyFourPagesAcceptedButFifthRequiredPageRejectsAtomically() public {
        uint256 id = hatch(alice);
        Expedition memory trip = embark(id, 2);
        while (core.settled() < trip.endRound) core.append(1, 1e9, bytes32(uint256(core.settled())));
        core.setPageCap(8);
        vm.expectRevert(Squeeklings.InvalidHistory.selector);
        game.returnHome(id);
        assertTrue(game.expedition(id).away);
        assertEq(inventoryTotal(id), 0);
        core.setPageCap(9);
        game.returnHome(id);
        assertFalse(game.expedition(id).away);
        assertEq(inventoryTotal(id), 1);
    }

    function testStateOutageLeavesTripRetryableWithoutLoot() public {
        uint256 id = hatch(alice);
        Expedition memory trip = embark(id, 0);
        settleEmpty(trip.endRound);
        core.setFaults(true, false, false);
        vm.expectRevert(Squeeklings.CoreUnavailable.selector);
        game.returnHome(id);
        assertTrue(game.expedition(id).away);
        assertEq(inventoryTotal(id), 0);
        core.setFaults(false, false, false);
        game.returnHome(id);
        assertEq(inventoryTotal(id), 1);
    }

    function testPityGuaranteesSixthMediumDreamReturnAndResets() public {
        uint256 id = hatch(alice);
        for (uint32 i; i < 6; ++i) {
            Expedition memory trip = embark(id, 1);
            settleEmpty(trip.endRound);
            Loot memory result = game.returnHome(id);
            assertEq(uint256(result.kind), uint256(Kind.Dream));
            if (i < 5) {
                assertLt(uint256(result.rarity), uint256(Rarity.Rare));
                assertEq(game.pet(id).pity, i + 1);
            } else {
                assertEq(uint256(result.rarity), uint256(Rarity.Rare));
                assertEq(game.pet(id).pity, 0);
            }
            advance();
        }
        assertEq(inventoryTotal(id), 6);
    }

    function testShortRouteAccumulatesPityWithoutForcingRare() public {
        uint256 id = hatch(alice);
        game.setPity(id, 9);
        Expedition memory trip = embark(id, 0);
        settleEmpty(trip.endRound);
        Loot memory result = game.returnHome(id);
        assertEq(uint256(result.rarity), uint256(Rarity.Common));
        assertEq(result.pity, 10);
    }

    function testFuzzTripWorkAndEntropy(uint8 rawRoute, uint16[36] memory works, uint32 salt) public {
        uint8 route = uint8(bound(rawRoute, 0, 2));
        uint256 id = hatch(alice);
        Expedition memory trip = embark(id, route);
        core.append(9999, 700_000_000, bytes32("outside"));
        uint64 expectedWork;
        uint64 expectedBusiest;
        uint96 expectedUnits = 700_000_000;
        bytes memory hashes;
        for (uint64 r = trip.startRound; r <= trip.endRound; ++r) {
            uint64 value = works[r - trip.startRound] % 1001;
            uint96 units = uint96(value) * 37_000_000;
            bytes32 hash = keccak256(abi.encode(r, value, salt));
            core.append(value, units, hash);
            expectedWork += value;
            expectedUnits += units;
            if (value > expectedBusiest) expectedBusiest = value;
            if (value > 0) hashes = bytes.concat(hashes, hash);
        }
        ReaderHarness reader = new ReaderHarness();
        (bool ok, Reader.History memory h) = reader.history(address(core), trip.startRound - 1, trip.endRound);
        assertTrue(ok);
        assertEq(h.work, expectedWork);
        assertEq(h.busiest, expectedBusiest);
        assertEq(h.blocks, expectedUnits / 1e9);
        assertEq(h.entropy, keccak256(hashes));
        Loot memory result = game.returnHome(id);
        assertEq(uint256(result.kind), expectedWork == 0 ? uint256(Kind.Dream) : uint256(Kind.Trail));
        assertEq(inventoryTotal(id), 1);
        assertEq(game.itemBalanceOf(id, result.itemId), 1);
        assertFalse(game.expedition(id).away);
    }
}
