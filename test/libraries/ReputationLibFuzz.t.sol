// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Constants as C} from "src/Constants.sol";
import {Project, ProjectStatus, Reputation} from "src/Types.sol";

/// @title ReputationLibFuzz
/// @notice Fuzz tests for the ReputationLib library through real contract interactions
contract ReputationLibFuzz is Test {
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

    function testFuzz_getScore_returnsDefaultForNewUser(address user, bytes32 role) public view {
        vm.assume(user != address(0));

        Reputation memory rep = engine.getReputation(user, role);
        assertEq(rep.score, C.DEFAULT_REPUTATION, "New user should have default reputation");
    }

    function testFuzz_reputation_updatedOnProjectCreation(bytes32 projectId) public {
        vm.assume(projectId != bytes32(0));

        Reputation memory repBefore = engine.getReputation(originator, C.ORIGINATOR_ROLE_KEY);
        uint256 scoreBefore = repBefore.score;

        Project memory config = _makeProjectConfig();
        vm.prank(originator);
        engine.createProject(projectId, "", config);

        Reputation memory repAfter = engine.getReputation(originator, C.ORIGINATOR_ROLE_KEY);

        assertGe(repAfter.score, scoreBefore, "Score should increase or stay same after project creation");
        assertEq(repAfter.totalActions, repBefore.totalActions + 1, "Total actions should increment");
        assertEq(repAfter.successfulActions, repBefore.successfulActions + 1, "Successful actions should increment");
    }

    function testFuzz_reputation_multipleProjectCreations(uint8 numProjects) public {
        numProjects = uint8(bound(numProjects, 1, 20));

        for (uint256 i; i < numProjects; ++i) {
            bytes32 projectId = keccak256(abi.encodePacked("project", i));
            Project memory config = _makeProjectConfig();

            vm.prank(originator);
            engine.createProject(projectId, "", config);
        }

        Reputation memory rep = engine.getReputation(originator, C.ORIGINATOR_ROLE_KEY);

        assertEq(rep.totalActions, numProjects, "Total actions should match project count");
        assertEq(rep.successfulActions, numProjects, "Successful actions should match project count");
        assertTrue(rep.score >= C.DEFAULT_REPUTATION, "Score should be at least default");
    }

    function testFuzz_reputation_dailyGainCapped(uint8 iterations) public {
        iterations = uint8(bound(iterations, 1, 100));

        for (uint256 i; i < iterations; ++i) {
            bytes32 projectId = keccak256(abi.encodePacked("project", i));
            Project memory config = _makeProjectConfig();

            vm.prank(originator);
            engine.createProject(projectId, "", config);
        }

        Reputation memory rep = engine.getReputation(originator, C.ORIGINATOR_ROLE_KEY);

        uint256 maxPossibleScore = C.DEFAULT_REPUTATION + C.MAX_DAILY_GAIN;
        assertTrue(rep.score <= maxPossibleScore, "Score should be capped by daily gain");
        assertTrue(rep.score <= C.MAX_REPUTATION, "Score should never exceed max");
    }

    function testFuzz_reputation_crossDayAccumulation() public {
        for (uint256 i; i < 5; ++i) {
            bytes32 projectId = keccak256(abi.encodePacked("day1-project", i));
            Project memory config = _makeProjectConfig();
            vm.prank(originator);
            engine.createProject(projectId, "", config);
        }

        Reputation memory repDay1 = engine.getReputation(originator, C.ORIGINATOR_ROLE_KEY);

        vm.warp(block.timestamp + 1 days);

        for (uint256 i; i < 5; ++i) {
            bytes32 projectId = keccak256(abi.encodePacked("day2-project", i));
            Project memory config = _makeProjectConfig();
            vm.prank(originator);
            engine.createProject(projectId, "", config);
        }

        Reputation memory repDay2 = engine.getReputation(originator, C.ORIGINATOR_ROLE_KEY);

        assertTrue(repDay2.score >= repDay1.score, "Score should accumulate across days");
    }

    function testFuzz_reputation_differentRolesIndependent(address user) public view {
        vm.assume(user != address(0));

        Reputation memory repRole1 = engine.getReputation(user, C.ORIGINATOR_ROLE_KEY);
        Reputation memory repRole2 = engine.getReputation(user, SKILL_ID);
        Reputation memory repRole3 = engine.getReputation(user, SKILL_ID);

        assertEq(repRole1.score, C.DEFAULT_REPUTATION);
        assertEq(repRole2.score, C.DEFAULT_REPUTATION);
        assertEq(repRole3.score, C.DEFAULT_REPUTATION);
    }

    function testFuzz_reputation_decayAfterTime(uint8 daysElapsed) public {
        daysElapsed = uint8(bound(daysElapsed, 1, 100));

        vm.prank(admin);
        engine.setDecayRate(100);

        bytes32 projectId = keccak256("decay-test-project");
        Project memory config = _makeProjectConfig();
        vm.prank(originator);
        engine.createProject(projectId, "", config);

        Reputation memory repInitial = engine.getReputation(originator, C.ORIGINATOR_ROLE_KEY);
        uint256 initialScore = repInitial.score;

        vm.warp(block.timestamp + uint256(daysElapsed) * 1 days);

        Reputation memory repDecayed = engine.getReputation(originator, C.ORIGINATOR_ROLE_KEY);

        assertTrue(repDecayed.score <= initialScore, "Score should decay or stay same");
        assertTrue(repDecayed.score >= C.MIN_REPUTATION, "Score should never go below minimum");
    }

    function testFuzz_reputation_zeroDecayNoChange(uint16 daysElapsed) public {
        daysElapsed = uint16(bound(daysElapsed, 1, 365));

        vm.prank(admin);
        engine.setDecayRate(0);

        bytes32 projectId = keccak256("no-decay-test");
        Project memory config = _makeProjectConfig();
        vm.prank(originator);
        engine.createProject(projectId, "", config);

        Reputation memory repInitial = engine.getReputation(originator, C.ORIGINATOR_ROLE_KEY);

        vm.warp(block.timestamp + uint256(daysElapsed) * 1 days);

        Reputation memory repLater = engine.getReputation(originator, C.ORIGINATOR_ROLE_KEY);

        assertEq(repLater.score, repInitial.score, "No decay should occur with zero rate");
    }

    function testFuzz_reputation_scoreBoundedByMinMax(uint8 iterations) public {
        iterations = uint8(bound(iterations, 1, 200));

        for (uint256 i; i < iterations; ++i) {
            vm.warp(block.timestamp + 1 days);

            bytes32 projectId = keccak256(abi.encodePacked("bounded-project", i));
            Project memory config = _makeProjectConfig();
            vm.prank(originator);
            engine.createProject(projectId, "", config);
        }

        Reputation memory rep = engine.getReputation(originator, C.ORIGINATOR_ROLE_KEY);

        assertTrue(rep.score >= C.MIN_REPUTATION, "Score should never go below minimum");
        assertTrue(rep.score <= C.MAX_REPUTATION, "Score should never exceed maximum");
    }

    function testFuzz_reputation_lastUpdatedTimestamp(bytes32 projectId) public {
        vm.assume(projectId != bytes32(0));

        uint256 timestamp = block.timestamp;

        Project memory config = _makeProjectConfig();
        vm.prank(originator);
        engine.createProject(projectId, "", config);

        Reputation memory rep = engine.getReputation(originator, C.ORIGINATOR_ROLE_KEY);

        assertEq(rep.lastUpdated, timestamp, "lastUpdated should match block timestamp");
    }

    function testFuzz_reputation_dailyGainDateTracking() public {
        uint256 today = block.timestamp / 1 days;

        bytes32 projectId = keccak256("daily-tracking-test");
        Project memory config = _makeProjectConfig();
        vm.prank(originator);
        engine.createProject(projectId, "", config);

        Reputation memory rep = engine.getReputation(originator, C.ORIGINATOR_ROLE_KEY);

        assertEq(rep.dailyGainDate, today, "Daily gain date should match current day");
        assertTrue(rep.dailyGain > 0, "Daily gain should be positive");
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
