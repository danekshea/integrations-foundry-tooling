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

interface IOAppCore {
    function endpoint() external view returns (address);
}

contract SimulateComposeV2 is Script {
    using stdJson for string;

    // ComposeSent(address from, address to, bytes32 guid, uint16 index, bytes message)
    bytes32 constant COMPOSE_SENT_TOPIC = 0x3d52ff888d033fd3dd1d8057da59e850c91d91a72c41dfa445b247dfedeb6dc1;

    struct ComposeParams {
        bytes32 guid;
        address from;
        address to;
        uint16 index;
        uint256 composeValue;
        string destTxHash;
        bytes message;
    }

    function run() external {
        string memory json = _fetchApiData();
        ComposeParams memory params = _parseComposeParams(json);
        _populateFromEvent(params);

        console.log("=== COMPOSE PARAMETERS ===");
        console.log("GUID:");
        console.logBytes32(params.guid);
        console.log("From:", params.from);
        console.log("To:", params.to);
        console.log("Index:", params.index);
        console.log("Compose Value (wei):", params.composeValue);
        console.log("Destination TX:", params.destTxHash);
        console.log("Compose Message Length:", params.message.length);
        console.log("Compose Message:");
        console.logBytes(params.message);

        address endpoint = IOAppCore(params.from).endpoint();
        console.log("Endpoint (derived from OApp):", endpoint);

        _validateComposeQueue(endpoint, params);
        _executeLzCompose(endpoint, params);
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

        string memory composeStatus = json.readString(".data[0].destination.lzCompose.status");
        console.log("Compose Status:", composeStatus);

        if (_stringsEqual(composeStatus, "SUCCEEDED")) {
            console.log("ERROR: Compose already succeeded according to API");
            revert("Compose already executed (status: SUCCEEDED)");
        }

        params.composeValue = json.readUint(".data[0].source.tx.options.compose[0].value");
        params.destTxHash = json.readString(".data[0].destination.tx.txHash");
    }

    function _stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function _validateComposeQueue(address endpoint, ComposeParams memory params) internal view {
        bytes32 composeHash = IEndpointV2Compose(endpoint).composeQueue(params.from, params.to, params.guid, params.index);
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

        bytes32 expectedHash = keccak256(params.message);
        console.log("Expected Hash:");
        console.logBytes32(expectedHash);

        if (composeHash != expectedHash) {
            console.log("WARNING: Hash mismatch - message may be incorrect");
        }
    }

    function _executeLzCompose(address endpoint, ComposeParams memory params) internal {
        uint256 bufferPercent = vm.envOr("COMPOSE_VALUE_BUFFER_PERCENT", uint256(50));
        uint256 valueWithBuffer = params.composeValue * (100 + bufferPercent) / 100;
        console.log("Buffer percent:", bufferPercent);
        console.log("Value with buffer (wei):", valueWithBuffer);

        console.log("=== EXECUTING lzCompose ===");
        vm.startBroadcast();
        IEndpointV2Compose(endpoint).lzCompose{value: valueWithBuffer}(
            params.from,
            params.to,
            params.guid,
            params.index,
            params.message,
            ""
        );
        vm.stopBroadcast();

        console.log("lzCompose executed successfully!");
    }

    function _populateFromEvent(ComposeParams memory params) internal {
        string memory rpcUrl = vm.envString("DESTINATION_CHAIN_RPC_URL");
        string memory dataFile = "./data/compose_event.txt";

        string[] memory fetchCommand = new string[](3);
        fetchCommand[0] = "bash";
        fetchCommand[1] = "-c";
        fetchCommand[2] = string(abi.encodePacked(
            "cast receipt ", params.destTxHash,
            " --json --rpc-url ", rpcUrl,
            " | jq -r '.logs[] | select(.topics[0] == \"0x3d52ff888d033fd3dd1d8057da59e850c91d91a72c41dfa445b247dfedeb6dc1\") | .data' > ",
            dataFile
        ));

        vm.ffi(fetchCommand);

        string memory hexData = vm.readLine(dataFile);
        bytes memory eventData = vm.parseBytes(hexData);

        // Event: ComposeSent(address from, address to, bytes32 guid, uint16 index, bytes message)
        // All non-indexed → all in data, ABI-encoded.
        (address from_, address to_, , uint16 index_, bytes memory message_) =
            abi.decode(eventData, (address, address, bytes32, uint16, bytes));

        params.from = from_;
        params.to = to_;
        params.index = index_;
        params.message = message_;
    }
}
