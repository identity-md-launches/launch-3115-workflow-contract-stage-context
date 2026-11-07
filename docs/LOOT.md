# Free Seed Capsules

Every successful return credits exactly one item. Duplicate copies count in inventory. There
are no paid pulls, fees, payouts or valuable prizes. A zero-work trip is a Dream trip; running
is never required. Both tables use the same tier odds, pity mechanism, and rarity slots.

## Tier and eligibility

| Trip type | T1 | T2 | T3 | Legendary eligible |
| --- | --- | --- | --- | --- |
| Dream (work = 0) | 6-round route | 18-round route | 36-round route | 36-round route |
| Trail (work > 0) | <40 blocks | 40–199 blocks | ≥200 blocks | busiest round ≥500 work |

The roll is `r = uint256(keccak256(abi.encode(entropy, seed, tokenId, endRound))) % 100`.
All four values are ABI-encoded static words; `endRound` has type `uint64`. The item variant
uses bits 8–15 of the same digest, reduced modulo the number of items in the selected rarity.
This makes the roll fully reproducible; modulo reduction has the tiny/bounded biases inherent
in this specified scheme (three common choices do not divide a byte evenly). These are game
odds, not cryptographic fairness guarantees.

**Dream rolls can be chosen by embark timing.** A zero-work window has no data hashes, so its
entropy is the constant `keccak256("")`; with the public seed and token ID, the only free input
is `endRound`, which the player fixes by choosing when to embark. While the hamster is idle a
player can therefore wait for an embark round whose Dream roll is below 10 (about one round in
ten) and take the 36-round route for a certain Wishing Star, falling back to an ordinary Trail
draw if the hamster works after all. The percentages below describe one untimed roll. This is
the approved formula as written; any change to it is the requester's decision.

Apply the following in order:

1. If eligible and `r < 10`, Legendary.
2. Otherwise, if entering the return with pity ≥5 and the route is 18 or 36 rounds, Rare.
3. Otherwise apply the tier table:

| Tier | Common | Uncommon | Rare |
| --- | --- | --- | --- |
| T1 | all rolls | — | — |
| T2 | 0–59 | 60–99 | — |
| T3 | 0–29 | 30–74 | 75–99 |

Without a pity guarantee, legendary eligibility replaces rolls 0–9: T1 becomes 90% common /
10% legendary; T2 50% common / 40% uncommon / 10% legendary; T3 20% common / 45% uncommon /
25% rare / 10% legendary. With pity active, eligible trips are 10% legendary and 90% rare;
ineligible trips are 100% rare. Dream's tiers depend on the chosen duration rather than work.
These route-dependent tiers are exactly the approved brief; there is no extra running bonus.

Rare or Legendary reset pity to zero. Any other Trail or Dream return adds one, saturating at
`uint32.max`. A 6-round trip can build pity but cannot consume it as a forced rare; naturally
rolled Trail rares or legendaries still reset it. If five consecutive returns were below rare,
the **next** 18/36-round return benefits. Fog gives one Compass, preserving pity exactly.

## Item IDs

| ID | Item | Slot | Rarity | Table |
| --- | --- | --- | --- | --- |
| 1 | Acorn | hand | Common | Trail |
| 2 | Sunflower Seed | hand | Common | Trail |
| 3 | Clover Sprig | head | Common | Trail |
| 4 | Leaf Scarf | neck | Uncommon | Trail |
| 5 | Copper Wheel | background | Uncommon | Trail |
| 6 | Walnut Helmet | head | Rare | Trail |
| 7 | Golden Wheel | background | Rare | Trail |
| 8 | Zoomies Relic | neck | Legendary | Trail |
| 9 | Moon Pebble | hand | Common | Dream |
| 10 | Star Seed | hand | Common | Dream |
| 11 | Nightcap | head | Common | Dream |
| 12 | Dream Scarf | neck | Uncommon | Dream |
| 13 | Cloud Bed | background | Uncommon | Dream |
| 14 | Comet Crown | head | Rare | Dream |
| 15 | Aurora Sky | background | Rare | Dream |
| 16 | Wishing Star | neck | Legendary | Dream |
| 17 | Compass | hand | Uncommon | Lost in the Fog |

Within each table, common uses `choice % 3`, uncommon and rare use `choice % 2`, and legendary
has one choice. Tables start at 1 and 9 respectively. Item 17 is available only from an old
epoch's return, never a normal capsule. Auto-equipping never overwrites an occupied slot.
