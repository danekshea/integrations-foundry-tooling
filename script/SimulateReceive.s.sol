// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { SendParam, OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

import { ILayerZeroEndpointV2, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract SimulateReceive is Script {
    using stdJson for string;

    function run() public {
        string memory json = vm.readFile("./data/scanApiResponse.json");
        uint32 srcEid = uint32(json.readUint(".data[0].pathway.srcEid"));
        address senderAddress = json.readAddress(".data[0].pathway.sender.address");
        uint64 nonce = uint64(json.readUint(".data[0].pathway.nonce"));
        bytes32 sender = addressToBytes32(senderAddress);
        address receiver = json.readAddress(".data[0].pathway.receiver.address");
        bytes32 guid = json.readBytes32(".data[0].guid");
        bytes memory payload = json.readBytes(".data[0].source.tx.payload");

        Origin memory origin = Origin({
            srcEid: srcEid,
            sender: sender,
            nonce: nonce
        });
        bytes memory extraData = "";

        IOAppCore(receiver).endpoint().lzReceive(origin, receiver, guid, payload, extraData);
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}