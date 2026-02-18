// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {QualityEngine} from "../src/QualityEngine.sol";
import {StakeVault} from "../src/StakeVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {
    Project,
    ProjectStatus,
    Claim,
    ClaimStatus,
    IndexState,
    SubmissionStatus,
    Contribution,
    ContributionStatus,
    Reputation
} from "../src/Types.sol";

/// @notice Base test contract with common setup for all test suites
contract BaseTest is Test {
    QualityEngine public engine;
    StakeVault public vault;
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
    uint256 public constant FUND_AMOUNT = 10_000e18;
    uint256 public constant QUANTITY = 10;
    uint256 public constant STAKE_AMOUNT = 100e18;
    uint256 public constant VALIDATOR_STAKE = 50e18;

    function setUp() public virtual {
        // Deploy token
        token = new MockERC20("Sapien Token", "SPN");

        // Deploy StakeVault behind proxy
        StakeVault vaultImpl = new StakeVault();
        bytes memory vaultInit = abi.encodeCall(StakeVault.initialize, (token, admin));
        vault = StakeVault(address(new ERC1967Proxy(address(vaultImpl), vaultInit)));

        // Deploy QualityEngine behind proxy
        QualityEngine engineImpl = new QualityEngine();
        bytes memory engineInit =
            abi.encodeCall(QualityEngine.initialize, (admin, address(vault), treasury, address(0)));
        engine = QualityEngine(address(new ERC1967Proxy(address(engineImpl), engineInit)));

        // Grant ENGINE_ROLE to QualityEngine on the vault
        vm.startPrank(admin);
        vault.grantRole(vault.ENGINE_ROLE(), address(engine));
        vm.stopPrank();

        // Mint tokens and set up balances
        _setupBalances();
    }

    function _setupBalances() internal {
        // Originator gets reward tokens
        token.mint(originator, FUND_AMOUNT * 2);

        // Contributors and validators get stake tokens
        address[5] memory stakers = [contributor1, contributor2, validator1, validator2, validator3];
        for (uint256 i; i < stakers.length; ++i) {
            token.mint(stakers[i], STAKE_AMOUNT * 10);
            vm.startPrank(stakers[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 5, stakers[i]);
            vm.stopPrank();
        }
    }

    /// @dev Helper to create and fund a standard test project
    function _createAndFundProject() internal returns (bytes32) {
        return _createAndFundProject(PROJECT_ID, FUND_AMOUNT, QUANTITY);
    }

    function _createAndFundProject(bytes32 projectId, uint256 amount, uint256 qty) internal returns (bytes32) {
        vm.startPrank(originator);

        Project memory config = Project({
            originator: address(0), // set by contract
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000, // 70%
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000, // 20%
            numberOfValidations: 3,
            requiredSkill: bytes32(0),
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0
        });

        engine.createProject(projectId, config);

        token.approve(address(engine), amount);
        engine.fundProject(projectId, amount, qty, adapter);

        vm.stopPrank();

        return projectId;
    }

    /// @dev Helper to claim and contribute a single index
    function _claimAndContribute(address contrib, bytes32 projectId, uint256 qty)
        internal
        returns (uint256 claimId, uint256[] memory indices)
    {
        vm.startPrank(contrib);
        (claimId, indices) = engine.claimToContribute(projectId, qty, adapter);
        for (uint256 i; i < indices.length; ++i) {
            bytes32 hash = keccak256(abi.encodePacked("submission", indices[i]));
            engine.contribute(claimId, indices[i], hash);
        }
        vm.stopPrank();
        return (claimId, indices);
    }

    /// @dev Helper for commit-reveal validation
    function _commitAndReveal(address val, bytes32 projectId, uint256 index, uint16 score, uint128 stakeAmt) internal {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, index));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        vm.startPrank(val);

        // Set validator capacity if needed
        engine.setValidatorCapacity(stakeAmt);

        // Commit
        engine.commitValidation(projectId, index, commitHash, stakeAmt);

        // Reveal
        engine.revealValidation(projectId, index, score, salt);

        vm.stopPrank();
    }
}
