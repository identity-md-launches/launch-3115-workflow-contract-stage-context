// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

enum Stage {
    Pinky,
    Fuzz,
    Runner,
    Elder
}
enum Mood {
    Napping,
    Jogging,
    Zoomies
}
enum Kind {
    Trail,
    Dream,
    Fog
}
enum Rarity {
    Common,
    Uncommon,
    Rare,
    Legendary
}
enum Slot {
    Head,
    Neck,
    Hand,
    Background
}

struct Pet {
    bytes32 seed;
    uint256 birthUnits;
    uint32 pity;
    uint8[4] equipped;
}

struct Expedition {
    uint64 startRound;
    uint64 endRound;
    uint64 epoch;
    uint8 route;
    bool away;
}

struct PetView {
    bytes32 seed;
    uint256 ageBlocks;
    uint32 pity;
    Stage stage;
    Mood mood;
    bool away;
    bool signalLost;
    uint8[4] equipped;
}

struct Loot {
    uint8 itemId;
    Kind kind;
    Rarity rarity;
    uint32 pity;
}
