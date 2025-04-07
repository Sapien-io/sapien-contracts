export type DeploymentMetadata = {
  network: string
  proxyAddress: `0x${string}`
  implementationAddress: `0x${string}`
  deploymentTime: string
  deployer: `0x${string}`
  safe: `0x${string}`
}

export type DeploymentConfig = {
  tokenName: string
  tokenSymbol: string
  initialSupply: bigint
  minStakeAmount: bigint
  lockPeriod: bigint
  earlyWithdrawalPenalty: bigint
  rewardRate: bigint
  rewardInterval: bigint
  bonusThreshold: bigint
  bonusRate: bigint
  safe: `0x${string}`
  totalSupply: bigint
  upgradedAt?: Date
  upgradeTransaction?: string
  upgradedBy?: string
}
