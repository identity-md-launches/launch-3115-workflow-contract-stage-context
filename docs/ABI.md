# Contract ABI and frontend handoff

The complete machine-readable ABIs are [Squeeklings.json](abi/Squeeklings.json) and
[SqueeklingsArt.json](abi/SqueeklingsArt.json). Generated from Solidity 0.8.26 artifacts using
`python3 scripts/export_abis.py`; `--check` compares them with the current build. All monetary
transaction values are **zero**. Use the launch's confirmed addresses; no guessed addresses
or precomputed deployment addresses are provided here.

## Player transactions

| Call | Caller | Result / requirements |
| --- | --- | --- |
| `hatch()` → `uint256 tokenId` | Any address that has never hatched | One safe-minted pet; cap 88,888 |
| `embark(uint256 tokenId, uint8 route)` | NFT owner | Routes 0/1/2, home pet, readable core |
| `returnHome(uint256 tokenId)` → `Loot` | Anyone | Settled current-epoch trip or any older-epoch trip; one item |
| `equip(uint256 tokenId, uint8 itemId)` | NFT owner | Item 1–17 already in that pet's inventory |
| `unequip(uint256 tokenId, uint8 slot)` | NFT owner | Slot 0–3; idempotent when already empty |
| ERC-721 `approve`, `setApprovalForAll`, transfer functions | Standard ERC-721 authorization | All transfers locked while away |

`Loot` is `(uint8 itemId, Kind kind, Rarity rarity, uint32 pity)`. Kind values are 0 Trail,
1 Dream, 2 Fog. Rarity values are 0 Common, 1 Uncommon, 2 Rare, 3 Legendary. Fog's human label
is **Lost in the Fog**. There are no separate item NFTs or fungible balances to transfer.

Simulate writes before prompting the wallet. Successful return data from simulation predicts
the capsule using already-settled history, but a concurrent core replacement can change the
outcome to Fog. Treat the transaction's actual `Returned` event as authoritative for reveal.

## Read methods

| Method | Meaning |
| --- | --- |
| `totalSupply()`, `MAX_SUPPLY()`, `hasHatched(address)` | Mint eligibility and supply |
| `ownerOf(id)`, `balanceOf(address)`, approvals, `supportsInterface(bytes4)` | Standard ERC-721 / ERC-165 |
| `pet(id)` → `Pet` | Seed, birth units, pity, four equipped IDs |
| `expedition(id)` → `Expedition` | Last route, boundaries and epoch, plus the current away flag |
| `inventory(id)` → `uint256[17]` | Copy counts; index 0 is item 1, index 16 is item 17 |
| `itemBalanceOf(id, itemId)` | Count of one item, including equipped copies |
| `itemInfo(itemId)` | `(string name, Slot slot, Rarity rarity, Kind kind)` |
| `ageUnits()` | Global age clock with unreadable-state fallback |
| `ageBlocks(id)`, `stage(id)`, `stageForAge(blocks)` | Pet age and stage (0 Pinky, 1 Fuzz, 2 Runner, 3 Elder) |
| `mood()` | `(Mood value, bool signalLost)`; values 0 Napping, 1 Jogging, 2 Zoomies |
| `currentRound()` | Current wall-clock round; reverts if config is unavailable |
| `routeRounds(route)` | 6, 18, or 36 |
| `displayData(id)` | Aggregated `PetView` used by the artwork |
| `tokenURI(id)` | Base64 JSON containing a Base64 SVG; no HTTP asset fetch |
| `core()`, `art()`, `owner()`, `coreEpoch()` | Active dependencies and explicit administrator |
| `ageBase()`, `coreStart()`, `lastSeenAgeUnits()` | Age migration/checkpoint details |

`Pet = (bytes32 seed, uint256 birthUnits, uint32 pity, uint8[4] equipped)`.
`Expedition = (uint64 startRound, uint64 endRound, uint64 epoch, uint8 route, bool away)`.
`PetView = (bytes32 seed, uint256 ageBlocks, uint32 pity, Stage stage, Mood mood, bool away,
bool signalLost, uint8[4] equipped)`. Enum values are ABI `uint8`. Slots are head, neck,
hand, background, in that order. Render `pity >= 5` as a full meter without hiding the actual
count; short trips can increase it beyond five.

The renderer exposes `render(uint256 tokenId, PetView data)` → data URI and
`svg(PetView data)` → raw SVG. Both are pure, deterministic, and usable directly by an indexer.

## Events and indexing

- `Hatched(address indexed minter, uint256 indexed tokenId, bytes32 seed, uint256 birthUnits)`.
- `Embarked(uint256 indexed tokenId, address indexed petOwner, uint8 route,
  uint64 startRound, uint64 endRound, uint64 epoch)`.
- `Returned(uint256 indexed tokenId, address indexed petOwner, uint8 itemId, Kind kind,
  Rarity rarity, uint64 work, uint96 blocks, uint64 busiest, bytes32 entropy, uint32 pity)`.
- `Equipped(uint256 indexed tokenId, Slot indexed slot, uint8 itemId)`: 0 means cleared;
  automatic equipment changes emit this event too.
- `CoreChanged(address indexed oldCore, address indexed newCore, uint64 epoch,
  uint256 ageBase, uint96 coreStart)`.
- Standard ERC-721 `Transfer`, `Approval`, and `ApprovalForAll`.

Index `Transfer` from the deployment block to derive current ownership and combine it with
`Hatched`, `Embarked`, and `Returned` for the Meadow and expedition log. No ERC721Enumerable
extension or unbounded owner enumeration is included. Global mood/age can change with core
settlement without a game transaction; polling views is necessary in addition to indexing logs.
Reconcile reorganizations using canonical block hashes. The frontend's 150-pet display limit
is its own bounded query policy, not an on-chain supply limit.

## Trip UI states

1. `away == false`: Home.
2. `trip.epoch != coreEpoch`: Ready, Lost in the Fog; no core read needed.
3. Current epoch and `settledThroughRound >= endRound`: Ready.
4. Otherwise, if current time is below `genesisTimestamp + endRound * roundDuration`: Away.
5. Otherwise: Waiting for settlement. Unknown work must not be displayed as zero.

If core reads fail, retain the trip and show Signal lost. Prefer this message to inventing a
work amount, a progress result, or an unavailable settlement status. After a return receipt,
animate the Seed Capsule and use the event's actual item ID and rarity. A failed simulation
or transaction does not consume a capsule or erase the trip.

## Error messages

| Error | Suggested player message |
| --- | --- |
| `AlreadyHatched` | This address has already hatched its free pet. |
| `SupplyCap` | All 88,888 pets have hatched. |
| `NotPetOwner` / ERC-721 insufficient approval | Use the wallet that owns this pet (or its approved transfer operator). |
| `PetAway` | Your pet is on an expedition. Return it home before transferring or departing again. |
| `PetAtHome` | Your pet is already home. |
| `NotSettledYet(needed, settled)` | Waiting for Squeekchain to settle through round `needed`. |
| `CoreUnavailable` / `InvalidHistory` | Signal lost. Your pet and inventory are safe; try again later. |
| `InvalidRoute` / `InvalidSlot` / `InvalidItem` | This choice is not available. Refresh the available choices. |
| `ItemNotOwned` | This pet does not have that item. |
| ERC-721 nonexistent token | This pet has not hatched. |

Owner-only errors are `OnlyOwner`, `InvalidAddress`, `InvalidCore`, and `CoreUnchanged`.
`RoundOverflow` rejects a calendar that cannot fit `uint64` round IDs. There is no owner API
other than `setCore(address)`. Consult the ABI for inherited ERC-721 and reentrancy errors.
