## Quick Start Guide

### 1. Install Dependencies
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Update git submodules (if any)
forge install
```

### 2. Build Contracts
```bash
forge build
```

### 3. Run Tests
```bash
# Run all tests
forge test

# Run with gas report
forge test --gas-report

# Run specific test file
forge test --match-path test/Vault.t.sol -vv

# Run specific test function
forge test --match-test test_Deposit -vvv
```

### 4. Check Coverage
```bash
forge coverage
```

### 5. Format Code
```bash
forge fmt
```

## Test Examples

### Run Pool Unit Tests
```bash
$ forge test --match-path test/Pool.t.sol -vv

Running tests for test/Pool.t.sol:PoolTest
[PASS] testNewOrder_LimitBuy() (gas: ...)
[PASS] testNewOrder_MarketMatch() (gas: ...)
[PASS] testCancelOrder_PendingOpen() (gas: ...)
...
```

### Run Integration Tests
```bash
$ forge test --match-path test/Integration.t.sol -vv

Running tests for test/Integration.t.sol:IntegrationTest
[PASS] test_FullTradingCycle() (gas: ...)
[PASS] test_LiquidationFlow() (gas: ...)
[PASS] test_FundingRate() (gas: ...)
...
```

### Run Gas Benchmark
```bash
$ forge test --match-path test/GasBenchmark.t.sol -vv
```

## Common Commands

```bash
# Clean build artifacts
forge clean

# Update dependencies
forge update

# Snapshot gas usage
forge snapshot

# Generate gas report
forge test --gas-report > gas-report.txt

# Run tests with traces
forge test -vvvv

# Run fuzz tests with more runs
forge test --fuzz-runs 10000
```

## Debugging Failed Tests

### With Traces
```bash
forge test --match-test test_FailingTest -vvvv
```

### With Console Logs
Add to test:
```solidity
import "forge-std/console.sol";

function test_Example() public {
    console.log("Value:", someValue);
    console.log("Address:", someAddress);
}
```

### Using Debugger
```bash
forge test --debug test_FailingTest
```

## Writing New Tests

### Template
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {CS2InDEXFactory} from "../src/Factory.sol";
import {Vault} from "../src/Vault.sol";
import {Pool} from "../src/Pool.sol";
import {OrderTypes} from "../src/interfaces/OrderTypes.sol";

contract MyNewTest is Test, OrderTypes {
    CS2InDEXFactory factory;
    Vault vault;
    Pool pool;

    address alice = address(0x1);

    function setUp() public {
        // Deploy via factory (same as Integration tests)
        TestERC20 usdc = new TestERC20("USDC", "USDC", 6);
        factory = new CS2InDEXFactory(address(usdc));
        vault = Vault(factory.vault());
        (address poolAddr,) = factory.createPool("Test", 100e6, 6);
        pool = Pool(poolAddr);

        usdc.mint(alice, 10000e6);
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(alice);
        vault.deposit(5000e6);
    }

    function test_MyFeature() public {
        // Arrange + Act
        vm.prank(alice);
        pool.newOrder(1000e6, PoolOrder({
            isSell: false,
            oType: orderType.Limit,
            size: 1e6,
            price: 99e6
        }));

        // Assert
        assertEq(vault.balanceOf(alice), 4000e6);
    }
}
```

## Test Coverage Goals

- ✅ Unit tests for all public functions
- ✅ Edge cases and boundary conditions
- ✅ Access control checks
- ✅ Revert conditions
- ✅ Integration tests for workflows
- ✅ Gas optimization validation

## CI/CD Integration

### GitHub Actions Example
```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          submodules: recursive

      - name: Install Foundry
        uses: foundry-rs/foundry-toolchain@v1

      - name: Run tests
        run: forge test --gas-report

      - name: Check coverage
        run: forge coverage
```

## Gas Optimization

Monitor gas usage:
```bash
forge test --gas-report

# Output:
| Contract | Function | Gas Used |
|----------|----------|----------|
| Vault    | deposit  | 52,341   |
| Pool     | newOrder | 234,567  |
| Pool     | match    | 187,432  |
```

## Troubleshooting

### "Compiler version not found"
```bash
forge install
forge build --force
```

### "Stack too deep"
Use `--via-ir` flag or restructure code:
```bash
forge build --via-ir
```

### "Out of gas"
Increase gas limit in test:
```solidity
vm.deal(address(this), 100 ether);
```

## Performance Tips

1. Use `vm.prank()` instead of creating new contracts
2. Reuse test setup with `BaseTest`
3. Cache commonly used values
4. Use `vm.warp()` for time-based tests
5. Snapshot state for repeated tests

## Additional Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [Foundry Cheatcodes](https://book.getfoundry.sh/cheatcodes/)
- [Best Practices](https://book.getfoundry.sh/tutorials/best-practices)
