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

interface IOFTCoreLike {
    function decimalConversionRate() external view returns (uint256);
}

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
        if (startsWith(senderChain, "solana")) {
            // If the chain is Solana, decode the Base58 address
            bytes memory decodedAddress = senderAddressStr.base58ToHex();

            // Ensure the decoded address is 32 bytes long
            require(decodedAddress.length == 32, "Decoded address must be 32 bytes");
            senderBytes32 = bytes32(decodedAddress);
        } else if (startsWith(senderChain, "aptos")) {
            // Aptos/Move: Direct hex to bytes32 conversion (64 hex chars -> 32 bytes)
            senderBytes32 = hexStringToBytes32(senderAddressStr);
        } else {
            // EVM chains: Use parseJsonAddress for 20-byte addresses
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
        console.log("=== EXECUTION DETAILS ===");
        console.log("Source EID:", srcEid);
        console.log("Nonce being executed:", nonce);
        console.logBytes32(senderBytes32);

        // Construct the Origin struct
        Origin memory origin = Origin({
            srcEid: srcEid,
            sender: senderBytes32, // Use the bytes32 sender
            nonce: nonce
        });
        bytes memory extraData = "";

        // === ENHANCED ERROR HANDLING AND DEBUGGING ===
        // Decode OFT payload: [bytes32 to][uint64 amountSD][optional compose...]
        address recipient;
        uint64 amountSD;
        uint256 amountLD;
        if (payload.length >= 40) {
            bytes32 sendToB32;
            assembly {
                sendToB32 := mload(add(payload, 0x20))
                let word := mload(add(payload, 0x40))
                amountSD := shr(192, word)
            }
            recipient = address(uint160(uint256(sendToB32)));
            uint256 dcr;
            // try to read decimalConversionRate from the adapter; default to 1 if not available
            try IOFTCoreLike(receiver).decimalConversionRate() returns (uint256 rate) {
                dcr = rate;
            } catch {
                dcr = 1;
            }
            amountLD = uint256(amountSD) * dcr;
        }
        console.log("=== DEBUGGING INFO ===");
        console.log("Payload length:", payload.length);
        console.log("Recipient (decoded):", recipient);
        console.log("AmountSD (uint64):", uint256(amountSD));
        console.log("AmountLD (uint256):", amountLD);
        if (receiver != address(0)) {
            console.log("Adapter native balance (wei):", receiver.balance);
            if (amountLD > 0 && receiver.balance < amountLD) {
                console.log("WARNING: Adapter lacks native to credit amountLD. Expect revert.");
            }
        }

        // Peer check
        try IOAppCore(receiver).peers(srcEid) returns (bytes32 configuredPeer) {
            console.log("Configured peer:");
            console.logBytes32(configuredPeer);
            console.log("Sender from API:");
            console.logBytes32(senderBytes32);
            if (configuredPeer != senderBytes32) {
                console.log("WARNING: Configured peer mismatch; OnlyPeer would revert.");
            }
        } catch {}

        // Determine token address (NativeOFTAdapter returns address(0))
        address tokenAddress = getTokenAddressInternal(receiver);
        if (tokenAddress != address(0)) {
            console.log("Token address:", tokenAddress);
        } else {
            console.log("Adapter is native (token() == address(0))");
        }

        // Check recipient balance before
        uint256 balanceBefore;
        if (recipient != address(0)) {
            if (tokenAddress != address(0)) {
                try IERC20(tokenAddress).balanceOf(recipient) returns (uint256 balanceErc20) {
                    balanceBefore = balanceErc20;
                    console.log("Recipient token balance before:", balanceBefore);
                } catch {
                    console.log("Could not check ERC20 balance before");
                }
            } else {
                balanceBefore = recipient.balance;
                console.log("Recipient native balance before (wei):", balanceBefore);
            }
        }

        // Simulate the lzReceive function with enhanced error handling
        vm.startBroadcast();
        bool ok = _executeLzReceive(receiver, origin, guid, payload, extraData);
        vm.stopBroadcast();

        if (ok && recipient != address(0)) {
            if (tokenAddress != address(0)) {
                try IERC20(tokenAddress).balanceOf(recipient) returns (uint256 balanceAfterErc20) {
                    console.log("Recipient token balance after:", balanceAfterErc20);
                    console.log("Tokens minted/credited:", balanceAfterErc20 - balanceBefore);
                } catch {
                    console.log("Could not check ERC20 balance after");
                }
            } else {
                uint256 balanceAfterNative = recipient.balance;
                console.log("Recipient native balance after (wei):", balanceAfterNative);
                console.log("Native credited (wei):", balanceAfterNative - balanceBefore);
            }
        }
    }

    function _executeLzReceive(
        address receiver,
        Origin memory origin,
        bytes32 guid,
        bytes memory payload,
        bytes memory extraData
    ) internal returns (bool ok) {
        uint256 gasStart = gasleft();
        console.log("Gas available at start:", gasStart);
        try IOAppCore(receiver).endpoint().lzReceive(origin, receiver, guid, payload, extraData) {
            console.log("=== SUCCESS ===");
            ok = true;
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
        uint256 gasEnd = gasleft();
        console.log("Gas used:", gasStart - gasEnd);
    }

    // Helper function to convert address to bytes32
    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    // Helper function to check if a string starts with a prefix
    function startsWith(string memory str, string memory prefix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);
        
        if (strBytes.length < prefixBytes.length) {
            return false;
        }
        
        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) {
                return false;
            }
        }
        
        return true;
    }

    // Helper function to get token address from OFT adapter
    function getTokenAddressInternal(address oftAdapter) internal view returns (address) {
        // Try different possible function signatures for getting token address
        (bool success, bytes memory data) = oftAdapter.staticcall(abi.encodeWithSignature("token()"));
        if (success && data.length >= 32) {
            return abi.decode(data, (address));
        }
        
        // Fallback: try innerToken() for MintBurnOFTAdapter
        (success, data) = oftAdapter.staticcall(abi.encodeWithSignature("innerToken()"));
        if (success && data.length >= 32) {
            return abi.decode(data, (address));
        }
        
        return address(0);
    }

    // Helper function to convert hex string to bytes32 for Aptos addresses
    function hexStringToBytes32(string memory hexStr) internal pure returns (bytes32) {
        bytes memory hexBytes = bytes(hexStr);
        require(hexBytes.length == 66, "Hex string must be 66 characters (0x + 64 hex chars)");
        require(hexBytes[0] == '0' && hexBytes[1] == 'x', "Hex string must start with 0x");
        
        bytes32 result;
        assembly {
            result := mload(add(hexBytes, 34)) // Skip length (32) + "0x" (2) = 34
        }
        return result;
    }
}