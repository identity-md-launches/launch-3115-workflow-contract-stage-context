// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    SqueekTestBase,
    Squeeklings,
    MockSqueekCore,
    Expedition,
    Loot,
    Kind,
    Rarity,
    Mood,
    Stage,
    Slot
} from "./TestBase.sol";

contract CoreAgeMoodTest is SqueekTestBase {
    function testAgeUsesBirthOffsetAndExactStageThresholds() public {
        core.setUnits(777e9);
        uint256 id = hatch(alice);
        assertEq(game.pet(id).birthUnits, 777e9);
        assertEq(game.ageBlocks(id), 0);
        assertEq(uint256(game.stage(id)), uint256(Stage.Pinky));
        uint96[8] memory ages = [uint96(0), 199, 200, 1999, 2000, 9999, 10000, 20000];
        Stage[8] memory expected = [
            Stage.Pinky,
            Stage.Pinky,
            Stage.Fuzz,
            Stage.Fuzz,
            Stage.Runner,
            Stage.Runner,
            Stage.Elder,
            Stage.Elder
        ];
        for (uint256 i; i < ages.length; ++i) {
            core.setUnits((777 + ages[i]) * 1e9);
            assertEq(game.ageBlocks(id), ages[i]);
            assertEq(uint256(game.stage(id)), uint256(expected[i]));
        }
        core.setUnits(776e9);
        assertEq(game.ageBlocks(id), 0);
    }

    function testCoreReplacementPreservesAgeAndAddsOnlyNewDelta() public {
        core.setUnits(100e9);
        uint256 id = hatch(alice);
        core.setUnits(350e9);
        assertEq(game.ageBlocks(id), 250);
        MockSqueekCore next = new MockSqueekCore(GENESIS);
        next.setUnits(8000e9);
        vm.prank(admin);
        game.setCore(address(next));
        assertEq(game.ageBase(), 350e9);
        assertEq(game.coreStart(), 8000e9);
        assertEq(game.coreEpoch(), 2);
        assertEq(game.ageUnits(), 350e9);
        assertEq(game.ageBlocks(id), 250);
        next.setUnits(8100e9);
        assertEq(game.ageBlocks(id), 350);
        assertEq(game.owner(), admin);
    }

    function testUnreadableOldCoreUsesLastMutationCheckpoint() public {
        core.setUnits(100e9);
        uint256 id = hatch(alice);
        core.setUnits(900e9);
        embark(id, 0);
        core.setUnits(1000e9);
        assertEq(game.ageUnits(), 1000e9); // A view cannot persist a checkpoint.
        assertEq(game.lastSeenAgeUnits(), 900e9);
        core.setFaults(true, false, false);
        assertEq(game.ageUnits(), 900e9);
        MockSqueekCore next = new MockSqueekCore(GENESIS);
        next.setUnits(400e9);
        vm.prank(admin);
        game.setCore(address(next));
        assertEq(game.ageBase(), 900e9);
        assertEq(game.ageBlocks(id), 800);
    }

    function testGlobalAgeClampsEntireExpressionWhenCoreMovesBackwards() public {
        core.setUnits(100e9);
        uint256 id = hatch(alice);
        MockSqueekCore next = new MockSqueekCore(GENESIS);
        next.setUnits(1000e9);
        vm.prank(admin);
        game.setCore(address(next));
        next.setUnits(950e9);
        assertEq(game.ageUnits(), 50e9);
        assertEq(game.ageBlocks(id), 0);
        next.setUnits(500e9);
        assertEq(game.ageUnits(), 0);
        assertEq(game.ageBlocks(id), 0);
    }

    function testSetCoreOnlyOwnerAndRejectsInvalidDependenciesAtomically() public {
        MockSqueekCore next = new MockSqueekCore(GENESIS);
        vm.prank(alice);
        vm.expectRevert(Squeeklings.OnlyOwner.selector);
        game.setCore(address(next));
        vm.startPrank(admin);
        vm.expectRevert(Squeeklings.InvalidAddress.selector);
        game.setCore(address(0));
        vm.expectRevert(Squeeklings.CoreUnchanged.selector);
        game.setCore(address(core));
        vm.expectRevert(Squeeklings.InvalidCore.selector);
        game.setCore(bob);
        vm.stopPrank();
        next.setConfiguration(GENESIS, 0, 1e9);
        _reject(next);
        next.setConfiguration(GENESIS + 1, 60, 1e9);
        _reject(next);
        next.setConfiguration(0, 60, 1e9);
        _reject(next);
        next.setConfiguration(GENESIS, 60, 1e8);
        _reject(next);
        next.setConfiguration(GENESIS, 60, 1e9);
        next.setFaults(true, false, false);
        _reject(next);
        next.setFaults(false, true, false);
        _reject(next);
        assertEq(game.core(), address(core));
        assertEq(game.coreEpoch(), 1);
        assertEq(game.ageBase(), 0);
    }

    function _reject(MockSqueekCore next) private {
        vm.prank(admin);
        vm.expectRevert(Squeeklings.InvalidCore.selector);
        game.setCore(address(next));
    }

    function testOldEpochReturnsFogWithoutNewOrOldCoreBeingReadable() public {
        uint256 id = hatch(alice);
        game.setPity(id, 5);
        embark(id, 2);
        MockSqueekCore next = new MockSqueekCore(GENESIS);
        vm.prank(admin);
        game.setCore(address(next));
        vm.prank(alice);
        vm.expectRevert(Squeeklings.PetAway.selector);
        game.transferFrom(alice, bob, id);
        core.setFaults(true, true, true);
        next.setFaults(true, true, true);
        vm.prank(bob);
        Loot memory result = game.returnHome(id);
        assertEq(result.itemId, 17);
        assertEq(uint256(result.kind), uint256(Kind.Fog));
        assertEq(uint256(result.rarity), uint256(Rarity.Uncommon));
        assertEq(result.pity, 5);
        assertEq(game.pet(id).pity, 5);
        assertEq(game.pet(id).equipped[uint8(Slot.Hand)], 17);
        assertEq(inventoryTotal(id), 1);
        assertFalse(game.expedition(id).away);
        vm.prank(alice);
        game.transferFrom(alice, bob, id);
        assertEq(game.ownerOf(id), bob);
    }

    function testRepeatedMigrationAndTripOnNewEpoch() public {
        uint256 id = hatch(alice);
        MockSqueekCore next = new MockSqueekCore(GENESIS);
        vm.prank(admin);
        game.setCore(address(next));
        Expedition memory trip = embark(id, 0);
        assertEq(trip.epoch, 2);
        while (next.settled() < trip.endRound) next.append(0, 0, bytes32(0));
        Loot memory result = game.returnHome(id);
        assertEq(uint256(result.kind), uint256(Kind.Dream));
        vm.prank(admin);
        game.setCore(address(core));
        assertEq(game.coreEpoch(), 3);
        assertEq(inventoryTotal(id), 1);
    }

    function testMoodLooksAtSixSettledRoundsNotWallClock() public {
        _mood(Mood.Napping, false);
        core.append(500, 1e9, bytes32("first"));
        _mood(Mood.Zoomies, false);
        settleEmpty(6);
        vm.warp(GENESIS + 10_000 * ROUND_SECONDS);
        _mood(Mood.Zoomies, false);
        settleEmpty(7);
        _mood(Mood.Napping, false);
        core.append(499, 1e9, bytes32("jog"));
        _mood(Mood.Jogging, false);
        core.append(500, 1e9, bytes32("zoom"));
        _mood(Mood.Zoomies, false);
        core.setFaults(false, false, true);
        _mood(Mood.Napping, true);
    }

    function _mood(Mood expected, bool lost) private view {
        (Mood value, bool signalLost) = game.mood();
        assertEq(uint256(value), uint256(expected));
        assertEq(signalLost, lost);
    }

    function testCurrentRoundBoundariesAndOverflowAreExplicit() public {
        assertEq(game.currentRound(), 1);
        vm.warp(GENESIS + 59);
        assertEq(game.currentRound(), 1);
        vm.warp(GENESIS + 60);
        assertEq(game.currentRound(), 2);
        core.setConfiguration(GENESIS, 1, 1e9);
        uint256 id = hatch(alice);
        vm.warp(uint256(GENESIS) + type(uint64).max - 1);
        assertEq(game.currentRound(), type(uint64).max);
        vm.prank(alice);
        vm.expectRevert(Squeeklings.RoundOverflow.selector);
        game.embark(id, 0);
        vm.warp(uint256(GENESIS) + type(uint64).max);
        vm.expectRevert(Squeeklings.RoundOverflow.selector);
        game.currentRound();
    }

    function testFuzzAgeContinuity(uint96 original, uint96 newBaseline, uint64 growth) public {
        core.setUnits(original);
        uint256 id = hatch(alice);
        MockSqueekCore next = new MockSqueekCore(GENESIS);
        next.setUnits(newBaseline);
        vm.prank(admin);
        game.setCore(address(next));
        assertEq(game.ageUnits(), original);
        uint96 delta = uint96(bound(growth, 0, type(uint96).max - newBaseline));
        next.setUnits(newBaseline + delta);
        assertEq(game.ageUnits(), uint256(original) + delta);
        assertEq(game.ageBlocks(id), uint256(delta) / 1e9);
    }
}
