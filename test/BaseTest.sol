// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SapienCore} from "../src/SapienCore.sol";
import {SapienVault} from "../src/SapienVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {
    Project,
    ProjectStatus,
    Claim,
    ClaimStatus,
    Contribution,
    ContributionStatus,
    Reputation
} from "../src/Types.sol";

/// @notice Base test contract with common setup for all test suites
contract BaseTest is Test {
    SapienCore public engine;
    SapienVault public vault;
    MockERC20 public token;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public originator = makeAddr("originator");
    address public contributor1 = makeAddr("contributor1");
    address public contributor2 = makeAddr("contributor2");
    address public validator1 = makeAddr("validator1");
    address public validator2 = makeAddr("validator2");
    address public validator3 = makeAddr("validator3");
    address public adapter = makeAddr("adapter");

    bytes32 public constant PROJECT_ID = keccak256("test-project-1");
    bytes32 public constant SKILL_ID = keccak256("DATA_ANNOTATION");
    uint256 public constant FUND_AMOUNT = 10_000e18;
    uint256 public constant QUANTITY = 10;
    uint256 public constant STAKE_AMOUNT = 100e18;
    uint256 public constant VALIDATOR_STAKE = 50e18;

    function setUp() public virtual {
        token = new MockERC20("Sapien Token", "SPN");

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

        _setupBalances();
    }

    function _setupBalances() internal {
        token.mint(originator, FUND_AMOUNT * 2);

        address[5] memory stakers = [contributor1, contributor2, validator1, validator2, validator3];
        for (uint256 i; i < stakers.length; ++i) {
            token.mint(stakers[i], STAKE_AMOUNT * 10);
            vm.startPrank(stakers[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 5, stakers[i]);
            vm.stopPrank();
        }
    }

    function _createAndFundProject() internal returns (bytes32) {
        return _createAndFundProject(PROJECT_ID, FUND_AMOUNT, QUANTITY);
    }

    function _createAndFundProject(bytes32 projectId, uint256 amount, uint256 qty) internal returns (bytes32) {
        vm.startPrank(originator);

        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
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

        engine.createProject(projectId, "", config);

        token.approve(address(engine), amount);
        engine.fundProject(projectId, amount, qty, adapter);

        vm.stopPrank();

        return projectId;
    }

    function _claimAndContribute(address contrib, bytes32 projectId, uint256 qty)
        internal
        returns (uint256 claimId, uint256[] memory indices)
    {
        vm.startPrank(contrib);
        (claimId, indices) = engine.claimToContribute(projectId, qty, adapter);
        for (uint256 i; i < indices.length; ++i) {
            bytes32 hash = keccak256(abi.encodePacked("submission", indices[i]));
            engine.contribute(claimId, indices[i], hash, "");
        }
        vm.stopPrank();
        return (claimId, indices);
    }

    function _ensureStake(address user, uint256 needed) internal virtual {
        uint256 available = vault.availableBalance(user);
        if (available < needed) {
            uint256 deficit = needed - available + 1e18;
            token.mint(user, deficit);
            vm.startPrank(user);
            token.approve(address(vault), deficit);
            vault.deposit(deficit, user);
            vm.stopPrank();
        }
    }

    function _warpPastChallengePeriod() internal {
        vm.warp(block.timestamp + engine.challengePeriod() + 1);
    }

    function _claimAndCommit(address val, bytes32 projectId, uint256 index, uint256 score, uint256 stakeAmt)
        internal
        virtual
    {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, index));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _ensureStake(val, stakeAmt * 2);

        vm.startPrank(val);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(stakeAmt);
        engine.commitValidation(projectId, index, commitHash, stakeAmt, address(0));
        vm.stopPrank();
    }

    function _reveal(address val, bytes32 projectId, uint256 index, uint256 score) internal virtual {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, index));
        vm.prank(val);
        engine.revealValidation(projectId, index, score, salt);
    }
}
