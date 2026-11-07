// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Kind, Rarity, Slot, Loot} from "../SqueekTypes.sol";

/// @notice The fixed, free capsule tables. All functions inline; there are no linked libraries.
library SqueekLoot {
    error InvalidItem();

    function draw(bytes32 digest, uint8 route, uint64 work, uint96 blocks, uint64 busiest, uint32 pity)
        internal
        pure
        returns (Loot memory result)
    {
        bool dream = work == 0;
        result.kind = dream ? Kind.Dream : Kind.Trail;
        uint256 tier = dream ? uint256(route) + 1 : blocks < 40 ? 1 : blocks < 200 ? 2 : 3;
        bool eligible = dream ? route == 2 : busiest >= 500;
        uint256 roll = uint256(digest) % 100;
        if (eligible && roll < 10) {
            result.rarity = Rarity.Legendary;
        } else if (pity >= 5 && route >= 1) {
            result.rarity = Rarity.Rare;
        } else if (tier == 1 || (tier == 2 && roll < 60) || (tier == 3 && roll < 30)) {
            result.rarity = Rarity.Common;
        } else if (tier == 2 || roll < 75) {
            result.rarity = Rarity.Uncommon;
        } else {
            result.rarity = Rarity.Rare;
        }

        uint256 choice = uint8(uint256(digest) >> 8);
        uint8 index;
        if (result.rarity == Rarity.Common) index = uint8(1 + choice % 3);
        else if (result.rarity == Rarity.Uncommon) index = uint8(4 + choice % 2);
        else if (result.rarity == Rarity.Rare) index = uint8(6 + choice % 2);
        else index = 8;
        result.itemId = index + (dream ? 8 : 0);
        if (result.rarity < Rarity.Rare) {
            result.pity = pity == type(uint32).max ? pity : pity + 1;
        }
    }

    function fog(uint32 pity) internal pure returns (Loot memory) {
        return Loot(17, Kind.Fog, Rarity.Uncommon, pity);
    }

    function info(uint8 id) internal pure returns (string memory name, Slot slot, Rarity rarity, Kind kind) {
        if (id == 0 || id > 17) revert InvalidItem();
        if (id == 17) return ("Compass", Slot.Hand, Rarity.Uncommon, Kind.Fog);
        kind = id > 8 ? Kind.Dream : Kind.Trail;
        uint8 index = id > 8 ? id - 8 : id;
        rarity = index <= 3
            ? Rarity.Common
            : index <= 5 ? Rarity.Uncommon : index <= 7 ? Rarity.Rare : Rarity.Legendary;
        slot = index <= 2
            ? Slot.Hand
            : index == 3 || index == 6 ? Slot.Head : index == 4 || index == 8 ? Slot.Neck : Slot.Background;
        if (id == 1) name = "Acorn";
        else if (id == 2) name = "Sunflower Seed";
        else if (id == 3) name = "Clover Sprig";
        else if (id == 4) name = "Leaf Scarf";
        else if (id == 5) name = "Copper Wheel";
        else if (id == 6) name = "Walnut Helmet";
        else if (id == 7) name = "Golden Wheel";
        else if (id == 8) name = "Zoomies Relic";
        else if (id == 9) name = "Moon Pebble";
        else if (id == 10) name = "Star Seed";
        else if (id == 11) name = "Nightcap";
        else if (id == 12) name = "Dream Scarf";
        else if (id == 13) name = "Cloud Bed";
        else if (id == 14) name = "Comet Crown";
        else if (id == 15) name = "Aurora Sky";
        else name = "Wishing Star";
    }
}
