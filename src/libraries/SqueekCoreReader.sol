// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ISqueekCoreV3} from "../interfaces/ISqueekCoreV3.sol";

/// @notice Bounded, defensive decoding keeps malformed or gas-burning cores out of metadata paths.
library SqueekCoreReader {
    uint256 internal constant UNITS_PER_BLOCK = 1e9;
    uint256 internal constant READ_GAS = 500_000;
    uint256 internal constant MAX_ROUNDS = 36;

    struct State {
        uint64 settled;
        uint64 work;
        uint96 units;
        bool paused;
    }

    struct Config {
        uint64 genesis;
        uint64 duration;
    }

    /// @dev Fixed part of a roundPage reply: offset word, certified, two points, rounds offset, count.
    uint256 internal constant PAGE_HEAD = 320;
    uint256 internal constant RECORD_BYTES = 160;

    struct Page {
        uint64 certified;
        ISqueekCoreV3.Point start;
        ISqueekCoreV3.Point end;
        ISqueekCoreV3.Round[] rounds;
    }

    struct History {
        uint64 work;
        uint96 blocks;
        uint64 busiest;
        bytes32 entropy;
    }

    /// @dev The EVM copies at most maxBytes, including when the callee returns a huge buffer.
    function boundedCall(address target, bytes memory input, uint256 maxBytes, uint256 gasLimit)
        internal
        view
        returns (bool ok, bytes memory data)
    {
        data = new bytes(maxBytes);
        uint256 size;
        assembly ("memory-safe") {
            ok := staticcall(gasLimit, target, add(input, 32), mload(input), add(data, 32), maxBytes)
            size := returndatasize()
        }
        if (!ok || size > maxBytes) return (false, new bytes(0));
        assembly ("memory-safe") { mstore(data, size) }
    }

    function word(bytes memory data, uint256 index) internal pure returns (uint256 value) {
        assembly ("memory-safe") { value := mload(add(add(data, 32), mul(index, 32))) }
    }

    function state(address core) internal view returns (bool ok, State memory s) {
        bytes memory data;
        (ok, data) = boundedCall(core, abi.encodeCall(ISqueekCoreV3.state, ()), 256, READ_GAS);
        if (!ok || data.length != 256) return (false, s);
        if (
            word(data, 0) > type(uint64).max || word(data, 1) > type(uint64).max
                || word(data, 2) > type(uint96).max || word(data, 3) > type(uint64).max
                || word(data, 4) > type(uint96).max || word(data, 5) > type(uint32).max || word(data, 7) > 1
        ) return (false, s);
        s = State(uint64(word(data, 0)), uint64(word(data, 1)), uint96(word(data, 2)), word(data, 7) == 1);
    }

    function config(address core) internal view returns (bool ok, Config memory c) {
        bytes memory data;
        (ok, data) = boundedCall(core, abi.encodeCall(ISqueekCoreV3.configuration, ()), 352, READ_GAS);
        if (!ok || data.length != 352) return (false, c);
        if (
            word(data, 1) == 0 || word(data, 1) > block.timestamp || word(data, 1) > type(uint64).max
                || word(data, 2) == 0 || word(data, 2) > type(uint64).max || word(data, 3) > type(uint64).max
                || word(data, 4) > type(uint16).max || word(data, 5) > type(uint160).max
                || word(data, 6) > type(uint160).max || word(data, 7) > type(uint32).max
                || word(data, 8) > type(uint64).max || word(data, 9) > type(uint64).max
                || word(data, 10) != UNITS_PER_BLOCK
        ) return (false, c);
        c = Config(uint64(word(data, 1)), uint64(word(data, 2)));
    }

    function _validPoint(bytes memory data, uint256 offset) private pure returns (bool) {
        return word(data, offset) <= type(uint64).max && word(data, offset + 1) <= type(uint96).max
            && word(data, offset + 2) <= type(uint32).max;
    }

    function page(address core, uint64 afterRound, uint64 throughRound, uint256 limit)
        internal
        view
        returns (bool ok, Page memory p)
    {
        bytes memory data;
        (ok, data) = boundedCall(
            core,
            abi.encodeCall(ISqueekCoreV3.roundPage, (afterRound, throughRound, limit)),
            PAGE_HEAD + limit * RECORD_BYTES,
            READ_GAS
        );
        if (!ok || data.length < PAGE_HEAD) return (false, p);
        // Single-struct layout, as the deployed V3 core encodes it: word 0 is the struct offset (32),
        // word 1 certified, words 2-4 start, words 5-7 end, word 8 the rounds offset (256) relative to
        // the struct, word 9 the record count, then five words per record.
        uint256 count = word(data, 9);
        if (
            word(data, 0) != 32 || word(data, 8) != 256 || count > limit
                || data.length != PAGE_HEAD + count * RECORD_BYTES || word(data, 1) < afterRound
                || word(data, 1) > throughRound || !_validPoint(data, 2) || !_validPoint(data, 5)
        ) return (false, p);
        for (uint256 i; i < count; ++i) {
            uint256 offset = 10 + i * 5;
            if (word(data, offset) > type(uint64).max || !_validPoint(data, offset + 1)) return (false, p);
        }
        ISqueekCoreV3.RoundPage memory decoded = abi.decode(data, (ISqueekCoreV3.RoundPage));
        p = Page(decoded.certifiedThroughRound, decoded.start, decoded.end, decoded.rounds);
    }

    function _same(ISqueekCoreV3.Point memory a, ISqueekCoreV3.Point memory b) private pure returns (bool) {
        return a.cumulativeWork == b.cumulativeWork && a.cumulativeBlockUnits == b.cumulativeBlockUnits;
    }

    /// @notice Scans at most 36 rounds, 16 active records/page, at most four pages.
    /// Entropy is keccak256 of the chronological concatenation of every active round's dataHash.
    function history(address core, uint64 afterRound, uint64 throughRound)
        internal
        view
        returns (bool ok, History memory h)
    {
        if (throughRound < afterRound || throughRound - afterRound > MAX_ROUNDS) return (false, h);
        (bool startOk, Page memory first) = page(core, afterRound, afterRound, 0);
        (bool endOk, Page memory last) = page(core, throughRound, throughRound, 0);
        if (!startOk || !endOk || !_same(first.start, first.end) || !_same(last.start, last.end)) {
            return (false, h);
        }
        if (
            last.end.cumulativeWork < first.end.cumulativeWork
                || last.end.cumulativeBlockUnits < first.end.cumulativeBlockUnits
        ) {
            return (false, h);
        }
        h.work = last.end.cumulativeWork - first.end.cumulativeWork;
        h.blocks = last.end.cumulativeBlockUnits / uint96(UNITS_PER_BLOCK) - first.end.cumulativeBlockUnits
            / uint96(UNITS_PER_BLOCK);
        bytes memory hashes = new bytes(MAX_ROUNDS * 32);
        uint256 count;
        uint64 cursor = afterRound;
        ISqueekCoreV3.Point memory running = first.end;
        for (uint256 i; i < 4 && cursor < throughRound; ++i) {
            (bool pageOk, Page memory p) = page(core, cursor, throughRound, 16);
            if (!pageOk || p.certified <= cursor || !_same(p.start, running)) return (false, h);
            uint64 previousRound = cursor;
            for (uint256 j; j < p.rounds.length; ++j) {
                ISqueekCoreV3.Round memory r = p.rounds[j];
                if (
                    count >= MAX_ROUNDS || r.roundId <= previousRound || r.roundId > p.certified
                        || r.cumulativeWork <= running.cumulativeWork
                        || r.cumulativeBlockUnits < running.cumulativeBlockUnits
                ) return (false, h);
                uint64 work = r.cumulativeWork - running.cumulativeWork;
                if (work > h.busiest) h.busiest = work;
                bytes32 dataHash = r.dataHash;
                assembly ("memory-safe") { mstore(add(add(hashes, 32), mul(count, 32)), dataHash) }
                ++count;
                previousRound = r.roundId;
                running = ISqueekCoreV3.Point(r.cumulativeWork, r.cumulativeBlockUnits, r.auxiliary);
            }
            if (!_same(p.end, running)) return (false, h);
            cursor = p.certified;
        }
        if (cursor != throughRound || !_same(running, last.end)) return (false, h);
        assembly ("memory-safe") { mstore(hashes, mul(count, 32)) }
        h.entropy = keccak256(hashes);
        return (true, h);
    }
}
