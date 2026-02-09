# Wagmi + React Implementation Guide

This guide provides a comprehensive implementation reference for building a React frontend application using wagmi to interact with the Sapien PoQ Protocol. The guide is based on the complete protocol lifecycle and includes practical code examples for all major operations.

## Table of Contents

1. [Setup & Configuration](#setup--configuration)
2. [Staking Requirements (Prerequisite)](#staking-requirements-prerequisite)
3. [Phase 1: Project Setup (Originator)](#phase-1-project-setup-originator)
4. [Phase 2: Contributor Workflow](#phase-2-contributor-workflow)
5. [Phase 3: Validator Workflow](#phase-3-validator-workflow)
6. [Phase 4: Consensus & Finalization](#phase-4-consensus--finalization)
7. [Phase 5: Reward Distribution](#phase-5-reward-distribution)
8. [Phase 6: Reputation & Skills](#phase-6-reputation--skills)
9. [Phase 7: Batch Operations](#phase-7-batch-operations)
10. [Utilities & Helpers](#utilities--helpers)

---

## Setup & Configuration

### Install Dependencies

```bash
npm install wagmi viem @tanstack/react-query
# or
yarn add wagmi viem @tanstack/react-query
```

### Configure Wagmi

```typescript
// wagmi.config.ts
import { defineConfig } from 'wagmi'
import { baseSepolia } from 'wagmi/chains'
import { createConfig, http } from 'wagmi'

// Contract addresses (Base Sepolia)
const CONTRACTS = {
  SAPIEN_CORE: '0xba050696Ad19E1961485B300D3b0Cb3D35eB640b',
  VALIDATION_ORACLE: '0x6c1Bb25b2eDcF7a970bD42F97d72676fAAF8a8D4',
  SAPIEN_TRUST: '0x21d2391D6bB9A9928EC15b24f1efC8b9DFCEf7A9',
  SAPIEN_VAULT: '0x1A7673226d6CD1634e7c78E2D48B351d9E306423',
  REWARDS: '0xC8996Af3b3D8642dc231F06b6D5486CA3378ac88',
  SAPIEN_TOKEN: '0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6',
  USDC: '0x4d4394119CF096FbdbbD3Efb00d204c891C6Cd05',
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

You'll need to import or generate ABIs for:
- `SapienCore`
- `ValidationOracle`
- `SapienTrust`
- `SapienVault`
- `Rewards`
- `IERC20` (for token approvals)

---

## Staking Requirements (Prerequisite)

> **Important:** Users must stake tokens in the SapienVault before participating in the protocol. Contributors need stake to claim work, and validators need stake to commit validations. Without sufficient stake, protocol operations will fail.

The SapienVault is an ERC-4626 compliant vault where users deposit the staking token (SAPIEN) and receive vault shares (vSAPIEN) in return. When participating in the protocol, stake is locked to prevent withdrawals during active contributions or validations.

### Stake Deposit (Required Before Contributing/Validating)

```typescript
// hooks/useDepositStake.ts
import { useWriteContract, useWaitForTransactionReceipt, useReadContract } from 'wagmi'
import { useAccount } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienVaultABI, erc20ABI } from '../abis'
import { parseEther, formatEther } from 'viem'

export function useDepositStake() {
  const { address } = useAccount()
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  // Step 1: Approve staking token
  const approveStakingToken = async (amount: string) => {
    const amountWei = parseEther(amount)
    await writeContract({
      address: CONTRACTS.SAPIEN_TOKEN,
      abi: erc20ABI,
      functionName: 'approve',
      args: [CONTRACTS.SAPIEN_VAULT, amountWei],
    })
  }

  // Step 2: Deposit tokens into vault
  const depositStake = async (amount: string) => {
    const amountWei = parseEther(amount)
    await writeContract({
      address: CONTRACTS.SAPIEN_VAULT,
      abi: sapienVaultABI,
      functionName: 'deposit',
      args: [amountWei, address!],
    })
  }

  // Combined: Approve and deposit in sequence
  const stakeTokens = async (amount: string) => {
    // Note: In production, check existing allowance first
    await approveStakingToken(amount)
    // Wait for approval to confirm before depositing
    await depositStake(amount)
  }

  return {
    approveStakingToken,
    depositStake,
    stakeTokens,
    isPending,
    isConfirming,
    isSuccess,
    error,
    hash,
  }
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

  // Total staked balance (in underlying assets)
  const { data: totalStake, isLoading: isLoadingTotal, refetch: refetchTotal } = useReadContract({
    address: CONTRACTS.SAPIEN_VAULT,
    abi: sapienVaultABI,
    functionName: 'getStake',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    },
  })

  // Available (unlocked) stake
  const { data: availableStake, isLoading: isLoadingAvailable, refetch: refetchAvailable } = useReadContract({
    address: CONTRACTS.SAPIEN_VAULT,
    abi: sapienVaultABI,
    functionName: 'getAvailableStake',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    },
  })

  // Locked stake (committed to active contributions/validations)
  const { data: lockedStake, isLoading: isLoadingLocked, refetch: refetchLocked } = useReadContract({
    address: CONTRACTS.SAPIEN_VAULT,
    abi: sapienVaultABI,
    functionName: 'getLockedStake',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    },
  })

  const refetchAll = () => {
    refetchTotal()
    refetchAvailable()
    refetchLocked()
  }

  return {
    totalStake: totalStake ? formatEther(totalStake) : '0',
    totalStakeWei: totalStake ?? BigInt(0),
    availableStake: availableStake ? formatEther(availableStake) : '0',
    availableStakeWei: availableStake ?? BigInt(0),
    lockedStake: lockedStake ? formatEther(lockedStake) : '0',
    lockedStakeWei: lockedStake ?? BigInt(0),
    isLoading: isLoadingTotal || isLoadingAvailable || isLoadingLocked,
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
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  // Withdraw a specific amount of assets
  const withdrawStake = async (amount: string) => {
    const amountWei = parseEther(amount)
    await writeContract({
      address: CONTRACTS.SAPIEN_VAULT,
      abi: sapienVaultABI,
      functionName: 'withdraw',
      args: [amountWei, address!, address!],
    })
  }

  return {
    withdrawStake,
    isPending,
    isConfirming,
    isSuccess,
    error,
    hash,
  }
}
```

### Check Token Allowance

```typescript
// hooks/useTokenAllowance.ts
import { useReadContract } from 'wagmi'
import { useAccount } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { erc20ABI } from '../abis'
import { formatEther } from 'viem'

export function useStakingTokenAllowance() {
  const { address } = useAccount()

  const { data: allowance, isLoading, refetch } = useReadContract({
    address: CONTRACTS.SAPIEN_TOKEN,
    abi: erc20ABI,
    functionName: 'allowance',
    args: address ? [address, CONTRACTS.SAPIEN_VAULT] : undefined,
    query: {
      enabled: !!address,
    },
  })

  return {
    allowance: allowance ? formatEther(allowance) : '0',
    allowanceWei: allowance ?? BigInt(0),
    isLoading,
    refetch,
  }
}
```

**Usage:**

```typescript
// components/StakingPanel.tsx
import { useDepositStake } from '../hooks/useDepositStake'
import { useWithdrawStake } from '../hooks/useWithdrawStake'
import { useStakeBalance } from '../hooks/useStakeBalance'
import { useStakingTokenAllowance } from '../hooks/useTokenAllowance'
import { useState } from 'react'
import { parseEther } from 'viem'

function StakingPanel() {
  const [amount, setAmount] = useState('')
  const { totalStake, availableStake, lockedStake, isLoading, refetch } = useStakeBalance()
  const { allowanceWei, refetch: refetchAllowance } = useStakingTokenAllowance()
  const { approveStakingToken, depositStake, isPending: isDepositing } = useDepositStake()
  const { withdrawStake, isPending: isWithdrawing } = useWithdrawStake()

  const handleDeposit = async () => {
    const amountWei = parseEther(amount)
    
    // Check if approval is needed
    if (allowanceWei < amountWei) {
      await approveStakingToken(amount)
      await refetchAllowance()
    }
    
    await depositStake(amount)
    refetch()
    setAmount('')
  }

  const handleWithdraw = async () => {
    await withdrawStake(amount)
    refetch()
    setAmount('')
  }

  return (
    <div className="staking-panel">
      <h2>Your Stake</h2>
      
      {isLoading ? (
        <p>Loading...</p>
      ) : (
        <div className="stake-info">
          <div className="stake-row">
            <span>Total Staked:</span>
            <span>{totalStake} SAPIEN</span>
          </div>
          <div className="stake-row">
            <span>Available:</span>
            <span>{availableStake} SAPIEN</span>
          </div>
          <div className="stake-row">
            <span>Locked:</span>
            <span>{lockedStake} SAPIEN</span>
          </div>
        </div>
      )}

      <div className="stake-actions">
        <input
          type="number"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="Amount to stake/withdraw"
          min="0"
          step="0.01"
        />
        
        <div className="button-group">
          <button 
            onClick={handleDeposit} 
            disabled={isDepositing || !amount}
          >
            {isDepositing ? 'Staking...' : 'Stake'}
          </button>
          
          <button 
            onClick={handleWithdraw} 
            disabled={isWithdrawing || !amount || parseFloat(amount) > parseFloat(availableStake)}
          >
            {isWithdrawing ? 'Withdrawing...' : 'Withdraw'}
          </button>
        </div>
        
        {parseFloat(lockedStake) > 0 && (
          <p className="warning">
            Note: {lockedStake} SAPIEN is locked for active contributions/validations
          </p>
        )}
      </div>
    </div>
  )
}
```

### Check Stake Requirements Before Actions

Use this hook to verify a user has sufficient stake before attempting protocol operations:

```typescript
// hooks/useStakeRequirements.ts
import { useStakeBalance } from './useStakeBalance'
import { useProject } from './useProject'
import { parseEther } from 'viem'

export function useStakeRequirements(projectId: `0x${string}` | undefined) {
  const { availableStakeWei, totalStakeWei, isLoading: isLoadingStake } = useStakeBalance()
  const { project, isLoading: isLoadingProject } = useProject(projectId)

  const minStakeToClaim = project?.config.minStakeToClaim ?? BigInt(0)
  const minStakeToContribute = project?.config.minStakeToContribute ?? BigInt(0)

  const canClaim = availableStakeWei >= minStakeToClaim
  const canContribute = availableStakeWei >= minStakeToContribute
  const stakingShortfall = minStakeToClaim > availableStakeWei 
    ? minStakeToClaim - availableStakeWei 
    : BigInt(0)

  return {
    canClaim,
    canContribute,
    minStakeToClaim,
    minStakeToContribute,
    availableStakeWei,
    totalStakeWei,
    stakingShortfall,
    isLoading: isLoadingStake || isLoadingProject,
  }
}
```

**Usage with Action Buttons:**

```typescript
// components/ClaimButton.tsx
import { useStakeRequirements } from '../hooks/useStakeRequirements'
import { useClaimToContribute } from '../hooks/useClaimToContribute'
import { formatEther } from 'viem'

function ClaimButton({ projectId }: { projectId: `0x${string}` }) {
  const { 
    canClaim, 
    minStakeToClaim, 
    stakingShortfall, 
    isLoading 
  } = useStakeRequirements(projectId)
  const { claimToContribute, isPending } = useClaimToContribute()

  const handleClaim = async () => {
    if (!canClaim) {
      alert(`Insufficient stake. Please stake at least ${formatEther(stakingShortfall)} more SAPIEN.`)
      return
    }
    
    await claimToContribute({ projectId, quantity: 1 })
  }

  if (isLoading) return <button disabled>Loading...</button>

  return (
    <div>
      <button 
        onClick={handleClaim} 
        disabled={!canClaim || isPending}
      >
        {isPending ? 'Claiming...' : 'Claim to Contribute'}
      </button>
      
      {!canClaim && (
        <p className="error">
          Requires {formatEther(minStakeToClaim)} SAPIEN staked. 
          You need {formatEther(stakingShortfall)} more.
        </p>
      )}
    </div>
  )
}
```

### Key Staking Concepts

| Concept | Description |
|---------|-------------|
| **Total Stake** | Your entire position in the vault (shares converted to asset value) |
| **Available Stake** | Stake that can be withdrawn or used for new claims |
| **Locked Stake** | Stake committed to active contributions/validations (cannot be withdrawn) |
| **minStakeToClaim** | Minimum stake required to claim a contribution slot (set per project) |
| **minStakeToContribute** | Minimum stake required to submit contributions (set per project) |

### Important Notes

1. **Stake Before Acting**: Always deposit stake before attempting to claim contributions or validate
2. **Locked Stake**: When you claim to contribute or commit a validation, stake is locked until finalization
3. **Slashing Risk**: Bad behavior (invalid contributions, wrong validations) can result in stake being slashed
4. **Unlocking**: Stake is automatically unlocked when contributions are finalized or validations complete
5. **Withdrawal Limits**: You can only withdraw your available (unlocked) stake

---

## Phase 1: Project Setup (Originator)

### 1.1 Create Project

```typescript
// hooks/useCreateProject.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { encodeFunctionData } from 'viem'
import { sapienCoreABI } from '../abis'

export function useCreateProject() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const createProject = async ({
    projectId,
    rewardToken,
    minStakeToClaim,
    minStakeToContribute,
    minValidations,
    validatorRewardBasisPoints,
    requiredSkill,
  }: {
    projectId: `0x${string}`
    rewardToken: `0x${string}`
    minStakeToClaim: bigint
    minStakeToContribute: bigint
    minValidations: number
    validatorRewardBasisPoints: number
    requiredSkill: string
  }) => {
    writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'createProject',
      args: [
        projectId,
        rewardToken,
        minStakeToClaim,
        minStakeToContribute,
        minValidations,
        validatorRewardBasisPoints,
        requiredSkill,
      ],
    })
  }

  return {
    createProject,
    isPending,
    isConfirming,
    isSuccess,
    error,
    hash,
  }
}
```

**Usage:**

```typescript
// components/CreateProjectForm.tsx
import { useCreateProject } from '../hooks/useCreateProject'
import { keccak256, toBytes, stringToBytes } from 'viem'

function CreateProjectForm() {
  const { createProject, isPending, isSuccess } = useCreateProject()

  const handleSubmit = async (formData: FormData) => {
    const projectId = keccak256(
      toBytes(`${formData.name}-${Date.now()}`)
    ) as `0x${string}`

    await createProject({
      projectId,
      rewardToken: CONTRACTS.USDC,
      minStakeToClaim: parseEther('100'),
      minStakeToContribute: parseEther('50'),
      minValidations: 3,
      validatorRewardBasisPoints: 1000, // 10%
      requiredSkill: 'Data Annotation',
    })
  }

  return (
    <form onSubmit={handleSubmit}>
      {/* Form fields */}
      <button type="submit" disabled={isPending}>
        {isPending ? 'Creating...' : 'Create Project'}
      </button>
      {isSuccess && <p>Project created successfully!</p>}
    </form>
  )
}
```

### 1.2 Fund Project

```typescript
// hooks/useFundProject.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { useAccount } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI, erc20ABI } from '../abis'
import { parseUnits } from 'viem'

export function useFundProject() {
  const { address } = useAccount()
  const { writeContract: writeCore, data: hash, isPending } = useWriteContract()
  const { writeContract: writeToken } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const fundProject = async ({
    projectId,
    rewardToken,
    rewardAmount,
    quantity,
    decimals = 18,
  }: {
    projectId: `0x${string}`
    rewardToken: `0x${string}`
    rewardAmount: string
    quantity: number
    decimals?: number
  }) => {
    const amount = parseUnits(rewardAmount, decimals)

    // Step 1: Approve token spending
    await writeToken({
      address: rewardToken,
      abi: erc20ABI,
      functionName: 'approve',
      args: [CONTRACTS.SAPIEN_CORE, amount],
    })

    // Step 2: Fund project
    await writeCore({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'fundProject',
      args: [projectId, amount, BigInt(quantity)],
    })
  }

  return {
    fundProject,
    isPending,
    isConfirming,
    isSuccess,
    error,
    hash,
  }
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
    query: {
      enabled: !!projectId,
    },
  })

  return {
    project,
    isLoading,
    error,
  }
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
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const claimToContribute = async ({
    projectId,
    quantity,
  }: {
    projectId: `0x${string}`
    quantity: number
  }) => {
    const result = await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'claimToContribute',
      args: [projectId, BigInt(quantity)],
    })

    return result
  }

  return {
    claimToContribute,
    isPending,
    isConfirming,
    isSuccess,
    hash,
  }
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
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const contribute = async ({
    projectId,
    claimId,
    contributionIndex,
    submissionHash, // IPFS CID or hash of work
  }: {
    projectId: `0x${string}`
    claimId: bigint
    contributionIndex: number
    submissionHash: `0x${string}`
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'contribute',
      args: [projectId, claimId, BigInt(contributionIndex), submissionHash],
    })
  }

  // Helper to hash IPFS CID or content
  const hashSubmission = (content: string): `0x${string}` => {
    return keccak256(toBytes(content))
  }

  return {
    contribute,
    hashSubmission,
    isPending,
    isConfirming,
    isSuccess,
    hash,
  }
}
```

**Usage:**

```typescript
// components/SubmitContribution.tsx
import { useContribute } from '../hooks/useContribute'
import { useState } from 'react'

function SubmitContribution({ projectId, claimId, contributionIndex }: Props) {
  const { contribute, hashSubmission, isPending } = useContribute()
  const [submissionContent, setSubmissionContent] = useState('')

  const handleSubmit = async () => {
    // Upload to IPFS first (using your IPFS client)
    // const ipfsHash = await uploadToIPFS(submissionContent)
    
    // Or hash the content directly
    const submissionHash = hashSubmission(submissionContent)

    await contribute({
      projectId,
      claimId,
      contributionIndex,
      submissionHash,
    })
  }

  return (
    <div>
      <textarea
        value={submissionContent}
        onChange={(e) => setSubmissionContent(e.target.value)}
        placeholder="Enter your contribution..."
      />
      <button onClick={handleSubmit} disabled={isPending}>
        {isPending ? 'Submitting...' : 'Submit Contribution'}
      </button>
    </div>
  )
}
```

### 2.3 Get Claim Details

```typescript
// hooks/useClaim.ts
import { useReadContract } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useClaim(
  projectId: `0x${string}` | undefined,
  claimId: bigint | undefined
) {
  const { data: claim, isLoading, error } = useReadContract({
    address: CONTRACTS.SAPIEN_CORE,
    abi: sapienCoreABI,
    functionName: 'getClaim',
    args:
      projectId && claimId !== undefined
        ? [projectId, claimId]
        : undefined,
    query: {
      enabled: !!projectId && claimId !== undefined,
    },
  })

  return {
    claim,
    isLoading,
    error,
  }
}
```

---

## Phase 3: Validator Workflow

### 3.1 Set Validator Capacity

```typescript
// hooks/useSetValidatorCapacity.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { validationOracleABI } from '../abis'
import { parseEther } from 'viem'

export function useSetValidatorCapacity() {
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const setCapacity = async (amount: string) => {
    await writeContract({
      address: CONTRACTS.VALIDATION_ORACLE,
      abi: validationOracleABI,
      functionName: 'setValidatorCapacity',
      args: [parseEther(amount)],
    })
  }

  return {
    setCapacity,
    isPending,
    isConfirming,
    isSuccess,
    hash,
  }
}
```

### 3.2 Get Available Capacity

```typescript
// hooks/useValidatorCapacity.ts
import { useReadContract } from 'wagmi'
import { useAccount } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { validationOracleABI } from '../abis'
import { formatEther } from 'viem'

export function useValidatorCapacity() {
  const { address } = useAccount()
  const { data: capacity, isLoading } = useReadContract({
    address: CONTRACTS.VALIDATION_ORACLE,
    abi: validationOracleABI,
    functionName: 'getAvailableCapacity',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    },
  })

  return {
    capacity: capacity ? formatEther(capacity) : '0',
    capacityWei: capacity,
    isLoading,
  }
}
```

### 3.3 Claim to Validate

```typescript
// hooks/useClaimToValidate.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { validationOracleABI } from '../abis'

export function useClaimToValidate() {
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const claimToValidate = async (projectId: `0x${string}`) => {
    const result = await writeContract({
      address: CONTRACTS.VALIDATION_ORACLE,
      abi: validationOracleABI,
      functionName: 'claimToValidate',
      args: [projectId],
    })

    return result
  }

  return {
    claimToValidate,
    isPending,
    isConfirming,
    isSuccess,
    hash,
  }
}
```

### 3.4 Commit Validation

```typescript
// hooks/useCommitValidation.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { validationOracleABI } from '../abis'
import { keccak256, toBytes, encodePacked } from 'viem'

export function useCommitValidation() {
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const commitValidation = async ({
    projectId,
    claimId,
    contributionIndex,
    score,
    stakeAmount,
    salt,
  }: {
    projectId: `0x${string}`
    claimId: bigint
    contributionIndex: number
    score: number // 0-10000
    stakeAmount: bigint
    salt: `0x${string}`
  }) => {
    // Calculate commit hash: keccak256(score, stakeAmount, salt)
    const commitHash = keccak256(
      encodePacked(
        ['uint256', 'uint256', 'bytes32'],
        [BigInt(score), stakeAmount, salt]
      )
    )

    await writeContract({
      address: CONTRACTS.VALIDATION_ORACLE,
      abi: validationOracleABI,
      functionName: 'commitValidation',
      args: [projectId, claimId, BigInt(contributionIndex), commitHash],
    })
  }

  // Helper to generate random salt
  const generateSalt = (): `0x${string}` => {
    const randomBytes = crypto.getRandomValues(new Uint8Array(32))
    return `0x${Array.from(randomBytes)
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('')}` as `0x${string}`
  }

  return {
    commitValidation,
    generateSalt,
    isPending,
    isConfirming,
    isSuccess,
    hash,
  }
}
```

**Usage:**

```typescript
// components/CommitValidation.tsx
import { useCommitValidation } from '../hooks/useCommitValidation'
import { useState } from 'react'

function CommitValidation({
  projectId,
  claimId,
  contributionIndex,
}: Props) {
  const { commitValidation, generateSalt, isPending } = useCommitValidation()
  const [score, setScore] = useState(8000) // 0-10000
  const [stakeAmount] = useState(parseEther('100'))
  const [salt] = useState(() => generateSalt())

  const handleCommit = async () => {
    await commitValidation({
      projectId,
      claimId,
      contributionIndex,
      score,
      stakeAmount,
      salt,
    })

    // Store salt locally for reveal (e.g., localStorage)
    localStorage.setItem(
      `commit-${projectId}-${contributionIndex}`,
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
      <p>Score: {score / 100}%</p>
      <button onClick={handleCommit} disabled={isPending}>
        {isPending ? 'Committing...' : 'Commit Validation'}
      </button>
    </div>
  )
}
```

### 3.5 Reveal Validation

```typescript
// hooks/useRevealValidation.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { validationOracleABI } from '../abis'

export function useRevealValidation() {
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const revealValidation = async ({
    projectId,
    contributionIndex,
    score,
    salt,
  }: {
    projectId: `0x${string}`
    contributionIndex: number
    score: number
    salt: `0x${string}`
  }) => {
    await writeContract({
      address: CONTRACTS.VALIDATION_ORACLE,
      abi: validationOracleABI,
      functionName: 'revealValidation',
      args: [projectId, BigInt(contributionIndex), BigInt(score), salt],
    })
  }

  return {
    revealValidation,
    isPending,
    isConfirming,
    isSuccess,
    hash,
  }
}
```

**Usage:**

```typescript
// components/RevealValidation.tsx
import { useRevealValidation } from '../hooks/useRevealValidation'
import { useEffect, useState } from 'react'

function RevealValidation({
  projectId,
  contributionIndex,
}: Props) {
  const { revealValidation, isPending } = useRevealValidation()
  const [commitData, setCommitData] = useState<{
    score: number
    salt: `0x${string}`
  } | null>(null)

  useEffect(() => {
    // Retrieve stored commit data
    const stored = localStorage.getItem(
      `commit-${projectId}-${contributionIndex}`
    )
    if (stored) {
      setCommitData(JSON.parse(stored))
    }
  }, [projectId, contributionIndex])

  const handleReveal = async () => {
    if (!commitData) return

    await revealValidation({
      projectId,
      contributionIndex,
      score: commitData.score,
      salt: commitData.salt,
    })

    // Clean up stored data
    localStorage.removeItem(`commit-${projectId}-${contributionIndex}`)
  }

  if (!commitData) {
    return <p>No commit found for this contribution</p>
  }

  return (
    <div>
      <p>Score: {commitData.score / 100}%</p>
      <button onClick={handleReveal} disabled={isPending}>
        {isPending ? 'Revealing...' : 'Reveal Validation'}
      </button>
    </div>
  )
}
```

---

## Phase 4: Consensus & Finalization

### 4.1 Get Consensus Report

```typescript
// hooks/useConsensus.ts
import { useReadContract } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { validationOracleABI } from '../abis'

export function useConsensus(
  projectId: `0x${string}` | undefined,
  contributionIndex: number | undefined,
  minValidations: number = 3
) {
  const { data: consensus, isLoading, error } = useReadContract({
    address: CONTRACTS.VALIDATION_ORACLE,
    abi: validationOracleABI,
    functionName: 'getConsensus',
    args:
      projectId !== undefined && contributionIndex !== undefined
        ? [projectId, BigInt(contributionIndex), BigInt(minValidations)]
        : undefined,
    query: {
      enabled: projectId !== undefined && contributionIndex !== undefined,
    },
  })

  return {
    consensus,
    isLoading,
    error,
    isReady: consensus?.isReady ?? false,
    weightedAverage: consensus?.weightedAverage,
    validatorCount: consensus?.validatorCount,
  }
}
```

### 4.2 Finalize Contribution

```typescript
// hooks/useFinalizeContribution.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useFinalizeContribution() {
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const finalizeContribution = async ({
    projectId,
    contributionIndex,
  }: {
    projectId: `0x${string}`
    contributionIndex: number
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'finalizeContribution',
      args: [projectId, BigInt(contributionIndex)],
    })
  }

  return {
    finalizeContribution,
    isPending,
    isConfirming,
    isSuccess,
    hash,
  }
}
```

**Usage:**

```typescript
// components/FinalizeContribution.tsx
import { useConsensus } from '../hooks/useConsensus'
import { useFinalizeContribution } from '../hooks/useFinalizeContribution'

function FinalizeContribution({
  projectId,
  contributionIndex,
  minValidations = 3,
}: Props) {
  const { consensus, isReady, weightedAverage } = useConsensus(
    projectId,
    contributionIndex,
    minValidations
  )
  const { finalizeContribution, isPending } = useFinalizeContribution()

  const handleFinalize = async () => {
    if (!isReady) {
      alert('Consensus not ready yet')
      return
    }

    await finalizeContribution({
      projectId,
      contributionIndex,
    })
  }

  return (
    <div>
      <p>Consensus Ready: {isReady ? 'Yes' : 'No'}</p>
      {weightedAverage !== undefined && (
        <p>Weighted Average: {(Number(weightedAverage) / 100).toFixed(2)}%</p>
      )}
      <button
        onClick={handleFinalize}
        disabled={!isReady || isPending}
      >
        {isPending ? 'Finalizing...' : 'Finalize Contribution'}
      </button>
    </div>
  )
}
```

---

## Phase 5: Reward Distribution

### 5.1 Get Available Rewards

```typescript
// hooks/useRewards.ts
import { useReadContract } from 'wagmi'
import { useAccount } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { rewardsABI } from '../abis'
import { formatUnits } from 'viem'

export function useAvailableRewards(
  projectId: `0x${string}` | undefined,
  token: `0x${string}` | undefined,
  decimals: number = 18
) {
  const { address } = useAccount()
  const { data: rewards, isLoading } = useReadContract({
    address: CONTRACTS.REWARDS,
    abi: rewardsABI,
    functionName: 'getAvailableRewards',
    args:
      address && projectId && token
        ? [address, projectId, token]
        : undefined,
    query: {
      enabled: !!address && !!projectId && !!token,
    },
  })

  return {
    rewards: rewards ? formatUnits(rewards, decimals) : '0',
    rewardsWei: rewards,
    isLoading,
  }
}

export function useAvailableValidatorRewards(
  projectId: `0x${string}` | undefined,
  token: `0x${string}` | undefined,
  decimals: number = 18
) {
  const { address } = useAccount()
  const { data: rewards, isLoading } = useReadContract({
    address: CONTRACTS.REWARDS,
    abi: rewardsABI,
    functionName: 'getAvailableValidatorRewards',
    args:
      address && projectId && token
        ? [address, projectId, token]
        : undefined,
    query: {
      enabled: !!address && !!projectId && !!token,
    },
  })

  return {
    rewards: rewards ? formatUnits(rewards, decimals) : '0',
    rewardsWei: rewards,
    isLoading,
  }
}
```

### 5.2 Claim Rewards

```typescript
// hooks/useClaimRewards.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { rewardsABI } from '../abis'

export function useClaimRewards() {
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const claimRewards = async ({
    projectId,
    token,
  }: {
    projectId: `0x${string}`
    token: `0x${string}`
  }) => {
    await writeContract({
      address: CONTRACTS.REWARDS,
      abi: rewardsABI,
      functionName: 'claimRewards',
      args: [projectId, token],
    })
  }

  return {
    claimRewards,
    isPending,
    isConfirming,
    isSuccess,
    hash,
  }
}

export function useClaimValidatorRewards() {
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const claimValidatorRewards = async ({
    projectId,
    token,
  }: {
    projectId: `0x${string}`
    token: `0x${string}`
  }) => {
    await writeContract({
      address: CONTRACTS.REWARDS,
      abi: rewardsABI,
      functionName: 'claimValidatorRewards',
      args: [projectId, token],
    })
  }

  return {
    claimValidatorRewards,
    isPending,
    isConfirming,
    isSuccess,
    hash,
  }
}
```

**Usage:**

```typescript
// components/ClaimRewards.tsx
import { useAvailableRewards } from '../hooks/useRewards'
import { useClaimRewards } from '../hooks/useClaimRewards'
import { CONTRACTS } from '../wagmi.config'

function ClaimRewards({ projectId }: { projectId: `0x${string}` }) {
  const { rewards, isLoading } = useAvailableRewards(
    projectId,
    CONTRACTS.USDC,
    6 // USDC has 6 decimals
  )
  const { claimRewards, isPending } = useClaimRewards()

  const handleClaim = async () => {
    await claimRewards({
      projectId,
      token: CONTRACTS.USDC,
    })
  }

  return (
    <div>
      <p>Available Rewards: {rewards} USDC</p>
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

## Phase 6: Reputation & Skills

### 6.1 Get Trust Score

```typescript
// hooks/useTrustScore.ts
import { useReadContract } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienTrustABI } from '../abis'
import { CONTRIBUTOR_ROLE, VALIDATOR_ROLE } from '../constants'

export function useTrustScore(
  address: `0x${string}` | undefined,
  role: typeof CONTRIBUTOR_ROLE | typeof VALIDATOR_ROLE
) {
  const { data: score, isLoading } = useReadContract({
    address: CONTRACTS.SAPIEN_TRUST,
    abi: sapienTrustABI,
    functionName: 'getTrustScore',
    args: address && role ? [address, role] : undefined,
    query: {
      enabled: !!address && !!role,
    },
  })

  return {
    score: score ? Number(score) : 0,
    isLoading,
  }
}
```

### 6.2 Check Skill

```typescript
// hooks/useSkill.ts
import { useReadContract } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienTrustABI } from '../abis'

export function useHasSkill(
  address: `0x${string}` | undefined,
  skill: string | undefined
) {
  const { data: hasSkill, isLoading } = useReadContract({
    address: CONTRACTS.SAPIEN_TRUST,
    abi: sapienTrustABI,
    functionName: 'hasValidatedSkill',
    args: address && skill ? [address, skill] : undefined,
    query: {
      enabled: !!address && !!skill,
    },
  })

  return {
    hasSkill: hasSkill ?? false,
    isLoading,
  }
}
```

---

## Phase 7: Batch Operations

### 7.1 Batch Contribute

```typescript
// hooks/useBatchContribute.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useBatchContribute() {
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const batchContribute = async ({
    projectId,
    claimId,
    contributionIndices,
    submissionHashes,
  }: {
    projectId: `0x${string}`
    claimId: bigint
    contributionIndices: number[]
    submissionHashes: `0x${string}`[]
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'batchContribute',
      args: [
        projectId,
        claimId,
        contributionIndices.map((i) => BigInt(i)),
        submissionHashes,
      ],
    })
  }

  return {
    batchContribute,
    isPending,
    isConfirming,
    isSuccess,
    hash,
  }
}
```

### 7.2 Batch Finalize

```typescript
// hooks/useBatchFinalize.ts
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useBatchFinalize() {
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const batchFinalize = async ({
    projectId,
    contributionIndices,
  }: {
    projectId: `0x${string}`
    contributionIndices: number[]
  }) => {
    await writeContract({
      address: CONTRACTS.SAPIEN_CORE,
      abi: sapienCoreABI,
      functionName: 'batchFinalizeContributions',
      args: [projectId, contributionIndices.map((i) => BigInt(i))],
    })
  }

  return {
    batchFinalize,
    isPending,
    isConfirming,
    isSuccess,
    hash,
  }
}
```

---

## Utilities & Helpers

### Contract Addresses

```typescript
// constants/contracts.ts
export const CONTRACTS = {
  SAPIEN_CORE: '0xba050696Ad19E1961485B300D3b0Cb3D35eB640b',
  VALIDATION_ORACLE: '0x6c1Bb25b2eDcF7a970bD42F97d72676fAAF8a8D4',
  SAPIEN_TRUST: '0x21d2391D6bB9A9928EC15b24f1efC8b9DFCEf7A9',
  SAPIEN_VAULT: '0x1A7673226d6CD1634e7c78E2D48B351d9E306423',
  REWARDS: '0xC8996Af3b3D8642dc231F06b6D5486CA3378ac88',
  SAPIEN_TOKEN: '0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6',
  USDC: '0x4d4394119CF096FbdbbD3Efb00d204c891C6Cd05',
} as const
```

### Role Constants

```typescript
// constants/roles.ts
export const CONTRIBUTOR_ROLE =
  '0x0000000000000000000000000000000000000000000000000000000000000001'
export const VALIDATOR_ROLE =
  '0x0000000000000000000000000000000000000000000000000000000000000002'
export const ORIGINATOR_ROLE =
  '0x0000000000000000000000000000000000000000000000000000000000000003'
```

### Helper Functions

```typescript
// utils/project.ts
import { keccak256, toBytes } from 'viem'

export function generateProjectId(name: string, timestamp?: number): `0x${string}` {
  const id = timestamp
    ? `${name}-${timestamp}`
    : `${name}-${Date.now()}`
  return keccak256(toBytes(id))
}

export function hashSubmission(content: string): `0x${string}` {
  return keccak256(toBytes(content))
}
```

### Event Listeners

```typescript
// hooks/useProjectEvents.ts
import { useWatchContractEvent } from 'wagmi'
import { CONTRACTS } from '../wagmi.config'
import { sapienCoreABI } from '../abis'

export function useProjectEvents(projectId: `0x${string}`) {
  // Listen for contribution submissions
  useWatchContractEvent({
    address: CONTRACTS.SAPIEN_CORE,
    abi: sapienCoreABI,
    eventName: 'ContributionSubmitted',
    args: {
      projectId,
    },
    onLogs(logs) {
      console.log('New contribution submitted:', logs)
    },
  })

  // Listen for finalizations
  useWatchContractEvent({
    address: CONTRACTS.SAPIEN_CORE,
    abi: sapienCoreABI,
    eventName: 'ContributionFinalized',
    args: {
      projectId,
    },
    onLogs(logs) {
      console.log('Contribution finalized:', logs)
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
import { useFinalizeContribution } from '../hooks/useFinalizeContribution'
import { useClaimRewards } from '../hooks/useClaimRewards'
import { useState } from 'react'

function ContributorDashboard({ projectId }: { projectId: `0x${string}` }) {
  const { address } = useAccount()
  const { project } = useProject(projectId)
  const { claimToContribute } = useClaimToContribute()
  const { contribute, hashSubmission } = useContribute()
  const { finalizeContribution } = useFinalizeContribution()
  const { claimRewards } = useClaimRewards()

  const [claimId, setClaimId] = useState<bigint | null>(null)
  const [contributionIndex, setContributionIndex] = useState<number | null>(
    null
  )

  const handleClaim = async () => {
    const result = await claimToContribute({
      projectId,
      quantity: 1,
    })
    // Extract claimId from transaction receipt or event
    setClaimId(result)
  }

  const handleSubmit = async (submissionContent: string) => {
    if (!claimId || contributionIndex === null) return

    const submissionHash = hashSubmission(submissionContent)
    await contribute({
      projectId,
      claimId,
      contributionIndex,
      submissionHash,
    })
  }

  return (
    <div>
      <h2>Contributor Dashboard</h2>
      <p>Project: {projectId}</p>
      <p>Available Quantity: {project?.state.totalQuantityAvailable}</p>

      {!claimId && (
        <button onClick={handleClaim}>Claim Contribution Slot</button>
      )}

      {claimId && (
        <div>
          <p>Claim ID: {claimId.toString()}</p>
          {/* Contribution form */}
        </div>
      )}
    </div>
  )
}
```

---

## Best Practices

1. **Error Handling**: Always wrap contract calls in try-catch blocks and provide user-friendly error messages
2. **Loading States**: Show loading indicators during pending transactions
3. **Transaction Confirmation**: Wait for transaction receipts before updating UI state
4. **Event Listening**: Use `useWatchContractEvent` to listen for on-chain events and update UI reactively
5. **Gas Estimation**: Use `useEstimateGas` before submitting transactions to show gas costs
6. **Token Approvals**: Always check and handle token approvals before calling functions that require them
7. **Salt Storage**: Store commit salts securely (localStorage or encrypted storage) for reveal phase
8. **Deadline Management**: Track claim deadlines and reveal deadlines to prevent expired operations

---

## Additional Resources

- [Wagmi Documentation](https://wagmi.sh)
- [Viem Documentation](https://viem.sh)
- [Sapien Protocol Documentation](../README.md)
- [Contract Interfaces](../contracts-and-interfaces.md)
