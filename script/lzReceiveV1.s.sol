// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import {Base58Decoder} from "../src/Base58Decoder.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice LayerZero V1 Endpoint interface
interface ILayerZeroEndpointV1 {
    function hasStoredPayload(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (bool);
    function storedPayload(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (uint64 payloadLength, address dstAddress);
    function retryPayload(uint16 _srcChainId, bytes calldata _srcAddress, bytes calldata _payload) external;
}

/// @notice LayerZero V1 OFT interface for getting token info
interface IOFTV1 {
    function token() external view returns (address);
    function trustedRemoteLookup(uint16 _srcChainId) external view returns (bytes memory);
    function lzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) external;
}

contract SimulateReceiveV1 is Script {
    using stdJson for string;
    using Base58Decoder for string;

    // Known LayerZero V1 Endpoint addresses by chain
    function getLzEndpointV1(string memory chain) internal pure returns (address) {
        bytes32 chainHash = keccak256(bytes(chain));
        
        if (chainHash == keccak256("ethereum")) return 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;
        if (chainHash == keccak256("bsc")) return 0x3c2269811836af69497E5F486A85D7316753cf62;
        if (chainHash == keccak256("avalanche")) return 0x3c2269811836af69497E5F486A85D7316753cf62;
        if (chainHash == keccak256("polygon")) return 0x3c2269811836af69497E5F486A85D7316753cf62;
        if (chainHash == keccak256("arbitrum")) return 0x3c2269811836af69497E5F486A85D7316753cf62;
        if (chainHash == keccak256("optimism")) return 0x3c2269811836af69497E5F486A85D7316753cf62;
        if (chainHash == keccak256("fantom")) return 0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7;
        if (chainHash == keccak256("base")) return 0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7;
        
        revert("Unknown chain for LZ V1 endpoint");
    }

    function run() public {
        bool mainnet = vm.envBool("MAINNET");
        string memory sourceChainTXHash = vm.envString("SOURCE_CHAIN_TX_HASH");

        string memory apiUrl = string(abi.encodePacked(
            mainnet ?
            "https://scan.layerzero-api.com" :
            "https://scan-testnet.layerzero-api.com",
            "/v1/messages/tx/",
            sourceChainTXHash
        ));

        console.log("=== LayerZero V1 Retry Script ===");
        console.log("Fetching message details...");
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
        string memory json = string(res);

        // Parse message details
        string memory senderChain = json.readString(".data[0].pathway.sender.chain");
        string memory destinationChain = json.readString(".data[0].pathway.receiver.chain");
        string memory senderAddressStr = json.readString(".data[0].pathway.sender.address");
        address receiver = json.readAddress(".data[0].pathway.receiver.address");
        uint64 nonce = uint64(json.readUint(".data[0].pathway.nonce"));
        uint16 srcChainId = uint16(json.readUint(".data[0].pathway.srcEid"));
        bytes memory payload = json.readBytes(".data[0].source.tx.payload");
        string memory status = json.readString(".data[0].status.name");

        console.log("");
        console.log("=== MESSAGE DETAILS ===");
        console.log("Source Chain: %s (EID: %s)", senderChain, vm.toString(srcChainId));
        console.log("Destination Chain: %s", destinationChain);
        console.log("Sender: %s", senderAddressStr);
        console.log("Receiver (OFT): %s", receiver);
        console.log("Nonce: %s", vm.toString(nonce));
        console.log("Status: %s", status);
        console.log("Payload length: %s bytes", vm.toString(payload.length));

        // Get LZ V1 Endpoint
        address lzEndpoint = getLzEndpointV1(destinationChain);
        console.log("");
        console.log("=== LZ V1 ENDPOINT ===");
        console.log("Endpoint: %s", lzEndpoint);

        // Build the trusted remote (srcAddress) - V1 format: sender + receiver concatenated
        bytes memory trustedRemote = abi.encodePacked(
            bytes20(uint160(json.readAddress(".data[0].pathway.sender.address"))),
            bytes20(uint160(receiver))
        );
        console.log("Trusted Remote (srcAddress):");
        console.logBytes(trustedRemote);

        // Check if payload is stored
        ILayerZeroEndpointV1 endpoint = ILayerZeroEndpointV1(lzEndpoint);
        bool hasStored = endpoint.hasStoredPayload(srcChainId, trustedRemote);
        console.log("");
        console.log("=== STORED PAYLOAD CHECK ===");
        console.log("Has stored payload: %s", hasStored ? "YES" : "NO");

        if (hasStored) {
            (uint64 storedLength, address dstAddress) = endpoint.storedPayload(srcChainId, trustedRemote);
            console.log("Stored payload length: %s", vm.toString(storedLength));
            console.log("Destination address: %s", dstAddress);
        }

        // Decode payload for debugging
        // V1 OFT payload formats:
        // - Standard: bytes32 toAddress (32) + uint64 amountSD (8) = 40 bytes
        // - With packet type: uint8 packetType (1) + bytes32 toAddress (32) + uint64 amountSD (8) = 41 bytes
        if (payload.length >= 40) {
            address toAddress;
            uint64 amountSD;
            
            console.log("");
            console.log("=== PAYLOAD DECODE (V1 OFT) ===");
            
            if (payload.length == 41) {
                // Format with packet type prefix
                uint8 packetType = uint8(payload[0]);
                console.log("Packet Type: %s", vm.toString(packetType));
                
                // Read bytes 1-32 as recipient, bytes 33-40 as amount
                bytes32 toAddressBytes32;
                assembly {
                    // Skip length (32 bytes) + packet type (1 byte) = start at 0x21
                    toAddressBytes32 := mload(add(payload, 0x21))
                }
                toAddress = address(uint160(uint256(toAddressBytes32)));
                
                // Read amount from bytes 33-40
                for (uint i = 0; i < 8; i++) {
                    amountSD = amountSD << 8 | uint64(uint8(payload[33 + i]));
                }
            } else {
                // Standard 40-byte format
                bytes32 toAddressBytes32;
                assembly {
                    toAddressBytes32 := mload(add(payload, 0x20))
                }
                toAddress = address(uint160(uint256(toAddressBytes32)));
                
                // Read amount from bytes 32-39
                for (uint i = 0; i < 8; i++) {
                    amountSD = amountSD << 8 | uint64(uint8(payload[32 + i]));
                }
            }
            
            console.log("Recipient: %s", toAddress);
            console.log("Amount (shared decimals): %s", vm.toString(uint256(amountSD)));
            
            // Calculate local decimals amount (assuming 1e10 conversion rate for 18->8 decimals)
            uint256 amountLD = uint256(amountSD) * 1e10;
            console.log("Amount (local decimals, assuming 1e10 rate): %s", vm.toString(amountLD));
        }

        // Get token info if available
        address tokenAddress = address(0);
        address recipientAddress = _decodeRecipient(payload);
        
        try IOFTV1(receiver).token() returns (address token) {
            tokenAddress = token;
            console.log("");
            console.log("=== TOKEN INFO ===");
            console.log("Token address: %s", tokenAddress);
            
            if (recipientAddress != address(0)) {
                try IERC20(tokenAddress).balanceOf(recipientAddress) returns (uint256 balance) {
                    console.log("Recipient balance before: %s", vm.toString(balance));
                } catch {}
            }
        } catch {}

        // Check if this is actually a stored payload that needs retry
        if (!hasStored) {
            console.log("");
            console.log("=== NO STORED PAYLOAD ===");
            console.log("This message does not have a stored payload to retry.");
            console.log("It may have already been delivered or is still pending.");
            return;
        }

        // Gas estimation note
        console.log("");
        console.log("=== GAS ESTIMATION ===");
        console.log("Recommended gas for retryPayload: 400,000+");
        console.log("(Use --gas-estimate-multiplier 200 when broadcasting)");

        // Execute retryPayload
        console.log("");
        console.log("=== EXECUTING RETRY ===");
        
        vm.startBroadcast();
        
        bool success = _executeRetry(endpoint, srcChainId, trustedRemote, payload);
        
        vm.stopBroadcast();

        // Check result
        if (success && tokenAddress != address(0) && recipientAddress != address(0)) {
            try IERC20(tokenAddress).balanceOf(recipientAddress) returns (uint256 balanceAfter) {
                console.log("Recipient balance after: %s", vm.toString(balanceAfter));
            } catch {}
        }

        // Verify payload is cleared
        bool stillStored = endpoint.hasStoredPayload(srcChainId, trustedRemote);
        console.log("");
        console.log("=== VERIFICATION ===");
        console.log("Payload still stored: %s", stillStored ? "YES (retry may have failed)" : "NO (success!)");
    }

    function _executeRetry(
        ILayerZeroEndpointV1 endpoint,
        uint16 srcChainId,
        bytes memory trustedRemote,
        bytes memory payload
    ) internal returns (bool success) {
        uint256 gasStart = gasleft();
        console.log("Gas available: %s", vm.toString(gasStart));
        
        try endpoint.retryPayload(srcChainId, trustedRemote, payload) {
            console.log("=== SUCCESS ===");
            console.log("retryPayload executed successfully!");
            success = true;
        } catch Error(string memory reason) {
            console.log("=== REVERT (string) ===");
            console.log("Reason: %s", reason);
        } catch Panic(uint errorCode) {
            console.log("=== PANIC ===");
            console.log("Panic code: %s", vm.toString(errorCode));
            _decodePanic(errorCode);
        } catch (bytes memory lowLevelData) {
            console.log("=== LOW LEVEL REVERT ===");
            console.log("Data length: %s", vm.toString(lowLevelData.length));
            if (lowLevelData.length > 0) {
                console.log("Raw data:");
                console.logBytes(lowLevelData);
                _tryDecodeError(lowLevelData);
            } else {
                console.log("Empty revert - possible causes:");
                console.log("  - require() without message");
                console.log("  - Out of gas");
                console.log("  - Invalid jump destination");
            }
        }
        
        uint256 gasEnd = gasleft();
        console.log("Gas used: %s", vm.toString(gasStart - gasEnd));
    }

    /// @notice Decode recipient address from V1 OFT payload
    function _decodeRecipient(bytes memory payload) internal pure returns (address) {
        if (payload.length < 40) return address(0);
        
        bytes32 toAddressBytes32;
        if (payload.length == 41) {
            // Format with packet type prefix - read from byte 1
            assembly {
                toAddressBytes32 := mload(add(payload, 0x21))
            }
        } else {
            // Standard format - read from byte 0
            assembly {
                toAddressBytes32 := mload(add(payload, 0x20))
            }
        }
        return address(uint160(uint256(toAddressBytes32)));
    }

    function _decodePanic(uint errorCode) internal pure {
        if (errorCode == 0x01) console.log("Panic: Assertion failed");
        else if (errorCode == 0x11) console.log("Panic: Arithmetic overflow/underflow");
        else if (errorCode == 0x12) console.log("Panic: Division by zero");
        else if (errorCode == 0x21) console.log("Panic: Invalid enum value");
        else if (errorCode == 0x22) console.log("Panic: Invalid storage access");
        else if (errorCode == 0x31) console.log("Panic: Pop on empty array");
        else if (errorCode == 0x32) console.log("Panic: Array out of bounds");
        else if (errorCode == 0x41) console.log("Panic: Too much memory");
        else if (errorCode == 0x51) console.log("Panic: Zero-init function pointer");
        else console.log("Panic: Unknown code");
    }

    function _tryDecodeError(bytes memory data) internal pure {
        if (data.length >= 4) {
            bytes4 selector;
            assembly {
                selector := mload(add(data, 32))
            }
            // Check for Error(string)
            if (selector == 0x08c379a0 && data.length >= 68) {
                assembly {
                    let len := mload(add(data, 68))
                    let str := add(data, 100)
                }
                // Can't easily decode in pure function, but selector match helps
                console.log("Error selector: Error(string)");
            }
        }
    }
}
