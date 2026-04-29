// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SapienVault} from "src/SapienVault.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

/// @title SlashRoundingTest
/// @notice Tests that _burnShares uses rounding-up (previewWithdraw) so slashes
///         are never economically weaker than intended, and reverts on zero-share burns.
contract SlashRoundingTest is Test {
    SapienVault public vault;
    MockERC20 public token;

    address public admin = makeAddr("admin");
    address public engine = makeAddr("engine");
    address public user1 = makeAddr("user1");
    address public donor = makeAddr("donor");

    uint256 public constant DEPOSIT = 1000e18;

    function setUp() public {
        token = new MockERC20("Sapien Token", "SPN");

        SapienVault vaultImpl = new SapienVault();
        bytes memory initData = abi.encodeCall(SapienVault.initialize, (IERC20(address(token)), admin));
        vault = SapienVault(address(new ERC1967Proxy(address(vaultImpl), initData)));

        vm.startPrank(admin);
        vault.grantRole(vault.ENGINE_ROLE(), engine);
        vm.stopPrank();

        token.mint(user1, DEPOSIT * 10);
        vm.startPrank(user1);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(DEPOSIT, user1);
        vm.stopPrank();
    }

    /// @dev Donate tokens directly to the vault to raise the exchange rate
    function _donateToVault(uint256 amount) internal {
        token.mint(donor, amount);
        vm.prank(donor);
        token.transfer(address(vault), amount);
    }

    // ─── slashContributor rounding tests ─────────────────────────────

    function test_slashContributor_roundsUp_afterDonation() public {
        vm.prank(engine);
        vault.lockContributor(user1, 500e18);

        // Donate to raise exchange rate: 1 share now represents ~2 assets
        _donateToVault(DEPOSIT);

        uint256 sharesBefore = vault.balanceOf(user1);
        uint256 expectedShares = vault.previewWithdraw(1);

        // previewWithdraw rounds up — must burn at least 1 share
        assertGt(expectedShares, 0, "previewWithdraw(1) should be > 0");

        // Slash 1 wei of assets — with round-up, should burn previewWithdraw(1) shares
        vm.prank(engine);
        vault.slashContributor(user1, 1);

        uint256 sharesAfter = vault.balanceOf(user1);
        assertLt(sharesAfter, sharesBefore, "Shares should decrease after slash");
        assertEq(sharesBefore - sharesAfter, expectedShares, "Shares burned should match previewWithdraw");
    }

    function test_slashContributor_burnsCorrectShares_atHighExchangeRate() public {
        vm.prank(engine);
        vault.lockContributor(user1, 500e18);

        // Donate 9x the deposit to raise rate to ~10:1 (assets:shares)
        _donateToVault(DEPOSIT * 9);

        uint256 sharesBefore = vault.balanceOf(user1);
        uint256 slashAmount = 50e18;

        uint256 expectedSharesBurned = vault.previewWithdraw(slashAmount);
        assertGt(expectedSharesBurned, 0, "Should burn non-zero shares");

        vm.prank(engine);
        vault.slashContributor(user1, slashAmount);

        uint256 sharesAfter = vault.balanceOf(user1);
        assertEq(sharesBefore - sharesAfter, expectedSharesBurned, "Shares burned should match previewWithdraw");
    }

    // ─── slashValidator rounding tests ───────────────────────────────

    function test_slashValidator_roundsUp_afterDonation() public {
        vm.startPrank(engine);
        vault.lockValidatorCapacity(user1, 500e18);
        vault.commitStake(user1, 200e18);
        vm.stopPrank();

        // Donate to raise exchange rate
        _donateToVault(DEPOSIT);

        uint256 sharesBefore = vault.balanceOf(user1);

        // Slash 1 wei of assets — should still burn at least 1 share
        vm.prank(engine);
        vault.slashValidator(user1, 1);

        uint256 sharesAfter = vault.balanceOf(user1);
        assertLt(sharesAfter, sharesBefore, "Shares should decrease after validator slash");
    }

    function test_slashValidator_burnsCorrectShares_atHighExchangeRate() public {
        vm.startPrank(engine);
        vault.lockValidatorCapacity(user1, 500e18);
        vault.commitStake(user1, 200e18);
        vm.stopPrank();

        _donateToVault(DEPOSIT * 9);

        uint256 sharesBefore = vault.balanceOf(user1);
        uint256 slashAmount = 30e18;

        uint256 expectedSharesBurned = vault.previewWithdraw(slashAmount);

        vm.prank(engine);
        vault.slashValidator(user1, slashAmount);

        uint256 sharesAfter = vault.balanceOf(user1);
        assertEq(sharesBefore - sharesAfter, expectedSharesBurned, "Validator slash should burn rounded-up shares");
    }

    // ─── slashAndUnlockContributor rounding tests ────────────────────

    function test_slashAndUnlockContributor_roundsUp() public {
        vm.prank(engine);
        vault.lockContributor(user1, 500e18);

        _donateToVault(DEPOSIT);

        uint256 sharesBefore = vault.balanceOf(user1);
        uint256 slashAmount = 1;
        uint256 unlockAmount = 100e18;

        vm.prank(engine);
        vault.slashAndUnlockContributor(user1, slashAmount, unlockAmount);

        uint256 sharesAfter = vault.balanceOf(user1);
        assertLt(sharesAfter, sharesBefore, "slashAndUnlock should burn shares even for 1 wei slash");
    }

    // ─── ZeroShareSlash revert ───────────────────────────────────────

    function test_slashContributor_revertsZeroShareSlash_forZeroAmount() public {
        vm.prank(engine);
        vault.lockContributor(user1, 500e18);

        // slashContributor already reverts with ZeroAmount for amount == 0,
        // but let's verify that path
        vm.prank(engine);
        vm.expectRevert(ISapienVault.ZeroAmount.selector);
        vault.slashContributor(user1, 0);
    }

    // ─── Normal slash at 1:1 rate still works ────────────────────────

    function test_slashContributor_normalRate_works() public {
        vm.prank(engine);
        vault.lockContributor(user1, 500e18);

        uint256 sharesBefore = vault.balanceOf(user1);
        uint256 slashAmount = 100e18;

        vm.prank(engine);
        vault.slashContributor(user1, slashAmount);

        uint256 sharesAfter = vault.balanceOf(user1);
        assertGt(sharesBefore - sharesAfter, 0, "Should burn shares at normal rate");
    }

    function test_slashValidator_normalRate_works() public {
        vm.startPrank(engine);
        vault.lockValidatorCapacity(user1, 400e18);
        vault.commitStake(user1, 200e18);
        vm.stopPrank();

        uint256 sharesBefore = vault.balanceOf(user1);

        vm.prank(engine);
        vault.slashValidator(user1, 100e18);

        uint256 sharesAfter = vault.balanceOf(user1);
        assertGt(sharesBefore - sharesAfter, 0, "Should burn shares at normal rate");
    }

    // ─── Slash rounds up rather than down (property test) ────────────

    function test_slash_alwaysBurnsAtLeastPreviewWithdrawShares() public {
        uint256[4] memory donations = [uint256(0), DEPOSIT / 2, DEPOSIT, DEPOSIT * 5];
        uint256[4] memory slashAmounts = [uint256(1e18), 10e18, 100e18, 1];

        for (uint256 i = 0; i < donations.length; i++) {
            MockERC20 freshToken = new MockERC20("Sapien Token", "SPN");
            SapienVault freshVault = SapienVault(
                address(
                    new ERC1967Proxy(
                        address(new SapienVault()),
                        abi.encodeCall(SapienVault.initialize, (IERC20(address(freshToken)), admin))
                    )
                )
            );

            vm.startPrank(admin);
            freshVault.grantRole(freshVault.ENGINE_ROLE(), engine);
            vm.stopPrank();

            freshToken.mint(user1, DEPOSIT * 10);
            vm.startPrank(user1);
            freshToken.approve(address(freshVault), type(uint256).max);
            freshVault.deposit(DEPOSIT, user1);
            vm.stopPrank();

            vm.prank(engine);
            freshVault.lockContributor(user1, 800e18);

            if (donations[i] > 0) {
                freshToken.mint(donor, donations[i]);
                vm.prank(donor);
                freshToken.transfer(address(freshVault), donations[i]);
            }

            uint256 expectedShares = freshVault.previewWithdraw(slashAmounts[i]);
            uint256 sharesBefore = freshVault.balanceOf(user1);

            vm.prank(engine);
            freshVault.slashContributor(user1, slashAmounts[i]);

            uint256 sharesAfter = freshVault.balanceOf(user1);
            uint256 actualBurned = sharesBefore - sharesAfter;

            assertEq(
                actualBurned,
                expectedShares,
                string.concat("Iteration ", vm.toString(i), ": shares burned should equal previewWithdraw")
            );
            assertGt(actualBurned, 0, string.concat("Iteration ", vm.toString(i), ": must burn at least 1 share"));
        }
    }
}
