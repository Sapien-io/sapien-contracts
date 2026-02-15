// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SqrtStakeConsensus} from "../src/consensus/SqrtStakeConsensus.sol";
import {IConsensusAlgorithm} from "../src/interface/IConsensusAlgorithm.sol";

contract ConsensusTest is Test {
    SqrtStakeConsensus public sqrt;

    function setUp() public {
        sqrt = new SqrtStakeConsensus();
    }

    function testSqrtStakeConsensus() public view {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](2);
        inputs[0] = IConsensusAlgorithm.ValidationInput(address(1), 8000, 100 ether, 5000); // sqrt(100) = 10
        inputs[1] = IConsensusAlgorithm.ValidationInput(address(2), 9000, 400 ether, 5000); // sqrt(400) = 20

        IConsensusAlgorithm.ConsensusResult memory result = sqrt.calculateConsensus(inputs);

        // (8000*10 + 9000*20) / 30 = (80000 + 180000) / 30 = 260000 / 30 = 8666
        assertEq(result.weightedAverage, 8666);
    }

    function testSqrtStakeSingleValidator() public view {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](1);
        inputs[0] = IConsensusAlgorithm.ValidationInput(address(1), 5000, 100 ether, 5000);

        IConsensusAlgorithm.ConsensusResult memory result = sqrt.calculateConsensus(inputs);
        assertEq(result.weightedAverage, 5000);
        assertEq(result.stdDev, 0);
    }

    function testConsensusMetadata() public view {
        assertEq(sqrt.getName(), "SqrtStake");
        assertEq(sqrt.getSecurityGrade(), "A-");
        assertTrue(bytes(sqrt.getDescription()).length > 0);
    }

    function testSqrtConsensusReverts() public {
        IConsensusAlgorithm.ValidationInput[] memory empty;
        vm.expectRevert(IConsensusAlgorithm.NoValidations.selector);
        sqrt.calculateConsensus(empty);

        IConsensusAlgorithm.ValidationInput[] memory invalidScore = new IConsensusAlgorithm.ValidationInput[](1);
        invalidScore[0] = IConsensusAlgorithm.ValidationInput(address(1), 10001, 100 ether, 5000);
        vm.expectRevert(abi.encodeWithSelector(IConsensusAlgorithm.InvalidScore.selector, 10001));
        sqrt.calculateConsensus(invalidScore);

        IConsensusAlgorithm.ValidationInput[] memory zeroStake = new IConsensusAlgorithm.ValidationInput[](1);
        zeroStake[0] = IConsensusAlgorithm.ValidationInput(address(1), 5000, 0, 5000);
        vm.expectRevert(IConsensusAlgorithm.InvalidStakeAmount.selector);
        sqrt.calculateConsensus(zeroStake);
    }
}

