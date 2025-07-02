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
     * @notice Generate Safe multisig transaction payload for executing scheduled timelock operation
     * @param newDelay The new delay value that was scheduled
     */
    function generateSafeExecutionPayload(uint256 newDelay) external view {
        DeployedContracts memory contracts = Contracts.get();
        require(contracts.timelock != address(0), "Timelock not deployed");

        TimelockController tc = TimelockController(payable(contracts.timelock));

        // Recreate the parameters that were used for scheduling
        bytes memory updateDelayData = abi.encodeWithSelector(TimelockController.updateDelay.selector, newDelay);
        bytes32 salt = keccak256(abi.encodePacked("updateMinDelay", newDelay, block.timestamp));

        // Note: If you have the exact salt from scheduling, use that instead
        console.log("WARNING: This uses current timestamp for salt generation.");
        console.log("If you have the original salt from scheduling, use that instead.");
        console.log("");

        // Generate operation ID
        bytes32 operationId = tc.hashOperation(contracts.timelock, 0, updateDelayData, bytes32(0), salt);

        // Create execute calldata for TimelockController
        bytes memory executeCallData = abi.encodeWithSelector(
            TimelockController.execute.selector,
            contracts.timelock, // target (timelock calls itself)
            0, // value
            updateDelayData, // payload (updateDelay call)
            bytes32(0), // predecessor
            salt // salt
        );

        console.log("=== SAFE MULTISIG EXECUTION PAYLOAD ===");
        console.log("TimelockController Address:", contracts.timelock);
        console.log("Operation ID:");
        console.logBytes32(operationId);
        console.log("");

        console.log("=== SAFE TRANSACTION DETAILS ===");
        console.log("To Address (TimelockController):", contracts.timelock);
        console.log("Value: 0");
        console.log("Data (execute call):");
        console.logBytes(executeCallData);
        console.log("");

        console.log("=== FUNCTION SELECTOR BREAKDOWN ===");
        console.log("Function: execute(address,uint256,bytes,bytes32,bytes32)");
        console.log("Selector:", vm.toString(TimelockController.execute.selector));
        console.log("");

        console.log("=== PARAMETERS ===");
        console.log("target:", contracts.timelock);
        console.log("value: 0");
        console.log("payload (updateDelay call):");
        console.logBytes(updateDelayData);
        console.log("predecessor: 0x0000000000000000000000000000000000000000000000000000000000000000");
        console.log("salt:");
        console.logBytes32(salt);
        console.log("");

        console.log("=== COPY THIS FOR SAFE UI ===");
        console.log("Contract Address:", contracts.timelock);
        console.log("Value: 0");
        console.log("Hex Data:");
        console.logBytes(executeCallData);
    }

    /**
     * @notice Generate Safe execution payload with known salt
     * @param newDelay The new delay value that was scheduled
     * @param knownSalt The salt that was used during scheduling
     */
    function generateSafeExecutionPayloadWithSalt(uint256 newDelay, bytes32 knownSalt) external view {
        DeployedContracts memory contracts = Contracts.get();
        require(contracts.timelock != address(0), "Timelock not deployed");

        TimelockController tc = TimelockController(payable(contracts.timelock));

        // Use the provided salt
        bytes memory updateDelayData = abi.encodeWithSelector(TimelockController.updateDelay.selector, newDelay);

        // Generate operation ID with known salt
        bytes32 operationId = tc.hashOperation(contracts.timelock, 0, updateDelayData, bytes32(0), knownSalt);

        // Check operation status
        bool isPending = tc.isOperationPending(operationId);
        bool isReady = tc.isOperationReady(operationId);
        bool isDone = tc.isOperationDone(operationId);

        // Create execute calldata for TimelockController
        bytes memory executeCallData = abi.encodeWithSelector(
            TimelockController.execute.selector,
            contracts.timelock, // target (timelock calls itself)
            0, // value
            updateDelayData, // payload (updateDelay call)
            bytes32(0), // predecessor
            knownSalt // salt
        );

        console.log("=== SAFE MULTISIG EXECUTION PAYLOAD (WITH KNOWN SALT) ===");
        console.log("TimelockController Address:", contracts.timelock);
        console.log("Operation ID:");
        console.logBytes32(operationId);
        console.log("");

        console.log("=== OPERATION STATUS ===");
        console.log("Is Pending:", isPending);
        console.log("Is Ready:", isReady);
        console.log("Is Done:", isDone);

        if (isReady) {
            console.log("READY TO EXECUTE");
        } else if (isPending) {
            uint256 timestamp = tc.getTimestamp(operationId);
            console.log("PENDING - Execution available at:", timestamp);
            console.log("Current time:", block.timestamp);
            if (timestamp > block.timestamp) {
                console.log("Time remaining:", timestamp - block.timestamp, "seconds");
            }
        } else if (isDone) {
            console.log("ALREADY EXECUTED");
        } else {
            console.log("NOT SCHEDULED");
        }
        console.log("");

        if (isReady) {
            console.log("=== SAFE TRANSACTION DETAILS ===");
            console.log("To Address (TimelockController):", contracts.timelock);
            console.log("Value: 0");
            console.log("Data (execute call):");
            console.logBytes(executeCallData);
            console.log("");

            console.log("=== COPY THIS FOR SAFE UI ===");
            console.log("Contract Address:", contracts.timelock);
            console.log("Value: 0");
            console.log("Hex Data:");
            console.logBytes(executeCallData);
        } else {
            console.log("Operation not ready for execution");
        }
    }

    /**
     * @notice Generate Safe execution payload without querying live contract (for offline use)
     * @param timelockAddress The address of the TimelockController
     * @param newDelay The new delay value that was scheduled
     * @param knownSalt The salt that was used during scheduling
     */
    function generateSafeExecutionPayloadOffline(address timelockAddress, uint256 newDelay, bytes32 knownSalt)
        external
        pure
    {
        // Create updateDelay calldata
        bytes memory updateDelayData = abi.encodeWithSelector(TimelockController.updateDelay.selector, newDelay);

        // Generate operation ID
        bytes32 operationId =
            keccak256(abi.encode(timelockAddress, 0, keccak256(updateDelayData), bytes32(0), knownSalt));

        // Create execute calldata for TimelockController
        bytes memory executeCallData = abi.encodeWithSelector(
            TimelockController.execute.selector,
            timelockAddress, // target (timelock calls itself)
            0, // value
            updateDelayData, // payload (updateDelay call)
            bytes32(0), // predecessor
            knownSalt // salt
        );

        console.log("=== SAFE MULTISIG EXECUTION PAYLOAD (OFFLINE) ===");
        console.log("TimelockController Address:", timelockAddress);
        console.log("New Delay:", newDelay, "seconds");
        console.log("Salt:");
        console.logBytes32(knownSalt);
        console.log("Operation ID:");
        console.logBytes32(operationId);
        console.log("");

        console.log("=== SAFE TRANSACTION DETAILS ===");
        console.log("To Address (TimelockController):", timelockAddress);
        console.log("Value: 0");
        console.log("Data (execute call):");
        console.logBytes(executeCallData);
        console.log("");

        console.log("=== FUNCTION BREAKDOWN ===");
        console.log("Function: execute(address,uint256,bytes,bytes32,bytes32)");
        console.log("Parameters:");
        console.log("  target:", timelockAddress);
        console.log("  value: 0");
        console.log("  payload (updateDelay call):");
        console.logBytes(updateDelayData);
        console.log("  predecessor: 0x0000000000000000000000000000000000000000000000000000000000000000");
        console.log("  salt:");
        console.logBytes32(knownSalt);
        console.log("");

        console.log("=== COPY THIS FOR SAFE UI ===");
        console.log("Contract Address:", timelockAddress);
        console.log("Value: 0");
        console.log("Hex Data:");
        console.logBytes(executeCallData);
        console.log("");

        console.log("=== VALIDATION ===");
        console.log("Make sure this operation was scheduled with these exact parameters:");
        console.log("- Target:", timelockAddress);
        console.log("- Value: 0");
        console.log("- Data:", vm.toString(updateDelayData));
        console.log("- Predecessor: 0x0000000000000000000000000000000000000000000000000000000000000000");
        console.log("- Salt:", vm.toString(knownSalt));
        console.log("- Operation ID should match your scheduled operation");
    }

    /**
     * @notice Check if an address has EXECUTOR_ROLE on the timelock
     * @param timelockAddress The TimelockController address
     * @param executor The address to check for EXECUTOR_ROLE
     */
    function checkExecutorRole(address timelockAddress, address executor) external view {
        TimelockController tc = TimelockController(payable(timelockAddress));

        bytes32 EXECUTOR_ROLE = tc.EXECUTOR_ROLE();
        bool hasExecutorRole = tc.hasRole(EXECUTOR_ROLE, executor);

        console.log("=== EXECUTOR ROLE CHECK ===");
        console.log("TimelockController:", timelockAddress);
        console.log("Address to check:", executor);
        console.log("EXECUTOR_ROLE:");
        console.logBytes32(EXECUTOR_ROLE);
        console.log("Has EXECUTOR_ROLE:", hasExecutorRole);

        if (hasExecutorRole) {
            console.log("SUCCESS: Address has EXECUTOR_ROLE");
        } else {
            console.log("ERROR: Address does NOT have EXECUTOR_ROLE");
            console.log("This address cannot execute timelock operations");
        }
    }

    /**
     * @notice Check operation status for debugging
     * @param timelockAddress The TimelockController address
     * @param target The target address (should be timelock itself for delay updates)
     * @param value The value (should be 0)
     * @param data The encoded function call data
     * @param predecessor The predecessor operation ID
     * @param salt The salt used when scheduling
     */
    function debugOperationStatus(
        address timelockAddress,
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) external view {
        TimelockController tc = TimelockController(payable(timelockAddress));

        bytes32 operationId = tc.hashOperation(target, value, data, predecessor, salt);

        console.log("=== OPERATION DEBUG ===");
        console.log("TimelockController:", timelockAddress);
        console.log("Target:", target);
        console.log("Value:", value);
        console.log("Data:");
        console.logBytes(data);
        console.log("Predecessor:");
        console.logBytes32(predecessor);
        console.log("Salt:");
        console.logBytes32(salt);
        console.log("");

        console.log("Operation ID:");
        console.logBytes32(operationId);
        console.log("");

        console.log("=== STATUS ===");
        console.log("Is Pending:", tc.isOperationPending(operationId));
        console.log("Is Ready:", tc.isOperationReady(operationId));
        console.log("Is Done:", tc.isOperationDone(operationId));
        console.log("Timestamp:", tc.getTimestamp(operationId));
        console.log("Current Time:", block.timestamp);
        console.log("Min Delay:", tc.getMinDelay());

        if (tc.isOperationReady(operationId)) {
            console.log("STATUS: READY TO EXECUTE");
        } else if (tc.isOperationPending(operationId)) {
            uint256 timestamp = tc.getTimestamp(operationId);
            if (timestamp > block.timestamp) {
                console.log("STATUS: PENDING - Execution available at timestamp:", timestamp);
                console.log("Time remaining:", timestamp - block.timestamp, "seconds");
            } else {
                console.log("STATUS: READY TO EXECUTE");
            }
        } else if (tc.isOperationDone(operationId)) {
            console.log("STATUS: ALREADY EXECUTED");
        } else {
            console.log("STATUS: NOT SCHEDULED");
        }
    }

    /**
     * @notice Decode and verify the parameters in the Safe transaction hex data
     * @param hexData The hex data from the Safe transaction
     */
    function decodeExecuteCall(bytes calldata hexData) external pure {
        console.log("=== DECODE EXECUTE CALL ===");
        console.log("Input hex data:");
        console.logBytes(hexData);
        console.log("");

        // Check if it starts with execute selector
        bytes4 executeSelector = TimelockController.execute.selector;
        console.log("Expected execute selector:");
        console.logBytes4(executeSelector);

        if (hexData.length < 4) {
            console.log("ERROR: Data too short");
            return;
        }

        bytes4 actualSelector;
        assembly {
            actualSelector := shr(224, calldataload(add(hexData.offset, 0)))
        }
        console.log("Actual selector:");
        console.logBytes4(actualSelector);

        if (actualSelector != executeSelector) {
            console.log("ERROR: Selector mismatch!");
            return;
        }

        console.log("SUCCESS: Correct execute selector");

        // Decode the parameters
        if (hexData.length >= 164) {
            // 4 + 32*5 = minimum length
            (address target, uint256 value, bytes memory payload, bytes32 predecessor, bytes32 salt) =
                abi.decode(hexData[4:], (address, uint256, bytes, bytes32, bytes32));

            console.log("");
            console.log("=== DECODED PARAMETERS ===");
            console.log("Target:", target);
            console.log("Value:", value);
            console.log("Payload:");
            console.logBytes(payload);
            console.log("Predecessor:");
            console.logBytes32(predecessor);
            console.log("Salt:");
            console.logBytes32(salt);

            // Check if payload is updateDelay call
            if (payload.length >= 4) {
                bytes4 payloadSelector;
                assembly {
                    payloadSelector := mload(add(payload, 0x20))
                }
                bytes4 updateDelaySelector = TimelockController.updateDelay.selector;

                console.log("");
                console.log("=== PAYLOAD ANALYSIS ===");
                console.log("Expected updateDelay selector:");
                console.logBytes4(updateDelaySelector);
                console.log("Actual payload selector:");
                console.logBytes4(payloadSelector);

                if (payloadSelector == updateDelaySelector) {
                    console.log("SUCCESS: Correct updateDelay call");
                    if (payload.length >= 36) {
                        uint256 newDelay;
                        assembly {
                            newDelay := mload(add(payload, 0x24))
                        }
                        console.log("New delay value:", newDelay, "seconds");
                    }
                } else {
                    console.log("ERROR: Payload is not updateDelay call");
                }
            }
        } else {
            console.log("ERROR: Data too short to decode parameters");
        }
    }

    /**
     * @notice Main run function with usage instructions
     */
    function run() external pure {
        console.log("=== TIMELOCK DELAY UPDATER ===");
        console.log("Usage examples:");
        console.log("");
        console.log("1. Generate payload to update delay to 24 hours (86400 seconds):");
        console.log("forge script script/TimelockDelay.s.sol --sig 'generateUpdateDelayPayload(uint256)' 86400");
        console.log("");
        console.log("2. Generate payload to update delay to 72 hours (259200 seconds):");
        console.log("forge script script/TimelockDelay.s.sol --sig 'generateUpdateDelayPayload(uint256)' 259200");
        console.log("");
        console.log("3. Check operation status:");
        console.log("forge script script/TimelockDelay.s.sol --sig 'checkOperationStatus(bytes32)' <OPERATION_ID>");
        console.log("");
        console.log("4. Generate operation ID:");
        console.log(
            "forge script script/TimelockDelay.s.sol --sig 'generateOperationId(address,uint256,bytes,bytes32,bytes32)' <TARGET> <VALUE> <DATA> <PREDECESSOR> <SALT>"
        );
        console.log("");
        console.log("=== SAFE MULTISIG EXECUTION ===");
        console.log("5. Generate Safe execution payload (auto-generate salt):");
        console.log("forge script script/TimelockDelay.s.sol --sig 'generateSafeExecutionPayload(uint256)' <NEW_DELAY>");
        console.log("");
        console.log("6. Generate Safe execution payload (with known salt):");
        console.log(
            "forge script script/TimelockDelay.s.sol --sig 'generateSafeExecutionPayloadWithSalt(uint256,bytes32)' <NEW_DELAY> <SALT>"
        );
        console.log("");
        console.log("7. Generate Safe execution payload (offline, no RPC needed):");
        console.log(
            "forge script script/TimelockDelay.s.sol --sig 'generateSafeExecutionPayloadOffline(address,uint256,bytes32)' <TIMELOCK_ADDRESS> <NEW_DELAY> <SALT>"
        );
        console.log("");
        console.log("Important Notes:");
        console.log("- Only accounts with PROPOSER_ROLE can schedule proposals");
        console.log("- Only accounts with EXECUTOR_ROLE can execute proposals");
        console.log("- The new delay must wait the current delay duration before execution");
        console.log("- The timelock calls updateDelay on itself to change the minimum delay");
        console.log("- For Safe multisig: Copy the hex data and use it in Safe UI transaction builder");
    }
}
