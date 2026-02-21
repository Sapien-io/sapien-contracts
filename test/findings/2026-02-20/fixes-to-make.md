Contributions
- claimToContribute CLAIM_DEADLINE should be a setter with a getter by the admin
- add batchContribution
- Allow admin to set CHALLENGE_PERIOD with setter and add getter

Validation
- We need to make these configurate with getters and setters: COMMIT_DEADLINE, REVEAL_DEADLINE, FORCE_SETTLE_DELAY
- change setValidatorCapcity and reduceValidatorCapacity to lockValidatorCapacity / unlockValidatorCapacity (which is what the vault already uses internally)
- add claimToValidator back
- add batchCommitValidations and batchRevealValidations back
- add cancelExpiredValidationClaim(bytes32, uint256) back 


Origintation
- Need ability to remove projects or slash an originator for breaching the terms of services (ie, inappropriate language or content)

Refactor
v0.3 -> v0.5
- need to use the IPFS CID as the data value for:
- createProject(bytes32 projectId, string IPFS CID, Project calldata config) add the IPFS CID here and emit as event
- contribute(submissionsHash, add the Ipfs CID) submit both the bytes32 and the ipfs cid and emit as event

QualityEngine -> SapienCore (the docs name)
StakeVault -> SapienVault (the docs name)


EXTRA FEATURES
- Need to add the ability for an Origintator to Pause all new claims on a project, then stop the project and remove funds. However, they must allow all previous claims, contributions and validations to complete prior to remove funds and stopping the project.