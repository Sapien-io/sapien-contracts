// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {Project, ProjectStatus} from "src/Types.sol";

/// @title OriginationLibFuzz
/// @notice Fuzz tests attempting to break OriginationLib with edge cases
contract OriginationLibFuzz is Test {
    SapienCore public engine;
    SapienVault public vault;
    MockERC20 public token;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public originator = makeAddr("originator");

    bytes32 constant SKILL_ID = keccak256("DATA_ANNOTATION");

    function setUp() public {
        token = new MockERC20("Test", "TST");

        SapienVault vaultImpl = new SapienVault();
        bytes memory vaultInit = abi.encodeCall(SapienVault.initialize, (token, admin));
        vault = SapienVault(address(new ERC1967Proxy(address(vaultImpl), vaultInit)));

        SapienCore engineImpl = new SapienCore();
        bytes memory engineInit = abi.encodeCall(SapienCore.initialize, (admin, address(vault), treasury));
        engine = SapienCore(address(new ERC1967Proxy(address(engineImpl), engineInit)));

        vm.startPrank(admin);
        vault.grantRole(vault.ENGINE_ROLE(), address(engine));
        engine.registerSkill("DATA_ANNOTATION");
        vm.stopPrank();

        token.mint(originator, 1_000_000e18);
        vm.prank(originator);
        token.approve(address(engine), type(uint256).max);
    }

    function testFuzz_createProject_validConfigurations(
        bytes32 projectId,
        uint16 consensusThreshold,
        uint16 validatorRewardBps,
        uint8 numberOfValidations
    ) public {
        vm.assume(projectId != bytes32(0));
        consensusThreshold = uint16(bound(consensusThreshold, 1, C.BPS));
        validatorRewardBps = uint16(bound(validatorRewardBps, 0, C.MAX_VALIDATOR_REWARD_BPS));
        numberOfValidations = uint8(bound(numberOfValidations, 1, C.MAX_NUMBER_OF_VALIDATIONS));

        Project memory config = _makeProjectConfig();
        config.consensusThreshold = consensusThreshold;
        config.validatorRewardBps = validatorRewardBps;
        config.numberOfValidations = numberOfValidations;

        vm.prank(originator);
        engine.createProject(projectId, "ipfs://test", config);

        Project memory proj = engine.getProject(projectId);
        assertEq(proj.originator, originator);
    }

    function testFuzz_createProject_revertsDuplicateId(bytes32 projectId) public {
        vm.assume(projectId != bytes32(0));

        Project memory config = _makeProjectConfig();

        vm.prank(originator);
        engine.createProject(projectId, "", config);

        vm.prank(originator);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "project already exists"));
        engine.createProject(projectId, "", config);
    }

    function testFuzz_createProject_revertsZeroRewardToken(bytes32 projectId) public {
        vm.assume(projectId != bytes32(0));

        Project memory config = _makeProjectConfig();
        config.rewardToken = address(0);

        vm.prank(originator);
        vm.expectRevert(ISapienCore.ZeroAddress.selector);
        engine.createProject(projectId, "", config);
    }

    function testFuzz_createProject_revertsInvalidConsensusThreshold(bytes32 projectId, uint256 threshold) public {
        vm.assume(projectId != bytes32(0));
        threshold = bound(threshold, C.BPS + 1, type(uint256).max);

        Project memory config = _makeProjectConfig();
        config.consensusThreshold = threshold;

        vm.prank(originator);
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "consensusThreshold out of range")
        );
        engine.createProject(projectId, "", config);
    }

    function testFuzz_createProject_revertsZeroConsensusThreshold(bytes32 projectId) public {
        vm.assume(projectId != bytes32(0));

        Project memory config = _makeProjectConfig();
        config.consensusThreshold = 0;

        vm.prank(originator);
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "consensusThreshold out of range")
        );
        engine.createProject(projectId, "", config);
    }

    function testFuzz_createProject_revertsHighValidatorReward(bytes32 projectId, uint256 rewardBps) public {
        vm.assume(projectId != bytes32(0));
        rewardBps = bound(rewardBps, C.MAX_VALIDATOR_REWARD_BPS + 1, type(uint256).max);

        Project memory config = _makeProjectConfig();
        config.validatorRewardBps = rewardBps;

        vm.prank(originator);
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "validatorRewardBps too high")
        );
        engine.createProject(projectId, "", config);
    }

    function testFuzz_createProject_revertsInvalidNumberOfValidations(bytes32 projectId, uint256 validations) public {
        vm.assume(projectId != bytes32(0));
        validations = bound(validations, C.MAX_NUMBER_OF_VALIDATIONS + 1, type(uint256).max);

        Project memory config = _makeProjectConfig();
        config.numberOfValidations = validations;

        vm.prank(originator);
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "numberOfValidations out of range")
        );
        engine.createProject(projectId, "", config);
    }

    function testFuzz_createProject_revertsZeroValidations(bytes32 projectId) public {
        vm.assume(projectId != bytes32(0));

        Project memory config = _makeProjectConfig();
        config.numberOfValidations = 0;

        vm.prank(originator);
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "numberOfValidations out of range")
        );
        engine.createProject(projectId, "", config);
    }

    function testFuzz_createProject_revertsWrongOriginator(bytes32 projectId, address wrongOriginator) public {
        vm.assume(projectId != bytes32(0));
        vm.assume(wrongOriginator != address(0) && wrongOriginator != originator);

        Project memory config = _makeProjectConfig();
        config.originator = wrongOriginator;

        vm.prank(originator);
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "originator must be msg.sender or zero")
        );
        engine.createProject(projectId, "", config);
    }

    function testFuzz_fundProject_validFunding(bytes32 projectId, uint256 amount, uint256 quantity) public {
        vm.assume(projectId != bytes32(0));
        amount = bound(amount, 1e18, 100_000e18);
        quantity = bound(quantity, 1, 100);

        _createProject(projectId);

        vm.prank(originator);
        engine.fundProject(projectId, amount, quantity, address(0));

        Project memory proj = engine.getProject(projectId);

        assertGt(proj.totalRewards, 0);
        assertEq(proj.totalQuantity, quantity);
        assertEq(proj.availableSlots, quantity);
        assertEq(uint8(proj.status), uint8(ProjectStatus.Funded));
    }

    function testFuzz_fundProject_revertsZeroAmount(bytes32 projectId, uint256 quantity) public {
        vm.assume(projectId != bytes32(0));
        quantity = bound(quantity, 1, 100);

        _createProject(projectId);

        vm.prank(originator);
        vm.expectRevert(ISapienCore.ZeroAmount.selector);
        engine.fundProject(projectId, 0, quantity, address(0));
    }

    function testFuzz_fundProject_revertsZeroQuantity(bytes32 projectId, uint256 amount) public {
        vm.assume(projectId != bytes32(0));
        amount = bound(amount, 1, 100_000e18);

        _createProject(projectId);

        vm.prank(originator);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "quantity must be > 0"));
        engine.fundProject(projectId, amount, 0, address(0));
    }

    function testFuzz_fundProject_revertsNonOriginator(bytes32 projectId, address notOriginator) public {
        vm.assume(projectId != bytes32(0));
        vm.assume(notOriginator != originator && notOriginator != address(0));

        _createProject(projectId);

        token.mint(notOriginator, 10_000e18);
        vm.startPrank(notOriginator);
        token.approve(address(engine), type(uint256).max);
        vm.expectRevert(ISapienCore.NotProjectOriginator.selector);
        engine.fundProject(projectId, 1000e18, 10, address(0));
        vm.stopPrank();
    }

    function testFuzz_fundProject_multipleFundings(bytes32 projectId, uint8 fundingRounds) public {
        vm.assume(projectId != bytes32(0));
        fundingRounds = uint8(bound(fundingRounds, 1, 10));

        _createProject(projectId);

        uint256 totalQuantity = 0;
        for (uint256 i; i < fundingRounds; ++i) {
            uint256 amount = 1000e18;
            uint256 qty = 5;

            vm.prank(originator);
            engine.fundProject(projectId, amount, qty, address(0));
            totalQuantity += qty;
        }

        Project memory proj = engine.getProject(projectId);
        assertEq(proj.totalQuantity, totalQuantity);
        assertEq(proj.availableSlots, totalQuantity);
    }

    function testFuzz_fundProject_protocolFeeDeduction(bytes32 projectId, uint16 feeBps) public {
        vm.assume(projectId != bytes32(0));
        feeBps = uint16(bound(feeBps, 0, C.MAX_PROTOCOL_FEE_BPS));

        vm.prank(admin);
        engine.setProtocolFee(feeBps);

        _createProject(projectId);

        uint256 treasuryBalanceBefore = token.balanceOf(treasury);
        uint256 amount = 10_000e18;

        vm.prank(originator);
        engine.fundProject(projectId, amount, 10, address(0));

        uint256 treasuryBalanceAfter = token.balanceOf(treasury);
        uint256 expectedFee = (amount * feeBps) / C.BPS;

        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, expectedFee);
    }

    function testFuzz_fundProject_originationAdapterFee(bytes32 projectId, address adapterAddr) public {
        vm.assume(projectId != bytes32(0));
        vm.assume(adapterAddr != address(0));

        uint16 originationFeeBps = 100;
        vm.prank(admin);
        engine.setOriginationFee(originationFeeBps);

        _createProject(projectId);

        uint256 amount = 10_000e18;

        vm.prank(originator);
        engine.fundProject(projectId, amount, 10, adapterAddr);

        uint256 adapterPending = engine.getPendingRewards(adapterAddr, address(token));
        assertTrue(adapterPending > 0, "Adapter should have pending rewards");
    }

    function testFuzz_fundProject_withOriginatorStakeRequirement(bytes32 projectId, uint256 stakeReq, uint256 quantity)
        public
    {
        vm.assume(projectId != bytes32(0));
        stakeReq = bound(stakeReq, 1e18, 100e18);
        quantity = bound(quantity, 1, 10);

        vm.prank(admin);
        engine.setOriginatorStakeRequirement(stakeReq);

        token.mint(originator, stakeReq * quantity * 2);
        vm.startPrank(originator);
        token.approve(address(vault), stakeReq * quantity);
        vault.deposit(stakeReq * quantity, originator);
        vm.stopPrank();

        _createProject(projectId);

        vm.prank(originator);
        engine.fundProject(projectId, 10_000e18, quantity, address(0));

        uint256 lockedStake = engine.getOriginatorLockedStake(projectId);
        assertEq(lockedStake, stakeReq * quantity);
    }

    function testFuzz_removeProject_slashesOriginator(bytes32 projectId) public {
        vm.assume(projectId != bytes32(0));

        uint256 stakeReq = 10e18;
        vm.prank(admin);
        engine.setOriginatorStakeRequirement(stakeReq);

        token.mint(originator, stakeReq * 100);
        vm.startPrank(originator);
        token.approve(address(vault), stakeReq * 100);
        vault.deposit(stakeReq * 50, originator);
        vm.stopPrank();

        _createProject(projectId);

        vm.prank(originator);
        engine.fundProject(projectId, 10_000e18, 10, address(0));

        uint256 lockedBefore = engine.getOriginatorLockedStake(projectId);
        assertTrue(lockedBefore > 0);

        vm.prank(admin);
        engine.removeProject(projectId);

        Project memory proj = engine.getProject(projectId);
        assertEq(uint8(proj.status), uint8(ProjectStatus.Cancelled));

        uint256 lockedAfter = engine.getOriginatorLockedStake(projectId);
        assertEq(lockedAfter, 0);
    }

    function testFuzz_removeProject_revertsNonExistent(bytes32 projectId) public {
        vm.assume(projectId != bytes32(0));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "project does not exist"));
        engine.removeProject(projectId);
    }

    function testFuzz_removeProject_revertsAlreadyCancelled(bytes32 projectId) public {
        vm.assume(projectId != bytes32(0));

        _createProject(projectId);

        vm.prank(originator);
        engine.fundProject(projectId, 1000e18, 5, address(0));

        vm.prank(admin);
        engine.removeProject(projectId);

        vm.prank(admin);
        vm.expectRevert(ISapienCore.ProjectNotCancellable.selector);
        engine.removeProject(projectId);
    }

    function _createProject(bytes32 projectId) internal {
        Project memory config = _makeProjectConfig();
        vm.prank(originator);
        engine.createProject(projectId, "", config);
    }

    function _makeProjectConfig() internal view returns (Project memory) {
        return Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: 100e18,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });
    }
}
