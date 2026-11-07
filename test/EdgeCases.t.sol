// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    SqueekTestBase,
    Squeeklings,
    MockSqueekCore,
    Expedition,
    Pet,
    Loot,
    Rarity,
    Kind,
    Mood,
    Stage,
    Slot,
    PetView
} from "./TestBase.sol";
import {LootHarness} from "./mocks/Harnesses.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract EdgeCasesTest is SqueekTestBase {
    event Embarked(
        uint256 indexed tokenId,
        address indexed petOwner,
        uint8 route,
        uint64 startRound,
        uint64 endRound,
        uint64 epoch
    );
    event CoreChanged(
        address indexed oldCore, address indexed newCore, uint64 epoch, uint256 ageBase, uint96 coreStart
    );
    event Hatched(address indexed minter, uint256 indexed tokenId, bytes32 seed, uint256 birthUnits);

    // ------------------------------------------------------------ failure paths

    function testHatchDuringOutageRevertsWithoutSpendingEligibility() public {
        core.setFaults(true, false, false);
        vm.prank(alice);
        vm.expectRevert(Squeeklings.CoreUnavailable.selector);
        game.hatch();
        core.setFaults(false, true, false);
        vm.prank(alice);
        vm.expectRevert(Squeeklings.CoreUnavailable.selector);
        game.hatch();
        assertFalse(game.hasHatched(alice));
        assertEq(game.totalSupply(), 0);
        assertEq(game.balanceOf(alice), 0);
        core.setFaults(false, false, false);
        core.setUnits(42e9);
        bytes32 seed = keccak256(abi.encode(blockhash(block.number - 1), alice, uint256(1)));
        vm.expectEmit(true, true, false, true, address(game));
        emit Hatched(alice, 1, seed, 42e9);
        assertEq(hatch(alice), 1);
        assertEq(game.pet(1).seed, seed);
    }

    function testEmbarkDuringOutageRevertsAndPetStaysTransferable() public {
        uint256 id = hatch(alice);
        core.setFaults(false, true, false);
        vm.prank(alice);
        vm.expectRevert(Squeeklings.CoreUnavailable.selector);
        game.embark(id, 1);
        core.setFaults(true, false, false);
        vm.prank(alice);
        vm.expectRevert(Squeeklings.CoreUnavailable.selector);
        game.embark(id, 1);
        assertFalse(game.expedition(id).away);
        vm.prank(alice);
        game.transferFrom(alice, bob, id);
        assertEq(game.ownerOf(id), bob);
    }

    function testNonexistentPetWritesUseERC721Error() public {
        bytes memory missing = abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 7);
        vm.expectRevert(missing);
        game.returnHome(7);
        vm.prank(alice);
        vm.expectRevert(missing);
        game.embark(7, 0);
        vm.prank(alice);
        vm.expectRevert(missing);
        game.equip(7, 1);
        vm.prank(alice);
        vm.expectRevert(missing);
        game.unequip(7, 0);
        vm.expectRevert(missing);
        game.expedition(7);
        vm.expectRevert(missing);
        game.inventory(7);
        vm.expectRevert(missing);
        game.ageBlocks(7);
        vm.expectRevert(missing);
        game.displayData(7);
    }

    function testApprovedOperatorCanMoveButNotManageThePet() public {
        uint256 id = hatch(alice);
        game.giveItem(id, 1);
        vm.prank(alice);
        game.approve(bob, id);
        vm.startPrank(bob);
        vm.expectRevert(Squeeklings.NotPetOwner.selector);
        game.embark(id, 0);
        vm.expectRevert(Squeeklings.NotPetOwner.selector);
        game.equip(id, 1);
        vm.expectRevert(Squeeklings.NotPetOwner.selector);
        game.unequip(id, 0);
        vm.stopPrank();
    }

    function testReturnHomeTwiceAndPageFaultLeaveExactlyOneCapsule() public {
        uint256 id = hatch(alice);
        Expedition memory trip = embark(id, 0);
        while (core.settled() < trip.endRound) core.append(3, 2e9, keccak256(abi.encode(core.settled())));
        core.setFaults(false, false, true);
        vm.expectRevert(Squeeklings.InvalidHistory.selector);
        game.returnHome(id);
        vm.prank(alice);
        vm.expectRevert(Squeeklings.PetAway.selector);
        game.transferFrom(alice, bob, id);
        core.setFaults(false, false, false);
        Loot memory result = game.returnHome(id);
        assertEq(uint8(result.kind), uint8(Kind.Trail));
        vm.expectRevert(Squeeklings.PetAtHome.selector);
        game.returnHome(id);
        assertEq(inventoryTotal(id), 1);
    }

    function testSetCoreEventAndExistingSettledTripStillBecomesFog() public {
        core.setUnits(10e9);
        uint256 id = hatch(alice);
        Expedition memory trip = embark(id, 0);
        while (core.settled() < trip.endRound) core.append(900, 300e9, keccak256(abi.encode(core.settled())));
        MockSqueekCore next = new MockSqueekCore(GENESIS);
        next.setUnits(5e9);
        uint256 age = game.ageUnits();
        vm.expectEmit(true, true, false, true, address(game));
        emit CoreChanged(address(core), address(next), 2, age, 5e9);
        vm.prank(admin);
        game.setCore(address(next));
        // Spec: trips from an older epoch return in the Fog, irrespective of their settlement on the old core.
        Loot memory result = game.returnHome(id);
        assertEq(result.itemId, 17);
        assertEq(uint8(result.kind), uint8(Kind.Fog));
        assertEq(game.itemBalanceOf(id, 17), 1);
        assertEq(game.lastSeenAgeUnits(), age);
    }

    function testNewEpochTripIgnoresOldCoreOutage() public {
        uint256 id = hatch(alice);
        MockSqueekCore next = new MockSqueekCore(GENESIS);
        vm.prank(admin);
        game.setCore(address(next));
        core.setFaults(true, true, true);
        Expedition memory trip = embark(id, 1);
        assertEq(trip.epoch, 2);
        while (next.settled() < trip.endRound) next.append(0, 0, bytes32(0));
        Loot memory result = game.returnHome(id);
        assertEq(uint8(result.kind), uint8(Kind.Dream));
        assertGe(result.itemId, 9);
        assertLe(result.itemId, 13); // medium dream table: common or uncommon at pity 0
    }

    // ------------------------------------------------------------ pity across Fog

    function testPityBuiltOnShortTripsSurvivesFogAndForcesRareOnNextMediumTrip() public {
        uint256 id = hatch(alice);
        for (uint32 i; i < 5; ++i) {
            Expedition memory t = embark(id, 0);
            settleEmpty(t.endRound);
            Loot memory r = game.returnHome(id);
            assertEq(uint8(r.rarity), uint8(Rarity.Common), "short dream trip is T1 and not eligible");
            assertEq(r.pity, i + 1);
            advance();
        }
        embark(id, 1);
        MockSqueekCore next = new MockSqueekCore(uint64(block.timestamp));
        vm.prank(admin);
        game.setCore(address(next));
        Loot memory fog = game.returnHome(id);
        assertEq(fog.itemId, 17);
        assertEq(game.pet(id).pity, 5);
        Expedition memory medium = embark(id, 1);
        while (next.settled() < medium.endRound) next.append(0, 0, bytes32(0));
        Loot memory rare = game.returnHome(id);
        assertEq(uint8(rare.rarity), uint8(Rarity.Rare));
        assertEq(uint8(rare.kind), uint8(Kind.Dream));
        assertTrue(rare.itemId == 14 || rare.itemId == 15);
        assertEq(game.pet(id).pity, 0);
        assertEq(inventoryTotal(id), 7);
    }

    // ------------------------------------------------------------ determinism

    function testOutcomeIndependentOfCallerTimeAndLaterRounds() public {
        uint256 id = hatch(alice);
        core.append(1000, 900e9, keccak256("before start"));
        Expedition memory trip = embark(id, 2);
        assertEq(trip.startRound, 2);
        while (core.settled() < trip.endRound) {
            uint64 r = core.settled() + 1;
            uint64 w = r % 4 == 0 ? 0 : r * 7;
            core.append(w, uint96(w) * 3e8, keccak256(abi.encode("trip", r)));
        }
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        vm.prank(bob);
        Loot memory a = game.returnHome(id);
        bytes memory firstLog = _lastLog();
        vm.revertToState(snap);

        for (uint256 i; i < 20; ++i) {
            core.append(999, 1000e9, keccak256(abi.encode("later", i)));
        }
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 10_000);
        vm.recordLogs();
        vm.prank(alice);
        Loot memory b = game.returnHome(id);
        assertEq(a.itemId, b.itemId);
        assertEq(uint8(a.rarity), uint8(b.rarity));
        assertEq(a.pity, b.pity);
        bytes memory secondLog = _lastLog();
        // Returned's busiest/work/blocks/entropy describe only rounds 2..37, never round 1 or later rounds.
        (,,, uint64 work1,, uint64 busiest1, bytes32 entropy1,) =
            abi.decode(firstLog, (uint8, Kind, Rarity, uint64, uint96, uint64, bytes32, uint32));
        (,,, uint64 work2,, uint64 busiest2, bytes32 entropy2,) =
            abi.decode(secondLog, (uint8, Kind, Rarity, uint64, uint96, uint64, bytes32, uint32));
        assertEq(work1, work2);
        assertEq(entropy1, entropy2);
        assertEq(busiest1, busiest2);
        assertEq(busiest1, 37 * 7);
        assertLt(busiest1, 1000);
    }

    function _lastLog() private returns (bytes memory) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        return logs[logs.length - 1].data;
    }

    // ------------------------------------------------------------ fuzzed properties

    /// forge-config: default.fuzz.runs = 512
    function testFuzzEmbarkWindowFollowsWallClockRound(uint64 rawDuration, uint64 rawOffset, uint8 rawRoute)
        public
    {
        uint64 duration = uint64(bound(rawDuration, 1, 1e6));
        uint64 offset = uint64(bound(rawOffset, 0, 1e12));
        uint8 route = uint8(bound(rawRoute, 0, 2));
        core.setConfiguration(GENESIS, duration, 1e9);
        uint256 id = hatch(alice);
        vm.warp(uint256(GENESIS) + offset);
        uint64 nowRound = offset / duration + 1;
        uint64 rounds = game.routeRounds(route);
        vm.expectEmit(true, true, false, true, address(game));
        emit Embarked(id, alice, route, nowRound + 1, nowRound + rounds, 1);
        Expedition memory trip = embark(id, route);
        assertEq(trip.startRound, nowRound + 1);
        assertEq(trip.endRound - trip.startRound + 1, rounds);
        // Unsettled rounds are unknown, not zero: no wall-clock time turns them into a Dream trip.
        vm.warp(block.timestamp + uint256(rounds + 1) * duration);
        vm.expectRevert(abi.encodeWithSelector(Squeeklings.NotSettledYet.selector, trip.endRound, uint64(0)));
        game.returnHome(id);
        assertTrue(game.expedition(id).away);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzMoodUsesExactlyTheLastSixSettledRounds(uint16[12] memory works, uint8 rawCount) public {
        uint256 n = bound(rawCount, 0, 12);
        for (uint256 i; i < n; ++i) {
            uint64 w = works[i] % 3 == 0 ? 0 : uint64(works[i] % 1001);
            core.append(w, w == 0 ? 0 : 1e9, keccak256(abi.encode(i)));
        }
        uint64 sum;
        uint64 busiest;
        for (uint256 i = n > 6 ? n - 6 : 0; i < n; ++i) {
            uint64 w = works[i] % 3 == 0 ? 0 : uint64(works[i] % 1001);
            sum += w;
            if (w > busiest) busiest = w;
        }
        Mood expected = sum == 0 ? Mood.Napping : busiest >= 500 ? Mood.Zoomies : Mood.Jogging;
        (Mood value, bool lost) = game.mood();
        assertFalse(lost);
        assertEq(uint8(value), uint8(expected));
        if (n > 0) {
            uint256 id = hatch(alice);
            PetView memory v = game.displayData(id);
            assertEq(uint8(v.mood), uint8(expected));
            assertFalse(v.signalLost);
        }
    }

    /// @notice Welfare: a zero-work trip draws from its own table at exactly the odds of the Trail tier
    /// its route maps to, so napping is never worse than running the same tier.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzzDreamTableMirrorsTrailTableAtSameTier(
        bytes32 digest,
        uint8 rawRoute,
        uint64 rawWork,
        uint96 rawBlocks,
        uint64 rawBusiest,
        uint32 pity
    ) public {
        LootHarness lottery = new LootHarness();
        uint8 route = uint8(bound(rawRoute, 0, 2));
        uint96 blocks = route == 0
            ? uint96(bound(rawBlocks, 0, 39))
            : route == 1 ? uint96(bound(rawBlocks, 40, 199)) : uint96(bound(rawBlocks, 200, type(uint96).max));
        uint64 work = uint64(bound(rawWork, 1, type(uint64).max));
        uint64 busiest =
            route == 2 ? uint64(bound(rawBusiest, 500, type(uint64).max)) : uint64(bound(rawBusiest, 0, 499));
        Loot memory dream = lottery.draw(digest, route, 0, 0, 0, pity);
        Loot memory trail = lottery.draw(digest, route, work, blocks, busiest, pity);
        assertEq(uint8(dream.kind), uint8(Kind.Dream));
        assertEq(uint8(trail.kind), uint8(Kind.Trail));
        assertEq(uint8(dream.rarity), uint8(trail.rarity), "same odds");
        assertEq(dream.itemId, trail.itemId + 8, "same position in the parallel table");
        assertEq(dream.pity, trail.pity);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzStageIsMonotoneAndMatchesThresholds(uint256 a, uint256 b) public view {
        (uint256 lo, uint256 hi) = a <= b ? (a, b) : (b, a);
        assertLe(uint8(game.stageForAge(lo)), uint8(game.stageForAge(hi)));
        Stage s = game.stageForAge(a);
        if (a < 200) assertEq(uint8(s), uint8(Stage.Pinky));
        else if (a < 2000) assertEq(uint8(s), uint8(Stage.Fuzz));
        else if (a < 10_000) assertEq(uint8(s), uint8(Stage.Runner));
        else assertEq(uint8(s), uint8(Stage.Elder));
    }

    // ------------------------------------------------------------ metadata at its heaviest

    function testFullyDressedElderRendersRealArtWithinArtGasBudget() public {
        uint256 id = hatch(alice);
        uint8[4] memory trail = [uint8(6), 8, 2, 7];
        uint8[4] memory dream = [uint8(14), 16, 10, 15];
        for (uint256 i; i < 4; ++i) {
            game.giveItem(id, trail[i]);
            game.giveItem(id, dream[i]);
        }
        core.append(1000, 20_000e9, keccak256("zoom"));
        embark(id, 2);
        for (uint256 set; set < 2; ++set) {
            for (uint256 i; i < 4; ++i) {
                vm.prank(alice);
                game.equip(id, set == 0 ? trail[i] : dream[i]);
            }
            PetView memory v = game.displayData(id);
            assertEq(uint8(v.stage), uint8(Stage.Elder));
            assertEq(uint8(v.mood), uint8(Mood.Zoomies));
            assertTrue(v.away);
            uint256 g = gasleft();
            art.render(id, v);
            uint256 used = g - gasleft();
            assertLt(used, game.ART_READ_GAS(), "art exceeds the budget tokenURI gives it");
            string memory json = decodeDataURI(game.tokenURI(id));
            assertFalse(contains(json, "Signal lost"), "fallback used for a healthy pet");
            assertTrue(contains(json, set == 0 ? "Zoomies Relic" : "Wishing Star"));
        }
    }
}
