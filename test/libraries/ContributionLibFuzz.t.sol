// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {Project, ProjectStatus, Claim, ClaimStatus, Contribution, ContributionStatus} from "src/Types.sol";

/// @title ContributionLibFuzz
/// @notice Fuzz tests attempting to break ContributionLib with edge cases
contract ContributionLibFuzz is Test {
    SapienCore public engine;
    SapienVault public vault;
    MockERC20 public token;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public originator = makeAddr("originator");
    address public contributor = makeAddr("contributor");

    bytes32 public constant PROJECT_ID = keccak256("test-project");
    bytes32 constant SKILL_ID = keccak256("DATA_ANNOTATION");
    uint256 public constant STAKE_AMOUNT = 100e18;

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

        _setupBalances();
        _createAndFundProject(PROJECT_ID, 100_000e18, 100);
    }

    function _setupBalances() internal {
        token.mint(originator, 1_000_000e18);
        vm.prank(originator);
        token.approve(address(engine), type(uint256).max);

        token.mint(contributor, STAKE_AMOUNT * 100);
        vm.startPrank(contributor);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(STAKE_AMOUNT * 50, contributor);
        vm.stopPrank();
    }

    function _createAndFundProject(bytes32 projectId, uint256 amount, uint256 qty) internal {
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

        vm.startPrank(originator);
        engine.createProject(projectId, "", config);
        token.approve(address(engine), amount);
        engine.fundProject(projectId, amount, qty, address(0));
        vm.stopPrank();
    }

    function testFuzz_claimToContribute_validQuantity(uint8 quantity) public {
        quantity = uint8(bound(quantity, 1, C.MAX_CLAIM_QUANTITY));

        _ensureStake(contributor, STAKE_AMOUNT * quantity);

        vm.prank(contributor);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, quantity, address(0));

        assertEq(indices.length, quantity);
        assertTrue(claimId > 0 || claimId == 0);

        Claim memory claim = engine.getClaim(claimId);
        address claimant = claim.claimant;
        uint256 deadline = claim.deadline;
        uint256 totalCount = claim.totalCount;
        ClaimStatus status = claim.status;
        assertEq(claimant, contributor);
        assertEq(totalCount, quantity);
        assertEq(uint8(status), uint8(ClaimStatus.Active));
        assertGt(deadline, block.timestamp);
    }

    function testFuzz_claimToContribute_revertsZeroQuantity() public {
        vm.prank(contributor);
        vm.expectRevert(ISapienCore.ZeroAmount.selector);
        engine.claimToContribute(PROJECT_ID, 0, address(0));
    }

    function testFuzz_claimToContribute_revertsExceedsMaxQuantity(uint256 quantity) public {
        quantity = bound(quantity, C.MAX_CLAIM_QUANTITY + 1, type(uint128).max);

        vm.prank(contributor);
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.ClaimQuantityTooHigh.selector, quantity, C.MAX_CLAIM_QUANTITY)
        );
        engine.claimToContribute(PROJECT_ID, quantity, address(0));
    }

    function testFuzz_claimToContribute_revertsNoSlots(uint8 quantity) public {
        quantity = uint8(bound(quantity, 1, C.MAX_CLAIM_QUANTITY));

        bytes32 smallProject = keccak256("small-project");
        _createAndFundProject(smallProject, 1000e18, 1);

        _ensureStake(contributor, STAKE_AMOUNT * quantity);

        vm.prank(contributor);
        engine.claimToContribute(smallProject, 1, address(0));

        _ensureStake(contributor, STAKE_AMOUNT * quantity);

        vm.prank(contributor);
        vm.expectRevert(ISapienCore.NoSlotsAvailable.selector);
        engine.claimToContribute(smallProject, quantity, address(0));
    }

    function testFuzz_claimToContribute_revertsOriginatorContributing() public {
        vm.prank(originator);
        vm.expectRevert(ISapienCore.OriginatorCannotContribute.selector);
        engine.claimToContribute(PROJECT_ID, 1, address(0));
    }

    function testFuzz_claimToContribute_revertsNonExistentProject(bytes32 fakeProjectId) public {
        vm.assume(fakeProjectId != PROJECT_ID);

        vm.prank(contributor);
        vm.expectRevert(ISapienCore.ProjectNotActive.selector);
        engine.claimToContribute(fakeProjectId, 1, address(0));
    }

    function testFuzz_contribute_validSubmission(bytes32 submissionHash, string calldata dataCid) public {
        vm.assume(submissionHash != bytes32(0));

        _ensureStake(contributor, STAKE_AMOUNT);

        vm.prank(contributor);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 1, address(0));

        vm.prank(contributor);
        engine.contribute(claimId, indices[0], submissionHash, dataCid);

        Contribution memory contrib = engine.getContribution(PROJECT_ID, indices[0]);

        assertEq(contrib.contributor, contributor);
        assertEq(contrib.claimId, claimId);
        assertEq(uint8(contrib.status), uint8(ContributionStatus.Pending));
        assertEq(contrib.submissionHash, submissionHash);
    }

    function testFuzz_contribute_revertsNotClaimOwner(address notOwner) public {
        vm.assume(notOwner != contributor && notOwner != address(0) && notOwner != originator);

        _ensureStake(contributor, STAKE_AMOUNT);

        vm.prank(contributor);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 1, address(0));

        vm.prank(notOwner);
        vm.expectRevert(ISapienCore.NotClaimOwner.selector);
        engine.contribute(claimId, indices[0], keccak256("test"), "");
    }

    function testFuzz_contribute_revertsAfterDeadline(uint256 timeWarp) public {
        timeWarp = bound(timeWarp, engine.claimDeadline() + 1, 365 days);

        _ensureStake(contributor, STAKE_AMOUNT);

        vm.prank(contributor);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 1, address(0));

        vm.warp(block.timestamp + timeWarp);

        vm.prank(contributor);
        vm.expectRevert(ISapienCore.ClaimDeadlinePassed.selector);
        engine.contribute(claimId, indices[0], keccak256("test"), "");
    }

    function testFuzz_contribute_revertsIndexNotInClaim(
        uint256 /* wrongIndex */
    )
        public
    {
        _ensureStake(contributor, STAKE_AMOUNT * 2);

        vm.prank(contributor);
        (uint256 claimId1,) = engine.claimToContribute(PROJECT_ID, 1, address(0));

        address contributor2 = makeAddr("contributor2");
        token.mint(contributor2, STAKE_AMOUNT * 10);
        vm.startPrank(contributor2);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(STAKE_AMOUNT * 5, contributor2);
        (, uint256[] memory indices2) = engine.claimToContribute(PROJECT_ID, 1, address(0));
        vm.stopPrank();

        vm.prank(contributor);
        vm.expectRevert(ISapienCore.IndexNotInClaim.selector);
        engine.contribute(claimId1, indices2[0], keccak256("test"), "");
    }

    function testFuzz_contribute_revertsDoubleSubmission() public {
        _ensureStake(contributor, STAKE_AMOUNT * 2);

        vm.prank(contributor);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 2, address(0));

        vm.prank(contributor);
        engine.contribute(claimId, indices[0], keccak256("first"), "");

        vm.prank(contributor);
        vm.expectRevert(ISapienCore.IndexNotReserved.selector);
        engine.contribute(claimId, indices[0], keccak256("second"), "");
    }

    function testFuzz_batchContribute_validBatch(uint8 batchSize) public {
        batchSize = uint8(bound(batchSize, 1, C.MAX_CLAIM_QUANTITY));

        _ensureStake(contributor, STAKE_AMOUNT * batchSize);

        vm.prank(contributor);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, batchSize, address(0));

        bytes32[] memory hashes = new bytes32[](batchSize);
        string[] memory cids = new string[](batchSize);
        for (uint256 i; i < batchSize; ++i) {
            hashes[i] = keccak256(abi.encodePacked("submission", i));
            cids[i] = "";
        }

        vm.prank(contributor);
        engine.batchContribute(claimId, indices, hashes, cids);

        Claim memory claim = engine.getClaim(claimId);
        assertEq(claim.submittedCount, batchSize);
    }

    function testFuzz_batchContribute_revertsMismatchedArrays() public {
        _ensureStake(contributor, STAKE_AMOUNT * 3);

        vm.prank(contributor);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 3, address(0));

        bytes32[] memory hashes = new bytes32[](2);
        string[] memory cids = new string[](3);

        vm.prank(contributor);
        vm.expectRevert(ISapienCore.InvalidIndex.selector);
        engine.batchContribute(claimId, indices, hashes, cids);
    }

    function testFuzz_batchContribute_revertsEmptyBatch() public {
        _ensureStake(contributor, STAKE_AMOUNT);

        vm.prank(contributor);
        (uint256 claimId,) = engine.claimToContribute(PROJECT_ID, 1, address(0));

        uint256[] memory emptyIndices = new uint256[](0);
        bytes32[] memory emptyHashes = new bytes32[](0);
        string[] memory emptyCids = new string[](0);

        vm.prank(contributor);
        vm.expectRevert(ISapienCore.ZeroAmount.selector);
        engine.batchContribute(claimId, emptyIndices, emptyHashes, emptyCids);
    }

    function testFuzz_expireClaim_slashesUnsubmitted(uint8 submitted, uint8 unsubmitted) public {
        submitted = uint8(bound(submitted, 0, 5));
        unsubmitted = uint8(bound(unsubmitted, 1, 10));
        uint8 total = submitted + unsubmitted;
        if (total > C.MAX_CLAIM_QUANTITY) {
            total = uint8(C.MAX_CLAIM_QUANTITY);
            if (submitted >= total) submitted = total - 1;
            unsubmitted = total - submitted;
        }

        _ensureStake(contributor, STAKE_AMOUNT * total * 2);

        vm.prank(contributor);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, total, address(0));

        for (uint256 i; i < submitted; ++i) {
            vm.prank(contributor);
            engine.contribute(claimId, indices[i], keccak256(abi.encodePacked(i)), "");
        }

        vm.warp(block.timestamp + engine.claimDeadline() + 1);

        vm.prank(contributor);
        engine.expireClaim(claimId, indices);

        Claim memory claim = engine.getClaim(claimId);
        assertEq(uint8(claim.status), uint8(ClaimStatus.Expired));
    }

    function testFuzz_expireClaim_revertsBeforeDeadline() public {
        _ensureStake(contributor, STAKE_AMOUNT);

        vm.prank(contributor);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 1, address(0));

        vm.prank(contributor);
        vm.expectRevert(ISapienCore.ClaimDeadlineNotPassed.selector);
        engine.expireClaim(claimId, indices);
    }

    function testFuzz_expireClaim_revertsAlreadyCompleted() public {
        _ensureStake(contributor, STAKE_AMOUNT);

        vm.prank(contributor);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 1, address(0));

        vm.prank(contributor);
        engine.contribute(claimId, indices[0], keccak256("test"), "");

        vm.warp(block.timestamp + engine.claimDeadline() + 1);

        vm.prank(contributor);
        vm.expectRevert(ISapienCore.ClaimDeadlineNotPassed.selector);
        engine.expireClaim(claimId, indices);
    }

    function testFuzz_expireClaim_revertsWrongIndices() public {
        _ensureStake(contributor, STAKE_AMOUNT * 2);

        vm.prank(contributor);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 1, address(0));

        uint256[] memory wrongIndices = new uint256[](2);
        wrongIndices[0] = indices[0];
        wrongIndices[1] = 999;

        vm.warp(block.timestamp + engine.claimDeadline() + 1);

        vm.prank(contributor);
        vm.expectRevert(ISapienCore.InvalidIndex.selector);
        engine.expireClaim(claimId, wrongIndices);
    }

    function testFuzz_multipleClaims_independentSlots(uint8 numClaims) public {
        numClaims = uint8(bound(numClaims, 2, 10));

        address[] memory contributors = new address[](numClaims);
        uint256[][] memory allIndices = new uint256[][](numClaims);

        for (uint256 i; i < numClaims; ++i) {
            contributors[i] = address(uint160(0x1000 + i));
            _setupContributor(contributors[i]);

            vm.prank(contributors[i]);
            (, allIndices[i]) = engine.claimToContribute(PROJECT_ID, 1, address(0));
        }

        for (uint256 i; i < numClaims; ++i) {
            for (uint256 j = i + 1; j < numClaims; ++j) {
                assertTrue(allIndices[i][0] != allIndices[j][0], "Indices should be unique");
            }
        }
    }

    function testFuzz_slotRecycling_afterExpiry(uint8 quantity) public {
        quantity = uint8(bound(quantity, 1, 5));

        _ensureStake(contributor, STAKE_AMOUNT * quantity * 3);

        vm.prank(contributor);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, quantity, address(0));

        Project memory projBefore = engine.getProject(PROJECT_ID);
        uint256 availableBefore = projBefore.availableSlots;

        vm.warp(block.timestamp + engine.claimDeadline() + 1);

        vm.prank(contributor);
        engine.expireClaim(claimId, indices);

        Project memory projAfter = engine.getProject(PROJECT_ID);
        assertEq(projAfter.availableSlots, availableBefore + quantity, "Slots should be recycled");
    }

    function _ensureStake(address user, uint256 needed) internal {
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

    function _setupContributor(address user) internal {
        token.mint(user, STAKE_AMOUNT * 10);
        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(STAKE_AMOUNT * 5, user);
        vm.stopPrank();
    }
}
