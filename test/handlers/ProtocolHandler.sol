// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SapienCore} from "../../src/SapienCore.sol";
import {ValidationOracle} from "../../src/ValidationOracle.sol";
import {SapienTrust} from "../../src/SapienTrust.sol";
import {SapienVault} from "../../src/SapienVault.sol";
import {Rewards} from "../../src/Rewards.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

contract ProtocolHandler is Test {
    SapienCore public core;
    ValidationOracle public oracle;
    SapienTrust public trust;
    SapienVault public vault;
    Rewards public rewards;
    MockERC20 public rewardToken;
    MockERC20 public stakeToken;

    address[] public contributors;
    address[] public validators;
    bytes32 public projectId;

    uint256 public constant INITIAL_STAKE = 1000 ether;
    uint256 public constant MIN_STAKE = 100 ether;

    constructor(
        SapienCore _core,
        ValidationOracle _oracle,
        SapienTrust _trust,
        SapienVault _vault,
        Rewards _rewards,
        MockERC20 _rewardToken,
        MockERC20 _stakeToken,
        bytes32 _projectId
    ) {
        core = _core;
        oracle = _oracle;
        trust = _trust;
        vault = _vault;
        rewards = _rewards;
        rewardToken = _rewardToken;
        stakeToken = _stakeToken;
        projectId = _projectId;
    }

    function addContributor(address contributor) public {
        if (contributor == address(0)) return;
        contributors.push(contributor);
        _setupUser(contributor);
    }

    function addValidator(address validator) public {
        if (validator == address(0)) return;
        validators.push(validator);
        _setupUser(validator);
        vm.prank(validator);
        oracle.setValidatorCapacity(INITIAL_STAKE);
    }

    function _setupUser(address user) internal {
        uint256 amount = INITIAL_STAKE * 2;
        stakeToken.mint(user, amount);
        vm.startPrank(user);
        stakeToken.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    // --- Action: Claim to Contribute ---
    function claimToContribute(uint256 contributorIdx, uint8 quantity) public {
        if (contributors.length == 0) return;
        address contributor = contributors[contributorIdx % contributors.length];
        quantity = uint8(bound(quantity, 1, 5));

        vm.prank(contributor);
        try core.claimToContribute(projectId, quantity) {} catch {}
    }

    // --- Action: Contribute ---
    function contribute(uint256 contributorIdx, uint256 claimId, uint256 index) public {
        if (contributors.length == 0) return;
        address contributor = contributors[contributorIdx % contributors.length];

        vm.prank(contributor);
        try core.contribute(projectId, claimId, index, keccak256(abi.encode(index))) {} catch {}
    }

    // --- Action: Claim to Validate ---
    function claimToValidate(uint256 validatorIdx) public {
        if (validators.length == 0) return;
        address validator = validators[validatorIdx % validators.length];

        vm.prank(validator);
        try oracle.claimToValidate(projectId) {} catch {}
    }

    // --- Action: Commit Validation ---
    function commitValidation(uint256 validatorIdx, uint256 claimId, uint256 index, uint256 score) public {
        if (validators.length == 0) return;
        address validator = validators[validatorIdx % validators.length];
        score = bound(score, 0, 10000);

        bytes32 salt = keccak256(abi.encode(validator, index));
        bytes32 hash = keccak256(abi.encodePacked(score, uint256(MIN_STAKE), salt));

        vm.prank(validator);
        try oracle.commitValidation(projectId, claimId, index, hash) {} catch {}
    }

    // --- Action: Reveal Validation ---
    function revealValidation(uint256 validatorIdx, uint256 index, uint256 score) public {
        if (validators.length == 0) return;
        address validator = validators[validatorIdx % validators.length];
        score = bound(score, 0, 10000);
        bytes32 salt = keccak256(abi.encode(validator, index));

        vm.prank(validator);
        try oracle.revealValidation(projectId, index, score, salt) {} catch {}
    }

    // --- Action: Finalize ---
    function finalizeContribution(uint256 index) public {
        try core.finalizeContribution(projectId, index) {} catch {}
    }

    // --- Action: Claim Rewards ---
    function claimRewards(uint256 contributorIdx) public {
        if (contributors.length == 0) return;
        address contributor = contributors[contributorIdx % contributors.length];

        vm.prank(contributor);
        try rewards.claimRewards(projectId, address(rewardToken), address(0), 0) {} catch {}
    }
}
