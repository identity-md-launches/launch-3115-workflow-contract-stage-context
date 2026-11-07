# Vendored dependencies

All required Solidity files are ordinary files inside this repository. There are no git
submodules, package-manager downloads during verification, runtime network dependencies for
tests, or paths into machine-global library folders.

| Library | Version | Included files | Upstream |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | v5.0.2 | ERC721, ReentrancyGuard, Strings, Base64 and their transitive imports | https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2 |
| forge-std | v1.9.7 | Complete `src/` and licenses | https://github.com/foundry-rs/forge-std/tree/v1.9.7 |

The OpenZeppelin sources are unmodified; their MIT license is
`lib/openzeppelin-contracts/LICENSE`. Forge's licenses are under `lib/forge-std/`.
The downloaded forge-std v1.9.7 source archive had SHA-256
`45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`.
Application imports deliberately use the vendored OpenZeppelin v5 ERC-721 `_update` hook to
enforce the expedition transfer lock on every transfer path. See the
[official ERC-721 documentation](https://docs.openzeppelin.com/contracts/5.x/erc721).
