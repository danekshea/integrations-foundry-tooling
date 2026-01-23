// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import "forge-std/StdJson.sol";

interface IEndpointV2Compose {
    function lzCompose(
        address _from,
        address _to,
        bytes32 _guid,
        uint16 _index,
        bytes calldata _message,
        bytes calldata _extraData
    ) external payable;

    function composeQueue(
        address _from,
        address _to,
        bytes32 _guid,
        uint16 _index
    ) external view returns (bytes32);
}

contract SimulateCompose is Script {
    using stdJson for string;

    // Ethereum mainnet EndpointV2
    address constant ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;
    
    struct ComposeParams {
        bytes32 guid;
        address from;
        address to;
        uint16 index;
        uint256 composeValue;
        string destTxHash;
    }

    function run() external {
        // Read environment variables and fetch API data
        string memory json = _fetchApiData();
        
        // Parse compose parameters
        ComposeParams memory params = _parseComposeParams(json);

        console.log("=== COMPOSE PARAMETERS ===");
        console.log("GUID:");
        console.logBytes32(params.guid);
        console.log("From:", params.from);
        console.log("To:", params.to);
        console.log("Index:", params.index);
        console.log("Compose Value (wei):", params.composeValue);
        console.log("Destination TX:", params.destTxHash);

        // Fetch the compose message from the destination tx logs
        bytes memory composeMessage = _fetchComposeMessage(params.destTxHash);
        
        console.log("Compose Message Length:", composeMessage.length);
        console.log("Compose Message:");
        console.logBytes(composeMessage);

        // Check if compose is still queued
        _validateComposeQueue(params, composeMessage);

        // Execute lzCompose with buffer
        _executeLzCompose(params, composeMessage);
    }
    
    function _fetchApiData() internal returns (string memory) {
        bool mainnet = vm.envBool("MAINNET");
        string memory sourceChainTXHash = vm.envString("SOURCE_CHAIN_TX_HASH");

        string memory apiUrl = string(abi.encodePacked(
            mainnet ? "https://scan.layerzero-api.com" : "https://scan-testnet.layerzero-api.com",
            "/v1/messages/tx/",
            sourceChainTXHash
        ));

        console.log("Fetching LayerZero message details for lzCompose...");
        console.log(" => TX Hash: %s", sourceChainTXHash);

        string[] memory curlCommand = new string[](7);
        curlCommand[0] = "curl";
        curlCommand[1] = "-s";
        curlCommand[2] = "-X";
        curlCommand[3] = "GET";
        curlCommand[4] = apiUrl;
        curlCommand[5] = "-H";
        curlCommand[6] = "accept: application/json";

        bytes memory res = vm.ffi(curlCommand);
        return string(res);
    }
    
    function _parseComposeParams(string memory json) internal view returns (ComposeParams memory params) {
        params.guid = json.readBytes32(".data[0].guid");
        
        // Check compose status - if SUCCEEDED, the compose already executed
        string memory composeStatus = json.readString(".data[0].destination.lzCompose.status");
        console.log("Compose Status:", composeStatus);
        
        if (_stringsEqual(composeStatus, "SUCCEEDED")) {
            console.log("ERROR: Compose already succeeded according to API");
            revert("Compose already executed (status: SUCCEEDED)");
        }
        
        // Get from/to from failedTx array (for PENDING or FAILED composes)
        params.from = json.readAddress(".data[0].destination.lzCompose.failedTx[0].from");
        params.to = json.readAddress(".data[0].destination.lzCompose.failedTx[0].to");
        params.index = uint16(json.readUint(".data[0].destination.lzCompose.failedTx[0].index"));

        params.composeValue = json.readUint(".data[0].source.tx.options.compose[0].value");
        params.destTxHash = json.readString(".data[0].destination.tx.txHash");
    }
    
    function _stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
    
    function _validateComposeQueue(ComposeParams memory params, bytes memory composeMessage) internal view {
        // NO_MESSAGE_HASH = 0x01 means already executed
        bytes32 composeHash = IEndpointV2Compose(ENDPOINT_V2).composeQueue(params.from, params.to, params.guid, params.index);
        console.log("Compose Queue Hash:");
        console.logBytes32(composeHash);

        if (composeHash == bytes32(0)) {
            console.log("ERROR: Compose not found in queue");
            revert("Compose not found in queue");
        }
        
        if (composeHash == bytes32(uint256(1))) {
            console.log("ERROR: Compose already executed (NO_MESSAGE_HASH)");
            revert("Compose already executed");
        }

        // Verify message hash
        bytes32 expectedHash = keccak256(abi.encodePacked(keccak256(composeMessage), params.composeValue));
        console.log("Expected Hash:");
        console.logBytes32(expectedHash);
        
        if (composeHash != expectedHash) {
            console.log("WARNING: Hash mismatch - message may be incorrect");
        }
    }
    
    function _executeLzCompose(ComposeParams memory params, bytes memory composeMessage) internal {
        // Add buffer for gas price fluctuations (configurable via COMPOSE_VALUE_BUFFER_PERCENT env var)
        uint256 bufferPercent = vm.envOr("COMPOSE_VALUE_BUFFER_PERCENT", uint256(50));
        uint256 valueWithBuffer = params.composeValue * (100 + bufferPercent) / 100;
        console.log("Buffer percent:", bufferPercent);
        console.log("Value with buffer (wei):", valueWithBuffer);

        console.log("=== EXECUTING lzCompose ===");
        vm.startBroadcast();
        IEndpointV2Compose(ENDPOINT_V2).lzCompose{value: valueWithBuffer}(
            params.from,
            params.to,
            params.guid,
            params.index,
            composeMessage,
            "" // extraData
        );
        vm.stopBroadcast();

        console.log("lzCompose executed successfully!");
    }

    function _fetchComposeMessage(string memory destTxHash) internal returns (bytes memory) {
        // Use bash to get the ComposeSent event data and save to a temp file
        string memory rpcUrl = vm.envString("DESTINATION_CHAIN_RPC_URL");
        string memory dataFile = "./data/compose_event.txt";
        
        // Fetch the event data using cast and jq, save to file
        string[] memory fetchCommand = new string[](3);
        fetchCommand[0] = "bash";
        fetchCommand[1] = "-c";
        fetchCommand[2] = string(abi.encodePacked(
            "cast receipt ", destTxHash,
            " --json --rpc-url ", rpcUrl,
            " | jq -r '.logs[] | select(.topics[0] == \"0x3d52ff888d033fd3dd1d8057da59e850c91d91a72c41dfa445b247dfedeb6dc1\") | .data' > ",
            dataFile
        ));
        
        vm.ffi(fetchCommand);
        
        // Read the hex string from file
        string memory hexData = vm.readLine(dataFile);
        
        // Parse the hex string to bytes
        bytes memory eventData = vm.parseBytes(hexData);
        
        // Extract message from event data using abi.decode
        // Event data layout (ABI encoded):
        // - from (address)
        // - to (address)  
        // - guid (bytes32)
        // - index (uint16)
        // - message (bytes) - dynamic, stored as offset + length + data
        
        // Skip the first 4 fixed params (4 * 32 = 128 bytes) and decode the message
        // The message offset is at position 0x80 (128), pointing to 0xa0 (160)
        // At 0xa0 we have the length, then the actual message bytes
        
        uint256 messageLength;
        assembly {
            // eventData in memory: [32 bytes length][actual data...]
            // Message length is at data offset 0xa0 (160 bytes into the data)
            // So memory position is: eventData + 32 (length prefix) + 160 (offset) = eventData + 192
            messageLength := mload(add(eventData, 0xc0))
        }
        
        // Message data starts at offset 0xc0 (192) in the event data
        bytes memory message = new bytes(messageLength);
        assembly {
            // Copy message data
            // Source: eventData + 32 (length) + 192 (data offset 0xc0) = eventData + 224
            // Dest: message + 32 (length prefix)
            let src := add(eventData, 0xe0)
            let dst := add(message, 0x20)
            for { let i := 0 } lt(i, messageLength) { i := add(i, 0x20) } {
                mstore(add(dst, i), mload(add(src, i)))
            }
        }
        
        return message;
    }
}
