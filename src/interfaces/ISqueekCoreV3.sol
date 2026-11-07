// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The supplied read-only SqueekCore V3 ABI. Unsettled history is unknown, never zero.
interface ISqueekCoreV3 {
    struct Point {
        uint64 cumulativeWork;
        uint96 cumulativeBlockUnits;
        uint32 auxiliary;
    }

    struct Round {
        uint64 roundId;
        uint64 cumulativeWork;
        uint96 cumulativeBlockUnits;
        uint32 auxiliary;
        bytes32 dataHash;
    }

    function state() external view returns (uint64, uint64, uint96, uint64, uint96, uint32, uint256, bool);

    function configuration()
        external
        view
        returns (bytes32, uint64, uint64, uint64, uint16, address, address, uint32, uint64, uint64, uint96);

    /// @dev The deployed V3 core returns the page as one dynamic struct: the reply begins with a
    /// 0x20 offset word, then certified, start, end, the rounds offset (256) and the record count.
    struct RoundPage {
        uint64 certifiedThroughRound;
        Point start;
        Point end;
        Round[] rounds;
    }

    function roundPage(uint64 afterRound, uint64 throughRound, uint256 maxRecords)
        external
        view
        returns (RoundPage memory page);
}
