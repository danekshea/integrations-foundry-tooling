// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import {Base58Decoder} from "../src/Base58Decoder.sol"; // Import the new library

import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { SendParam, OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { ILayerZeroEndpointV2, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimulateReceive is Script {
    using stdJson for string;
    using Base58Decoder for string; // Use the library

       function run() public {
        // -- New mainnet/testnet toggle added here --
        bool mainnet = vm.envBool("MAINNET"); // Set to false for testnet
        string memory sourceChainTXHash = vm.envString("SOURCE_CHAIN_TX_HASH");

        string memory apiUrl = string(abi.encodePacked(
            mainnet ?
            "https://scan.layerzero-api.com" :    // Mainnet
            "https://scan-testnet.layerzero-api.com", // Testnet
            "/v1/messages/tx/",
            sourceChainTXHash
        ));

        console.log("Fetching LayerZero message details...");
        console.log(" => TX Hash: %s", sourceChainTXHash);
        console.log(" => API Endpoint: %s", apiUrl);

        string[] memory curlCommand = new string[](7);
        curlCommand[0] = "curl";
        curlCommand[1] = "-s"; // Suppress progress meter.
        curlCommand[2] = "-X";
        curlCommand[3] = "GET";
        curlCommand[4] = apiUrl;
        curlCommand[5] = "-H";
        curlCommand[6] = "accept: application/json";

        bytes memory res = vm.ffi(curlCommand);

        // Convert the result to a string
        string memory json = string(res);

        // Read the sender chain
        string memory senderChain = json.readString(".data[0].pathway.sender.chain");

        // Read the destination chain
        string memory destinationChain = json.readString(".data[0].pathway.receiver.chain");

        // Read the sender address
        bytes32 senderBytes32;
        string memory senderAddressStr = json.readString(".data[0].pathway.sender.address");
        if (keccak256(bytes(senderChain)) == keccak256(bytes("solana"))) {
            // If the chain is Solana, decode the Base58 address
            bytes memory decodedAddress = senderAddressStr.base58ToHex();

            // Ensure the decoded address is 32 bytes long
            require(decodedAddress.length == 32, "Decoded address must be 32 bytes");
            senderBytes32 = bytes32(decodedAddress);
        } else {
            // Otherwise, read the address directly and convert to bytes32
            address senderAddress = json.readAddress(".data[0].pathway.sender.address");
            senderBytes32 = addressToBytes32(senderAddress);
        }
        console.log("Sender: %s (%s)", senderAddressStr, senderChain);

        // Read the receiver address
        address receiver = json.readAddress(".data[0].pathway.receiver.address");
        console.log("Receiver: %s (%s)", receiver, destinationChain);

        // Read the nonce
        uint64 nonce = uint64(json.readUint(".data[0].pathway.nonce"));
        console.log("Nonce:", nonce);

        // Read the transaction hash
        string memory fetchedTxHash = json.readString(".data[0].source.tx.txHash");
        console.log("Source Transaction Hash:", fetchedTxHash);

        // Read other fields from the JSON
        uint32 srcEid = uint32(json.readUint(".data[0].pathway.srcEid"));
        bytes32 guid = json.readBytes32(".data[0].guid");
        bytes memory payload = json.readBytes(".data[0].source.tx.payload");

        console.log("Invoking lzReceive...");

        // Construct the Origin struct
        Origin memory origin = Origin({
            srcEid: srcEid,
            sender: senderBytes32, // Use the bytes32 sender
            nonce: nonce
        });
        bytes memory extraData = "";

        // === ENHANCED ERROR HANDLING AND DEBUGGING ===
        
        // Extract recipient and amount from payload for debugging
        address recipient;
        uint256 amount;
        if (payload.length >= 64) {
            assembly {
                recipient := mload(add(payload, 32))
                amount := mload(add(payload, 64))
            }
        }
        console.log("=== DEBUGGING INFO ===");
        console.log("Recipient from payload:", recipient);
        console.log("Amount from payload:", amount);
        
        // Get token address from the OFT adapter
        address tokenAddress;
        try IOAppCore(receiver).token() returns (address token) {
            tokenAddress = token;
            console.log("Token address:", tokenAddress);
        } catch {
            console.log("Could not get token address");
        }
        
        // Check recipient balance before
        uint256 balanceBefore;
        if (tokenAddress != address(0) && recipient != address(0)) {
            try IERC20(tokenAddress).balanceOf(recipient) returns (uint256 balance) {
                balanceBefore = balance;
                console.log("Recipient balance before:", balanceBefore);
            } catch {
                console.log("Could not check balance before");
            }
        }

        // Simulate the lzReceive function with enhanced error handling
        vm.startBroadcast();
        
        uint256 gasStart = gasleft();
        console.log("Gas available at start:", gasStart);
        
        try IOAppCore(receiver).endpoint().lzReceive(origin, receiver, guid, payload, extraData) {
            console.log("=== SUCCESS ===");
            
            // Check balance after success
            if (tokenAddress != address(0) && recipient != address(0)) {
                try IERC20(tokenAddress).balanceOf(recipient) returns (uint256 balanceAfter) {
                    console.log("Recipient balance after:", balanceAfter);
                    console.log("Tokens minted:", balanceAfter - balanceBefore);
                } catch {
                    console.log("Could not check balance after");
                }
            }
            
        } catch Error(string memory reason) {
            console.log("=== STRING REVERT ===");
            console.log("Revert reason:", reason);
            
        } catch Panic(uint errorCode) {
            console.log("=== PANIC ERROR ===");
            console.log("Panic code:", errorCode);
            
            // Decode common panic codes
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
                
                // Try to decode as string
                if (lowLevelData.length >= 68) {
                    // Check if it starts with Error(string) selector (0x08c379a0)
                    bytes4 selector;
                    assembly {
                        selector := mload(add(lowLevelData, 32))
                    }
                    if (selector == 0x08c379a0) {
                        // Decode the string
                        string memory errorMessage = abi.decode(lowLevelData[4:], (string));
                        console.log("Decoded error message:", errorMessage);
                    }
                }
            }
        }
        
        uint256 gasEnd = gasleft();
        console.log("Gas used:", gasStart - gasEnd);
        
        vm.stopBroadcast();
    }

    // Helper function to convert address to bytes32
    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}