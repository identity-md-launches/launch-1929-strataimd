# StrataIMD (STRATA)

A plain, fixed-supply ERC-20 token for an IMD custom-token launch on Ethereum.

| Parameter | Value |
|-----------|-------|
| Solidity contract | `StrataToken` (`src/StrataToken.sol`) |
| Token name | `StrataIMD` |
| Token symbol | `STRATA` |
| Decimals | 18 |
| Total supply | 1,000,000,000 STRATA = `1000000000000000000000000000` minor units |
| Minting | Once, in the constructor, the whole supply to `msg.sender` (the deployer) |
| Constructor arguments | None |
| Owner / admin | None |

The contract name `StrataToken` is the launch's record name (11 characters, within the 32-character
limit). The token's name and symbol are what `name()` and `symbol()` return.

## Layout

```
foundry.toml                   Foundry configuration (solc 0.8.26, bytecode_hash = "none")
src/StrataToken.sol            The token
src/interfaces/IERC20.sol      ERC-20 interface and ERC-6093 errors
test/StrataToken.t.sol         Unit and fuzz tests for every ERC-20 path
test/StrataTokenLaunch.t.sol   The launch flows against a factory-like deployer
test/utils/Vm.sol              The subset of forge's cheatcode interface the tests use
test/utils/TestBase.sol        Cheatcode handle and reverting assertions
```

The project has no external dependencies. The token implements ERC-20 directly, following the
semantics and the ERC-6093 custom errors of OpenZeppelin's ERC20 v5, and the tests declare the
handful of forge cheatcodes they use instead of vendoring forge-std. Nothing is linked, so the
runtime bytecode is complete as built.

## Behaviour

- `transfer`, `approve`, `transferFrom`, `allowance`, `balanceOf`, `totalSupply`, `name`,
  `symbol`, `decimals`: standard ERC-20. Every transfer moves exactly the amount requested; there
  is no fee, tax, reflection or burn on transfer.
- `transferFrom` spends the caller's allowance first. An allowance of `type(uint256).max` is
  unlimited and is not decreased. Spending an allowance does not emit `Approval`.
- Failures revert with ERC-6093 errors: `ERC20InsufficientBalance`, `ERC20InvalidReceiver`,
  `ERC20InsufficientAllowance`, `ERC20InvalidSpender`, `ERC20InvalidApprover`, `ERC20InvalidSender`.
- The supply is fixed. There is no `mint`, `burn`, `burnFrom`, owner, minter, pause, blocklist,
  freeze, seize or upgrade path, and the contract has no `receive` or `fallback`, so it accepts no
  ether and answers no unknown selector. The runtime contains no `DELEGATECALL`, `CALLCODE` or
  `SELFDESTRUCT`.

## Assumptions

- The deployer is the IMD ProjectFactory. The constructor mints the whole supply to `msg.sender`,
  so the factory receives it and pays it out as the launch directs: 10% to the launch's
  MerkleDistributor, 80% to the single-sided Uniswap v4 pool, and the remaining 10% to the
  requester's `remainderTo` address. The token does nothing special for any of these addresses
  because it treats every transfer identically, so none needs to be exempted or configured.
- The constructor calls no other contract and takes no arguments, so it deploys on an empty chain.
- Decimals are 18, matching the manifest's `token.decimals`, and the manifest's `token.totalSupply`
  must be `1000000000000000000000000000`.

## Deployment parameters

The launch is deployed by IMD through the factory, not from this repository. What the launch needs
from here:

| Setting | Value |
|---------|-------|
| Chain | Ethereum mainnet (chain id 1) |
| Compiler | solc 0.8.26, EVM version cancun, optimizer on, 200 runs, `via_ir = false` |
| Metadata | `bytecode_hash = "none"` so the deployed bytes are reproducible |
| Token constructor args | none |
| Application contracts | none |
| Pool pair | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` (18 decimals) |
| Pool fee / tick spacing | 12500 (1.25%) / 60, the launch policy's values |
| Economics | `poolBps` 8000, `initialMarketCapWei` 3500 IMD (`3500000000000000000000`), `remainderTo` `0xd380a8b40fcea7c0a699ff0d8232a264b37a2f9f` |

The manifest step writes `launch.json` after this work is accepted; this repository deliberately
contains none.

### Named constants

| Constant | Where | Value | Why |
|----------|-------|-------|-----|
| `INITIAL_SUPPLY` | `StrataToken` | `1_000_000_000 * 10 ** 18` | The requested supply in minor units |
| `TOKEN_NAME` | `StrataToken` | `StrataIMD` | The requested name |
| `TOKEN_SYMBOL` | `StrataToken` | `STRATA` | The requested symbol |
| `TOKEN_DECIMALS` | `StrataToken` | `18` | The requested decimals |

The brief left no number open, so nothing was chosen here beyond the compiler settings above.

## After launch

Nothing. The token has no owner and no settable value, so there is no setter to call and no
address to configure once it is deployed.

## Operational responsibilities

- **Holders** are the only parties who can move their balances, directly or through allowances
  they grant. There is no recovery path for tokens sent to a wrong address or to the token
  contract itself.
- **The requester** receives the remainder share at `remainderTo` and is responsible for that
  wallet. Nothing in the token depends on it afterwards.
- **IMD's deployer** builds the attested source with this `foundry.toml`, deploys through the
  factory and records the manifest. Explorer verification uses the same compiler settings.
- **Nobody** holds an administrative key: there is nothing to rotate, pause or upgrade. A change to
  the token's behaviour would be a new token.

## Checks

```
forge build
forge test
forge fmt --check
```

The fuzz tests bound every input to the valid range themselves, so they hold under any
`FOUNDRY_FUZZ_SEED`, including the verifier's.

Tests pass in any order and in parallel: no test reads or writes the environment, and the tests
deploy their own token in `setUp`.

## Security notes

Tests passing are not an audit. The token holds no funds of its own and has no privileged
functions, which removes the usual admin, upgrade and reentrancy surfaces, but a launch that
holds other people's value should still get an independent adversarial review before release.
Reviewed against the eth-security checklist: no external calls, no ether handling, no oracle,
no decimals assumption beyond the token's own 18, checked arithmetic everywhere except the two
balance updates whose sum is bounded by the fixed supply. Slither and Mythril did not run in this
session.
