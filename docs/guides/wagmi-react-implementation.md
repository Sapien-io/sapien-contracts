# Wagmi + React Implementation Guide

This guide provides a comprehensive implementation reference for building a React frontend application using wagmi to interact with the Sapien PoQ v0.5 Protocol. All protocol operations are called on `SapienCore`. Staking deposit/withdrawal uses `SapienVault` (ERC-4626).

## Table of Contents

1. [Setup and Configuration](#setup-and-configuration)
2. [Staking (Prerequisite)](#staking-prerequisite)
3. [Phase 1: Project Setup (Originator)](#phase-1-project-setup-originator)
4. [Phase 2: Contributor Workflow](#phase-2-contributor-workflow)
5. [Phase 3: Validator Workflow](#phase-3-validator-workflow)
6. [Phase 4: Consensus and Finalization](#phase-4-consensus-and-finalization)
7. [Phase 5: Reward Distribution](#phase-5-reward-distribution)
8. [Phase 6: Disputes](#phase-6-disputes)
9. [Phase 7: Reputation](#phase-7-reputation)
10. [Phase 8: Batch Operations](#phase-8-batch-operations)
11. [Utilities and Helpers](#utilities-and-helpers)

---

## Setup and Configuration

### Install Dependencies

```bash
npm install wagmi viem @tanstack/react-query
```

### Configure Wagmi

```typescript
// wagmi.config.ts
import { createConfig, http } from 'wagmi'
import { baseSepolia } from 'wagmi/chains'

const CONTRACTS = {
  SAPIEN_CORE: '0x...',
  SAPIEN_VAULT: '0x...',
  SAPIEN_TOKEN: '0x...',
  USDC: '0x...',
} as const

export const config = createConfig({
  chains: [baseSepolia],
  transports: {
    [baseSepolia.id]: http('https://sepolia.base.org'),
  },
})

export { CONTRACTS }
```

### Setup Wagmi Provider

```typescript
// App.tsx
import { WagmiProvider } from 'wagmi'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { config } from './wagmi.config'

const queryClient = new QueryClient()

function App() {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        {/* Your app components */}
      </QueryClientProvider>
    </WagmiProvider>
  )
}
```

### Contract ABIs

You need ABIs for two protocol contracts and the ERC-20 standard:

- `SapienCore` — all protocol operations
- `SapienVault` — staking deposit/withdrawal and balance queries
- `IERC20` — token approvals

---

## Staking (Prerequisite)

Users must deposit SAPIEN tokens into the `SapienVault` before participating. The vault is ERC-4626 compliant — users deposit the staking token and receive vault shares in return.

### Deposit Stake

```typescript
// hooks/useDepositStake.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { useAccount } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienVaultABI, erc20ABI } from '../abis'
import { parseEther } from 'viem'

export function useDepositStake() {
  const { address } = useAccount()
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const approveStakingToken = async (amount: string) => {
    const amountWei = parseEther(amount)
    await writeContract({
      address: CONTRACTS.SAPIEN_TOKEN,
      abi: erc20ABI,
      functionName: 'approve',
      args: [CONTRACTS.SAPIEN_VAULT, amountWei],
    })
  }

  const depositStake = async (amount: string) => {
    const amountWei = parseEther(amount)
    await writeContract({
      address: CONTRACTS.SAPIEN_VAULT,
      abi: sapienVaultABI,
      functionName: 'deposit',
      args: [amountWei, address!],
    })
  }

  return { approveStakingToken, depositStake, isPending, isConfirming, isSuccess, error, hash }
}
```

### Get Stake Balance

```typescript
// hooks/useStakeBalance.ts
import { useReadContract } from 'wagmi'
import { useAccount } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienVaultABI } from '../abis'
import { formatEther } from 'viem'

export function useStakeBalance() {
  const { address } = useAccount()

  const { data: stakeAccount, isLoading, refetch } = useReadContract({
    address: CONTRACTS.SAPIEN_VAULT,
    abi: sapienVaultABI,
    functionName: 'getStakeAccount',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  })

  const { data: available, refetch: refetchAvailable } = useReadContract({
    address: CONTRACTS.SAPIEN_VAULT,
    abi: sapienVaultABI,
    functionName: 'availableBalance',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  })

  const { data: total, refetch: refetchTotal } = useReadContract({
    address: CONTRACTS.SAPIEN_VAULT,
    abi: sapienVaultABI,
    functionName: 'totalStaked',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  })

  const refetchAll = () => {
    refetch()
    refetchAvailable()
    refetchTotal()
  }

  return {
    contributorLock: stakeAccount ? formatEther(stakeAccount.contributorLock) : '0',
    validatorCapacity: stakeAccount ? formatEther(stakeAccount.validatorCapacity) : '0',
    inFlight: stakeAccount ? formatEther(stakeAccount.inFlight) : '0',
    availableBalance: available ? formatEther(available) : '0',
    availableBalanceWei: available ?? BigInt(0),
    totalStaked: total ? formatEther(total) : '0',
    totalStakedWei: total ?? BigInt(0),
    isLoading,
    refetch: refetchAll,
  }
}
```

### Withdraw Stake

```typescript
// hooks/useWithdrawStake.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { useAccount } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienVaultABI } from '../abis'
import { parseEther } from 'viem'

export function useWithdrawStake() {
  const { address } = useAccount()
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const withdrawStake = async (amount: string) => {
    const amountWei = parseEther(amount)
    await writeContract({
      address: CONTRACTS.SAPIEN_VAULT,
      abi: sapienVaultABI,
      functionName: 'withdraw',
      args: [amountWei, address!, address!],
    })
  }

  return { withdrawStake, isPending, isConfirming, isSuccess, error, hash }
}
```

### Key Staking Concepts

| Concept | Description |
|---------|-------------|
| **Available Balance** | Stake not locked in any bucket — can be withdrawn or locked |
| **Contributor Lock** | Stake locked as collateral for active contribution claims |
| **Validator Capacity** | Stake locked as a pool for validation commits |
| **In-Flight** | Stake committed to active validations (drawn from capacity) |
| **Total Staked** | Sum of all buckets (available + contributor lock + capacity + in-flight) |

---

## Phase 1: Project Setup (Originator)

### 1.1 Create Project

```typescript
// hooks/useCreateProject.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'
import { parseEther } from 'viem'

export function useCreateProject() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const createProject = async ({
    projectId,
    metadataCid,
    rewardToken,
    minStakeToClaim,
    minValidationStake,
    consensusThreshold,
    validatorRewardBps,
    numberOfValidations,
    requiredSkill,
    minValidatorReputation,
  }: {
    projectId: `0x${string}`
    metadataCid: string
    rewardToken: `0x${string}`
    minStakeToClaim: bigint
    minValidationStake: bigint
    consensusThreshold: number
    validatorRewardBps: number
    numberOfValidations: number
    requiredSkill: `0x${string}`
    minValidatorReputation: number
  }) => {
    const emptyAddress = '0x0000000000000000000000000000000000000000' as `0x${string}`

    writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'createProject',
      args: [
        projectId,
        metadataCid,
        {
          originator: emptyAddress,
          rewardToken,
          totalRewards: BigInt(0),
          totalQuantity: BigInt(0),
          availableSlots: BigInt(0),
          minStakeToClaim,
          minValidationStake,
          requiredSkill,
          consensusThreshold: BigInt(consensusThreshold),
          validatorRewardBps: BigInt(validatorRewardBps),
          numberOfValidations: BigInt(numberOfValidations),
          minValidatorReputation: BigInt(minValidatorReputation),
          status: 0,
          activatedAt: BigInt(0),
          completedAt: BigInt(0),
        },
      ],
    })
  }

  return { createProject, isPending, isConfirming, isSuccess, error, hash }
}
```

### 1.2 Fund Project

```typescript
// hooks/useFundProject.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI, erc20ABI } from '../abis'
import { parseUnits } from 'viem'

export function useFundProject() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const approveRewardToken = async ({
    rewardToken,
    amount,
    decimals = 18,
  }: {
    rewardToken: `0x${string}`
    amount: string
    decimals?: number
  }) => {
    const amountWei = parseUnits(amount, decimals)
    await writeContract({
      address: rewardToken,
      abi: erc20ABI,
      functionName: 'approve',
      args: [CONTRACTS.SAPIEN_CORE, amountWei],
    })
  }

  const fundProject = async ({
    projectId,
    amount,
    quantity,
    adapter = '0x0000000000000000000000000000000000000000',
    decimals = 18,
  }: {
    projectId: `0x${string}`
    amount: string
    quantity: number
    adapter?: `0x${string}`
    decimals?: number
  }) => {
    const amountWei = parseUnits(amount, decimals)
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'fundProject',
      args: [projectId, amountWei, BigInt(quantity), adapter],
    })
  }

  return { approveRewardToken, fundProject, isPending, isConfirming, isSuccess, error, hash }
}
```

### 1.3 Get Project Details

```typescript
// hooks/useProject.ts
import { useReadContract } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useProject(projectId: `0x${string}` | undefined) {
  const { data: project, isLoading, error } = useReadContract({
    address: CONTRACTS.SAPIEN_CORE,
    abi: sapienCoreABI,
    functionName: 'getProject',
    args: projectId ? [projectId] : undefined,
    query: { enabled: !!projectId },
  })

  return { project, isLoading, error }
}
```

### 1.4 Complete Project and Refund

```typescript
// hooks/useCompleteProject.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useCompleteProject() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const completeProject = async (projectId: `0x${string}`) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'completeProject',
      args: [projectId],
    })
  }

  const refundEscrow = async (projectId: `0x${string}`) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'refundEscrow',
      args: [projectId],
    })
  }

  return { completeProject, refundEscrow, isPending, isConfirming, isSuccess, error, hash }
}
```

---

## Phase 2: Contributor Workflow

### 2.1 Claim to Contribute

```typescript
// hooks/useClaimToContribute.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useClaimToContribute() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const claimToContribute = async ({
    projectId,
    quantity,
    adapter = '0x0000000000000000000000000000000000000000',
  }: {
    projectId: `0x${string}`
    quantity: number
    adapter?: `0x${string}`
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'claimToContribute',
      args: [projectId, BigInt(quantity), adapter],
    })
  }

  return { claimToContribute, isPending, isConfirming, isSuccess, error, hash }
}
```

### 2.2 Submit Contribution

```typescript
// hooks/useContribute.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'
import { keccak256, toBytes } from 'viem'

export function useContribute() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const contribute = async ({
    claimId,
    index,
    submissionHash,
    dataCid,
  }: {
    claimId: bigint
    index: bigint
    submissionHash: `0x${string}`
    dataCid: string
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'contribute',
      args: [claimId, index, submissionHash, dataCid],
    })
  }

  const hashSubmission = (content: string): `0x${string}` => {
    return keccak256(toBytes(content))
  }

  return { contribute, hashSubmission, isPending, isConfirming, isSuccess, error, hash }
}
```

**Usage:**

```typescript
// components/SubmitContribution.tsx
import { useContribute } from '../hooks/useContribute'
import { useState } from 'react'

function SubmitContribution({ claimId, index }: { claimId: bigint; index: bigint }) {
  const { contribute, hashSubmission, isPending } = useContribute()
  const [dataCid, setDataCid] = useState('')

  const handleSubmit = async () => {
    const submissionHash = hashSubmission(dataCid)
    await contribute({ claimId, index, submissionHash, dataCid })
  }

  return (
    <div>
      <input
        value={dataCid}
        onChange={(e) => setDataCid(e.target.value)}
        placeholder="IPFS CID of your contribution"
      />
      <button onClick={handleSubmit} disabled={isPending}>
        {isPending ? 'Submitting...' : 'Submit Contribution'}
      </button>
    </div>
  )
}
```

### 2.3 Expire Claim

```typescript
// hooks/useExpireClaim.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useExpireClaim() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const expireClaim = async ({
    claimId,
    indices,
  }: {
    claimId: bigint
    indices: bigint[]
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'expireClaim',
      args: [claimId, indices],
    })
  }

  return { expireClaim, isPending, isConfirming, isSuccess, error, hash }
}
```

### 2.4 Get Claim Details

```typescript
// hooks/useClaim.ts
import { useReadContract } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useClaim(claimId: bigint | undefined) {
  const { data: claim, isLoading, error } = useReadContract({
    address: CONTRACTS.SAPIEN_CORE,
    abi: sapienCoreABI,
    functionName: 'getClaim',
    args: claimId !== undefined ? [claimId] : undefined,
    query: { enabled: claimId !== undefined },
  })

  return { claim, isLoading, error }
}
```

---

## Phase 3: Validator Workflow

### 3.1 Lock Validator Capacity

```typescript
// hooks/useValidatorCapacity.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'
import { parseEther } from 'viem'

export function useValidatorCapacity() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const lockCapacity = async (amount: string) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'lockValidatorCapacity',
      args: [parseEther(amount)],
    })
  }

  const unlockCapacity = async (amount: string) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'unlockValidatorCapacity',
      args: [parseEther(amount)],
    })
  }

  return { lockCapacity, unlockCapacity, isPending, isConfirming, isSuccess, error, hash }
}
```

### 3.2 Claim to Validate

```typescript
// hooks/useClaimToValidate.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useClaimToValidate() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const claimToValidate = async ({
    projectId,
    indices,
  }: {
    projectId: `0x${string}`
    indices: bigint[]
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'claimToValidate',
      args: [projectId, indices],
    })
  }

  return { claimToValidate, isPending, isConfirming, isSuccess, error, hash }
}
```

### 3.3 Commit Validation

```typescript
// hooks/useCommitValidation.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'
import { keccak256, encodePacked, parseEther } from 'viem'

export function useCommitValidation() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const commitValidation = async ({
    projectId,
    index,
    score,
    stakeAmount,
    salt,
    adapter = '0x0000000000000000000000000000000000000000',
  }: {
    projectId: `0x${string}`
    index: bigint
    score: number
    stakeAmount: bigint
    salt: `0x${string}`
    adapter?: `0x${string}`
  }) => {
    const commitHash = keccak256(
      encodePacked(['uint16', 'bytes32'], [score, salt])
    )

    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'commitValidation',
      args: [projectId, index, commitHash, stakeAmount, adapter],
    })
  }

  const generateSalt = (): `0x${string}` => {
    const randomBytes = crypto.getRandomValues(new Uint8Array(32))
    return `0x${Array.from(randomBytes)
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('')}` as `0x${string}`
  }

  return { commitValidation, generateSalt, isPending, isConfirming, isSuccess, error, hash }
}
```

**Usage:**

```typescript
// components/CommitValidation.tsx
import { useCommitValidation } from '../hooks/useCommitValidation'
import { useState } from 'react'
import { parseEther } from 'viem'

function CommitValidation({ projectId, index }: { projectId: `0x${string}`; index: bigint }) {
  const { commitValidation, generateSalt, isPending } = useCommitValidation()
  const [score, setScore] = useState(8000)
  const [salt] = useState(() => generateSalt())

  const handleCommit = async () => {
    await commitValidation({
      projectId,
      index,
      score,
      stakeAmount: parseEther('100'),
      salt,
    })

    // Store salt locally for reveal phase
    localStorage.setItem(
      `commit-${projectId}-${index}`,
      JSON.stringify({ score, salt })
    )
  }

  return (
    <div>
      <input
        type="range"
        min="0"
        max="10000"
        value={score}
        onChange={(e) => setScore(Number(e.target.value))}
      />
      <p>Score: {(score / 100).toFixed(2)}%</p>
      <button onClick={handleCommit} disabled={isPending}>
        {isPending ? 'Committing...' : 'Commit Validation'}
      </button>
    </div>
  )
}
```

### 3.4 Reveal Validation

```typescript
// hooks/useRevealValidation.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useRevealValidation() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const revealValidation = async ({
    projectId,
    index,
    score,
    salt,
  }: {
    projectId: `0x${string}`
    index: bigint
    score: number
    salt: `0x${string}`
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'revealValidation',
      args: [projectId, index, BigInt(score), salt],
    })
  }

  return { revealValidation, isPending, isConfirming, isSuccess, error, hash }
}
```

**Usage:**

```typescript
// components/RevealValidation.tsx
import { useRevealValidation } from '../hooks/useRevealValidation'
import { useEffect, useState } from 'react'

function RevealValidation({ projectId, index }: { projectId: `0x${string}`; index: bigint }) {
  const { revealValidation, isPending } = useRevealValidation()
  const [commitData, setCommitData] = useState<{
    score: number
    salt: `0x${string}`
  } | null>(null)

  useEffect(() => {
    const stored = localStorage.getItem(`commit-${projectId}-${index}`)
    if (stored) setCommitData(JSON.parse(stored))
  }, [projectId, index])

  const handleReveal = async () => {
    if (!commitData) return
    await revealValidation({
      projectId,
      index,
      score: commitData.score,
      salt: commitData.salt,
    })
    localStorage.removeItem(`commit-${projectId}-${index}`)
  }

  if (!commitData) return <p>No commit found for this contribution</p>

  return (
    <div>
      <p>Score: {(commitData.score / 100).toFixed(2)}%</p>
      <button onClick={handleReveal} disabled={isPending}>
        {isPending ? 'Revealing...' : 'Reveal Validation'}
      </button>
    </div>
  )
}
```

---

## Phase 4: Consensus and Finalization

### 4.1 Compute Consensus

```typescript
// hooks/useComputeConsensus.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useComputeConsensus() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const computeConsensus = async ({
    projectId,
    index,
  }: {
    projectId: `0x${string}`
    index: bigint
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'computeConsensus',
      args: [projectId, index],
    })
  }

  return { computeConsensus, isPending, isConfirming, isSuccess, error, hash }
}
```

### 4.2 Settle Validator

```typescript
// hooks/useSettleValidator.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useSettleValidator() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const settleValidator = async ({
    projectId,
    index,
    nonce,
  }: {
    projectId: `0x${string}`
    index: bigint
    nonce: bigint
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'settleValidator',
      args: [projectId, index, nonce],
    })
  }

  const forceSettleValidator = async ({
    projectId,
    index,
    nonce,
    validator,
  }: {
    projectId: `0x${string}`
    index: bigint
    nonce: bigint
    validator: `0x${string}`
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'forceSettleValidator',
      args: [projectId, index, nonce, validator],
    })
  }

  return { settleValidator, forceSettleValidator, isPending, isConfirming, isSuccess, error, hash }
}
```

### 4.3 Release Contributor Reward

```typescript
// hooks/useReleaseContributorReward.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useReleaseContributorReward() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const releaseContributorReward = async ({
    projectId,
    index,
  }: {
    projectId: `0x${string}`
    index: bigint
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'releaseContributorReward',
      args: [projectId, index],
    })
  }

  return { releaseContributorReward, isPending, isConfirming, isSuccess, error, hash }
}
```

### 4.4 Get Contribution Details

```typescript
// hooks/useContribution.ts
import { useReadContract } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useContribution(
  projectId: `0x${string}` | undefined,
  index: bigint | undefined
) {
  const { data: contribution, isLoading, error } = useReadContract({
    address: CONTRACTS.SAPIEN_CORE,
    abi: sapienCoreABI,
    functionName: 'getContribution',
    args: projectId !== undefined && index !== undefined ? [projectId, index] : undefined,
    query: { enabled: projectId !== undefined && index !== undefined },
  })

  return { contribution, isLoading, error }
}
```

---

## Phase 5: Reward Distribution

### 5.1 Get Pending Rewards

```typescript
// hooks/usePendingRewards.ts
import { useReadContract } from 'wagmi'
import { useAccount } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'
import { formatUnits } from 'viem'

export function usePendingRewards(
  token: `0x${string}` | undefined,
  decimals: number = 18
) {
  const { address } = useAccount()
  const { data: rewards, isLoading, refetch } = useReadContract({
    address: CONTRACTS.SAPIEN_CORE,
    abi: sapienCoreABI,
    functionName: 'getPendingRewards',
    args: address && token ? [address, token] : undefined,
    query: { enabled: !!address && !!token },
  })

  return {
    rewards: rewards ? formatUnits(rewards, decimals) : '0',
    rewardsWei: rewards ?? BigInt(0),
    isLoading,
    refetch,
  }
}
```

### 5.2 Claim Reward

```typescript
// hooks/useClaimReward.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useClaimReward() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const claimReward = async (token: `0x${string}`) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'claimReward',
      args: [token],
    })
  }

  return { claimReward, isPending, isConfirming, isSuccess, error, hash }
}
```

**Usage:**

```typescript
// components/ClaimRewards.tsx
import { usePendingRewards } from '../hooks/usePendingRewards'
import { useClaimReward } from '../hooks/useClaimReward'
import { CONTRACTS } from '../wagmi.config'

function ClaimRewards() {
  const { rewards, isLoading, refetch } = usePendingRewards(CONTRACTS.USDC, 6)
  const { claimReward, isPending } = useClaimReward()

  const handleClaim = async () => {
    await claimReward(CONTRACTS.USDC)
    refetch()
  }

  return (
    <div>
      <p>Pending Rewards: {rewards} USDC</p>
      <button
        onClick={handleClaim}
        disabled={rewards === '0' || isPending || isLoading}
      >
        {isPending ? 'Claiming...' : 'Claim Rewards'}
      </button>
    </div>
  )
}
```

---

## Phase 6: Disputes

### 6.1 Open Dispute

```typescript
// hooks/useDispute.ts
import { useWriteContract, useWaitForTransactionReceipt, useReadContract } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useOpenDispute() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const openDispute = async ({
    projectId,
    index,
    evidenceHash,
    evidenceCid,
  }: {
    projectId: `0x${string}`
    index: bigint
    evidenceHash: `0x${string}`
    evidenceCid: string
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'openDispute',
      args: [projectId, index, evidenceHash, evidenceCid],
    })
  }

  return { openDispute, isPending, isConfirming, isSuccess, error, hash }
}

export function useEscalateDispute() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const escalateDispute = async ({
    projectId,
    index,
  }: {
    projectId: `0x${string}`
    index: bigint
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'escalateDispute',
      args: [projectId, index],
    })
  }

  return { escalateDispute, isPending, isConfirming, isSuccess, error, hash }
}
```

### 6.2 Get Dispute Details

```typescript
// hooks/useDisputeDetails.ts
import { useReadContract } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useDispute(
  projectId: `0x${string}` | undefined,
  index: bigint | undefined
) {
  const { data: dispute, isLoading, error } = useReadContract({
    address: CONTRACTS.SAPIEN_CORE,
    abi: sapienCoreABI,
    functionName: 'getDispute',
    args: projectId !== undefined && index !== undefined ? [projectId, index] : undefined,
    query: { enabled: projectId !== undefined && index !== undefined },
  })

  return { dispute, isLoading, error }
}
```

---

## Phase 7: Reputation

### 7.1 Get Reputation

```typescript
// hooks/useReputation.ts
import { useReadContract } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'
import { keccak256, toBytes } from 'viem'

const ROLE_KEYS = {
  ORIGINATOR: keccak256(toBytes('ORIGINATOR')),
  CONTRIBUTOR: keccak256(toBytes('CONTRIBUTOR')),
  VALIDATOR: keccak256(toBytes('VALIDATOR')),
} as const

export function useReputation(
  address: `0x${string}` | undefined,
  role: keyof typeof ROLE_KEYS
) {
  const roleKey = ROLE_KEYS[role]

  const { data: reputation, isLoading, error } = useReadContract({
    address: CONTRACTS.SAPIEN_CORE,
    abi: sapienCoreABI,
    functionName: 'getReputation',
    args: address ? [address, roleKey] : undefined,
    query: { enabled: !!address },
  })

  return {
    score: reputation ? Number(reputation.score) : 5000,
    totalActions: reputation ? Number(reputation.totalActions) : 0,
    successfulActions: reputation ? Number(reputation.successfulActions) : 0,
    lastUpdated: reputation ? Number(reputation.lastUpdated) : 0,
    isLoading,
    error,
  }
}
```

**Usage:**

```typescript
// components/ReputationBadge.tsx
import { useReputation } from '../hooks/useReputation'
import { useAccount } from 'wagmi'

function ReputationBadge() {
  const { address } = useAccount()
  const contributor = useReputation(address, 'CONTRIBUTOR')
  const validator = useReputation(address, 'VALIDATOR')

  return (
    <div>
      <div>
        <span>Contributor Reputation: </span>
        <span>{contributor.score} / 10000</span>
        <span> ({contributor.successfulActions}/{contributor.totalActions} success rate)</span>
      </div>
      <div>
        <span>Validator Reputation: </span>
        <span>{validator.score} / 10000</span>
        <span> ({validator.successfulActions}/{validator.totalActions} success rate)</span>
      </div>
    </div>
  )
}
```

---

## Phase 8: Batch Operations

### 8.1 Batch Contribute

```typescript
// hooks/useBatchContribute.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useBatchContribute() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const batchContribute = async ({
    claimId,
    indices,
    submissionHashes,
    dataCids,
  }: {
    claimId: bigint
    indices: bigint[]
    submissionHashes: `0x${string}`[]
    dataCids: string[]
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'batchContribute',
      args: [claimId, indices, submissionHashes, dataCids],
    })
  }

  return { batchContribute, isPending, isConfirming, isSuccess, error, hash }
}
```

### 8.2 Batch Commit Validations

```typescript
// hooks/useBatchCommitValidations.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'
import { keccak256, encodePacked } from 'viem'

export function useBatchCommitValidations() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const batchCommitValidations = async ({
    projectId,
    indices,
    scores,
    stakeAmounts,
    salts,
    adapter = '0x0000000000000000000000000000000000000000',
  }: {
    projectId: `0x${string}`
    indices: bigint[]
    scores: number[]
    stakeAmounts: bigint[]
    salts: `0x${string}`[]
    adapter?: `0x${string}`
  }) => {
    const commitHashes = scores.map((score, i) =>
      keccak256(encodePacked(['uint16', 'bytes32'], [score, salts[i]]))
    )

    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'batchCommitValidations',
      args: [projectId, indices, commitHashes, stakeAmounts, adapter],
    })
  }

  return { batchCommitValidations, isPending, isConfirming, isSuccess, error, hash }
}
```

### 8.3 Batch Reveal Validations

```typescript
// hooks/useBatchRevealValidations.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useBatchRevealValidations() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const batchRevealValidations = async ({
    projectId,
    indices,
    scores,
    salts,
  }: {
    projectId: `0x${string}`
    indices: bigint[]
    scores: number[]
    salts: `0x${string}`[]
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'batchRevealValidations',
      args: [
        projectId,
        indices,
        scores.map((s) => BigInt(s)),
        salts,
      ],
    })
  }

  return { batchRevealValidations, isPending, isConfirming, isSuccess, error, hash }
}
```

---

## Utilities and Helpers

### Contract Addresses

```typescript
// constants/contracts.ts
export const CONTRACTS = {
  SAPIEN_CORE: '0x...',
  SAPIEN_VAULT: '0x...',
  SAPIEN_TOKEN: '0x...',
  USDC: '0x...',
} as const
```

### Role Keys

```typescript
// constants/roles.ts
import { keccak256, toBytes } from 'viem'

export const ROLE_KEYS = {
  ORIGINATOR: keccak256(toBytes('ORIGINATOR')),
  CONTRIBUTOR: keccak256(toBytes('CONTRIBUTOR')),
  VALIDATOR: keccak256(toBytes('VALIDATOR')),
} as const
```

### Helper Functions

```typescript
// utils/project.ts
import { keccak256, toBytes } from 'viem'

export function generateProjectId(name: string, timestamp?: number): `0x${string}` {
  const id = timestamp ? `${name}-${timestamp}` : `${name}-${Date.now()}`
  return keccak256(toBytes(id))
}

export function hashSubmission(content: string): `0x${string}` {
  return keccak256(toBytes(content))
}

export function generateSalt(): `0x${string}` {
  const randomBytes = crypto.getRandomValues(new Uint8Array(32))
  return `0x${Array.from(randomBytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')}` as `0x${string}`
}
```

### Event Listeners

```typescript
// hooks/useProjectEvents.ts
import { useWatchContractEvent } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useProjectEvents(projectId: `0x${string}`) {
  useWatchContractEvent({
    address: CONTRACTS.SAPIEN_CORE,
    abi: sapienCoreABI,
    eventName: 'ContributionSubmitted',
    args: { projectId },
    onLogs(logs) {
      console.log('Contribution submitted:', logs)
    },
  })

  useWatchContractEvent({
    address: CONTRACTS.SAPIEN_CORE,
    abi: sapienCoreABI,
    eventName: 'ConsensusReached',
    args: { projectId },
    onLogs(logs) {
      console.log('Consensus reached:', logs)
    },
  })

  useWatchContractEvent({
    address: CONTRACTS.SAPIEN_CORE,
    abi: sapienCoreABI,
    eventName: 'ValidatorSettled',
    args: { projectId },
    onLogs(logs) {
      console.log('Validator settled:', logs)
    },
  })

  useWatchContractEvent({
    address: CONTRACTS.SAPIEN_CORE,
    abi: sapienCoreABI,
    eventName: 'ContributorRewardReleased',
    args: { projectId },
    onLogs(logs) {
      console.log('Contributor reward released:', logs)
    },
  })

  useWatchContractEvent({
    address: CONTRACTS.SAPIEN_CORE,
    abi: sapienCoreABI,
    eventName: 'DisputeOpened',
    args: { projectId },
    onLogs(logs) {
      console.log('Dispute opened:', logs)
    },
  })
}
```

---

## Complete Example: Full Contributor Flow

```typescript
// components/ContributorDashboard.tsx
import { useAccount } from 'wagmi'
import { useProject } from '../hooks/useProject'
import { useClaimToContribute } from '../hooks/useClaimToContribute'
import { useContribute } from '../hooks/useContribute'
import { useReleaseContributorReward } from '../hooks/useReleaseContributorReward'
import { useClaimReward } from '../hooks/useClaimReward'
import { usePendingRewards } from '../hooks/usePendingRewards'
import { useState } from 'react'
import { CONTRACTS } from '../wagmi.config'

function ContributorDashboard({ projectId }: { projectId: `0x${string}` }) {
  const { address } = useAccount()
  const { project } = useProject(projectId)
  const { claimToContribute } = useClaimToContribute()
  const { contribute, hashSubmission } = useContribute()
  const { releaseContributorReward } = useReleaseContributorReward()
  const { claimReward } = useClaimReward()
  const { rewards } = usePendingRewards(CONTRACTS.USDC, 6)

  const [claimId, setClaimId] = useState<bigint | null>(null)
  const [indices, setIndices] = useState<bigint[]>([])

  const handleClaim = async () => {
    await claimToContribute({ projectId, quantity: 1 })
    // Extract claimId and indices from transaction receipt events
  }

  const handleSubmit = async (dataCid: string) => {
    if (!claimId || indices.length === 0) return
    const submissionHash = hashSubmission(dataCid)
    await contribute({ claimId, index: indices[0], submissionHash, dataCid })
  }

  const handleClaimRewards = async () => {
    await claimReward(CONTRACTS.USDC)
  }

  return (
    <div>
      <h2>Contributor Dashboard</h2>
      <p>Project: {projectId}</p>
      <p>Available Slots: {project?.availableSlots?.toString()}</p>
      <p>Pending Rewards: {rewards} USDC</p>

      {!claimId && (
        <button onClick={handleClaim}>Claim Contribution Slot</button>
      )}

      {claimId && (
        <div>
          <p>Claim ID: {claimId.toString()}</p>
          <p>Assigned Indices: {indices.map((i) => i.toString()).join(', ')}</p>
        </div>
      )}

      {parseFloat(rewards) > 0 && (
        <button onClick={handleClaimRewards}>Withdraw Rewards</button>
      )}
    </div>
  )
}
```

---

## Best Practices

1. **Error handling**: Wrap contract calls in try-catch blocks and provide user-friendly error messages. Parse custom error types from the ABI for specific error handling.
2. **Loading states**: Show loading indicators during pending transactions using `isPending` and `isConfirming` flags.
3. **Transaction confirmation**: Wait for transaction receipts before updating UI state.
4. **Event listening**: Use `useWatchContractEvent` to reactively update UI when on-chain state changes.
5. **Gas estimation**: Use `useEstimateGas` before submitting transactions to show gas costs to users.
6. **Token approvals**: Always check and handle ERC-20 approvals before calling functions that transfer tokens (e.g., `fundProject`, `deposit`).
7. **Salt storage**: Store commit salts securely (localStorage or encrypted storage) — losing the salt means you cannot reveal and your stake will be slashed.
8. **Deadline management**: Track claim deadlines, commit deadlines, and reveal deadlines to prevent expired operations and stake slashing.
9. **Multi-step finalization**: The reward flow is `computeConsensus` -> `settleValidator` -> `releaseContributorReward` -> `claimReward`. Build UI that guides users through each step.

---

## Additional Resources

- [Wagmi Documentation](https://wagmi.sh)
- [Viem Documentation](https://viem.sh)
- [Sapien Protocol Documentation](../README.md)
- [Contract Interfaces](../contracts-and-interfaces.md)
