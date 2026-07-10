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
| `make simulate-solana`         | Simulate lzReceive on a **Solana** destination |
| `make broadcast-solana`        | Broadcast lzReceive on a **Solana** destination |

### Solana destinations

When the message's destination is Solana (EID 30168/40168), the EVM forge scripts don't apply — use the `-solana` targets instead. They fetch every parameter from LayerZero Scan via `SOURCE_CHAIN_TX_HASH` (same as the EVM flow) and self-execute `lzReceive` on Solana, so you deliver a stuck message by acting as the executor yourself.

This is the fix for messages that fail with `InsufficientBalance (6014 / 0x177e)` in the executor's PostExecute — i.e. the source send used `value: 0` and the executor couldn't cover the recipient's Associated Token Account (ATA) rent. You cannot change the options on an already-sent packet, but `lzReceive` on Solana is permissionless, so you fund the ~0.0025 SOL of ATA rent + fees yourself.

Extra `.env` for Solana (see [.env.example](.env.example)):

- `SOLANA_KEYPAIR` — fee-payer keypair (defaults to `~/.config/solana/id.json`). This is **not** the `CAST_ACCOUNT` keystore used by the EVM targets.
- `SOLANA_RPC_URL` — defaults to the public endpoint for the selected `MAINNET`; use a private RPC for reliability.
- `SOLANA_VALUE_LAMPORTS` — optional override; defaults to the source option value, floored to 2,500,000 lamports to cover ATA creation.
- `SOLANA_COMPUTE_UNITS` — optional CU limit (default 200000).

Always run `make simulate-solana` first — it runs an on-chain `simulateTransaction` and prints the program logs. If the message was already delivered it surfaces `AccountNotInitialized (3012 / 0xbc4)` on `payload_hash`, so you don't waste a broadcast.

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
