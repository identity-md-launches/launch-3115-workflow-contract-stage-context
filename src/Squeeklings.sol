// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Pet, Expedition, PetView, Stage, Mood, Loot, Slot, Rarity, Kind} from "./SqueekTypes.sol";
import {SqueekCoreReader as Reader} from "./libraries/SqueekCoreReader.sol";
import {SqueekLoot} from "./libraries/SqueekLoot.sol";

interface ISqueeklingsArt {
    function render(uint256 tokenId, PetView calldata data) external pure returns (string memory);
}

/// @title Squeeklings — free pets, settled hamster history, and equally welcome naps.
/// @notice The administrator's only power is replacing the read-only core. No funds are accepted.
contract Squeeklings is ERC721, ReentrancyGuard {
    uint256 public constant MAX_SUPPLY = 88_888;
    uint256 public constant UNITS_PER_BLOCK = 1e9;
    uint256 public constant CORE_READ_GAS = 500_000;
    uint256 public constant ART_READ_GAS = 3_000_000;
    uint256 public constant MAX_ART_BYTES = 65_536;

    address public core;
    address public immutable art;
    address public immutable owner;
    uint64 public coreEpoch = 1;
    uint256 public ageBase;
    uint96 public coreStart;
    uint256 public lastSeenAgeUnits;
    uint256 public totalSupply;
    mapping(address => bool) public hasHatched;
    mapping(uint256 => Pet) internal _pets;
    mapping(uint256 => Expedition) internal _expeditions;
    mapping(uint256 => mapping(uint8 => uint256)) internal _inventory;

    error InvalidAddress();
    error OnlyOwner();
    error NotPetOwner();
    error AlreadyHatched();
    error SupplyCap();
    error CoreUnavailable();
    error InvalidCore();
    error CoreUnchanged();
    error RoundOverflow();
    error InvalidRoute();
    error PetAway();
    error PetAtHome();
    error NotSettledYet(uint64 needed, uint64 settled);
    error InvalidHistory();
    error ItemNotOwned();
    error InvalidSlot();

    event Hatched(address indexed minter, uint256 indexed tokenId, bytes32 seed, uint256 birthUnits);
    event Embarked(
        uint256 indexed tokenId,
        address indexed petOwner,
        uint8 route,
        uint64 startRound,
        uint64 endRound,
        uint64 epoch
    );
    event Returned(
        uint256 indexed tokenId,
        address indexed petOwner,
        uint8 itemId,
        Kind kind,
        Rarity rarity,
        uint64 work,
        uint96 blocks,
        uint64 busiest,
        bytes32 entropy,
        uint32 pity
    );
    event Equipped(uint256 indexed tokenId, Slot indexed slot, uint8 itemId);
    event CoreChanged(
        address indexed oldCore, address indexed newCore, uint64 epoch, uint256 ageBase, uint96 coreStart
    );

    /// @dev No dependency reads: compatible with factory deployment on an otherwise empty chain.
    constructor(address core_, address art_, address owner_) ERC721("Squeeklings", "SQLING") {
        if (core_ == address(0) || art_ == address(0) || owner_ == address(0)) revert InvalidAddress();
        core = core_;
        art = art_;
        owner = owner_;
    }

    function hatch() external nonReentrant returns (uint256 tokenId) {
        if (hasHatched[msg.sender]) revert AlreadyHatched();
        if (totalSupply >= MAX_SUPPLY) revert SupplyCap();
        Reader.State memory s = _liveState();
        uint256 birth = _checkpoint(s.units);
        tokenId = ++totalSupply;
        bytes32 previous = block.number == 0 ? bytes32(0) : blockhash(block.number - 1);
        bytes32 seed = keccak256(abi.encode(previous, msg.sender, tokenId));
        hasHatched[msg.sender] = true;
        _pets[tokenId].seed = seed;
        _pets[tokenId].birthUnits = birth;
        // Emit and record everything before the ERC-721 receiver callback.
        emit Hatched(msg.sender, tokenId, seed, birth);
        _safeMint(msg.sender, tokenId);
    }

    /// @notice Routes 0/1/2 last 6/18/36 rounds. Only the NFT owner chooses a trip.
    function embark(uint256 tokenId, uint8 route) external nonReentrant {
        _requirePetOwner(tokenId);
        if (_expeditions[tokenId].away) revert PetAway();
        uint64 duration = routeRounds(route);
        Reader.State memory s = _liveState();
        uint64 nowRound = currentRound();
        if (nowRound > type(uint64).max - duration) revert RoundOverflow();
        uint64 start = nowRound + 1;
        uint64 end = nowRound + duration;
        _checkpoint(s.units);
        _expeditions[tokenId] = Expedition(start, end, coreEpoch, route, true);
        emit Embarked(tokenId, msg.sender, route, start, end, coreEpoch);
    }

    /// @notice Anyone can finish a settled trip; exactly one item is credited to its NFT.
    function returnHome(uint256 tokenId) external nonReentrant returns (Loot memory result) {
        address petOwner = _requireOwned(tokenId);
        Expedition memory trip = _expeditions[tokenId];
        if (!trip.away) revert PetAtHome();
        Pet storage p = _pets[tokenId];
        Reader.History memory h;
        if (trip.epoch != coreEpoch) {
            result = SqueekLoot.fog(p.pity);
        } else {
            Reader.State memory s = _liveState();
            if (s.settled < trip.endRound) revert NotSettledYet(trip.endRound, s.settled);
            bool ok;
            (ok, h) = Reader.history(core, trip.startRound - 1, trip.endRound);
            if (!ok) revert InvalidHistory();
            bytes32 digest = keccak256(abi.encode(h.entropy, p.seed, tokenId, trip.endRound));
            result = SqueekLoot.draw(digest, trip.route, h.work, h.blocks, h.busiest, p.pity);
            _checkpoint(s.units);
        }
        _expeditions[tokenId].away = false;
        p.pity = result.pity;
        ++_inventory[tokenId][result.itemId];
        (, Slot slot,,) = SqueekLoot.info(result.itemId);
        if (p.equipped[uint8(slot)] == 0) {
            p.equipped[uint8(slot)] = result.itemId;
            emit Equipped(tokenId, slot, result.itemId);
        }
        emit Returned(
            tokenId,
            petOwner,
            result.itemId,
            result.kind,
            result.rarity,
            h.work,
            h.blocks,
            h.busiest,
            h.entropy,
            result.pity
        );
    }

    /// @notice The sole admin operation. Existing trips become Fog trips, irrespective of settlement.
    function setCore(address newCore) external nonReentrant {
        if (msg.sender != owner) revert OnlyOwner();
        if (newCore == address(0)) revert InvalidAddress();
        if (newCore == core) revert CoreUnchanged();
        (bool configOk,) = Reader.config(newCore);
        (bool stateOk, Reader.State memory next) = Reader.state(newCore);
        if (!configOk || !stateOk) revert InvalidCore();
        (bool oldOk, Reader.State memory oldState) = Reader.state(core);
        uint256 preservedAge = oldOk ? _ageAt(oldState.units) : lastSeenAgeUnits;
        address previous = core;
        ageBase = preservedAge;
        lastSeenAgeUnits = preservedAge;
        coreStart = next.units;
        core = newCore;
        ++coreEpoch;
        emit CoreChanged(previous, newCore, coreEpoch, preservedAge, next.units);
    }

    function equip(uint256 tokenId, uint8 itemId) external {
        _requirePetOwner(tokenId);
        (, Slot slot,,) = SqueekLoot.info(itemId);
        if (_inventory[tokenId][itemId] == 0) revert ItemNotOwned();
        _pets[tokenId].equipped[uint8(slot)] = itemId;
        emit Equipped(tokenId, slot, itemId);
    }

    function unequip(uint256 tokenId, uint8 slot) external {
        _requirePetOwner(tokenId);
        if (slot > uint8(Slot.Background)) revert InvalidSlot();
        _pets[tokenId].equipped[slot] = 0;
        emit Equipped(tokenId, Slot(slot), 0);
    }

    function pet(uint256 tokenId) external view returns (Pet memory) {
        _requireOwned(tokenId);
        return _pets[tokenId];
    }

    function expedition(uint256 tokenId) external view returns (Expedition memory) {
        _requireOwned(tokenId);
        return _expeditions[tokenId];
    }

    /// @notice Counts for item IDs 1..17 in that order. Equipped copies remain in the inventory.
    function inventory(uint256 tokenId) external view returns (uint256[17] memory counts) {
        _requireOwned(tokenId);
        for (uint8 i; i < 17; ++i) {
            counts[i] = _inventory[tokenId][i + 1];
        }
    }

    function itemBalanceOf(uint256 tokenId, uint8 itemId) external view returns (uint256) {
        _requireOwned(tokenId);
        SqueekLoot.info(itemId);
        return _inventory[tokenId][itemId];
    }

    function itemInfo(uint8 itemId)
        external
        pure
        returns (string memory name_, Slot slot, Rarity rarity, Kind kind)
    {
        return SqueekLoot.info(itemId);
    }

    function routeRounds(uint8 route) public pure returns (uint64) {
        if (route == 0) return 6;
        if (route == 1) return 18;
        if (route == 2) return 36;
        revert InvalidRoute();
    }

    function currentRound() public view returns (uint64) {
        (bool ok, Reader.Config memory c) = Reader.config(core);
        if (!ok) revert CoreUnavailable();
        uint256 round = (block.timestamp - c.genesis) / c.duration + 1;
        if (round > type(uint64).max) revert RoundOverflow();
        return uint64(round);
    }

    /// @notice Global age clock, clamped at zero; unreadable state falls back to the last write checkpoint.
    function ageUnits() public view returns (uint256) {
        (bool ok, Reader.State memory s) = Reader.state(core);
        return ok ? _ageAt(s.units) : lastSeenAgeUnits;
    }

    function ageBlocks(uint256 tokenId) public view returns (uint256) {
        _requireOwned(tokenId);
        uint256 nowUnits = ageUnits();
        uint256 birth = _pets[tokenId].birthUnits;
        return nowUnits > birth ? (nowUnits - birth) / UNITS_PER_BLOCK : 0;
    }

    function stage(uint256 tokenId) external view returns (Stage) {
        return stageForAge(ageBlocks(tokenId));
    }

    function stageForAge(uint256 blocks) public pure returns (Stage) {
        if (blocks < 200) return Stage.Pinky;
        if (blocks < 2_000) return Stage.Fuzz;
        if (blocks < 10_000) return Stage.Runner;
        return Stage.Elder;
    }

    function mood() external view returns (Mood value, bool signalLost) {
        (bool ok, Reader.State memory s) = Reader.state(core);
        if (!ok) return (Mood.Napping, true);
        return _mood(s.settled);
    }

    function displayData(uint256 tokenId) public view returns (PetView memory data) {
        _requireOwned(tokenId);
        Pet memory p = _pets[tokenId];
        data.seed = p.seed;
        data.pity = p.pity;
        data.equipped = p.equipped;
        data.away = _expeditions[tokenId].away;
        (bool ok, Reader.State memory s) = Reader.state(core);
        (bool configOk,) = Reader.config(core);
        uint256 nowUnits = ok ? _ageAt(s.units) : lastSeenAgeUnits;
        data.ageBlocks = nowUnits > p.birthUnits ? (nowUnits - p.birthUnits) / UNITS_PER_BLOCK : 0;
        data.stage = stageForAge(data.ageBlocks);
        if (ok && configOk) (data.mood, data.signalLost) = _mood(s.settled);
        else data.signalLost = true;
    }

    /// @notice Existing pets always retain on-chain metadata when dependencies fail.
    /// Nonexistent IDs keep the standard ERC-721 error; callers must still provide sufficient gas.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        PetView memory data = displayData(tokenId);
        (bool ok, bytes memory output) = Reader.boundedCall(
            art, abi.encodeCall(ISqueeklingsArt.render, (tokenId, data)), MAX_ART_BYTES, ART_READ_GAS
        );
        if (ok && output.length >= 64 && Reader.word(output, 0) == 32) {
            uint256 size = Reader.word(output, 1);
            if (size > 0 && size <= output.length - 64) return abi.decode(output, (string));
        }
        return string.concat(
            "data:application/json;base64,",
            Base64.encode(
                bytes(
                    string.concat(
                        '{"name":"Squeekling #',
                        Strings.toString(tokenId),
                        '","description":"Signal lost. Your pet and inventory are safe. Rest is welcome.",',
                        '"image":"data:image/svg+xml;base64,',
                        Base64.encode(
                            bytes(
                                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 320"><rect width="320" height="320" fill="#201c35"/><text x="160" y="150" text-anchor="middle" fill="#f9edd4">Signal lost</text><text x="160" y="180" text-anchor="middle" fill="#f9edd4">Your Squeekling is safe.</text></svg>'
                            )
                        ),
                        '"}'
                    )
                )
            )
        );
    }

    function _mood(uint64 settled) internal view returns (Mood value, bool signalLost) {
        uint64 afterRound = settled > 6 ? settled - 6 : 0;
        (bool ok, Reader.History memory h) = Reader.history(core, afterRound, settled);
        if (!ok) return (Mood.Napping, true);
        if (h.work == 0) return (Mood.Napping, false);
        return (h.busiest >= 500 ? Mood.Zoomies : Mood.Jogging, false);
    }

    function _liveState() internal view returns (Reader.State memory s) {
        (bool configOk,) = Reader.config(core);
        bool ok;
        (ok, s) = Reader.state(core);
        if (!ok || !configOk) revert CoreUnavailable();
    }

    function _ageAt(uint96 units) internal view returns (uint256) {
        uint256 total = ageBase + units;
        return total > coreStart ? total - coreStart : 0;
    }

    function _checkpoint(uint96 units) internal returns (uint256 value) {
        value = _ageAt(units);
        lastSeenAgeUnits = value;
    }

    function _requirePetOwner(uint256 tokenId) internal view {
        if (_requireOwned(tokenId) != msg.sender) revert NotPetOwner();
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (_expeditions[tokenId].away) revert PetAway();
        return super._update(to, tokenId, auth);
    }
}
