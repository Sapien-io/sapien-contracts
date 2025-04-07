import {type DeploymentConfig} from "../scripts/utils/types";

const config: DeploymentConfig = {
  "tokenName": "Sapien Token",
  "tokenSymbol": "SAP",
  "initialSupply": 950000000000000000000000000n,
  "minStakeAmount": 100000000000000000000n,
  "lockPeriod": 604800n,
  "earlyWithdrawalPenalty": 1000n,
  "rewardRate": 100n,
  "rewardInterval": 2592000n,
  "bonusThreshold": 1000000000000000000000n,
  "bonusRate": 50n,
  "safe": "0x0b02e5D662a37A533c557AD842c55D913c87392C",
  "totalSupply": 950000000000000000000000000n
}



export default config
