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
        // Read the JSON file
        string memory json = vm.readFile("./data/scanApiResponse.json");

        // Read the sender chain
        string memory senderChain = json.readString(".data[0].pathway.sender.chain");

        // Read the sender address
        bytes32 senderBytes32;
        if (keccak256(bytes(senderChain)) == keccak256(bytes("solana"))) {
            // If the chain is Solana, decode the Base58 address
            string memory base58Address = json.readString(".data[0].pathway.sender.address");
            bytes memory decodedAddress = base58Address.base58ToHex();

            // Ensure the decoded address is 32 bytes long
            require(decodedAddress.length == 32, "Decoded address must be 32 bytes");
            senderBytes32 = bytes32(decodedAddress);
        } else {
            // Otherwise, read the address directly and convert to bytes32
            address senderAddress = json.readAddress(".data[0].pathway.sender.address");
            senderBytes32 = addressToBytes32(senderAddress);
        }

        // Read other fields from the JSON
        uint32 srcEid = uint32(json.readUint(".data[0].pathway.srcEid"));
        uint64 nonce = uint64(json.readUint(".data[0].pathway.nonce"));
        address receiver = json.readAddress(".data[0].pathway.receiver.address");
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