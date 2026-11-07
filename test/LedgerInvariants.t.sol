// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Squeeklings} from "../src/Squeeklings.sol";
import {SqueeklingsArt} from "../src/SqueeklingsArt.sol";
import {ISqueekCoreV3} from "../src/interfaces/ISqueekCoreV3.sol";
import {MockSqueekCore} from "./mocks/MockSqueekCore.sol";
import {Expedition, Loot, Slot, Rarity, Kind, Pet, PetView} from "../src/SqueekTypes.sol";

/// @notice Drives the production contract with several actors, wrong callers, core outages and
/// migrations, and keeps an independent ledger of what every pet should hold. Every expected failure
/// is asserted with its exact revert data, so `fail_on_revert` catches any revert nobody predicted.
contract LedgerHandler is Test {
    uint256 internal constant MAX_PETS = 8;
    uint256 internal constant MAX_MIGRATIONS = 4;

    Squeeklings public immutable game;
    address public immutable admin;
    MockSqueekCore public core;
    address[] public actors;
    uint256 public pets;
    uint256 public migrations;
    uint256 public completed;
    uint256 public fogReturns;
    uint256 public dreamReturns;
    uint256 public trailReturns;
    uint256 public expectedFailures;
    uint256 public ghostAge;

    mapping(uint256 => mapping(uint8 => uint256)) public ghostInv;
    mapping(uint256 => uint32) public ghostPity;
    mapping(uint256 => address) public ghostOwner;
    mapping(address => mapping(uint64 => uint64)) internal roundWork;

    constructor(Squeeklings game_, MockSqueekCore core_, address admin_) {
        game = game_;
        core = core_;
        admin = admin_;
        actors.push(makeAddr("outsider-a"));
        actors.push(makeAddr("outsider-b"));
        for (uint256 i; i < 3; ++i) {
            _hatch(makeAddr(string.concat("starter", vm.toString(i))));
        }
        ghostAge = game.ageUnits();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    // ---------------------------------------------------------------- actions

    function hatchSomeone(uint256 pick) external {
        address who = actors[pick % actors.length];
        if (game.hasHatched(who)) {
            _expectFail(
                who,
                abi.encodeCall(Squeeklings.hatch, ()),
                abi.encodeWithSelector(Squeeklings.AlreadyHatched.selector)
            );
        }
        if (pets < MAX_PETS) {
            _hatch(address(uint160(uint256(keccak256(abi.encode("hatcher", pets))))));
        }
        _sync();
    }

    function embark(uint256 pick, uint8 route, uint8 callerMode, uint256 callerPick) external {
        uint256 id = _id(pick);
        address holder = game.ownerOf(id);
        assertEq(holder, ghostOwner[id], "owner drifted");
        address caller = callerMode % 4 == 0 ? actors[callerPick % actors.length] : holder;
        uint8 r = route % 4; // 3 is an invalid route
        bytes memory data = abi.encodeCall(Squeeklings.embark, (id, r));
        if (caller != holder) {
            _expectFail(caller, data, abi.encodeWithSelector(Squeeklings.NotPetOwner.selector));
        } else if (game.expedition(id).away) {
            _expectFail(caller, data, abi.encodeWithSelector(Squeeklings.PetAway.selector));
        } else if (r == 3) {
            _expectFail(caller, data, abi.encodeWithSelector(Squeeklings.InvalidRoute.selector));
        } else {
            uint64 nowRound = game.currentRound();
            vm.prank(caller);
            game.embark(id, r);
            Expedition memory t = game.expedition(id);
            assertTrue(t.away);
            assertEq(t.route, r);
            assertEq(t.startRound, nowRound + 1, "trip must start next round");
            assertEq(t.endRound, nowRound + game.routeRounds(r), "trip length");
            assertEq(t.epoch, game.coreEpoch());
        }
        _sync();
    }

    function settle(uint256 count, uint256 workSeed) external {
        _settle(bound(count, 1, 40), workSeed);
        _sync();
    }

    /// @dev A whole trip in one call so that long sequences complete many returns of every kind.
    function fullTrip(uint256 pick, uint8 route, uint256 workSeed, uint256 callerPick) external {
        uint256 id = _id(pick);
        if (!game.expedition(id).away) {
            vm.prank(game.ownerOf(id));
            game.embark(id, route % 3);
        }
        Expedition memory t = game.expedition(id);
        if (t.epoch == game.coreEpoch() && core.settled() < t.endRound) {
            _settle(t.endRound - core.settled(), workSeed);
        }
        this.goHome(pick, callerPick);
    }

    function _settle(uint256 n, uint256 workSeed) internal {
        bool napping = workSeed % 4 == 0;
        for (uint256 i; i < n; ++i) {
            uint64 r = core.settled() + 1;
            uint256 h = uint256(keccak256(abi.encode(workSeed, r, address(core))));
            uint64 w = napping || h % 3 == 0 ? 0 : uint64((h >> 8) % 1001);
            uint96 u = w == 0 ? 0 : uint96((h >> 32) % 5e10);
            core.append(w, u, bytes32(h));
            roundWork[address(core)][r] = w;
        }
        uint256 target = uint256(core.genesis()) + uint256(core.settled()) * core.duration();
        if (target > block.timestamp) vm.warp(target);
    }

    function goHome(uint256 pick, uint256 callerPick) external {
        uint256 id = _id(pick);
        Expedition memory t = game.expedition(id);
        address caller = actors[callerPick % actors.length];
        bytes memory data = abi.encodeCall(Squeeklings.returnHome, (id));
        if (!t.away) {
            _expectFail(caller, data, abi.encodeWithSelector(Squeeklings.PetAtHome.selector));
            _sync();
            return;
        }
        bool fog = t.epoch != game.coreEpoch();
        if (!fog && core.settled() < t.endRound) {
            _expectFail(
                caller,
                data,
                abi.encodeWithSelector(Squeeklings.NotSettledYet.selector, t.endRound, core.settled())
            );
            _sync();
            return;
        }
        uint32 oldPity = game.pet(id).pity;
        assertEq(oldPity, ghostPity[id]);
        uint8[4] memory before = game.pet(id).equipped;
        vm.prank(caller);
        Loot memory res = game.returnHome(id);
        (, Slot slot, Rarity rarity, Kind kind) = game.itemInfo(res.itemId);
        assertEq(uint8(rarity), uint8(res.rarity), "reported rarity is the item's rarity");
        assertEq(uint8(kind), uint8(res.kind), "reported kind is the item's kind");
        if (fog) {
            assertEq(res.itemId, 17, "stale epoch must give a Compass");
            assertEq(res.pity, oldPity, "fog leaves pity");
            ++fogReturns;
        } else {
            _checkDraw(t, res, oldPity);
        }
        uint8[4] memory afterEq = game.pet(id).equipped;
        if (before[uint8(slot)] == 0) assertEq(afterEq[uint8(slot)], res.itemId, "auto-equip empty slot");
        else assertEq(afterEq[uint8(slot)], before[uint8(slot)], "occupied slot kept");
        assertFalse(game.expedition(id).away);
        ++ghostInv[id][res.itemId];
        ghostPity[id] = res.pity;
        ++completed;
        _sync();
    }

    function _checkDraw(Expedition memory t, Loot memory res, uint32 oldPity) internal {
        (,, ISqueekCoreV3.Point memory s,) = core.roundPage(t.startRound - 1, t.startRound - 1, 0);
        (,, ISqueekCoreV3.Point memory e,) = core.roundPage(t.endRound, t.endRound, 0);
        uint64 work = e.cumulativeWork - s.cumulativeWork;
        uint96 blocks = e.cumulativeBlockUnits / 1e9 - s.cumulativeBlockUnits / 1e9;
        uint64 busiest;
        for (uint64 r = t.startRound; r <= t.endRound; ++r) {
            uint64 w = roundWork[address(core)][r];
            if (w > busiest) busiest = w;
        }
        bool dream = work == 0;
        if (dream) ++dreamReturns;
        else ++trailReturns;
        assertEq(uint8(res.kind), uint8(dream ? Kind.Dream : Kind.Trail), "zero work is a Dream trip");
        if (dream) assertTrue(res.itemId >= 9 && res.itemId <= 16, "dream table");
        else assertTrue(res.itemId >= 1 && res.itemId <= 8, "trail table");
        bool eligible = dream ? t.route == 2 : busiest >= 500;
        bool pityRare = oldPity >= 5 && t.route >= 1;
        uint256 tier = dream ? uint256(t.route) + 1 : blocks < 40 ? 1 : blocks < 200 ? 2 : 3;
        if (!eligible) assertTrue(res.rarity != Rarity.Legendary, "legendary needs eligibility");
        if (pityRare) assertTrue(res.rarity >= Rarity.Rare, "pity guarantee");
        if (!pityRare && res.rarity != Rarity.Legendary) {
            if (tier == 1) assertEq(uint8(res.rarity), uint8(Rarity.Common), "T1 is common");
            if (tier == 2) assertTrue(res.rarity <= Rarity.Uncommon, "T2 tops at uncommon");
        }
        if (res.rarity >= Rarity.Rare) assertEq(res.pity, 0, "rare or better resets pity");
        else assertEq(res.pity, oldPity + 1, "other items add one");
    }

    function move(uint256 pick, uint256 toPick, uint8 callerMode) external {
        uint256 id = _id(pick);
        address from = game.ownerOf(id);
        address to = actors[toPick % actors.length];
        address caller = callerMode % 5 == 0 ? actors[(toPick / 7) % actors.length] : from;
        bytes memory data = abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, id);
        if (game.expedition(id).away) {
            _expectFail(caller, data, abi.encodeWithSelector(Squeeklings.PetAway.selector));
        } else if (caller != from) {
            _expectFail(
                caller,
                data,
                abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, caller, id)
            );
        } else {
            vm.prank(caller);
            game.transferFrom(from, to, id);
            ghostOwner[id] = to;
        }
        _sync();
    }

    function dress(uint256 pick, uint8 item, uint8 slot, uint8 callerMode, uint256 callerPick) external {
        uint256 id = _id(pick);
        address holder = game.ownerOf(id);
        address caller = callerMode % 4 == 0 ? actors[callerPick % actors.length] : holder;
        uint8 itemId = item % 17 + 1;
        uint8 s = slot % 5; // 4 is invalid
        if (caller != holder) {
            _expectFail(
                caller,
                abi.encodeCall(Squeeklings.equip, (id, itemId)),
                abi.encodeWithSelector(Squeeklings.NotPetOwner.selector)
            );
            _expectFail(
                caller,
                abi.encodeCall(Squeeklings.unequip, (id, s)),
                abi.encodeWithSelector(Squeeklings.NotPetOwner.selector)
            );
            _sync();
            return;
        }
        if (game.itemBalanceOf(id, itemId) == 0) {
            _expectFail(
                caller,
                abi.encodeCall(Squeeklings.equip, (id, itemId)),
                abi.encodeWithSelector(Squeeklings.ItemNotOwned.selector)
            );
        } else {
            vm.prank(caller);
            game.equip(id, itemId);
            (, Slot itemSlot,,) = game.itemInfo(itemId);
            assertEq(game.pet(id).equipped[uint8(itemSlot)], itemId);
        }
        if (item % 3 == 0) {
            if (s == 4) {
                _expectFail(
                    caller,
                    abi.encodeCall(Squeeklings.unequip, (id, s)),
                    abi.encodeWithSelector(Squeeklings.InvalidSlot.selector)
                );
            } else {
                vm.prank(caller);
                game.unequip(id, s);
                assertEq(game.pet(id).equipped[s], 0);
            }
        }
        _sync();
    }

    function migrate(uint256 startUnits, uint256 attackerPick) external {
        address attacker = actors[attackerPick % actors.length];
        _expectFail(
            attacker,
            abi.encodeCall(Squeeklings.setCore, (address(0xC0DE))),
            abi.encodeWithSelector(Squeeklings.OnlyOwner.selector)
        );
        if (migrations < MAX_MIGRATIONS && startUnits % 3 == 0) {
            MockSqueekCore next = new MockSqueekCore(uint64(block.timestamp));
            next.setUnits(uint96(bound(startUnits, 0, 1e24)));
            uint256 before = game.ageUnits();
            uint64 epoch = game.coreEpoch();
            vm.prank(admin);
            game.setCore(address(next));
            assertEq(game.ageUnits(), before, "migration keeps age");
            assertEq(game.coreEpoch(), epoch + 1);
            core = next;
            ++migrations;
        }
        _sync();
    }

    /// @dev A temporary outage inside one call: writes fail cleanly, metadata survives, nothing moves.
    function outage(uint256 pick, uint8 mode) external {
        uint256 id = _id(pick);
        address holder = game.ownerOf(id);
        Expedition memory t = game.expedition(id);
        uint8 m = mode % 3;
        core.setFaults(m == 0, m == 1, m == 2);
        bytes memory unavailable = abi.encodeWithSelector(Squeeklings.CoreUnavailable.selector);
        if (m < 2) {
            if (!t.away) {
                _expectFail(holder, abi.encodeCall(Squeeklings.embark, (id, 0)), unavailable);
            } else if (t.epoch == game.coreEpoch()) {
                _expectFail(holder, abi.encodeCall(Squeeklings.returnHome, (id)), unavailable);
            }
            if (pets < MAX_PETS) {
                _expectFail(
                    address(uint160(uint256(keccak256(abi.encode("hatcher", pets))))),
                    abi.encodeCall(Squeeklings.hatch, ()),
                    unavailable
                );
            }
        } else if (t.away && t.epoch == game.coreEpoch() && core.settled() >= t.endRound) {
            _expectFail(
                holder,
                abi.encodeCall(Squeeklings.returnHome, (id)),
                abi.encodeWithSelector(Squeeklings.InvalidHistory.selector)
            );
        }
        PetView memory v = game.displayData(id);
        assertTrue(v.signalLost, "outage shows signal lost");
        assertGt(bytes(game.tokenURI(id)).length, 0);
        core.setFaults(false, false, false);
        assertEq(game.expedition(id).away, t.away, "outage changed the trip");
        _sync();
    }

    // ---------------------------------------------------------------- helpers

    function _hatch(address who) internal {
        vm.prank(who);
        uint256 id = game.hatch();
        ++pets;
        assertEq(id, pets);
        ghostOwner[id] = who;
        actors.push(who);
    }

    function _id(uint256 pick) internal view returns (uint256) {
        return pick % pets + 1;
    }

    function _expectFail(address who, bytes memory data, bytes memory expected) internal {
        vm.prank(who);
        (bool ok, bytes memory ret) = address(game).call(data);
        assertFalse(ok, "call that must fail succeeded");
        assertEq(ret, expected, "unexpected revert reason");
        ++expectedFailures;
    }

    function _sync() internal {
        uint256 a = game.ageUnits();
        assertGe(a, ghostAge, "age went backwards");
        ghostAge = a;
    }
}

contract LedgerInvariantsTest is Test {
    Squeeklings internal game;
    LedgerHandler internal handler;

    function setUp() public {
        vm.warp(1_000_000);
        vm.roll(50);
        MockSqueekCore core = new MockSqueekCore(1_000_000);
        SqueeklingsArt art = new SqueeklingsArt();
        address admin = makeAddr("ledger-admin");
        game = new Squeeklings(address(core), address(art), admin);
        handler = new LedgerHandler(game, core, admin);
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = handler.hatchSomeone.selector;
        selectors[1] = handler.embark.selector;
        selectors[2] = handler.settle.selector;
        selectors[3] = handler.goHome.selector;
        selectors[4] = handler.move.selector;
        selectors[5] = handler.dress.selector;
        selectors[6] = handler.migrate.selector;
        selectors[7] = handler.outage.selector;
        selectors[8] = handler.fullTrip.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 96
    /// forge-config: default.invariant.depth = 64
    function invariantInventoryMatchesIndependentLedger() public view {
        uint256 total;
        for (uint256 id = 1; id <= handler.pets(); ++id) {
            uint256[17] memory counts = game.inventory(id);
            for (uint8 i; i < 17; ++i) {
                assertEq(counts[i], handler.ghostInv(id, i + 1), "item count differs from ledger");
                total += counts[i];
            }
        }
        assertEq(total, handler.completed(), "one capsule per return");
        assertEq(handler.completed(), handler.fogReturns() + handler.dreamReturns() + handler.trailReturns());
    }

    /// forge-config: default.invariant.runs = 96
    /// forge-config: default.invariant.depth = 64
    function invariantPityOwnershipAndSupply() public view {
        uint256 n = handler.pets();
        assertEq(game.totalSupply(), n);
        assertLe(n, game.MAX_SUPPLY());
        for (uint256 id = 1; id <= n; ++id) {
            assertEq(game.pet(id).pity, handler.ghostPity(id), "pity differs from ledger");
            assertEq(game.ownerOf(id), handler.ghostOwner(id), "owner differs from ledger");
        }
        uint256 held;
        for (uint256 i; i < handler.actorCount(); ++i) {
            held += game.balanceOf(handler.actors(i));
        }
        assertEq(held, n, "every pet is held by a known actor");
        assertEq(address(game).balance, 0, "never holds ETH");
    }

    /// forge-config: default.invariant.runs = 96
    /// forge-config: default.invariant.depth = 64
    function invariantTripsEquipmentAndAgeAreConsistent() public view {
        uint256 age = game.ageUnits();
        assertGe(age, handler.ghostAge(), "age never decreases");
        assertEq(game.coreEpoch(), handler.migrations() + 1);
        assertEq(game.core(), address(handler.core()));
        for (uint256 id = 1; id <= handler.pets(); ++id) {
            Pet memory p = game.pet(id);
            assertLe(p.birthUnits, age, "born in the future");
            assertEq(game.ageBlocks(id), (age - p.birthUnits) / 1e9);
            Expedition memory t = game.expedition(id);
            if (t.away) {
                assertEq(t.endRound - t.startRound + 1, game.routeRounds(t.route), "trip length");
                assertLe(t.epoch, game.coreEpoch());
                assertGe(t.startRound, 2);
            }
            for (uint8 slot; slot < 4; ++slot) {
                uint8 item = p.equipped[slot];
                if (item == 0) continue;
                assertGt(game.itemBalanceOf(id, item), 0, "equipped item not owned");
                (, Slot s,,) = game.itemInfo(item);
                assertEq(uint8(s), slot, "item in wrong slot");
            }
        }
    }
}
