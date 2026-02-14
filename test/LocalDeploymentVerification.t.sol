// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {SapienCore} from "src/SapienCore.sol";
import {ValidationOracle} from "src/ValidationOracle.sol";
import {SapienTrust} from "src/SapienTrust.sol";
import {SapienVault} from "src/SapienVault.sol";
import {Rewards} from "src/Rewards.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {
    LOCKER_ROLE,
    SLASHER_ROLE,
    PAUSER_ROLE,
    UPDATER_ROLE,
    SAPIEN_CORE_ROLE
} from "src/interface/ISharedTypes.sol";

/**
 * @title LocalDeploymentVerification
 * @notice Verifies that a local Anvil deployment (from deploy-local.sh) is correctly configured.
 * @dev Requires: 1) deploy-local.sh run first (creates deployments/local.json)
 *                2) Anvil running on http://localhost:8545
 *
 * Run: forge test --match-contract LocalDeploymentVerification --fork-url http://localhost:8545
 */
contract LocalDeploymentVerification is Test {
    string constant DEPLOYMENTS_PATH = "deployments/local.json";
    string constant RPC_URL = "http://localhost:8545";

    // Anvil default test accounts (from DeployToAnvil)
    address constant ADMIN = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant ORIGINATOR = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant CONTRIBUTOR = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address constant VALIDATOR1 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    address constant VALIDATOR2 = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;
    address constant VALIDATOR3 = 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc;

    SapienCore core;
    ValidationOracle oracle;
    SapienTrust trust;
    SapienVault vault;
    Rewards rewards;
    MockERC20 stakeToken;
    MockERC20 rewardToken;

    function setUp() public {
        string memory json = vm.readFile(DEPLOYMENTS_PATH);
        require(bytes(json).length > 0, "deployments/local.json is empty - run deploy-local.sh first");

        address coreAddr = vm.parseJsonAddress(json, ".SAPIEN_CORE");
        address oracleAddr = vm.parseJsonAddress(json, ".VALIDATION_ORACLE");
        address trustAddr = vm.parseJsonAddress(json, ".SAPIEN_TRUST");
        address vaultAddr = vm.parseJsonAddress(json, ".SAPIEN_VAULT");
        address rewardsAddr = vm.parseJsonAddress(json, ".REWARDS");
        address stakeTokenAddr = vm.parseJsonAddress(json, ".SAPIEN_TOKEN");
        address rewardTokenAddr = vm.parseJsonAddress(json, ".USDC");

        vm.createSelectFork(RPC_URL);

        core = SapienCore(coreAddr);
        oracle = ValidationOracle(oracleAddr);
        trust = SapienTrust(trustAddr);
        vault = SapienVault(vaultAddr);
        rewards = Rewards(rewardsAddr);
        stakeToken = MockERC20(stakeTokenAddr);
        rewardToken = MockERC20(rewardTokenAddr);
    }

    function test_contractsHaveCode() public view {
        assertTrue(_hasCode(address(core)), "SapienCore has no code");
        assertTrue(_hasCode(address(oracle)), "ValidationOracle has no code");
        assertTrue(_hasCode(address(trust)), "SapienTrust has no code");
        assertTrue(_hasCode(address(vault)), "SapienVault has no code");
        assertTrue(_hasCode(address(rewards)), "Rewards has no code");
        assertTrue(_hasCode(address(stakeToken)), "StakeToken has no code");
        assertTrue(_hasCode(address(rewardToken)), "RewardToken has no code");
    }

    function test_coreContractLinks() public view {
        assertEq(core.getVault(), address(vault), "Core -> Vault link");
        assertEq(core.getRewards(), address(rewards), "Core -> Rewards link");
        assertEq(core.getTrust(), address(trust), "Core -> Trust link");
        assertEq(core.getValidationOracle(), address(oracle), "Core -> Oracle link");
    }

    function test_rewardsLinkedToCore() public view {
        assertEq(rewards.core(), address(core), "Rewards.core");
    }

    function test_trustConfiguration() public view {
        assertEq(address(trust.vault()), address(vault), "Trust -> Vault link");
        assertEq(trust.minStakeRequired(), 100 ether, "Trust minStakeRequired");
        assertTrue(trust.hasRole(UPDATER_ROLE, address(oracle)), "Trust: Oracle has UPDATER_ROLE");
        assertTrue(trust.hasRole(UPDATER_ROLE, address(core)), "Trust: Core has UPDATER_ROLE");
        assertTrue(trust.hasRole(UPDATER_ROLE, ADMIN), "Trust: Admin has UPDATER_ROLE");
    }

    function test_oracleConfiguration() public view {
        assertEq(address(oracle.trust()), address(trust), "Oracle -> Trust link");
        assertEq(address(oracle.vault()), address(vault), "Oracle -> Vault link");
        assertTrue(oracle.hasRole(SAPIEN_CORE_ROLE, address(core)), "Oracle: Core has SAPIEN_CORE_ROLE");
        assertTrue(oracle.hasRole(SAPIEN_CORE_ROLE, ADMIN), "Oracle: Admin has SAPIEN_CORE_ROLE");

        bytes32 sqrtStakeAlgo = keccak256("SqrtStake");
        assertTrue(oracle.algorithms(sqrtStakeAlgo) != address(0), "Oracle: SqrtStake algorithm registered");
    }

    function test_vaultConfiguration() public view {
        assertEq(address(vault.asset()), address(stakeToken), "Vault asset is stake token");
        assertFalse(vault.paused(), "Vault should not be paused");

        assertTrue(vault.hasRole(LOCKER_ROLE, address(oracle)), "Vault: Oracle has LOCKER_ROLE");
        assertTrue(vault.hasRole(LOCKER_ROLE, address(core)), "Vault: Core has LOCKER_ROLE");
        assertTrue(vault.hasRole(LOCKER_ROLE, ADMIN), "Vault: Admin has LOCKER_ROLE");
        assertTrue(vault.hasRole(SLASHER_ROLE, address(oracle)), "Vault: Oracle has SLASHER_ROLE");
        assertTrue(vault.hasRole(SLASHER_ROLE, address(core)), "Vault: Core has SLASHER_ROLE");
        assertTrue(vault.hasRole(SLASHER_ROLE, address(vault)), "Vault: self-slashing");
        assertTrue(vault.hasRole(PAUSER_ROLE, ADMIN), "Vault: Admin has PAUSER_ROLE");
    }

    function test_testAccountsHaveVaultDeposits() public view {
        uint256 minExpected = 100 ether; // DeployToAnvil deposits 1000 ether each

        assertGe(vault.balanceOf(ORIGINATOR), minExpected, "Originator vault balance");
        assertGe(vault.balanceOf(CONTRIBUTOR), minExpected, "Contributor vault balance");
        assertGe(vault.balanceOf(VALIDATOR1), minExpected, "Validator1 vault balance");
        assertGe(vault.balanceOf(VALIDATOR2), minExpected, "Validator2 vault balance");
        assertGe(vault.balanceOf(VALIDATOR3), minExpected, "Validator3 vault balance");
    }

    function test_mockTokensConfigured() public view {
        assertEq(stakeToken.decimals(), 18, "Stake token decimals");
        assertEq(rewardToken.decimals(), 6, "Reward token decimals");
        assertGe(stakeToken.totalSupply(), 5000 ether, "Stake token minted"); // 5 accounts * 1000
        assertGe(rewardToken.balanceOf(ORIGINATOR), 10000 ether, "Originator has reward tokens");
    }

    function _hasCode(address account) internal view returns (bool) {
        return account.code.length > 0;
    }
}
