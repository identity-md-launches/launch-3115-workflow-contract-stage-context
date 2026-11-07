# Squeeklings

Free on-chain hamster pets on Sepolia (chain ID **11155111**). Each address may hatch one
Squeeklings (`SQLING`) ERC-721, with a lifetime cap of **88,888**. All artwork, metadata,
inventories, expedition results, and capsule rules live on chain. Napping is welcome:
zero-work expeditions receive Dream items, including rare and legendary possibilities.

This repository delivers the **contract implementation stage**: two application contracts,
tests, vendored dependencies, and ABI documentation. The separate manifest and independent
review assignments prepare and review `launch.json`. Publication, attestation, admission,
deployment, and the IPFS website are subsequent service stages. No deployment, wallet access,
or transactions are performed by this project.

## Build and test

Requires Foundry and Solidity **0.8.26**. All Solidity dependencies are included as ordinary
files under `lib/`; no package installation, submodules, RPC, environment variables, or
network are needed to build or test when that compiler is installed.

```sh
forge build
forge test
forge fmt --check
python3 scripts/export_abis.py --check
```

`foundry.toml` pins the requested fuzz seed
`0x67c08e72c8b2f566ab62cce45655ea03e64bfa82c983ea27bd61254c7e483604`,
256 fuzz runs, optimization, IR compilation, Cancun, and `bytecode_hash = "none"`.
There is no FFI or filesystem permission in Foundry. After changing an interface, run
`forge build` and `python3 scripts/export_abis.py` to refresh the ABI exports.

## Deployment parameters

Deploy exactly these two applications in order, with **zero ETH**:

| Order | Solidity contract | Constructor arguments, in order |
| --- | --- | --- |
| 1 | `SqueeklingsArt` | None |
| 2 | `Squeeklings` | `core_`, `art_`, `owner_` (three addresses) |

- `core_`: supplied Sepolia SqueekCore V3, **`0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4`**.
- `art_`: the actual address of the `SqueeklingsArt` deployed immediately before this contract;
  the separate manifest can use `$contract:SqueeklingsArt`.
- `owner_`: the launch owner, written by the manifest as **`$owner`**. The approved workflow
  names no owner address; `$owner` resolves to the wallet the launch terms record as the
  owner (the requester's named owner, else the wallet that paid). This README deliberately
  states no literal so the manifest cannot copy a value the brief did not supply.
  Ownership is explicit and immutable; the factory and transaction origin receive no powers.

Constructors reject zero addresses but make **no external calls** and do not require
dependency code. Runtime validation happens on use. The artwork address is immutable.
The core starts in epoch 1. There is no proxy, initializer, linked library, token distributor,
pool, fungible token, or deployment script that reads keys or broadcasts.

The supplied core's live deployment has not been independently attested here. The implementation
uses the supplied V3 function signatures, with one encoding detail taken from the deployed
contract rather than the brief's prose: the live core returns `roundPage` as **one dynamic
struct** `(uint64 certifiedThroughRound, Point start, Point end, Round[] rounds)`, so a reply
begins with a `0x20` offset word, carries the rounds offset `256` at word 8 and the record count
at word 9, and is `320 + 160 * records` bytes long. `ISqueekCoreV3.RoundPage` declares that
layout and the reader enforces it. `test/LiveCoreLayout.t.sol` replays byte-exact `eth_call`
replies captured from the pinned Sepolia core at block 12,085,427, and the mock returns the same
layout. The launch service/reviewer must still confirm the deployed source and configuration;
tests use captured replies and a deterministic mock, not a live-chain fork.

## Game rules and chosen conventions

`hatch()` is nonpayable and free apart from network gas. IDs begin at 1. Eligibility records
whether an address has **ever hatched**, not whether it currently owns a pet. Transferring a pet
does not restore eligibility. An address can receive multiple pets and can hatch after receiving
one if it has never hatched before. Contract wallets must accept safe ERC-721 minting.

The seed is `keccak256(abi.encode(previousBlockHash, minter, tokenId))`. It chooses one of six
fur palettes and participates in capsule selection. This is the requested deterministic game
randomness, **not a verifiable or manipulation-resistant randomness service**. There are no
payments or monetary rewards. Addresses and hatch timing can be selected; core data producers
influence data hashes. Do not attach financial prizes or paid pulls to this mechanism.

**Dream rolls are predictable in advance.** The specified roll is
`keccak256(entropy, seed, tokenId, endRound) % 100`, and a window with no active rounds has the
constant entropy `keccak256("")`. The seed is public and the end round follows from the embark
round, so a player who embarks while the hamster is idle can compute the capsule a zero-work trip
would open and choose an embark round whose Dream roll is legendary (about one round in ten).
If the hamster works during the trip, it becomes an ordinary Trail draw instead, so the tactic
costs nothing. The published Dream odds are therefore the odds of one untimed roll, not an
upper bound on what a timing player can obtain. This is the approved formula implemented as
written; changing it (for example mixing in a value unknown at embark) would alter the brief's
roll and is left to the requester. Nothing of value is at stake and no fix is applied here.

Global age is `max(ageBase + core.cumulativeBlockUnits - coreStart, 0)`. Initially `ageBase`
and `coreStart` are both zero: the initial age clock uses the core's cumulative origin, and a
pet records that clock at birth. No deployment-time core read or lazy initialization is needed.
Pet age is `max(globalAge - birthUnits, 0) / 1e9`, with integer division. Stages are Pinky below
200 blocks, Fuzz below 2,000, Runner below 10,000, then Elder.

Mood uses the **last six settled rounds**, including settled empty rounds: Napping if total
work is zero, Zoomies if any round has at least 500 work, otherwise Jogging. Wall-clock time
never substitutes for settled history. The core's `paused` flag does not invalidate already
settled data or pause this game.

Routes use indices **0, 1, 2**: Burrow Loop (6 rounds), Meadow Trail (18), Moonlit Ridge (36).
The current round is `(block.timestamp - genesisTimestamp) / roundDuration + 1`. Trips begin
at `currentRound + 1` and end at `startRound + duration - 1`, inclusively. A frontend can show
the expected settlement boundary as `genesisTimestamp + endRound * roundDuration`; actual
settlement may arrive later. Only the NFT's current owner can embark, equip, or unequip;
ERC-721 approvals grant transfers only. Equipment can be changed during a trip.

All transfers, including self-transfers and both safe-transfer overloads, revert `PetAway`
until `returnHome` succeeds. Anyone may return a pet once the end round is settled. A result
always credits its NFT, never the caller. No early exit or duplicate return is possible.
Unreadable history leaves the trip and its loot unchanged and can be retried.

Trip work and blocks come from `roundPage(startRound - 1, startRound - 1, 0).end` and
`roundPage(endRound, endRound, 0).end`. Blocks are **`endUnits / 1e9 - startUnits / 1e9`**,
not `(endUnits - startUnits) / 1e9`. Busiest work is the largest difference between consecutive
active-round cumulative work counters, starting with the trip's boundary point.

Active rounds are paged with limit 16 and the cursor advances to `certifiedThroughRound`,
including certified empty gaps. At most four pages and 36 active records are accepted. The
reader rejects stalled cursors, out-of-order or duplicate records, backward totals, missing
active work, and inconsistent endpoints. The entropy is **one keccak256 over the chronological
concatenation of all active dataHash values** (32 bytes each), independent of page boundaries;
empty history uses `keccak256("")`. No current timestamp, caller, or return-time block enters
the capsule roll. See [the capsule table](docs/LOOT.md) for exact probabilities and encoding.

Inventories count copies of IDs 1–17. They travel with the NFT. Equipping never consumes an
item or removes it from inventory. A return auto-equips the new item only when its corresponding
slot is empty. Slots are 0 head, 1 neck, 2 hand, 3 background. `pet(id)` exposes `pity` and all
four equipped IDs; a zero equipped ID means an empty slot.

## Failure handling and trust

The owner's **only administrative operation** is `setCore(newCore)`. It checks the new core's
configuration and state, preserves readable old age (or its last mutation checkpoint), sets
`coreStart` to the new cumulative units, and increments the epoch. Each older-epoch trip can
immediately return **Lost in the Fog**, receiving one uncommon Compass; pity is unchanged.
This path needs neither core to be readable or settled. Home pets get no migration loot.
Calling with the same core address is rejected. Switching away and back creates new epochs.

This administrator is trusted to select a genuine core. A replacement can affect future age,
moods and capsule results, and turn existing trips into Fog trips, including trips whose end
round is already settled and would otherwise have opened a Trail or Dream capsule. `setCore`
checks only that the candidate decodes with the V3 shape (readable configuration and state,
genesis no later than now, nonzero duration, `1e9` units per block); an owner-authored core
that passes those checks dictates every pet's age, mood and capsule inputs. The game validates
structure and consistency, not the honesty of an external oracle, so launch services should
treat the `$owner` wallet as the game's oracle authority. There is no ownership transfer,
renunciation, pause, arbitrary call, admin mint, inventory grant, price, or withdrawal function.

`lastSeenAgeUnits` records successful hatch, embark, normal return, and core replacement.
Read-only calls cannot update it. If the old core becomes unreadable, age since the last such
checkpoint may be lost on migration. A readable core that moves backwards is clamped according
to the specified formula. Neither accumulated age nor pet age can underflow.

Each core static call has a **500,000 gas** budget. State/config returns must have exact static
ABI sizes; page output is limited to **`320 + 160 * maxRecords` bytes (2,880 at the 16-record
limit)** and its struct offset, rounds offset, record count and field widths are validated
before decoding. Core config
must have a nonzero genesis no later than now, a nonzero duration, canonical field widths,
and `blockUnitsPerBlock == 1e9`. Future-genesis cores are rejected until genesis. A replacement
may be paused; historical reads must still work. Responses that exceed the gas/size bounds
are treated as unavailable rather than copied without limit.

For an existing pet, `tokenURI` returns on-chain Base64 JSON and Base64 SVG even if core
reads fail: it uses the latest readable age or its checkpoint and displays **Signal lost**. If the immutable renderer is
missing, reverts, exhausts its **3,000,000 gas** budget, or returns malformed ABI/oversized data,
the game returns an embedded fallback image. Renderer output is capped at **65,536 bytes**.
Like any EVM view, metadata needs sufficient caller gas; these bounds do not promise success
with arbitrarily little gas. Nonexistent token IDs retain the standard ERC-721 revert.

The SVG uses CSS keyframes for breathing, blinking, Zzz, speed lines and legendary shimmer;
reduced motion is honored. There are no scripts or remote resources. Metadata is dynamic,
so consumers should refresh it as settled core history advances.

No operation accepts ETH, ERC-20, or ERC-721 deposits. There is no receiver callback or funds
accounting. EVM forced ETH and ERC-20 transfers made without receiver consent cannot be
prevented; any such unsolicited assets have no recovery mechanism. Do not send assets here.

## After launch

There are **no missing configuration values or required initialization calls**. The supplied
core, deployed art, and explicit owner fully specify the application.

If Squeekchain migrates, the owner obtains the authentic replacement V3 core address from
Squeekchain's deployment record, verifies its chain, interface, units and history, simulates,
then calls `setCore(address)`. Indexers track `CoreChanged` and expose Fog returns immediately.
Anyone can settle trips through `returnHome`; no operator, funded keeper, backend signer,
subscription, fee recipient, treasury, or separate service key is required.

The launch services publish source, perform independent review, attest and admit the artifact,
deploy the two contracts, verify them on the explorer, and hand the **confirmed** addresses
and ABIs to the frontend. Those service outcomes are not prerequisites of this implementation.
The later frontend must source game state from these contracts. The Squeekchain status API
may animate its wheel/status strip only; it cannot supply age, loot, settlement, or mood.

See [ABI and integration notes](docs/ABI.md), [loot rules](docs/LOOT.md),
[verification and review notes](docs/VERIFICATION.md), and [vendored dependencies](docs/DEPENDENCIES.md).
