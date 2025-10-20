// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Contracts, DeployedContracts} from "script/Contracts.sol";

/**
 * @title Upgrader
 * @notice Simplified script to generate upgrade payloads for TimelockController
 */
contract Upgrader is Script {
    /**
     * @notice Generate upgrade payload for any contract
     * @param contractType 0=Vault, 1=Rewards, 2=QA
     * @param newImplementation Address of new implementation
     */
    function generateUpgradePayload(uint8 contractType, address newImplementation) external view {
        DeployedContracts memory contracts = Contracts.get();

        address proxy;
        string memory contractName;

        if (contractType == 0) {
            proxy = contracts.sapienVault;
            contractName = "SapienVault";
        } else if (contractType == 1) {
            proxy = contracts.sapienRewards;
            contractName = "SapienRewards";
        } else if (contractType == 2) {
            proxy = contracts.sapienQA;
            contractName = "SapienQA";
        } else if (contractType == 3) {
            proxy = contracts.usdcRewards;
            contractName = "USDCRewards";
        } else {
            revert("Invalid contract type");
        }

        _generatePayload(proxy, newImplementation, contracts.timelock, contractName);
    }

    /**
     * @notice Internal function to generate the actual payload
     */
    function _generatePayload(address proxy, address newImplementation, address timelock, string memory contractName)
        internal
        view
    {
        // Get ProxyAdmin
        address proxyAdmin = _getProxyAdmin(proxy);

        // Get delay
        TimelockController tc = TimelockController(payable(timelock));
        uint256 delay = tc.getMinDelay();

        // Create upgrade calldata
        bytes memory upgradeData = abi.encodeWithSelector(
            ProxyAdmin.upgradeAndCall.selector, ITransparentUpgradeableProxy(proxy), newImplementation, ""
        );

        // Create salt for unique operation
        bytes32 salt = keccak256(abi.encodePacked(contractName, newImplementation, block.timestamp));

        // Create schedule calldata
        bytes memory scheduleData = abi.encodeWithSelector(
            TimelockController.schedule.selector, proxyAdmin, 0, upgradeData, bytes32(0), salt, delay
        );

        // Create execute calldata
        bytes memory executeData =
            abi.encodeWithSelector(TimelockController.execute.selector, proxyAdmin, 0, upgradeData, bytes32(0), salt);

        // Generate operation ID
        bytes32 operationId = tc.hashOperation(proxyAdmin, 0, upgradeData, bytes32(0), salt);

        // Print results
        console.log("=== UPGRADE PAYLOAD FOR", contractName, "===");
        console.log("Proxy:", proxy);
        console.log("New Implementation:", newImplementation);
        console.log("ProxyAdmin:", proxyAdmin);
        console.log("TimelockController:", timelock);
        console.log("Delay:", delay, "seconds");
        console.log("");
        console.log("Operation ID:");
        console.logBytes32(operationId);
        console.log("");
        console.log("=== STEP 1: SCHEDULE (Security Council) ===");
        console.log("To:", timelock);
        console.log("Value: 0");
        console.log("Data:");
        console.logBytes(scheduleData);
        console.log("");
        console.log("=== STEP 2: EXECUTE (Foundation Safe #1) ===");
        console.log("(Wait", delay, "seconds after scheduling)");
        console.log("To:", timelock);
        console.log("Value: 0");
        console.log("Data:");
        console.logBytes(executeData);
    }

    /**
     * @notice Get ProxyAdmin address from proxy storage
     */
    function _getProxyAdmin(address proxy) internal view returns (address) {
        bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        return address(uint160(uint256(vm.load(proxy, adminSlot))));
    }

    /**
     * @notice Check operation status
     */
    function checkOperationStatus(bytes32 operationId) external view {
        DeployedContracts memory contracts = Contracts.get();
        TimelockController tc = TimelockController(payable(contracts.timelock));

        console.log("=== OPERATION STATUS ===");
        console.log("Operation ID:");
        console.logBytes32(operationId);
        console.log("Is Pending:", tc.isOperationPending(operationId));
        console.log("Is Ready:", tc.isOperationReady(operationId));
        console.log("Is Done:", tc.isOperationDone(operationId));
        console.log("Timestamp:", tc.getTimestamp(operationId));
        console.log("Current Time:", block.timestamp);
    }

    /**
     * @notice Generate cancel payload for a timelock operation
     * @param operationId The operation ID to cancel
     */
    function generateCancelPayload(bytes32 operationId) external view {
        DeployedContracts memory contracts = Contracts.get();

        console.log("=== CANCEL OPERATION PAYLOAD ===");
        console.log("Chain ID:", block.chainid);
        console.log("Timelock Address:", contracts.timelock);
        console.log("Operation ID:");
        console.logBytes32(operationId);
        console.log("");

        // Check if timelock contract exists
        uint256 codeSize;
        address timelockAddr = contracts.timelock;
        assembly {
            codeSize := extcodesize(timelockAddr)
        }

        if (codeSize == 0) {
            console.log("=== ERROR: TIMELOCK CONTRACT NOT DEPLOYED ===");
            console.log("The timelock contract at address", contracts.timelock, "does not exist or is not deployed.");
            console.log("Please ensure the timelock is deployed before trying to cancel operations.");
            return;
        }

        TimelockController tc = TimelockController(payable(contracts.timelock));

        // Try to check operation status with error handling
        bool isPending;
        bool isReady;
        bool isDone;
        uint256 timestamp;

        try tc.isOperationPending(operationId) returns (bool pending) {
            isPending = pending;
        } catch {
            console.log("=== ERROR: CANNOT ACCESS TIMELOCK CONTRACT ===");
            console.log("The timelock contract exists but cannot be accessed.");
            console.log("This could be due to:");
            console.log("- Contract not properly initialized");
            console.log("- Wrong contract address");
            console.log("- Network connectivity issues");
            return;
        }

        try tc.isOperationReady(operationId) returns (bool ready) {
            isReady = ready;
        } catch {
            isReady = false;
        }

        try tc.isOperationDone(operationId) returns (bool done) {
            isDone = done;
        } catch {
            isDone = false;
        }

        try tc.getTimestamp(operationId) returns (uint256 ts) {
            timestamp = ts;
        } catch {
            timestamp = 0;
        }

        // Check if operation exists and is pending
        if (!isPending) {
            console.log("=== CANCEL OPERATION ERROR ===");
            console.log("Operation is not pending or doesn't exist");
            console.log("Operation ID:");
            console.logBytes32(operationId);
            console.log("Is Pending:", isPending);
            console.log("Is Ready:", isReady);
            console.log("Is Done:", isDone);
            if (timestamp > 0) {
                console.log("Timestamp:", timestamp);
                console.log("Current Time:", block.timestamp);
            }
            return;
        }

        // Create cancel calldata
        bytes memory cancelData = abi.encodeWithSelector(TimelockController.cancel.selector, operationId);

        console.log("=== CANCEL TRANSACTION ===");
        console.log("To:", contracts.timelock);
        console.log("Value: 0");
        console.log("Data:");
        console.logBytes(cancelData);
        console.log("");
        console.log("Note: Only proposers can cancel operations");
    }

    /**
     * @notice Main run function with examples
     */
    function run() external pure {
        console.log("=== SAPIEN UPGRADER ===");
        console.log("Usage examples:");
        console.log("");
        console.log("1. Generate Vault upgrade payload:");
        console.log(
            "forge script script/Upgrader.s.sol --sig 'generateUpgradePayload(uint8,address)' 0 <NEW_IMPLEMENTATION>"
        );
        console.log("");
        console.log("2. Generate Rewards upgrade payload:");
        console.log(
            "forge script script/Upgrader.s.sol --sig 'generateUpgradePayload(uint8,address)' 1 <NEW_IMPLEMENTATION>"
        );
        console.log("");
        console.log("3. Generate QA upgrade payload:");
        console.log(
            "forge script script/Upgrader.s.sol --sig 'generateUpgradePayload(uint8,address)' 2 <NEW_IMPLEMENTATION>"
        );
        console.log("");
        console.log("4. Check operation status:");
        console.log("forge script script/Upgrader.s.sol --sig 'checkOperationStatus(bytes32)' <OPERATION_ID>");
        console.log("");
        console.log("5. Generate cancel payload:");
        console.log("forge script script/Upgrader.s.sol --sig 'generateCancelPayload(bytes32)' <OPERATION_ID>");
    }
}
