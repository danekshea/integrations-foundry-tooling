## Usage

```shell
cp .env.example .env
pnpm install
forge build
```

1. Find the source transaction hash of the message that has failed on [LayerZero Scan](https://layerzeroscan.com)
2. Populate the [.env](.env.example) file with the following:
   - `SOURCE_CHAIN_TX_HASH=<your_source_tx_hash>`
   - `MAINNET=true` or `MAINNET=false` (for the scan API)
   - `DESTINATION_CHAIN_RPC_URL=<your_rpc_url>` (can use shortcuts from [foundry.toml](foundry.toml), e.g. `eth`, `bnb`)
   - `CAST_ACCOUNT=<your_cast_account>` (use `cast wallet import -i <ACCOUNT_NAME>` to import a private key)
   - `KEYSTORE_PASSWORD=<your_password>` (optional, skips the keystore prompt for unattended runs; leave unset for the interactive prompt). Note: the value is passed to the shell unquoted via `${KEYSTORE_PASSWORD+--password=$KEYSTORE_PASSWORD}`, so passwords containing spaces, `$`, or other shell-special characters will be mangled by word splitting — for those, use the interactive prompt or wrap your make invocation (e.g. `KEYSTORE_PASSWORD=$(op read ...) make broadcast-v2`) so the password never lives in `.env`.
   - `COMPOSE_VALUE_BUFFER_PERCENT=50` (optional, buffer % added to compose value for gas fluctuations, default: 50)

3. Run the appropriate command:

| Command                        | Description                              |
| ------------------------------ | ---------------------------------------- |
| `make simulate-v2`             | Simulate lzReceive execution             |
| `make broadcast-v2`            | Broadcast lzReceive transaction           |
| `make simulate-v2-zksync`      | Simulate lzReceive execution (zkSync)    |
| `make broadcast-v2-zksync`     | Broadcast lzReceive transaction (zkSync) |
| `make simulate-v2-compose`     | Simulate lzCompose execution             |
| `make broadcast-v2-compose`    | Broadcast lzCompose transaction           |
| `make simulate-v2-compose-zksync`  | Simulate lzCompose execution (zkSync)    |
| `make broadcast-v2-compose-zksync` | Broadcast lzCompose transaction (zkSync) |
| `make simulate-v2-commit`      | Simulate commitVerification execution    |
| `make broadcast-v2-commit`     | Broadcast commitVerification transaction |
| `make simulate-v2-commit-zksync`   | Simulate commitVerification execution (zkSync)    |
| `make broadcast-v2-commit-zksync`  | Broadcast commitVerification transaction (zkSync) |

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
