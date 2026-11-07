// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ISqueekCoreV3} from "../../src/interfaces/ISqueekCoreV3.sol";

/// @notice Cumulative history with real sparse paging and point reads, independent of game logic.
contract MockSqueekCore is ISqueekCoreV3 {
    uint64 public genesis;
    uint64 public duration = 60;
    uint96 public unitsPerBlock = 1e9;
    uint64 public settled;
    uint64 public work;
    uint96 public units;
    bool public paused;
    bool public failState;
    bool public failConfig;
    bool public failPage;
    bool public certifyGaps = true;
    uint8 public badPage;
    uint8 public pageCap = 16;
    mapping(uint64 => Point) internal points;
    Round[] internal active;

    constructor(uint64 genesis_) {
        genesis = genesis_;
    }

    function setConfiguration(uint64 genesis_, uint64 duration_, uint96 unitsPerBlock_) external {
        genesis = genesis_;
        duration = duration_;
        unitsPerBlock = unitsPerBlock_;
    }

    function setFaults(bool state_, bool config_, bool page_) external {
        failState = state_;
        failConfig = config_;
        failPage = page_;
    }

    function setPaused(bool value) external {
        paused = value;
    }

    function setBadPage(uint8 value) external {
        badPage = value;
    }

    function setCertifyGaps(bool value) external {
        certifyGaps = value;
    }

    function setPageCap(uint8 value) external {
        require(value > 0 && value <= 16);
        pageCap = value;
    }

    /// @dev Age-only fault simulation, including a core moving backwards.
    function setUnits(uint96 value) external {
        units = value;
        points[settled].cumulativeBlockUnits = value;
    }

    function append(uint64 addedWork, uint96 addedUnits, bytes32 dataHash) external {
        require(addedWork > 0 || addedUnits == 0, "empty rounds have no units");
        ++settled;
        work += addedWork;
        units += addedUnits;
        points[settled] = Point(work, units, 0);
        if (addedWork > 0) active.push(Round(settled, work, units, 0, dataHash));
    }

    function state() external view returns (uint64, uint64, uint96, uint64, uint96, uint32, uint256, bool) {
        require(!failState, "state offline");
        return (settled, work, units, 0, 0, 0, 0, paused);
    }

    function configuration()
        external
        view
        returns (bytes32, uint64, uint64, uint64, uint16, address, address, uint32, uint64, uint64, uint96)
    {
        require(!failConfig, "config offline");
        return
            (
                keccak256("mock-v3"),
                genesis,
                duration,
                0,
                0,
                address(this),
                address(this),
                0,
                0,
                0,
                unitsPerBlock
            );
    }

    /// @dev Returns one dynamic struct, exactly as the deployed Sepolia V3 core encodes its reply.
    function roundPage(uint64 afterRound, uint64 throughRound, uint256 maxRecords)
        external
        view
        returns (RoundPage memory page)
    {
        (page.certifiedThroughRound, page.start, page.end, page.rounds) =
            _roundPage(afterRound, throughRound, maxRecords);
    }

    function _roundPage(uint64 afterRound, uint64 throughRound, uint256 maxRecords)
        internal
        view
        returns (uint64 certified, Point memory start, Point memory end, Round[] memory rounds)
    {
        require(!failPage, "pages offline");
        require(maxRecords <= 16 && afterRound <= throughRound && throughRound <= settled, "bad request");
        start = points[afterRound];
        certified = throughRound;
        if (maxRecords == 0) return (certified, start, points[throughRound], new Round[](0));
        if (maxRecords > pageCap) maxRecords = pageCap;
        // Binary search to the first active round strictly after the cursor.
        uint256 low;
        uint256 high = active.length;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (active[mid].roundId <= afterRound) low = mid + 1;
            else high = mid;
        }
        rounds = new Round[](maxRecords);
        uint256 count;
        for (uint256 i = low; i < active.length; ++i) {
            if (active[i].roundId > throughRound) break;
            if (count == maxRecords) {
                certified = certifyGaps ? active[i].roundId - 1 : active[i - 1].roundId;
                break;
            }
            rounds[count++] = active[i];
        }
        assembly ("memory-safe") { mstore(rounds, count) }
        end = points[certified];
        if (badPage == 1) certified = afterRound;
        if (badPage == 2 && count > 0) rounds[0].roundId = afterRound;
        if (badPage == 3 && count > 1) rounds[1] = rounds[0];
        if (badPage == 4 && count > 0) rounds[0].cumulativeWork = start.cumulativeWork;
        if (badPage == 5) ++end.cumulativeBlockUnits;
        if (badPage == 6) certified = throughRound + 1;
        if (badPage == 7 && count > 0) rounds[count - 1].roundId = throughRound + 1;
        if (badPage == 8) ++start.cumulativeWork;
    }
}
