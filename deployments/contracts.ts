/**
 * Base Sepolia Contract Addresses
 * Generated from deployment on Base Sepolia testnet
 */

export interface ContractAddresses {
  // Core Contracts
  sapienToken: string;
  timelock: string;
  sapienQA: string;
  multiplier: string;
  
  // Rewards System
  sapienRewards: string;
  sapienRewardsProxy: string;
  rewardsProxyAdmin: string;
  
  // Vault System
  sapienVault: string;
  sapienVaultProxy: string;
  
  // System Roles
  proposer: string;
  executor: string;
  admin: string;
  rewardsSafe: string;
  rewardsManager: string;
  securityCouncil: string;
  treasury: string;
}

export const baseSepolia: ContractAddresses = {
  // Core Contracts
  sapienToken: "0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6", // use this one
  timelock: "0x2a5F9e1Be3A78C73EA1aB256D3Eb0C5A475742cC",
  sapienQA: "0x93263cB5AfC26Aa8910D5038aC01a12e4881B478",
  multiplier: "0x8816D0CC618E4Ca88Fb67d97586B691b0Dae3E2b",
  
  // Rewards System
  sapienRewards: "0x8014DAF1Cc0E204689cBd18fe11f2fC557B22A66",
  sapienRewardsProxy: "0xFfC83AF7b215a026A9A8BBE9c3E8835fB29f479B", // use this one
  rewardsProxyAdmin: "0xFf8D9eb1b8919D546a2fa5fF3dcCDD22BCA43810",
  
  // Vault System  
  sapienVault: "0x422b5214900a412C2194e12d67eA518b740b59F1",
  sapienVaultProxy: "0x63962218ea90237d79E7833811E920BB7CE78311", // use this one
  
  // System Roles (all using the same address in this deployment)
  proposer: "0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC",
  executor: "0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC", 
  admin: "0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC",
  rewardsSafe: "0x09F4897735f3Ec9Af6C2dda49d97D454B7dD1e59",
  rewardsManager: "0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC",
  securityCouncil: "0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC",
  treasury: "0x09F4897735f3Ec9Af6C2dda49d97D454B7dD1e59",
};

export default { baseSepolia };