# Verification and independent-review handoff

This is the implementation contributor's verification record, **not an independent security
audit or a launch attestation**. The final independent review must inspect the accepted source
and the separate manifest, including the actual constructor references and administrator.

Final local result: **`forge build`, `forge test`, `forge fmt --check`, and the ABI consistency
check passed**. Forge reported 56 passing test groups across eight suites, with no failures or
skips: 55 unit/fuzz tests plus one campaign covering three invariant properties. The final
stateful run executed 4,096 actions with **zero unexpected reverts**. Each of the four fuzz
tests ran 256 cases with the specified seed.

| Application | Runtime bytes | Creation bytecode bytes | External library links |
| --- | ---: | ---: | --- |
| `SqueeklingsArt` | 20,313 | 20,339 | None |
| `Squeeklings` | 17,626 | 18,675 (+96 constructor argument bytes) | None |

## Reproducible checks

```sh
forge build
FOUNDRY_FUZZ_SEED=0x67c08e72c8b2f566ab62cce45655ea03e64bfa82c983ea27bd61254c7e483604 forge test
forge fmt --check
python3 scripts/export_abis.py --check
```

Compiler: 0.8.26, optimizer 200 runs, via IR, Cancun, metadata hash disabled. Dependencies are
vendored. The same fuzz seed is pinned in `foundry.toml`; no test reads or modifies environment
variables, starts a fork, performs a network request, or requires filesystem cheatcodes.

## Coverage

| Suite | Meaningful behavior and failure checks |
| --- | --- |
| `HatchAndOwnership` | Lifetime one-hatch rule, transfer eligibility, last supply slot and rejection, exact seed, ERC-165 interfaces, nonpayable calls, rejecting and reentrant receivers, owner vs operator privileges, constructor validation |
| `Expeditions` | Future start and inclusive end, invalid/duplicate embark, all transfer locks, delayed settlement, one return only, 36 active rounds, sparse certified gaps, exact fractional-block rounding, complete hash entropy, malformed pages, four-page limit, outage/retry, six-return pity sequence, random trip work |
| `CoreAgeMood` | All age boundaries, birth offset, negative-age clamps, live and unreadable-core migrations, invalid configuration and unauthorized migration, Fog independent of either core, later epoch trips, last six settled rounds, 499/500 threshold, calendar overflow, fuzzed age continuity |
| `Loot` | All 100 roll buckets at each tier, exact rarity boundaries, Dream and Trail tables, legendary precedence over pity, all 16 regular items reachable, Fog, saturating pity, fuzzed table and pity consistency |
| `Inventory` | Exact 17-item catalogue, slot mapping, ownership checks, absent/invalid items, auto-equip versus occupied slots, no consumption on equip, inventory and equipment following transfers |
| `MetadataAndFaults` | Base64 decoding and JSON parsing, SVG equality and embedded assets, six palettes, stages and all equipment, CSS/reduced motion, signal loss, malformed/truncated/noncanonical core ABI, oversized returns, gas burning, renderer fallback, fuzzed arbitrary core payloads |
| `Deployment` | CREATE2 deployment in one factory call with no pre-existing core code, explicit supplied launch owner, both runtime sizes and initcode sizes, reachable-opcode scan matching the provided floor's method |
| `Stateful` | Production contracts under mixed route, return, transfer, dress, migration and duplicate-hatch actions; exactly one item per completed return, valid equipped inventory slots, constant minted supply, ownership balances, epochs, no funds |

Stateful testing uses 64 runs at depth 64 (4,096 handler actions), with unexpected reverts
configured to **fail** the campaign. Intentional invalid transfers and duplicate hatches are
checked inside the handler. No artificial mint, pity or inventory setters exist in the production
contracts; isolated unit tests use a clearly separate test-only harness for cap and extreme-value
boundaries. The stateful campaign uses the unmodified production `Squeeklings`.

The mock implements cumulative point snapshots and active-round paging with a binary search.
It can certify gaps beyond the last returned active round, return either full or deliberately
partial pages, and fail or corrupt each read family. Tests compare returned history to independently
accumulated work, block endpoints, and the chronological data-hash list. No mock proves that
the actual supplied core is honest, deployed, or byte-for-byte compatible.

## Review observations and operational responsibilities

- Constructor dependency reads are absent. All three game constructor parameters are static
  addresses; the renderer has none. Libraries are internal/inlined. Both applications are
  below EIP-170's 24,576-byte runtime limit and the 49,152-byte initcode limit.
- Production source has no payable function, proxy, initializer, delegatecall, selfdestruct,
  arbitrary executor, admin mint, admin item grant, custody accounting, or withdrawal.
- Mutation follows checks/effects before the safe-mint receiver callback, and the callback
  paths are guarded. Core and art interactions are static calls. No token or ETH transfer occurs.
- Native integer widths and explicit bounds guard decoding, calendar arithmetic, page sizes,
  monotonic history, stage thresholds and pity overflow. The trip-block floor division is
  intentionally performed separately at both endpoints, as required.
- The specified deterministic seed/entropy mechanism is not VRF. It is suitable only for this
  free, no-value testnet game under its documented trust model. The core authority and the
  launch owner can influence outcomes. A runtime structure check cannot prove oracle honesty.
- `setCore` can end old trips in Fog. If the old core is unreadable, only the last mutation's
  age checkpoint survives. Core outage leaves current-epoch trips locked until reads recover
  or the owner selects a valid replacement. There is no arbitrary timeout settlement.
- Metadata fallbacks cover existing pets with adequate view gas; unknown IDs correctly use
  the ERC-721 nonexistent-token error. Consumers need to refresh dynamic metadata as the
  core settles new history, even without an NFT event.
- The separate reviewer and deployment service confirm the actual supplied Sepolia core ABI
  and config, the art reference, the `$owner` mapping, and final artifact bytes. They handle
  publication, signed linkage, admission, broadcast, and explorer verification. No manifest,
  attestation, deployment claim, private key, or guessed contract address is produced here.

Slither, Mythril, a live-chain fork, and an independent audit were not run in this assignment.
The local security review and Foundry results do not replace the required independent stage.
