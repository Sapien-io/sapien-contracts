# Code Improvement Checklist

1. [y] Make the Multiplier contract a library instead of a contract
2. [y] Remove isValidLockupPeriod() function from Multiplier contract
3. [y] Add validation to Multiplier.interpolate() function
4. [y] Fix misleading T1_FACTOR - T5_FACTOR constants
5. [y] Remove unused errors from IMultiplier interface
6. [y] Use different address for PAUSER_ROLE in SapienVault
7. [y] Remove parameters from MultiplierUpdated event
8. [y] Remove address(0) check in SapienVault.stake()
9. [n] Re-evaluate storage savings in UserStake struct
    - The cost savings are significant with variable packing
    https://github.com/Sapien-io/sapien-contracts/blob/audit/june%2Bremove-variable-packing-test/test/unit/june-audit-findings/remove-vault-variable-packing/readme.md
10. [ ] Add constant for magic number in _validateIncreaseAmount()
11. [y] Avoid double validation in increaseAmount()
12. [y] Streamline EIP-712 implementation in SapienRewards
13. [ ] Reconsider reward token accounting in SapienRewards
14. [ ] Define MAXIMUM_STAKE_AMOUNT constant
15. [y] Make calculateMultiplier() revert instead of return zero
16. [y] Remove redundant checks in _calculateWeightedValues()
17. [y] Remove unnecessary overflow checks
18. [y] Add expiration to _verifySignature()
19. [y] Use delete for _resetUserStake()
20. [y] Add hasStake check in getUserStakingSummary()
21. [y] Remove redundant QAPenaltyPartial event
22. [y] Remove unnecessary uint256 upcasts
23. [y] Remove penalty > 0 check in earlyUnstake()
24. [y] Add minimum unstake amount to prevent precision loss