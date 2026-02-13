// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {SapienCore} from "../src/SapienCore.sol";
import {ValidationOracle} from "../src/ValidationOracle.sol";
import {SapienTrust} from "../src/SapienTrust.sol";
import {SapienVault} from "../src/SapienVault.sol";
import {Rewards} from "../src/Rewards.sol";
import {SqrtStakeConsensus} from "../src/consensus/SqrtStakeConsensus.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
    LOCKER_ROLE,
    SLASHER_ROLE,
    PAUSER_ROLE,
    UPDATER_ROLE,
    SAPIEN_CORE_ROLE
} from "../src/interface/ISharedTypes.sol";
import {ISharedTypes} from "../src/interface/ISharedTypes.sol";

abstract contract BaseTest is Test, ISharedTypes {
    SapienCore public core;
    ValidationOracle public oracle;
    SapienTrust public trust;
    SapienVault public vault;
    Rewards public rewards;

    MockERC20 public stakeToken;
    MockERC20 public rewardToken;

    address public admin = makeAddr("admin");
    address public originator = makeAddr("originator");
    address public contributor = makeAddr("contributor");
    address public validator1 = makeAddr("validator1");
    address public validator2 = makeAddr("validator2");
    address public validator3 = makeAddr("validator3");

    function setUp() public virtual {
        _deployTokens();
        _deployProtocol();
        _setupRolesAndAlgorithms();
        _setupInitialFunds();
    }

    function _deployTokens() internal {
        stakeToken = new MockERC20("Stake", "STAKE", 18);
        rewardToken = new MockERC20("Reward", "REWARD", 18);
    }

    function _deployProtocol() internal {
        _deployVault();
        _deployRewards();
        _deployTrust();
        _deployOracle();
        _deployCore();
    }

    function _deployVault() internal {
        address vaultImpl = address(new SapienVault());
        bytes memory vaultInitData = abi.encodeWithSelector(SapienVault.initialize.selector, address(stakeToken), admin);
        vault = SapienVault(address(new ERC1967Proxy(vaultImpl, vaultInitData)));
    }

    function _deployRewards() internal {
        address rewardsImpl = address(new Rewards());
        bytes memory rewardsInitData = abi.encodeWithSelector(Rewards.initialize.selector, admin);
        rewards = Rewards(address(new ERC1967Proxy(rewardsImpl, rewardsInitData)));
    }

    function _deployTrust() internal {
        address trustImpl = address(new SapienTrust());
        bytes memory trustInitData =
            abi.encodeWithSelector(SapienTrust.initialize.selector, address(vault), 100 ether, 10, admin);
        trust = SapienTrust(address(new ERC1967Proxy(trustImpl, trustInitData)));
    }

    function _deployOracle() internal {
        address oracleImpl = address(new ValidationOracle());
        bytes memory oracleInitData = abi.encodeWithSelector(
            ValidationOracle.initialize.selector, address(trust), address(vault), "SqrtStake", admin
        );
        oracle = ValidationOracle(address(new ERC1967Proxy(oracleImpl, oracleInitData)));
    }

    function _deployCore() internal {
        address coreImpl = address(new SapienCore());
        bytes memory coreInitData = abi.encodeWithSelector(
            SapienCore.initialize.selector, address(vault), address(rewards), address(trust), address(oracle), admin
        );
        core = SapienCore(address(new ERC1967Proxy(coreImpl, coreInitData)));
    }

    function _setupRolesAndAlgorithms() internal {
        vm.startPrank(admin);

        oracle.registerAlgorithm("SqrtStake", address(new SqrtStakeConsensus()));
        rewards.setCore(address(core));

        trust.grantRole(UPDATER_ROLE, address(oracle));
        trust.grantRole(UPDATER_ROLE, address(core));
        trust.grantRole(UPDATER_ROLE, admin);

        vault.grantRole(LOCKER_ROLE, admin);
        vault.grantRole(SLASHER_ROLE, admin);
        vault.grantRole(PAUSER_ROLE, admin);

        vault.grantRole(LOCKER_ROLE, address(oracle));
        vault.grantRole(LOCKER_ROLE, address(core));
        vault.grantRole(SLASHER_ROLE, address(oracle));
        vault.grantRole(SLASHER_ROLE, address(core));
        vault.grantRole(SLASHER_ROLE, address(vault));

        oracle.grantRole(SAPIEN_CORE_ROLE, address(core));
        oracle.grantRole(SAPIEN_CORE_ROLE, admin);

        vm.stopPrank();
    }

    function _setupInitialFunds() internal {
        _setupUser(originator, 1000 ether);
        _setupUser(contributor, 1000 ether);
        _setupUser(validator1, 1000 ether);
        _setupUser(validator2, 1000 ether);
        _setupUser(validator3, 1000 ether);

        rewardToken.mint(originator, 10000 ether);
    }

    function _setupUser(address user, uint256 amount) internal {
        stakeToken.mint(user, amount);
        vm.startPrank(user);
        stakeToken.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    /**
     * @notice Helper to set validator capacity (required for new capacity-based staking)
     * @param validator The validator address
     * @param capacity The capacity amount to set
     */
    function _setValidatorCapacity(address validator, uint256 capacity) internal {
        // Skip if capacity is already at target to avoid CapacityUnchanged revert
        (uint256 currentCapacity,) = oracle.validatorStates(validator);
        if (currentCapacity == capacity) return;
        vm.prank(validator);
        oracle.setValidatorCapacity(capacity);
    }

    // --- SAPPIEN CORE GETTER HELPERS ---

    function getProjectOriginator(bytes32 projectId) internal view returns (address originatorAddr) {
        return core.getProject(projectId).originator;
    }

    function getProjectRewards(bytes32 projectId) internal view returns (uint256 rewardsAvailable) {
        return core.getProject(projectId).state.totalRewardsAvailable;
    }

    function getProjectQuantity(bytes32 projectId) internal view returns (uint256 quantityAvailable) {
        return core.getProject(projectId).state.totalQuantityAvailable;
    }

    function getClaimStatus(bytes32 projectId, uint256 claimId) internal view returns (ClaimStatus status) {
        return core.getClaim(projectId, claimId).status;
    }

    function getClaimContributor(bytes32 projectId, uint256 claimId) internal view returns (address contributorAddr) {
        return core.getClaim(projectId, claimId).contributor;
    }

    function getClaimQuantity(bytes32 projectId, uint256 claimId) internal view returns (uint256 quantity) {
        return core.getClaim(projectId, claimId).quantity;
    }

    function getContributionStatus(bytes32 projectId, uint256 index) internal view returns (ContributionStatus status) {
        return core.getContribution(projectId, index).status;
    }

    function getContributionContributor(bytes32 projectId, uint256 index)
        internal
        view
        returns (address contributorAddr)
    {
        return core.getContribution(projectId, index).contributor;
    }

    function getContributionHash(bytes32 projectId, uint256 index) internal view returns (bytes32 subHash) {
        return core.getContribution(projectId, index).submissionHash;
    }
}
