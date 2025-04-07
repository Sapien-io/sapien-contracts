import hre from 'hardhat'
import * as fs from 'fs'
import * as path from 'path'
import {type DeploymentConfig} from './types'
import config from '../../config/deploy-config'

export enum Contract {
  SapienToken,
  SapienStaking,
  SapienRewards
}
export const loadConfig = (contract: Contract ): DeploymentConfig => {
  if (!(contract in Contract)) {
    throw new Error(`Invalid contract type: ${contract}`)
  }
  const network = hre.network.name
  const dir = `deployments/${network}`
  if (fs.existsSync(dir)) {
    console.log('existing deployment found')
    console.log('checking for token')
    console.log(dir)
    if (fs.existsSync(`${dir}/SapienToken.json`)) {
      console.log('token found')
      const tokenDep = JSON.parse(fs.readFileSync(`${dir}/SapienToken.json`, 'utf8'))
      config.token = tokenDep
    } else {
      if (contract === Contract.SapienStaking) {
        throw new Error('Please deploy the Sapien Token first')
      }
      if (contract === Contract.SapienRewards) {
        throw new Error('Please deploy the Sapien Token first')
      }
    }
    console.log('checking for staking')
    if (fs.existsSync(`${dir}/SapienStaking.json`)) {
      console.log('staking found')
      const stakingDep = JSON.parse(fs.readFileSync(`${dir}/SapienStaking.json`, 'utf8'))
      config.staking = stakingDep
    } else {
      if (contract === Contract.SapienRewards) {
        throw new Error('Please deploy the Sapien Staking contract first')
      }
    }
    console.log('checking for rewards')
    if (fs.existsSync(`${dir}/SapienRewards.json`)) {
      console.log('rewards found')
      const rewardDep = JSON.parse(fs.readFileSync(`${dir}/SapienRewards.json`, 'utf8'))
      config.rewards = rewardDep
    }
  }
  return config
}
