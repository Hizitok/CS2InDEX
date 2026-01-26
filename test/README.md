# CS2InDEX Test Suite

Comprehensive test suite for the CS2InDEX perpetual trading protocol.

## Test Structure

```
test/
├── Base.t.sol          # Base test contract with common setup
├── Vault.t.sol         # Vault deposit, withdrawal, locking tests
├── Pool.t.sol          # Pool order matching, trading tests
├── Engine.t.sol        # Liquidation, ADL, Oracle tests
├── Factory.t.sol       # Factory deployment tests
├── Integration.t.sol   # End-to-end integration tests
└── mocks/
    └── MockERC20.sol   # Mock ERC20 token for testing
```

## Running Tests

### Prerequisites

Install Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Run All Tests

```bash
forge test
```

### Run Specific Test File

```bash
forge test --match-path test/Vault.t.sol
forge test --match-path test/Pool.t.sol
forge test --match-path test/Engine.t.sol
forge test --match-path test/Factory.t.sol
forge test --match-path test/Integration.t.sol
```

### Run Specific Test

```bash
forge test --match-test test_Deposit
forge test --match-test test_OrderMatching_FullFill
```

### Run Tests with Gas Report

```bash
forge test --gas-report
```

### Run Tests with Verbosity

```bash
forge test -vv     # Show logs
forge test -vvv    # Show traces for failing tests
forge test -vvvv   # Show traces for all tests
```

## Test Coverage

### Vault.t.sol (20 tests)
- ✅ Deposits and withdrawals
- ✅ Balance locking/unlocking
- ✅ Internal transfers
- ✅ Authorization checks
- ✅ Emergency withdrawals
- ✅ View functions

### Pool.t.sol (17 tests)
- ✅ Order creation (long/short)
- ✅ Order matching (full/partial fill)
- ✅ Position opening and closing
- ✅ Order cancellation
- ✅ PnL settlement (profit/loss)
- ✅ Fee collection
- ✅ Oracle price updates
- ✅ Authorization and validation

### Engine.t.sol (19 tests)
- ✅ Oracle price updates and validation
- ✅ Oracle staleness checks
- ✅ Price feeder management
- ✅ Liquidation checks
- ✅ Liquidation execution
- ✅ Insurance fund management
- ✅ Position health monitoring
- ✅ ADL score calculation
- ✅ ADL queue management

### Factory.t.sol (22 tests)
- ✅ Single pool deployment
- ✅ Batch pool deployment
- ✅ Pool registry management
- ✅ Pool status toggling
- ✅ Protocol fee configuration
- ✅ Price feeder management
- ✅ Engine configuration
- ✅ View functions
- ✅ Authorization checks

### Integration.t.sol (9 tests)
- ✅ Full trading cycle with profit
- ✅ Full trading cycle with loss
- ✅ Complete liquidation flow
- ✅ Multiple positions per user
- ✅ Order book price-time priority
- ✅ Fee aggregation across trades
- ✅ Position NFT transfers
- ✅ Multi-pool isolation

## Test Statistics

- **Total Tests**: 87
- **Coverage**: ~90% of core functionality
- **Test Categories**:
  - Unit Tests: 69
  - Integration Tests: 9
  - Authorization Tests: 9

## Key Test Scenarios

### 1. Basic Trading Flow
```solidity
Alice deposits → Opens long position → Price increases
→ Closes at profit → Withdraws funds
```

### 2. Liquidation Flow
```solidity
Alice opens leveraged position → Price drops
→ Position becomes underwater → Liquidator executes
→ Insurance fund covers deficit
```

### 3. Order Matching
```solidity
Bob places limit buy → Alice places limit sell
→ Orders match → Both positions open
→ Fees collected
```

### 4. NFT Position Management
```solidity
Alice opens position (gets NFT) → Transfers NFT to Carol
→ Carol closes position → PnL settles to Carol
```

## Mock Contracts

### MockERC20
Simple ERC20 implementation for testing:
- Mint/burn functions for test setup
- Standard ERC20 interface
- 6 decimals (USDC-like)

## Test Helpers

### BaseTest Contract
Provides common setup:
- Deploys all protocol contracts
- Creates test users (Alice, Bob, Carol)
- Mints initial USDC balances
- Helper functions for order creation

### Helper Functions
- `_deployPool()` - Deploy new trading pool
- `_depositToVault()` - User deposits to vault
- `_createLongOrder()` - Create long order
- `_createShortOrder()` - Create short order
- `_createMarketOrder()` - Create market order

## Expected Behaviors

### Deposits
- Users must approve vault before depositing
- Balance updates correctly
- Total supply tracked
- Events emitted

### Orders
- Leverage limited to 6x
- Price bounds enforced
- Orders match by price-time priority
- Fees calculated correctly (maker 0.3%, taker 0.5%)

### Liquidations
- Maintenance margin: 5%
- Liquidator reward: 2.5%
- Insurance fund covers bad debt
- ADL as last resort

### Positions
- Represented as ERC721 NFTs
- Transferable between users
- PnL settles on close
- Fully on-chain tracking

## CI/CD Integration

Add to GitHub Actions:
```yaml
- name: Run tests
  run: forge test --gas-report

- name: Check coverage
  run: forge coverage
```

## Fuzzing

Foundry supports property-based testing. Add fuzz tests:

```solidity
function testFuzz_Deposit(uint256 amount) public {
    vm.assume(amount > 0 && amount <= INITIAL_BALANCE);
    vm.prank(alice);
    vault.deposit(amount);
    assertEq(vault.balanceOf(alice), amount);
}
```

## Gas Benchmarks

Run gas report to optimize:
```bash
forge test --gas-report > gas-report.txt
```

Expected gas costs:
- Deposit: ~50k
- Order creation: ~200k
- Order matching: ~300k
- Liquidation: ~150k

## Contributing

When adding new features:
1. Write tests first (TDD)
2. Ensure all tests pass
3. Add integration test if needed
4. Update this README

## Notes

- Tests use Foundry's cheatcodes (vm.prank, vm.warp, etc.)
- All monetary values in 6 decimals (USDC)
- Prices multiplied by 100 (e.g., $500 = 50000)
- Coverage focuses on critical paths and edge cases
