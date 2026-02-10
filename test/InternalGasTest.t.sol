// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/**
 * @title 内部 Gas 测试
 * @notice 测量实际的字节码执行效率，避免外部调用开销
 */
contract InternalGasTest is Test {

    function testInternalComparison() public {
        uint256 gasStart;
        uint256 gasUsed;
        uint256 result;

        console.log("\n=== Internal Execution Comparison ===\n");

        // =============== Test 1: Simple condition ===============
        console.log("Test 1: Simple condition (x > 100 ? x : 100)");

        gasStart = gasleft();
        result = 150 > 100 ? 150 : 100;
        gasUsed = gasStart - gasleft();
        console.log("Ternary:", gasUsed, "gas");

        gasStart = gasleft();
        if (150 > 100) {
            result = 150;
        } else {
            result = 100;
        }
        gasUsed = gasStart - gasleft();
        console.log("If-else:", gasUsed, "gas");

        // =============== Test 2: With arithmetic ===============
        console.log("\nTest 2: With arithmetic (x > 100 ? x * 2 : x / 2)");

        gasStart = gasleft();
        result = 150 > 100 ? 150 * 2 : 150 / 2;
        gasUsed = gasStart - gasleft();
        console.log("Ternary:", gasUsed, "gas");

        gasStart = gasleft();
        if (150 > 100) {
            result = 150 * 2;
        } else {
            result = 150 / 2;
        }
        gasUsed = gasStart - gasleft();
        console.log("If-else:", gasUsed, "gas");

        // =============== Test 3: Nested conditions ===============
        console.log("\nTest 3: Nested conditions");

        gasStart = gasleft();
        result = true ? (false ? 100 : 200) : 300;
        gasUsed = gasStart - gasleft();
        console.log("Ternary:", gasUsed, "gas");

        gasStart = gasleft();
        if (true) {
            if (false) {
                result = 100;
            } else {
                result = 200;
            }
        } else {
            result = 300;
        }
        gasUsed = gasStart - gasleft();
        console.log("If-else:", gasUsed, "gas");

        // =============== Test 4: Boolean selection ===============
        console.log("\nTest 4: Boolean selection");

        bool boolResult;
        gasStart = gasleft();
        boolResult = 5 > 3 ? true : false;
        gasUsed = gasStart - gasleft();
        console.log("Ternary:", gasUsed, "gas");

        gasStart = gasleft();
        if (5 > 3) {
            boolResult = true;
        } else {
            boolResult = false;
        }
        gasUsed = gasStart - gasleft();
        console.log("If-else:", gasUsed, "gas");
    }

    function testCompilerOptimization() public {
        console.log("\n=== Compiler Optimization Analysis ===\n");

        // 测试编译器是否会将两者优化成相同的字节码
        uint256 gasStart;
        uint256 gasUsed;

        // 最简单的情况
        gasStart = gasleft();
        uint256 a = true ? 1 : 2;
        gasUsed = gasStart - gasleft();
        console.log("Constant ternary:", gasUsed, "gas, result:", a);

        gasStart = gasleft();
        uint256 b;
        if (true) {
            b = 1;
        } else {
            b = 2;
        }
        gasUsed = gasStart - gasleft();
        console.log("Constant if-else:", gasUsed, "gas, result:", b);
    }
}
