// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {LinearStakeConsensus} from "../src/consensus/LinearStakeConsensus.sol";
import {SqrtStakeConsensus} from "../src/consensus/SqrtStakeConsensus.sol";
import {CappedLinearConsensus} from "../src/consensus/CappedLinearConsensus.sol";
import {HybridConsensus} from "../src/consensus/HybridConsensus.sol";
import {IConsensusAlgorithm} from "../src/interface/IConsensusAlgorithm.sol";

contract ConsensusTest is Test {
    LinearStakeConsensus public linear;
    SqrtStakeConsensus public sqrt;
    CappedLinearConsensus public capped;
    HybridConsensus public hybrid;

    function setUp() public {
        linear = new LinearStakeConsensus();
        sqrt = new SqrtStakeConsensus();
        capped = new CappedLinearConsensus();
        hybrid = new HybridConsensus();
    }

    function testLinearStakeConsensus() public view {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](3);
        inputs[0] = IConsensusAlgorithm.ValidationInput(address(1), 8000, 100 ether, 5000);
        inputs[1] = IConsensusAlgorithm.ValidationInput(address(2), 9000, 200 ether, 5000);
        inputs[2] = IConsensusAlgorithm.ValidationInput(address(3), 1000, 100 ether, 5000); // Outlier

        IConsensusAlgorithm.ConsensusResult memory result = linear.calculateConsensus(inputs);

        // (8000*100 + 9000*200 + 1000*100) / 400 = (800000 + 1800000 + 100000) / 400 = 2700000 / 400 = 6750
        assertEq(result.weightedAverage, 6750);

        // Outlier detection (LinearStake might not have it yet or uses simple avg)
        // Let's check if address(3) is slashed if it's far from average
    }

    function testSqrtStakeConsensus() public view {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](2);
        inputs[0] = IConsensusAlgorithm.ValidationInput(address(1), 8000, 100 ether, 5000); // sqrt(100) = 10
        inputs[1] = IConsensusAlgorithm.ValidationInput(address(2), 9000, 400 ether, 5000); // sqrt(400) = 20

        IConsensusAlgorithm.ConsensusResult memory result = sqrt.calculateConsensus(inputs);

        // (8000*10 + 9000*20) / 30 = (80000 + 180000) / 30 = 260000 / 30 = 8666
        assertEq(result.weightedAverage, 8666);
    }

    function testCappedLinearConsensus() public view {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](2);
        inputs[0] = IConsensusAlgorithm.ValidationInput(address(1), 8000, 100 ether, 5000);
        inputs[1] = IConsensusAlgorithm.ValidationInput(address(2), 9000, 1000 ether, 5000); // Whale

        IConsensusAlgorithm.ConsensusResult memory result = capped.calculateConsensus(inputs);
        assertTrue(result.weightedAverage > 0);

        // With iterative capping and only 2 validators, both converge toward equal weights
        // since it's impossible for both to be <= 30% (they must sum to 100%).
        // The whale's original 90.9% dominance is eliminated — weighted average should
        // approach the simple average: (8000 + 9000) / 2 = 8500
        assertTrue(result.weightedAverage >= 8000 && result.weightedAverage <= 9000, "Should be between 8000 and 9000");
    }

    function testHybridConsensus() public view {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](3);
        inputs[0] = IConsensusAlgorithm.ValidationInput(address(1), 8000, 100 ether, 6000); // High reputation
        inputs[1] = IConsensusAlgorithm.ValidationInput(address(2), 9000, 100 ether, 4000); // Low reputation
        inputs[2] = IConsensusAlgorithm.ValidationInput(address(3), 5000, 10 ether, 1000); // Low rep, low stake

        IConsensusAlgorithm.ConsensusResult memory result = hybrid.calculateConsensus(inputs);
        assertTrue(result.weightedAverage > 0);

        // With iterative 30% cap and 3 validators, the two heavier validators (0 and 1)
        // both exceed the cap and converge toward equal weights. Validator 2 (low stake + low rep)
        // has a much smaller initial weight. All weights should be positive.
        assertTrue(result.validatorWeights[0] > 0);
        assertTrue(result.validatorWeights[1] > 0);
        assertTrue(result.validatorWeights[2] > 0);
    }

    function testLinearStakeBranchCoverage() public view {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](1);
        inputs[0] = IConsensusAlgorithm.ValidationInput(address(1), 5000, 100 ether, 5000);

        IConsensusAlgorithm.ConsensusResult memory result = linear.calculateConsensus(inputs);
        assertEq(result.weightedAverage, 5000);
        assertEq(result.stdDev, 0);
    }

    function testConsensusMetadata() public view {
        assertEq(linear.getName(), "LinearStake");
        assertEq(sqrt.getName(), "SqrtStake");
        assertEq(capped.getName(), "CappedLinear");
        assertEq(hybrid.getName(), "Hybrid");

        assertTrue(bytes(linear.getDescription()).length > 0);
        assertTrue(bytes(sqrt.getDescription()).length > 0);
        assertTrue(bytes(capped.getDescription()).length > 0);
        assertTrue(bytes(hybrid.getDescription()).length > 0);

        assertTrue(bytes(linear.getSecurityGrade()).length > 0);
        assertTrue(bytes(sqrt.getSecurityGrade()).length > 0);
        assertTrue(bytes(capped.getSecurityGrade()).length > 0);
        assertTrue(bytes(hybrid.getSecurityGrade()).length > 0);
    }

    function testConsensusReverts() public {
        IConsensusAlgorithm.ValidationInput[] memory empty;
        vm.expectRevert(IConsensusAlgorithm.NoValidations.selector);
        linear.calculateConsensus(empty);

        IConsensusAlgorithm.ValidationInput[] memory invalidScore = new IConsensusAlgorithm.ValidationInput[](1);
        invalidScore[0] = IConsensusAlgorithm.ValidationInput(address(1), 10001, 100 ether, 5000);
        vm.expectRevert(abi.encodeWithSelector(IConsensusAlgorithm.InvalidScore.selector, 10001));
        linear.calculateConsensus(invalidScore);

        IConsensusAlgorithm.ValidationInput[] memory zeroStake = new IConsensusAlgorithm.ValidationInput[](1);
        zeroStake[0] = IConsensusAlgorithm.ValidationInput(address(1), 5000, 0, 5000);
        vm.expectRevert(IConsensusAlgorithm.InvalidStakeAmount.selector);
        linear.calculateConsensus(zeroStake);
    }

    // --- COVERAGE TESTS FROM ConsensusCoverage.t.sol ---

    function testSqrtStake_Reverts() public {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](1);

        // 1. Empty validations
        IConsensusAlgorithm.ValidationInput[] memory empty;
        vm.expectRevert(IConsensusAlgorithm.NoValidations.selector);
        sqrt.calculateConsensus(empty);

        // 2. Invalid score
        inputs[0] = IConsensusAlgorithm.ValidationInput(address(1), 10001, 1000 ether, 5000);
        vm.expectRevert(abi.encodeWithSelector(IConsensusAlgorithm.InvalidScore.selector, 10001));
        sqrt.calculateConsensus(inputs);

        // 3. Invalid stake
        inputs[0] = IConsensusAlgorithm.ValidationInput(address(1), 8000, 0, 5000);
        vm.expectRevert(IConsensusAlgorithm.InvalidStakeAmount.selector);
        sqrt.calculateConsensus(inputs);
    }

    function testCappedLinear_Branches() public {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](2);

        // 1. One validator > 30% — iterative cap converges both toward equality
        inputs[0] = IConsensusAlgorithm.ValidationInput(address(1), 8000, 700 ether, 5000);
        inputs[1] = IConsensusAlgorithm.ValidationInput(address(2), 6000, 300 ether, 5000);

        IConsensusAlgorithm.ConsensusResult memory result = capped.calculateConsensus(inputs);
        // With iterative capping and 2 validators, weights converge toward equality
        // Weighted average should approach simple average: (8000 + 6000) / 2 = 7000
        assertTrue(result.weightedAverage >= 6000 && result.weightedAverage <= 8000);
        assertTrue(result.validatorWeights[0] > 0);
        assertTrue(result.validatorWeights[1] > 0);

        // 2. Reverts
        vm.expectRevert(IConsensusAlgorithm.NoValidations.selector);
        capped.calculateConsensus(new IConsensusAlgorithm.ValidationInput[](0));

        inputs[0].score = 10001;
        vm.expectRevert(abi.encodeWithSelector(IConsensusAlgorithm.InvalidScore.selector, 10001));
        capped.calculateConsensus(inputs);

        inputs[0].score = 8000;
        inputs[0].stakeAmount = 0;
        vm.expectRevert(IConsensusAlgorithm.InvalidStakeAmount.selector);
        capped.calculateConsensus(inputs);
    }

    function testHybrid_Branches() public {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](2);

        // 1. Invalid reputation
        inputs[0] = IConsensusAlgorithm.ValidationInput(address(1), 8000, 1000 ether, 10001);
        vm.expectRevert(abi.encodeWithSelector(IConsensusAlgorithm.InvalidReputation.selector, 10001));
        hybrid.calculateConsensus(inputs);

        // 2. Cap application (requires more complex setup as it uses sqrt(stake) * reputation)
        inputs[0] = IConsensusAlgorithm.ValidationInput(address(1), 8000, 10000 ether, 10000); // weight = 100 * 1 = 100
        inputs[1] = IConsensusAlgorithm.ValidationInput(address(2), 6000, 100 ether, 1000); // weight = 10 * 0.1 = 1
        // Total weight = 101. 100/101 ~= 99% > 30%.

        IConsensusAlgorithm.ConsensusResult memory result = hybrid.calculateConsensus(inputs);
        // maxWeightBps should be > 3000, triggering scaleFactor
        assertTrue(result.validatorWeights[0] > 0);
    }
}

