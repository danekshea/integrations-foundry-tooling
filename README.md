## Usage

```shell
yarn
forge build
```

1. Obtain not delivered cross chain source transaction hash
2. Go to Scan API URL: mainnet: https://scan.layerzero-api.com/v1/messages/tx/YOUR_SOURCE_TX_HASH ; testnet: https://scan-testnet.layerzero-api.com/v1/messages/tx/YOUR_SOURCE_TX_HASH
3. Copy whole JSON response of that API and replace content of [data/scanApiResponse.json](./data/scanApiResponse.json) file.
4. Run: `forge script script/SimulateReceive.s.sol --rpc-url YOUR_DESTINATION_CHAIN_RPC_URL`

Remember to replace `YOUR_SOURCE_TX_HASH` and `YOUR_DESTINATION_CHAIN_RPC_URL` with correct values.

If you get an error from SimulateReceive script eg. `script failed: custom error 7182306f` you can do:

```
cast 4byte 7182306f
```

Example result:
```
LZ_PayloadHashNotFound(bytes32,bytes32)
```