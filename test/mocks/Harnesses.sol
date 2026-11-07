// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Squeeklings} from "../../src/Squeeklings.sol";
import {SqueekLoot} from "../../src/libraries/SqueekLoot.sol";
import {SqueekCoreReader as Reader} from "../../src/libraries/SqueekCoreReader.sol";
import {Loot} from "../../src/SqueekTypes.sol";

contract SqueeklingsHarness is Squeeklings {
    constructor(address core_, address art_, address owner_) Squeeklings(core_, art_, owner_) {}

    function setSupply(uint256 value) external {
        totalSupply = value;
    }

    function setPity(uint256 id, uint32 value) external {
        _pets[id].pity = value;
    }

    function giveItem(uint256 id, uint8 item) external {
        ++_inventory[id][item];
    }
}

contract ReaderHarness {
    function history(address core, uint64 afterRound, uint64 throughRound)
        external
        view
        returns (bool, Reader.History memory)
    {
        return Reader.history(core, afterRound, throughRound);
    }

    function page(address core, uint64 afterRound, uint64 throughRound, uint256 limit)
        external
        view
        returns (bool, Reader.Page memory)
    {
        return Reader.page(core, afterRound, throughRound, limit);
    }
}

contract LootHarness {
    function draw(bytes32 digest, uint8 route, uint64 work, uint96 blocks, uint64 busiest, uint32 pity)
        external
        pure
        returns (Loot memory)
    {
        return SqueekLoot.draw(digest, route, work, blocks, busiest, pity);
    }
}

contract GasBurner {
    fallback() external {
        assembly ("memory-safe") { for {} 1 {} {} }
    }
}

contract LargeReturn {
    fallback() external {
        assembly ("memory-safe") { return(0, 100000) }
    }
}
