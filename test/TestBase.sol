// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Squeeklings} from "../src/Squeeklings.sol";
import {SqueeklingsArt} from "../src/SqueeklingsArt.sol";
import {MockSqueekCore} from "./mocks/MockSqueekCore.sol";
import {SqueeklingsHarness} from "./mocks/Harnesses.sol";
import {Expedition, Pet, Loot, Rarity, Kind, Mood, Stage, Slot, PetView} from "../src/SqueekTypes.sol";

abstract contract SqueekTestBase is Test {
    uint64 internal constant GENESIS = 1_000_000;
    uint64 internal constant ROUND_SECONDS = 60;
    MockSqueekCore internal core;
    SqueeklingsArt internal art;
    SqueeklingsHarness internal game;
    address internal admin;
    address internal alice;
    address internal bob;

    function setUp() public virtual {
        vm.warp(GENESIS);
        vm.roll(100);
        admin = makeAddr("launch-owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        core = new MockSqueekCore(GENESIS);
        art = new SqueeklingsArt();
        game = new SqueeklingsHarness(address(core), address(art), admin);
    }

    function hatch(address who) internal returns (uint256) {
        vm.prank(who);
        return game.hatch();
    }

    function embark(uint256 id, uint8 route) internal returns (Expedition memory) {
        vm.prank(game.ownerOf(id));
        game.embark(id, route);
        return game.expedition(id);
    }

    function settleEmpty(uint64 through) internal {
        while (core.settled() < through) core.append(0, 0, bytes32(0));
    }

    function advance() internal {
        vm.warp(GENESIS + uint256(core.settled()) * ROUND_SECONDS);
    }

    function inventoryTotal(uint256 id) internal view returns (uint256 total) {
        uint256[17] memory counts = game.inventory(id);
        for (uint256 i; i < 17; ++i) {
            total += counts[i];
        }
    }

    function decodeDataURI(string memory uri) internal pure returns (string memory) {
        bytes memory data = bytes(uri);
        uint256 comma;
        while (comma < data.length && data[comma] != ",") ++comma;
        require(comma < data.length, "missing data URI comma");
        uint256 offset = comma + 1;
        require((data.length - offset) % 4 == 0, "base64 length");
        uint256 size = (data.length - offset) / 4 * 3;
        if (data[data.length - 1] == "=") --size;
        if (data[data.length - 2] == "=") --size;
        bytes memory decoded = new bytes(size);
        uint256 cursor;
        for (uint256 i = offset; i < data.length; i += 4) {
            uint256 value = (_base64Digit(data[i]) << 18) | (_base64Digit(data[i + 1]) << 12)
                | (_base64Digit(data[i + 2]) << 6) | _base64Digit(data[i + 3]);
            if (cursor < size) decoded[cursor++] = bytes1(uint8(value >> 16));
            if (cursor < size) decoded[cursor++] = bytes1(uint8(value >> 8));
            if (cursor < size) decoded[cursor++] = bytes1(uint8(value));
        }
        return string(decoded);
    }

    function _base64Digit(bytes1 ch) private pure returns (uint256) {
        uint8 c = uint8(ch);
        if (c >= 65 && c <= 90) return c - 65;
        if (c >= 97 && c <= 122) return c - 71;
        if (c >= 48 && c <= 57) return c + 4;
        if (ch == "+") return 62;
        if (ch == "/") return 63;
        require(ch == "=", "bad base64 character");
        return 0;
    }

    function contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;
        for (uint256 i; i <= h.length - n.length; ++i) {
            bool match_ = true;
            for (uint256 j; j < n.length; ++j) {
                if (h[i + j] != n[j]) {
                    match_ = false;
                    break;
                }
            }
            if (match_) return true;
        }
        return false;
    }
}
