// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";

interface IEndpointV2Compose {
    function lzCompose(
        address _from,
        address _to,
        bytes32 _guid,
        uint16 _index,
        bytes calldata _message,
        bytes calldata _extraData
    ) external payable;
}

contract SimulateCompose is Script {
    function run() external {
        // --- inline params (edit these!) ---
        address endpoint = 0x1a44076050125825900e736c501f859c50fE728c; // EndpointV2 (Ethereum mainnet)
        address from     = 0xc026395860Db2d07ee33e05fE50ed7bD583189C7; // Stargate Pool (from ComposeSent event)
        address to       = 0x3D838AEF542A94A31f2FC490a9F9D73EAc91Db4A; // new composer
        bytes32 guid     = 0xdf5ba5a23c4f6a59dcc63b1f9f186cb8505ab0d54762cca66f5be95ded9f864e;
        uint16 index     = 0;
        // Compose message from ComposeSent event (nonce + srcEid + amountLD + composeMsg)
        bytes memory message   = hex"000000000001c502000075e800000000000000000000000000000000000000000000000000000000000f41db0000000000000000000000003d96edbea3c8ab7469bdbcd243bd5c5ca9976ed40000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000010367bb5ca8500000000000000000000000000000000000000000000000000000000000075e80000000000000000000000003d96edbea3c8ab7469bdbcd243bd5c5ca9976ed40000000000000000000000000000000000000000000000000da2841d4b4142ab0000000000000000000000000000000000000000000000000d911040fccc744100000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000016000301001101000000000000000000000000000186a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory extraData = hex"";
        uint256 valueWei       = 25000000000000; // ~0.000025 ETH (increased for gas price fluctuation)

        console.log("Endpoint:", endpoint);
        console.log("From:", from);
        console.log("To:", to);
        console.logBytes32(guid);
        console.log("Index:", index);

        vm.startBroadcast();
        IEndpointV2Compose(endpoint).lzCompose{value: valueWei}(
            from,
            to,
            guid,
            index,
            message,
            extraData
        );
        vm.stopBroadcast();

        console.log("lzCompose sent.");
    }
}
