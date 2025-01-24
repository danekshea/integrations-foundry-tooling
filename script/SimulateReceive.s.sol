// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import {Base58Decoder} from "../src/Base58Decoder.sol"; // Import the new library

import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { SendParam, OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { ILayerZeroEndpointV2, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract SimulateReceive is Script {
    using stdJson for string;
    using Base58Decoder for string; // Use the library

    function run() public {
        // Define the transaction hash as a variable
        string memory txHash = "0x0c61c4db115f57b2fba78df78879f9e8230e67d75e78ac2782a3b4c929b5d12f";

        // Use Foundry's ffi to call curl and fetch the JSON data
        string[] memory curlCommand = new string[](5);
        curlCommand[0] = "curl";
        curlCommand[1] = "-X";
        curlCommand[2] = "GET";
        curlCommand[3] = string(abi.encodePacked("https://scan.layerzero-api.com/v1/messages/tx/", txHash));
        curlCommand[4] = "-H 'accept: application/json'";

        // Execute the curl command
        bytes memory result = vm.ffi(curlCommand);

        // Convert the result to a string
        string memory json = string(result);

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

        // Construct the Origin struct
        Origin memory origin = Origin({
            srcEid: srcEid,
            sender: senderBytes32, // Use the bytes32 sender
            nonce: nonce
        });
        bytes memory extraData = "";

        // Simulate the lzReceive function
        vm.startBroadcast();
        IOAppCore(receiver).endpoint().lzReceive(origin, receiver, guid, payload, extraData);
    }

    // Helper function to convert address to bytes32
    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}