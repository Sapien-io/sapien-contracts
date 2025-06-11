# Code Improvement Checklist

- [x] Make the Multiplier contract a library instead of a contract
- [x] Remove isValidLockupPeriod() function from Multiplier contract
- [x] Add validation to Multiplier.interpolate() function
- [x] Fix misleading T1_FACTOR - T5_FACTOR constants
- [x] Remove unused errors from IMultiplier interface
    - The interface is no longer required.
- [x] Use different address for PAUSER_ROLE in SapienVault
- [x] Remove parameters from MultiplierUpdated event
- [x] Remove address(0) check in SapienVault.stake()
- [x] Re-evaluate storage savings in UserStake struct
    - The cost savings are significant with variable packing
    https://github.com/Sapien-io/sapien-contracts/blob/audit/june%2Bremove-variable-packing-test/test/unit/june-audit-findings/remove-vault-variable-packing/readme.md

- [ ] Add constant for magic number in _validateIncreaseAmount()
- [x] Avoid double validation in increaseAmount()
- [ ] Streamline EIP-712 implementation in SapienRewards
- [ ] Reconsider reward token accounting in SapienRewards
- [ ] Define MAXIMUM_STAKE_AMOUNT constant
- [ ] Make calculateMultiplier() revert instead of return zero
- [ ] Remove redundant checks in _calculateWeightedValues()
- [x] Remove unnecessary overflow checks
- [ ] Add expiration to _verifySignature()
- [ ] Use delete for _resetUserStake()
- [ ] Add hasStake check in getUserStakingSummary()
- [ ] Remove redundant QAPenaltyPartial event
- [x] Remove unnecessary uint256 upcasts
- [ ] Remove penalty > 0 check in earlyUnstake()
- [x] Add minimum unstake amount to prevent precision loss