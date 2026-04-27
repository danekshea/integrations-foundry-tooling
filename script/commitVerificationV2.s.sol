// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import "forge-std/StdJson.sol";

interface IReceiveUlnE2 {
    function commitVerification(bytes calldata _packetHeader, bytes32 _payloadHash) external;
}

contract CommitVerificationV2 is Script {
    using stdJson for string;

    function run() external {
        // Fetch and validate API data
        (string memory json, string memory apiUrl) = _fetchApiData();
        address receiveLib = _validateStatus(json);

        // Fetch DVN proof data (packetHeader + payloadHash)
        (bytes memory packetHeader, bytes32 payloadHash) = _fetchDvnProof(apiUrl);

        // Log packet header details for human verification
        _logPacketHeader(packetHeader);

        console.log("=== COMMIT VERIFICATION PARAMETERS ===");
        console.log("Receive Library:", receiveLib);
        console.log("Packet Header Length:", packetHeader.length);
        console.log("Packet Header:");
        console.logBytes(packetHeader);
        console.log("Payload Hash:");
        console.logBytes32(payloadHash);

        // Execute commitVerification
        _executeCommitVerification(receiveLib, packetHeader, payloadHash);
    }

    function _fetchApiData() internal returns (string memory json, string memory apiUrl) {
        bool mainnet = vm.envBool("MAINNET");
        string memory sourceChainTXHash = vm.envString("SOURCE_CHAIN_TX_HASH");

        apiUrl = string(abi.encodePacked(
            mainnet ? "https://scan.layerzero-api.com" : "https://scan-testnet.layerzero-api.com",
            "/v1/messages/tx/",
            sourceChainTXHash
        ));

        console.log("Fetching LayerZero message details for commitVerification...");
        console.log(" => TX Hash: %s", sourceChainTXHash);
        console.log(" => API Endpoint: %s", apiUrl);

        string[] memory curlCommand = new string[](7);
        curlCommand[0] = "curl";
        curlCommand[1] = "-s";
        curlCommand[2] = "-X";
        curlCommand[3] = "GET";
        curlCommand[4] = apiUrl;
        curlCommand[5] = "-H";
        curlCommand[6] = "accept: application/json";

        bytes memory res = vm.ffi(curlCommand);
        json = string(res);
    }

    function _validateStatus(string memory json) internal pure returns (address receiveLib) {
        // Read pathway info for logging
        uint32 srcEid = uint32(json.readUint(".data[0].pathway.srcEid"));
        uint32 dstEid = uint32(json.readUint(".data[0].pathway.dstEid"));
        string memory senderChain = json.readString(".data[0].pathway.sender.chain");
        string memory receiverChain = json.readString(".data[0].pathway.receiver.chain");
        string memory senderAddress = json.readString(".data[0].pathway.sender.address");
        address receiverAddress = json.readAddress(".data[0].pathway.receiver.address");
        bytes32 guid = json.readBytes32(".data[0].guid");

        console.log("=== MESSAGE INFO ===");
        console.log("Source EID:", srcEid);
        console.log("Destination EID:", dstEid);
        console.log("Sender: %s (%s)", senderAddress, senderChain);
        console.log("Receiver: %s (%s)", receiverAddress, receiverChain);
        console.log("GUID:");
        console.logBytes32(guid);

        // Check DVN verification status
        string memory dvnStatus = json.readString(".data[0].verification.dvn.status");
        console.log("DVN Status:", dvnStatus);
        require(
            _stringsEqual(dvnStatus, "SUCCEEDED"),
            "DVN verification has not succeeded yet"
        );

        // Check sealer/commit status
        string memory sealerStatus = json.readString(".data[0].verification.sealer.status");
        console.log("Sealer Status:", sealerStatus);
        require(
            _stringsEqual(sealerStatus, "WAITING"),
            "Commit verification is not in WAITING state (may already be committed)"
        );

        // Get the receive library address from config
        receiveLib = json.readAddress(".data[0].config.receiveLibrary");
        console.log("Receive Library:", receiveLib);
    }

    function _fetchDvnProof(string memory apiUrl) internal returns (bytes memory packetHeader, bytes32 payloadHash) {
        string memory dataFile = "./data/dvn_proof.txt";

        // Use jq to extract packetHeader and payloadHash from the first DVN's proof.
        // DVN proofs are under dynamic keys (DVN addresses), so we use jq to grab the first one.
        string[] memory fetchCommand = new string[](3);
        fetchCommand[0] = "bash";
        fetchCommand[1] = "-c";
        fetchCommand[2] = string(abi.encodePacked(
            "curl -s '", apiUrl, "' -H 'accept: application/json'"
            " | jq -r '[(.data[0].verification.dvn.dvns | to_entries[0].value.proof.packetHeader),"
            " (.data[0].verification.dvn.dvns | to_entries[0].value.proof.payloadHash)] | .[]' > ",
            dataFile
        ));

        vm.ffi(fetchCommand);

        // Read packetHeader (first line) and payloadHash (second line)
        string memory packetHeaderHex = vm.readLine(dataFile);
        string memory payloadHashHex = vm.readLine(dataFile);

        require(bytes(packetHeaderHex).length > 0, "Failed to extract packetHeader from DVN proof");
        require(bytes(payloadHashHex).length > 0, "Failed to extract payloadHash from DVN proof");

        packetHeader = vm.parseBytes(packetHeaderHex);
        payloadHash = vm.parseBytes32(payloadHashHex);
    }

    function _logPacketHeader(bytes memory packetHeader) internal pure {
        // Packet header is 81 bytes:
        // - version (1 byte)
        // - nonce (8 bytes)
        // - srcEid (4 bytes)
        // - sender (32 bytes)
        // - dstEid (4 bytes)
        // - receiver (32 bytes)
        require(packetHeader.length == 81, "Invalid packet header length (expected 81 bytes)");

        uint8 version;
        uint64 nonce;
        uint32 srcEid;
        bytes32 sender;
        uint32 dstEid;
        bytes32 receiver;

        assembly {
            let ptr := add(packetHeader, 32) // skip length prefix
            version := byte(0, mload(ptr))
            nonce := shr(192, mload(add(ptr, 1)))
            srcEid := shr(224, mload(add(ptr, 9)))
            sender := mload(add(ptr, 13))
            dstEid := shr(224, mload(add(ptr, 45)))
            receiver := mload(add(ptr, 49))
        }

        console.log("=== PACKET HEADER DECODED ===");
        console.log("Version:", version);
        console.log("Nonce:", nonce);
        console.log("Source EID:", srcEid);
        console.log("Sender:");
        console.logBytes32(sender);
        console.log("Destination EID:", dstEid);
        console.log("Receiver:");
        console.logBytes32(receiver);
    }

    function _executeCommitVerification(
        address receiveLib,
        bytes memory packetHeader,
        bytes32 payloadHash
    ) internal {
        console.log("=== EXECUTING commitVerification ===");
        uint256 gasStart = gasleft();

        vm.startBroadcast();

        try IReceiveUlnE2(receiveLib).commitVerification(packetHeader, payloadHash) {
            console.log("=== SUCCESS ===");
            console.log("commitVerification executed successfully!");
        } catch Error(string memory reason) {
            console.log("=== STRING REVERT ===");
            console.log("Revert reason:", reason);
        } catch Panic(uint errorCode) {
            console.log("=== PANIC ERROR ===");
            console.log("Panic code:", errorCode);
            if (errorCode == 0x01) {
                console.log("Panic type: Assertion failed (assert)");
            } else if (errorCode == 0x11) {
                console.log("Panic type: Arithmetic overflow/underflow");
            } else if (errorCode == 0x12) {
                console.log("Panic type: Division by zero");
            } else if (errorCode == 0x21) {
                console.log("Panic type: Invalid enum value");
            } else if (errorCode == 0x22) {
                console.log("Panic type: Invalid storage byte array access");
            } else if (errorCode == 0x31) {
                console.log("Panic type: Pop on empty array");
            } else if (errorCode == 0x32) {
                console.log("Panic type: Array index out of bounds");
            } else if (errorCode == 0x41) {
                console.log("Panic type: Too much memory allocated");
            } else if (errorCode == 0x51) {
                console.log("Panic type: Zero-initialized variable of internal function type");
            } else {
                console.log("Panic type: Unknown");
            }
        } catch (bytes memory lowLevelData) {
            console.log("=== LOW LEVEL REVERT ===");
            console.log("Revert data length:", lowLevelData.length);
            if (lowLevelData.length == 0) {
                console.log("Empty revert data - likely assertion failure or require() without message");
            } else {
                console.log("Raw revert data:");
                console.logBytes(lowLevelData);
                if (lowLevelData.length >= 68) {
                    bytes4 selector;
                    assembly {
                        selector := mload(add(lowLevelData, 32))
                    }
                    if (selector == 0x08c379a0) {
                        bytes memory errorData = new bytes(lowLevelData.length - 4);
                        for (uint i = 0; i < errorData.length; i++) {
                            errorData[i] = lowLevelData[i + 4];
                        }
                        string memory errorMessage = abi.decode(errorData, (string));
                        console.log("Decoded error message:", errorMessage);
                    }
                }
            }
        }

        vm.stopBroadcast();

        uint256 gasEnd = gasleft();
        console.log("Gas used:", gasStart - gasEnd);
    }

    function _stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}
