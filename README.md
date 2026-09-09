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
| `make simulate-starknet`       | Simulate lzReceive on a **Starknet** destination |
| `make broadcast-starknet`      | Broadcast lzReceive on a **Starknet** destination |

### Solana destinations

When the message's destination is Solana (EID 30168/40168), the EVM forge scripts don't apply — use the `-solana` targets instead. They fetch every parameter from LayerZero Scan via `SOURCE_CHAIN_TX_HASH` (same as the EVM flow) and self-execute `lzReceive` on Solana, so you deliver a stuck message by acting as the executor yourself.

This is the fix for messages that fail with `InsufficientBalance (6014 / 0x177e)` in the executor's PostExecute — i.e. the source send used `value: 0` and the executor couldn't cover the recipient's Associated Token Account (ATA) rent. You cannot change the options on an already-sent packet, but `lzReceive` on Solana is permissionless, so you fund the ~0.0025 SOL of ATA rent + fees yourself.

Extra `.env` for Solana (see [.env.example](.env.example)):

- `SOLANA_KEYPAIR` — fee-payer keypair (defaults to `~/.config/solana/id.json`). This is **not** the `CAST_ACCOUNT` keystore used by the EVM targets.
- `SOLANA_RPC_URL` — defaults to the public endpoint for the selected `MAINNET`; use a private RPC for reliability.
- `SOLANA_VALUE_LAMPORTS` — optional override; defaults to the source option value, floored to 2,500,000 lamports to cover ATA creation.
- `SOLANA_COMPUTE_UNITS` — optional CU limit (default 200000).

Always run `make simulate-solana` first — it runs an on-chain `simulateTransaction` and prints the program logs. If the message was already delivered it surfaces `AccountNotInitialized (3012 / 0xbc4)` on `payload_hash`, so you don't waste a broadcast.

### Starknet destinations

When the message's destination is Starknet (EID 30500/40500), neither the EVM forge scripts nor `cast` apply — Starknet is a Cairo VM chain with its own RPC, felt252 calldata encoding and account abstraction. Use the `-starknet` targets instead. Like the Solana ones they read every parameter from LayerZero Scan via `SOURCE_CHAIN_TX_HASH`; [`script/lzReceiveStarknet.ts`](script/lzReceiveStarknet.ts) does the Cairo calldata serialization and shells out to [`sncast`](https://foundry-rs.github.io/starknet-foundry/) (Starknet Foundry) for account signing and fee estimation.

`lz_receive` on the Starknet EndpointV2 is permissionless — whoever calls it becomes the `executor` passed to the OApp — so you can deliver a verified-but-unexecuted message yourself, paying the STRK fee from your own account.

**Prerequisites.** Install Starknet Foundry, then import the account you want to sign with:

```bash
# Release binary, no shell-profile changes (starkup also works, but it installs asdf
# and appends to ~/.zshrc, which is a symlink into the dotfiles repo):
V=v0.63.0
curl -sL "https://github.com/foundry-rs/starknet-foundry/releases/download/$V/starknet-foundry-$V-aarch64-apple-darwin.tar.gz" \
  | tar xz -C /tmp
install -m 755 /tmp/starknet-foundry-$V-aarch64-apple-darwin/bin/{sncast,snforge} ~/.local/bin/

# Already have a deployed Starknet account (Argent/Braavos)? Just import it:
sncast account import --name burner --address <ADDRESS> --type argent --private-key <KEY>
```

**The `burner` account.** Starknet cannot reuse your EVM `CAST_ACCOUNT` directly: it signs on the STARK curve (order ≈2^251.6) rather than secp256k1, and addresses derive from `hash(class_hash, constructor_calldata, salt)` rather than from the pubkey — so the address differs even with identical key material.

What it *can* share is the keystore. Foundry and starkli both use the same v3 `eth-keystore` format (aes-128-ctr + scrypt), and `sncast --keystore` accepts a cast-created keystore, reading its password from the same `KEYSTORE_PASSWORD` this repo already uses for the EVM targets. So the Starknet key lives encrypted in `~/.foundry/keystores/` next to your EVM ones — not in plaintext in sncast's default accounts file.

The Starknet key is *derived* from the EVM burner, so there is one secret to back up and the key is always recoverable from `burner`:

```bash
# 1. secp256k1 key -> reduce mod the STARK curve order -> Starknet private key
#    (zero-pad to 32 bytes; the reduction can drop a leading nibble)
EVM_KEY=$(cast wallet decrypt-keystore burner --unsafe-password "$KEYSTORE_PASSWORD" \
  | grep -oE '0x[0-9a-fA-F]{64}')
STARK_KEY=$(python3 -c "print('0x%064x' % ($EVM_KEY % 3618502788666131213697322783095070105526743751716087489154079457884512865583))")

# 2. Create the Starknet account, then store the key in the cast keystore
sncast account create --name burner --type oz --private-key "$STARK_KEY" \
  --url https://api.cartridge.gg/x/starknet/mainnet
cast wallet import starknet-burner --private-key "$STARK_KEY" --unsafe-password "$KEYSTORE_PASSWORD"
```

A newly created account is *counterfactual* — the contract does not exist on-chain until deployed, and `sncast` fails with `Account with address 0x… not found on network SN_MAIN` until then. Prefund the printed address with STRK (deployment alone was ~0.067 STRK, a delivery ~0.46 STRK), then:

```bash
sncast account deploy --name burner --url https://api.cartridge.gg/x/starknet/mainnet
```

Finally, switch to keystore mode and delete sncast's plaintext accounts file. `--keystore` needs a starkli-format account descriptor (address, class hash, public key — no secret), which you can write from the values `account create` saved:

```bash
cat > ~/.starknet_accounts/burner.account.json <<'JSON'
{
  "version": 1,
  "variant": { "type": "open_zeppelin", "version": 1, "public_key": "0x<PUBLIC_KEY>", "legacy": false },
  "deployment": { "status": "deployed", "class_hash": "0x<CLASS_HASH>", "address": "0x<ADDRESS>" }
}
JSON
chmod 600 ~/.starknet_accounts/burner.account.json
rm ~/.starknet_accounts/starknet_open_zeppelin_accounts.json   # drops the plaintext key
```

Then point `.env` at both:

```
STARKNET_KEYSTORE=$HOME/.foundry/keystores/starknet-burner
STARKNET_ACCOUNT=$HOME/.starknet_accounts/burner.account.json
```

Note that a leak of either key compromises both, since one is derived from the other. Fine for a burner; do not do this for a funded account.

Extra `.env` for Starknet (see [.env.example](.env.example)):

- `STARKNET_ACCOUNT` — the `sncast` account name from `account import`. Omit to use sncast's default. This is **not** the `CAST_ACCOUNT` keystore used by the EVM targets.
- `STARKNET_ACCOUNTS_FILE` / `STARKNET_KEYSTORE` — optional, for a non-default accounts file or a starkli keystore.
- `STARKNET_RPC_URL` — defaults to the public Cartridge endpoint for the selected `MAINNET`; use a private RPC for reliability.
- `STARKNET_ENDPOINT` — optional override; by default the EndpointV2 address is resolved from the LayerZero metadata API.
- `STARKNET_VALUE` — optional override of the `value` (in wei) forwarded to the OApp; defaults to the source option value.
- `STARKNET_FORCE` — proceed even when the pre-flight reports a non-`Executable` state.

Always run `make simulate-starknet` first. It calls `endpoint.executable(origin, receiver)` and refuses to proceed unless the state is `Executable`, which catches the common cases cheaply:

| `ExecutionState` | Meaning |
| --- | --- |
| `NotExecutable` | Not verified/committed yet — commit verification first. |
| `VerifiedButNotExecutable` | Verified, but an earlier nonce is still pending (ordered delivery). |
| `Executable` | Ready to deliver — this is what you want. |
| `Executed` | Already delivered; nothing to do. |

It then runs `sncast invoke --dry-run` to estimate the fee without sending anything.

One Starknet-specific wrinkle: the endpoint moves `value` with `native_token.transfer_from(executor, receiver, value)`, so a non-zero `value` needs an STRK allowance from your account to the endpoint. `make broadcast-starknet` sends that `approve` for you before the `lz_receive`. When `value` is 0 (the common case for a plain OFT transfer) no approval is needed.

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
