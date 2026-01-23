## Usage

```shell
cp .env.example .env
yarn
forge build
```

1. Find the source transaction hash of the message that has failed on [LayerZero Scan](https://layerzeroscan.com)
2. Populate the [.env](.env.example) file with the following:

   - `SOURCE_CHAIN_TX_HASH=<your_source_tx_hash>`
   - `MAINNET=true` or `MAINNET=false` (for the scan API)
   - `DESTINATION_CHAIN_RPC_URL=<your_rpc_url>` (can use shortcuts from [foundry.toml](foundry.toml), e.g. `eth`, `bnb`)
   - `CAST_ACCOUNT=<your_cast_account>` (use `cast wallet import -i <ACCOUNT_NAME>` to import a private key)

3. Run the appropriate command:

| Command                  | Description                     |
| ------------------------ | ------------------------------- |
| `make simulate`          | Simulate lzReceive execution    |
| `make broadcast`         | Broadcast lzReceive transaction |
| `make simulate-compose`  | Simulate lzCompose execution    |
| `make broadcast-compose` | Broadcast lzCompose transaction |

Alternatively, edit the [Makefile](Makefile) to use `--private-key <PRIVATE_KEY>` instead of `--account`.

## Troubleshooting

If you get a custom error like `script failed: custom error 7182306f`, decode it with:

```
cast 4byte 7182306f
```

Example result:

```
LZ_PayloadHashNotFound(bytes32,bytes32)
```
