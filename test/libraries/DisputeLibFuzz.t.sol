// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {
    Project,
    ProjectStatus,
    Contribution,
    ContributionStatus,
    Dispute,
    DisputeStatus,
    OriginatorReport,
    OriginatorReportStatus
} from "src/Types.sol";

/// @title DisputeLibFuzz
/// @notice Fuzz tests attempting to break DisputeLib with edge cases
contract DisputeLibFuzz is Test {
    SapienCore public engine;
    SapienVault public vault;
    MockERC20 public token;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public originator = makeAddr("originator");
    address public contributor = makeAddr("contributor");
    address public challenger = makeAddr("challenger");
    address public validator1 = makeAddr("validator1");
    address public validator2 = makeAddr("validator2");
    address public validator3 = makeAddr("validator3");

    bytes32 public constant PROJECT_ID = keccak256("test-project");
    bytes32 constant SKILL_ID = keccak256("DATA_ANNOTATION");
    uint256 public constant STAKE_AMOUNT = 100e18;
    uint256 public constant VALIDATOR_STAKE = 50e18;

    uint256 public acceptedIndex;

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
        engine.setDisputeBondBps(500);
        vm.stopPrank();

        _setupBalances();
        _createProjectAndAcceptContribution();
    }

    function _setupBalances() internal {
        token.mint(originator, 1_000_000e18);
        vm.prank(originator);
        token.approve(address(engine), type(uint256).max);

        address[5] memory users = [contributor, challenger, validator1, validator2, validator3];
        for (uint256 i; i < users.length; ++i) {
            token.mint(users[i], STAKE_AMOUNT * 100);
            vm.startPrank(users[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 50, users[i]);
            vm.stopPrank();
        }
    }

    function _createProjectAndAcceptContribution() internal {
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
        engine.createProject(PROJECT_ID, "", config);
        engine.fundProject(PROJECT_ID, 100_000e18, 50, address(0));
        vm.stopPrank();

        vm.prank(contributor);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 1, address(0));

        vm.prank(contributor);
        engine.contribute(claimId, indices[0], keccak256("submission"), "");
        acceptedIndex = indices[0];

        _validateAndAccept(acceptedIndex, 8000);
    }

    function _validateAndAccept(uint256 index, uint256 score) internal {
        address[3] memory validators = [validator1, validator2, validator3];
        bytes32[3] memory salts;

        // Commit phase
        for (uint256 i; i < 3; ++i) {
            salts[i] = keccak256(abi.encodePacked("salt", validators[i], index));
            bytes32 commitHash = keccak256(abi.encodePacked(score, salts[i]));

            vm.prank(validators[i]);
            engine.claimToValidate(PROJECT_ID, 1);

            vm.prank(validators[i]);
            engine.lockValidatorCapacity(VALIDATOR_STAKE);

            vm.prank(validators[i]);
            engine.commitValidation(PROJECT_ID, index, commitHash, VALIDATOR_STAKE, address(0));
        }

        // Warp past commit deadline to allow reveals (only once)
        vm.warp(block.timestamp + engine.commitDeadline());

        // Reveal phase
        for (uint256 i; i < 3; ++i) {
            vm.prank(validators[i]);
            engine.revealValidation(PROJECT_ID, index, score, salts[i]);
        }

        engine.computeConsensus(PROJECT_ID, index);
    }

    function _fullValidation(address val, uint256 index, uint256 score) internal {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, index));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        vm.prank(val);
        engine.claimToValidate(PROJECT_ID, 1);

        vm.prank(val);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);

        vm.prank(val);
        engine.commitValidation(PROJECT_ID, index, commitHash, VALIDATOR_STAKE, address(0));

        // Warp past commit deadline to allow reveals
        vm.warp(block.timestamp + engine.commitDeadline());

        vm.prank(val);
        engine.revealValidation(PROJECT_ID, index, score, salt);
    }

    function testFuzz_openDispute_validDispute(bytes32 evidenceHash) public {
        vm.assume(evidenceHash != bytes32(0));

        vm.prank(challenger);
        engine.openDispute(PROJECT_ID, acceptedIndex, evidenceHash, "ipfs://evidence");

        Dispute memory dispute = engine.getDispute(PROJECT_ID, acceptedIndex);

        assertEq(dispute.challenger, challenger);
        assertEq(uint8(dispute.status), uint8(DisputeStatus.Open));
        assertGt(dispute.bondAmount, 0);
    }

    function testFuzz_openDispute_revertsZeroEvidenceHash() public {
        vm.prank(challenger);
        vm.expectRevert(ISapienCore.InvalidEvidenceHash.selector);
        engine.openDispute(PROJECT_ID, acceptedIndex, bytes32(0), "");
    }

    function testFuzz_openDispute_revertsNoConsensus(uint256 randomIndex) public {
        randomIndex = bound(randomIndex, 100, 1000);

        vm.prank(challenger);
        vm.expectRevert(ISapienCore.ConsensusNotComputed.selector);
        engine.openDispute(PROJECT_ID, randomIndex, keccak256("evidence"), "");
    }

    function testFuzz_openDispute_revertsAfterChallengePeriod(uint256 timeWarp) public {
        Contribution memory contrib = engine.getContribution(PROJECT_ID, acceptedIndex);
        timeWarp = bound(timeWarp, contrib.challengeEndsAt - block.timestamp + 1, 365 days);

        vm.warp(block.timestamp + timeWarp);

        vm.prank(challenger);
        vm.expectRevert(ISapienCore.DisputeWindowClosed.selector);
        engine.openDispute(PROJECT_ID, acceptedIndex, keccak256("evidence"), "");
    }

    function testFuzz_openDispute_revertsContributorDisputing() public {
        vm.prank(contributor);
        vm.expectRevert(ISapienCore.CannotDisputeOwnContribution.selector);
        engine.openDispute(PROJECT_ID, acceptedIndex, keccak256("evidence"), "");
    }

    function testFuzz_openDispute_revertsDoubleDispute() public {
        vm.prank(challenger);
        engine.openDispute(PROJECT_ID, acceptedIndex, keccak256("evidence1"), "");

        address challenger2 = makeAddr("challenger2");
        _setupUser(challenger2);

        vm.prank(challenger2);
        vm.expectRevert(ISapienCore.DisputeAlreadyOpen.selector);
        engine.openDispute(PROJECT_ID, acceptedIndex, keccak256("evidence2"), "");
    }

    function testFuzz_openDispute_bondCalculation(uint16 bondBps) public {
        bondBps = uint16(bound(bondBps, 1, C.MAX_DISPUTE_BOND_BPS));

        vm.prank(admin);
        engine.setDisputeBondBps(bondBps);

        bytes32 newProjectId = keccak256("new-project-for-bond-test");
        uint256 contribIndex = _createNewProjectWithAcceptedContribution(newProjectId);

        vm.prank(challenger);
        engine.openDispute(newProjectId, contribIndex, keccak256("evidence"), "");

        Dispute memory dispute = engine.getDispute(newProjectId, contribIndex);

        Contribution memory contrib = engine.getContribution(newProjectId, contribIndex);
        uint256 expectedBond = (contrib.rewardRate * bondBps) / C.BPS;
        if (expectedBond == 0) expectedBond = 1;

        assertEq(dispute.bondAmount, expectedBond);
    }

    function testFuzz_reportOriginator_validReport(bytes32 evidenceHash) public {
        vm.assume(evidenceHash != bytes32(0));

        vm.prank(challenger);
        engine.reportOriginator(PROJECT_ID, evidenceHash);

        OriginatorReport memory report = engine.getOriginatorReport(PROJECT_ID);

        assertEq(report.reporter, challenger);
        assertEq(uint8(report.status), uint8(OriginatorReportStatus.Open));
        assertGt(report.bondAmount, 0);
    }

    function testFuzz_reportOriginator_revertsZeroEvidenceHash() public {
        vm.prank(challenger);
        vm.expectRevert(ISapienCore.InvalidEvidenceHash.selector);
        engine.reportOriginator(PROJECT_ID, bytes32(0));
    }

    function testFuzz_reportOriginator_revertsNonExistentProject(bytes32 fakeProjectId) public {
        vm.assume(fakeProjectId != PROJECT_ID);

        vm.prank(challenger);
        vm.expectRevert(ISapienCore.ProjectNotFound.selector);
        engine.reportOriginator(fakeProjectId, keccak256("evidence"));
    }

    function testFuzz_reportOriginator_revertsOriginatorReporting() public {
        vm.prank(originator);
        vm.expectRevert(ISapienCore.NotProjectOriginator.selector);
        engine.reportOriginator(PROJECT_ID, keccak256("evidence"));
    }

    function testFuzz_reportOriginator_revertsDoubleReport() public {
        vm.prank(challenger);
        engine.reportOriginator(PROJECT_ID, keccak256("evidence1"));

        address reporter2 = makeAddr("reporter2");
        _setupUser(reporter2);

        vm.prank(reporter2);
        vm.expectRevert(ISapienCore.OriginatorReportAlreadyOpen.selector);
        engine.reportOriginator(PROJECT_ID, keccak256("evidence2"));
    }

    function testFuzz_reportOriginator_blocksClaiming() public {
        vm.prank(challenger);
        engine.reportOriginator(PROJECT_ID, keccak256("evidence"));

        address newContributor = makeAddr("newContributor");
        _setupUser(newContributor);

        vm.prank(newContributor);
        vm.expectRevert(ISapienCore.DisputeInProgress.selector);
        engine.claimToContribute(PROJECT_ID, 1, address(0));
    }

    function testFuzz_reportOriginator_bondCalculation(uint16 bondBps) public {
        bondBps = uint16(bound(bondBps, 1, C.MAX_ORIGINATOR_REPORT_BOND_BPS));

        vm.prank(admin);
        engine.setOriginatorReportBondBps(bondBps);

        bytes32 newProjectId = keccak256("bond-test-project");
        _createSimpleProject(newProjectId, 50_000e18, 10);

        vm.prank(challenger);
        engine.reportOriginator(newProjectId, keccak256("evidence"));

        OriginatorReport memory report = engine.getOriginatorReport(newProjectId);

        Project memory proj = engine.getProject(newProjectId);
        uint256 expectedBond = (proj.totalRewards * bondBps) / C.BPS;
        if (expectedBond == 0) expectedBond = 1;

        assertEq(report.bondAmount, expectedBond);
    }

    function testFuzz_multipleDisputesAcrossProjects(uint8 numProjects) public {
        numProjects = uint8(bound(numProjects, 1, 5));

        for (uint256 i; i < numProjects; ++i) {
            bytes32 projectId = keccak256(abi.encodePacked("multi-project", i));
            uint256 contribIndex = _createNewProjectWithAcceptedContribution(projectId);

            vm.prank(challenger);
            engine.openDispute(projectId, contribIndex, keccak256(abi.encodePacked("evidence", i)), "");

            Dispute memory dispute = engine.getDispute(projectId, contribIndex);
            assertEq(dispute.challenger, challenger);
            assertEq(uint8(dispute.status), uint8(DisputeStatus.Open));
        }
    }

    function testFuzz_disputeOnRejectedContribution(uint256 lowScore) public {
        lowScore = bound(lowScore, 0, 5000);

        bytes32 projectId = keccak256("rejected-project");
        _createSimpleProject(projectId, 100_000e18, 50);

        address newContrib = makeAddr("newContrib");
        _setupUser(newContrib);

        vm.prank(newContrib);
        (uint256 newClaimId, uint256[] memory newIndices) = engine.claimToContribute(projectId, 1, address(0));

        vm.prank(newContrib);
        engine.contribute(newClaimId, newIndices[0], keccak256("rejected-sub"), "");

        _validateContributionOnProject(projectId, newIndices[0], lowScore);

        Contribution memory contrib = engine.getContribution(projectId, newIndices[0]);
        assertEq(uint8(contrib.status), uint8(ContributionStatus.Rejected));

        vm.prank(challenger);
        engine.openDispute(projectId, newIndices[0], keccak256("evidence"), "");

        Dispute memory dispute = engine.getDispute(projectId, newIndices[0]);
        assertEq(uint8(dispute.status), uint8(DisputeStatus.Open));
    }

    function _setupUser(address user) internal {
        token.mint(user, STAKE_AMOUNT * 100);
        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(STAKE_AMOUNT * 50, user);
        vm.stopPrank();
    }

    function _createSimpleProject(bytes32 projectId, uint256 amount, uint256 qty) internal {
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
        engine.fundProject(projectId, amount, qty, address(0));
        vm.stopPrank();
    }

    function _createNewProjectWithAcceptedContribution(bytes32 projectId) internal returns (uint256 contribIndex) {
        _createSimpleProject(projectId, 100_000e18, 50);

        address newContrib = makeAddr(string(abi.encodePacked("contrib-", projectId)));
        _setupUser(newContrib);

        vm.prank(newContrib);
        (uint256 newClaimId, uint256[] memory newIndices) = engine.claimToContribute(projectId, 1, address(0));
        contribIndex = newIndices[0];

        vm.prank(newContrib);
        engine.contribute(newClaimId, contribIndex, keccak256("submission"), "");

        _validateContributionOnProject(projectId, contribIndex, 8000);
    }

    function _validateContributionOnProject(bytes32 projectId, uint256 index, uint256 score) internal {
        address[3] memory validators = [validator1, validator2, validator3];
        bytes32[3] memory salts;

        // Commit phase
        for (uint256 i; i < 3; ++i) {
            salts[i] = keccak256(abi.encodePacked("salt", validators[i], projectId, index));
            bytes32 commitHash = keccak256(abi.encodePacked(score, salts[i]));

            vm.prank(validators[i]);
            engine.claimToValidate(projectId, 1);

            vm.prank(validators[i]);
            engine.lockValidatorCapacity(VALIDATOR_STAKE);

            vm.prank(validators[i]);
            engine.commitValidation(projectId, index, commitHash, VALIDATOR_STAKE, address(0));
        }

        // Warp past commit deadline to allow reveals (only once)
        vm.warp(block.timestamp + engine.commitDeadline());

        // Reveal phase
        for (uint256 i; i < 3; ++i) {
            vm.prank(validators[i]);
            engine.revealValidation(projectId, index, score, salts[i]);
        }

        engine.computeConsensus(projectId, index);
    }

    function _fullValidationOnProject(address val, bytes32 projectId, uint256 index, uint256 score) internal {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, projectId, index));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        vm.prank(val);
        engine.claimToValidate(projectId, 1);

        vm.prank(val);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);

        vm.prank(val);
        engine.commitValidation(projectId, index, commitHash, VALIDATOR_STAKE, address(0));

        // Warp past commit deadline to allow reveals
        vm.warp(block.timestamp + engine.commitDeadline());

        vm.prank(val);
        engine.revealValidation(projectId, index, score, salt);
    }
}
