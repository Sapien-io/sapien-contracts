// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {Contracts, DeployedContracts} from "script/Contracts.sol";

/**
 * @title UpdateTimelockDelay
 * @notice Script to generate proposal and execution calls for updating TimelockController minimum delay
 * @dev The updateDelay function can only be called by the timelock itself, so it requires a governance proposal
 */
contract UpdateTimelockDelay is Script {
    /**
     * @notice Generate proposal to update timelock minimum delay
     * @param newDelay New minimum delay in seconds
     */
    function generateUpdateDelayPayload(uint256 newDelay) external view {
        DeployedContracts memory contracts = Contracts.get();

        require(contracts.timelock != address(0), "Timelock not deployed");

        TimelockController tc = TimelockController(payable(contracts.timelock));
        uint256 currentDelay = tc.getMinDelay();

        // Create updateDelay calldata - this calls updateDelay on the timelock itself
        bytes memory updateDelayData = abi.encodeWithSelector(TimelockController.updateDelay.selector, newDelay);

        // Create salt for unique operation
        bytes32 salt = keccak256(abi.encodePacked("updateMinDelay", newDelay, block.timestamp));

        // Create schedule calldata
        bytes memory scheduleData = abi.encodeWithSelector(
            TimelockController.schedule.selector,
            contracts.timelock, // target is the timelock itself
            0, // value
            updateDelayData, // data to call updateDelay
            bytes32(0), // predecessor
            salt, // salt
            currentDelay // delay (must use current delay)
        );

        // Create execute calldata
        bytes memory executeData = abi.encodeWithSelector(
            TimelockController.execute.selector,
            contracts.timelock, // target is the timelock itself
            0, // value
            updateDelayData, // data to call updateDelay
            bytes32(0), // predecessor
            salt // salt
        );

        // Generate operation ID
        bytes32 operationId = tc.hashOperation(contracts.timelock, 0, updateDelayData, bytes32(0), salt);

        // Print results
        console.log("=== UPDATE TIMELOCK MINIMUM DELAY ===");
        console.log("TimelockController:", contracts.timelock);
        console.log("Current Delay:", currentDelay, "seconds");
        console.log("New Delay:", newDelay, "seconds");
        console.log("");
        console.log("Operation ID:");
        console.logBytes32(operationId);
        console.log("");
        console.log("Salt:");
        console.logBytes32(salt);
        console.log("");
        console.log("=== STEP 1: SCHEDULE (Proposer Role Required) ===");
        console.log("Target:", contracts.timelock);
        console.log("Value: 0");
        console.log("Function: schedule(address,uint256,bytes,bytes32,bytes32,uint256)");
        console.log("Parameters:");
        console.log("  target:", contracts.timelock);
        console.log("  value: 0");
        console.log("  data:");
        console.logBytes(updateDelayData);
        console.log("  predecessor: 0x0000000000000000000000000000000000000000000000000000000000000000");
        console.log("  salt:");
        console.logBytes32(salt);
        console.log("  delay:", currentDelay);
        console.log("");
        console.log("Schedule Call Data:");
        console.logBytes(scheduleData);
        console.log("");
        console.log("=== STEP 2: EXECUTE (Executor Role Required) ===");
        console.log("(Wait", currentDelay, "seconds after scheduling)");
        console.log("Target:", contracts.timelock);
        console.log("Value: 0");
        console.log("Function: execute(address,uint256,bytes,bytes32,bytes32)");
        console.log("Parameters:");
        console.log("  target:", contracts.timelock);
        console.log("  value: 0");
        console.log("  data:");
        console.logBytes(updateDelayData);
        console.log("  predecessor: 0x0000000000000000000000000000000000000000000000000000000000000000");
        console.log("  salt:");
        console.logBytes32(salt);
        console.log("");
        console.log("Execute Call Data:");
        console.logBytes(executeData);
        console.log("");
        console.log("=== DECODED UPDATE DELAY CALL ===");
        console.log("Function: updateDelay(uint256)");
        console.log("Parameter: newDelay =", newDelay);
        console.log("Raw updateDelay call data:");
        console.logBytes(updateDelayData);
    }

    /**
     * @notice Check operation status for a given operation ID
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

        if (tc.isOperationReady(operationId)) {
            console.log("Status: READY TO EXECUTE");
        } else if (tc.isOperationPending(operationId)) {
            uint256 timestamp = tc.getTimestamp(operationId);
            if (timestamp > block.timestamp) {
                console.log("Status: PENDING - Execution available at timestamp:", timestamp);
                console.log("Time remaining:", timestamp - block.timestamp, "seconds");
            } else {
                console.log("Status: READY TO EXECUTE");
            }
        } else if (tc.isOperationDone(operationId)) {
            console.log("Status: EXECUTED");
        } else {
            console.log("Status: NOT SCHEDULED");
        }
    }

    /**
     * @notice Generate operation ID for a given set of parameters
     */
    function generateOperationId(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt)
        external
        view
        returns (bytes32)
    {
        DeployedContracts memory contracts = Contracts.get();
        TimelockController tc = TimelockController(payable(contracts.timelock));

        bytes32 operationId = tc.hashOperation(target, value, data, predecessor, salt);

        console.log("=== OPERATION ID GENERATOR ===");
        console.log("Target:", target);
        console.log("Value:", value);
        console.log("Data:");
        console.logBytes(data);
        console.log("Predecessor:");
        console.logBytes32(predecessor);
        console.log("Salt:");
        console.logBytes32(salt);
        console.log("Generated Operation ID:");
        console.logBytes32(operationId);

        return operationId;
    }

    /**
     * @notice Main run function with usage instructions
     */
    function run() external pure {
        console.log("=== TIMELOCK DELAY UPDATER ===");
        console.log("Usage examples:");
        console.log("");
        console.log("1. Generate payload to update delay to 24 hours (86400 seconds):");
        console.log("forge script script/UpdateTimelockDelay.s.sol --sig 'generateUpdateDelayPayload(uint256)' 86400");
        console.log("");
        console.log("2. Generate payload to update delay to 72 hours (259200 seconds):");
        console.log("forge script script/UpdateTimelockDelay.s.sol --sig 'generateUpdateDelayPayload(uint256)' 259200");
        console.log("");
        console.log("3. Check operation status:");
        console.log(
            "forge script script/UpdateTimelockDelay.s.sol --sig 'checkOperationStatus(bytes32)' <OPERATION_ID>"
        );
        console.log("");
        console.log("4. Generate operation ID:");
        console.log(
            "forge script script/UpdateTimelockDelay.s.sol --sig 'generateOperationId(address,uint256,bytes,bytes32,bytes32)' <TARGET> <VALUE> <DATA> <PREDECESSOR> <SALT>"
        );
        console.log("");
        console.log("Important Notes:");
        console.log("- Only accounts with PROPOSER_ROLE can schedule proposals");
        console.log("- Only accounts with EXECUTOR_ROLE can execute proposals");
        console.log("- The new delay must wait the current delay duration before execution");
        console.log("- The timelock calls updateDelay on itself to change the minimum delay");
    }
}
