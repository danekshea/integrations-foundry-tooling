/**
 * lzReceiveStarknet.ts — manually execute (deliver) a stuck LayerZero message whose
 * destination is Starknet, by acting as the executor yourself.
 *
 * This is the Starknet counterpart to the EVM `lzReceiveV2.s.sol` forge script and the
 * Solana `lzReceiveSolana.ts`. It is driven by the same `.env` convention: set
 * `SOURCE_CHAIN_TX_HASH` (+ `MAINNET`) and every other parameter (guid, message, sender,
 * receiver, nonce, srcEid, dstEid, option value) is fetched automatically from the
 * LayerZero Scan API.
 *
 * Why this exists: forge/cast cannot talk to Starknet — it is a Cairo VM chain with its
 * own RPC, calldata encoding (felt252 arrays) and account abstraction. So instead of a
 * forge script this shells out to `sncast` (Starknet Foundry), which handles account
 * signing and fee estimation, while this script does the Cairo calldata serialization.
 *
 * `lz_receive` on the Starknet EndpointV2 is permissionless — the caller becomes the
 * `executor` passed to the OApp — so you can deliver a verified-but-unexecuted message
 * yourself, paying the STRK fee out of your own account.
 *
 * Usage (via Makefile):
 *   make simulate-starknet    # dry-run: `sncast invoke --dry-run`, estimates fee, no tx
 *   make broadcast-starknet   # actually sign + submit, spends your STRK
 *
 * Env:
 *   SOURCE_CHAIN_TX_HASH     (required) source-chain tx hash of the stuck message
 *   MAINNET                  (default true) selects scan + default RPC network
 *   STARKNET_RPC_URL         (optional) defaults to a public endpoint for the network
 *   STARKNET_ACCOUNT         (optional) sncast account name (or path, with keystore)
 *   STARKNET_ACCOUNTS_FILE   (optional) path to the sncast accounts file
 *   STARKNET_KEYSTORE        (optional) keystore path; then STARKNET_ACCOUNT is a path to
 *                            the starkli account JSON. Foundry and starkli share the v3
 *                            eth-keystore format, so a `cast wallet import` keystore works
 *                            here and is unlocked by the same KEYSTORE_PASSWORD as the EVM
 *                            targets — preferred over sncast's plaintext accounts file.
 *   STARKNET_ENDPOINT        (optional) override the EndpointV2 address
 *   STARKNET_NATIVE_TOKEN    (optional) override the fee/value token (default STRK)
 *   STARKNET_VALUE           (optional) override the `value` (in wei) forwarded to the OApp
 *   STARKNET_FORCE           (optional) proceed even if ExecutionState is not Executable
 *   SIMULATE                 (set by `make simulate-starknet`) true => --dry-run only
 */
import { spawnSync } from 'child_process'

import 'dotenv/config'

const MAINNET = (process.env.MAINNET ?? 'true').toLowerCase() === 'true'
const SIMULATE = (process.env.SIMULATE ?? 'false').toLowerCase() === 'true'
const FORCE = (process.env.STARKNET_FORCE ?? 'false').toLowerCase() === 'true'

const SCAN_BASE = MAINNET ? 'https://scan.layerzero-api.com' : 'https://scan-testnet.layerzero-api.com'
const METADATA_URL = 'https://metadata.layerzero-api.com/v1/metadata'
const CHAIN_KEY = MAINNET ? 'starknet' : 'starknet-testnet'
const DEFAULT_RPC = MAINNET
    ? 'https://api.cartridge.gg/x/starknet/mainnet'
    : 'https://api.cartridge.gg/x/starknet/sepolia'
const STARKNET_EIDS = new Set([30500, 40500])

// STRK is the fee/native token on both Starknet mainnet and Sepolia, at the same address.
// The endpoint pulls `value` from the executor via `transfer_from`, so any non-zero value
// requires an allowance from your account to the endpoint first.
const STRK = '0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d'

const EXECUTION_STATES = ['NotExecutable', 'VerifiedButNotExecutable', 'Executable', 'Executed'] as const

interface ScanMessage {
    pathway: {
        srcEid: number
        dstEid: number
        sender: { address: string }
        receiver: { address: string }
        nonce: number
    }
    guid: string
    source: { tx: { payload: string; options?: { lzReceive?: { value?: string } } } }
}

async function fetchMessage(txHash: string): Promise<ScanMessage> {
    const url = `${SCAN_BASE}/v1/messages/tx/${txHash}`
    console.log(' => Scan API:', url)
    const res = await fetch(url, { headers: { accept: 'application/json' } })
    if (!res.ok) throw new Error(`Scan API returned ${res.status} for ${url}`)
    const body = (await res.json()) as { data?: ScanMessage[] }
    const message = body?.data?.[0]
    if (!message) throw new Error(`No LayerZero message found for tx ${txHash}`)
    return message
}

/** Resolve the Starknet EndpointV2 address from the LayerZero metadata API. */
async function fetchEndpoint(): Promise<string> {
    const res = await fetch(METADATA_URL, { headers: { accept: 'application/json' } })
    if (!res.ok) throw new Error(`Metadata API returned ${res.status}`)
    const body = (await res.json()) as Record<
        string,
        { deployments?: { version: number; endpointV2?: { address: string } }[] }
    >
    const address = body[CHAIN_KEY]?.deployments?.find((d) => d.version === 2)?.endpointV2?.address
    if (!address) throw new Error(`No EndpointV2 deployment found for chainKey ${CHAIN_KEY}`)
    return address
}

/** Left-pad an address (EVM 20-byte hex, or any <=32-byte hex) to a 32-byte hex string. */
function hexlify32(addr: string): string {
    const hex = addr.toLowerCase().replace(/^0x/, '')
    if (hex.length > 64) throw new Error(`address too long for bytes32: ${addr}`)
    return '0x' + hex.padStart(64, '0')
}

/** Serialize a u256 as the [low, high] felt pair Cairo expects. */
function u256(value: bigint): string[] {
    if (value < 0n) throw new Error(`u256 cannot be negative: ${value}`)
    const MASK = (1n << 128n) - 1n
    return ['0x' + (value & MASK).toString(16), '0x' + (value >> 128n).toString(16)]
}

/**
 * Serialize arbitrary bytes as a Cairo `core::byte_array::ByteArray`.
 *
 * A ByteArray is `{ data: Array<bytes31>, pending_word: felt252, pending_word_len: u32 }`,
 * which flattens into calldata as:
 *   [data.len(), ...data words..., pending_word, pending_word_len]
 * Bytes are packed big-endian, 31 to a word, with the remainder in `pending_word`.
 */
function byteArray(hex: string): string[] {
    const clean = hex.replace(/^0x/, '')
    if (clean.length % 2 !== 0) throw new Error(`byte string has odd length: ${hex}`)
    const bytes = Buffer.from(clean, 'hex')

    const fullWords = Math.floor(bytes.length / 31)
    const pendingLen = bytes.length % 31

    const felts = ['0x' + fullWords.toString(16)]
    for (let i = 0; i < fullWords; i++) {
        felts.push('0x' + bytes.subarray(i * 31, (i + 1) * 31).toString('hex'))
    }
    const pending = bytes.subarray(fullWords * 31)
    felts.push(pending.length > 0 ? '0x' + pending.toString('hex') : '0x0')
    felts.push('0x' + pendingLen.toString(16))
    return felts
}

/**
 * Global sncast flags (account selection). These must precede the subcommand; `--url` is
 * a subcommand-level flag and is appended separately by the callers below.
 */
function sncastGlobals(): string[] {
    const args: string[] = []
    if (process.env.STARKNET_KEYSTORE) args.push('--keystore', process.env.STARKNET_KEYSTORE)
    if (process.env.STARKNET_ACCOUNTS_FILE) args.push('--accounts-file', process.env.STARKNET_ACCOUNTS_FILE)
    if (process.env.STARKNET_ACCOUNT) args.push('--account', process.env.STARKNET_ACCOUNT)
    return args
}

function runSncast(args: string[]): string {
    console.log(' $ sncast', args.join(' '))
    const res = spawnSync('sncast', args, { encoding: 'utf-8', stdio: ['inherit', 'pipe', 'pipe'] })
    if (res.error) {
        const hint =
            (res.error as NodeJS.ErrnoException).code === 'ENOENT'
                ? '\nsncast not found on PATH. Install Starknet Foundry: ' +
                  'https://foundry-rs.github.io/starknet-foundry/getting-started/installation.html'
                : ''
        throw new Error(`${res.error.message}${hint}`)
    }
    const out = (res.stdout ?? '') + (res.stderr ?? '')
    process.stdout.write(out)
    if (res.status !== 0) throw new Error(`sncast exited with status ${res.status}`)
    return out
}

async function main(): Promise<void> {
    const txHash = process.env.SOURCE_CHAIN_TX_HASH
    if (!txHash) throw new Error('SOURCE_CHAIN_TX_HASH is required (set it in .env)')

    const d = await fetchMessage(txHash)
    const { srcEid, dstEid, nonce } = d.pathway
    if (!STARKNET_EIDS.has(dstEid)) {
        throw new Error(
            `Destination EID ${dstEid} is not Starknet (expected 30500/40500). ` +
                `For EVM destinations use the forge make targets (e.g. make broadcast-v2); ` +
                `for Solana use make broadcast-solana.`
        )
    }

    const sender = hexlify32(d.pathway.sender.address)
    const receiver = d.pathway.receiver.address
    const guid = d.guid
    const message = d.source.tx.payload
    const optionValue = BigInt(d.source.tx.options?.lzReceive?.value ?? '0')
    const value = process.env.STARKNET_VALUE ? BigInt(process.env.STARKNET_VALUE) : optionValue

    const rpc = process.env.STARKNET_RPC_URL ?? DEFAULT_RPC
    const endpoint = process.env.STARKNET_ENDPOINT ?? (await fetchEndpoint())
    const nativeToken = process.env.STARKNET_NATIVE_TOKEN ?? STRK

    console.log('--- LayerZero Starknet lzReceive ---')
    console.log('mode          :', SIMULATE ? 'SIMULATE (--dry-run)' : 'BROADCAST')
    console.log('source tx     :', txHash)
    console.log('srcEid        :', srcEid)
    console.log('dstEid        :', dstEid, '(Starknet)')
    console.log('sender        :', sender)
    console.log('receiver      :', receiver)
    console.log('nonce         :', nonce)
    console.log('guid          :', guid)
    console.log('message       :', message)
    console.log('option value  :', optionValue.toString(), 'wei (from source send)')
    console.log('value funded  :', value.toString(), 'wei', process.env.STARKNET_VALUE ? '(overridden)' : '')
    console.log('endpoint      :', endpoint)
    console.log('rpc           :', rpc)

    // Origin is { src_eid: u32, sender: Bytes32, nonce: u64 }; Bytes32 wraps a u256.
    const origin = ['0x' + srcEid.toString(16), ...u256(BigInt(sender)), '0x' + nonce.toString(16)]
    const globals = sncastGlobals()

    // Pre-flight: `executable(origin, receiver)` tells us whether this message is actually
    // deliverable, so we don't burn a fee re-delivering something already executed.
    console.log('\n--- pre-flight: endpoint.executable() ---')
    const stateOut = runSncast([
        ...globals,
        'call',
        '--url',
        rpc,
        '--contract-address',
        endpoint,
        '--function',
        'executable',
        '--calldata',
        ...origin,
        receiver,
    ])
    const state = EXECUTION_STATES.find((s) => stateOut.includes(`ExecutionState::${s}`))
    console.log('execution state:', state ?? '(could not parse)')
    if (state !== 'Executable' && !FORCE) {
        const why: Record<string, string> = {
            Executed: 'this message has already been delivered — nothing to do.',
            NotExecutable: 'the payload has not been verified/committed yet. Commit verification first.',
            VerifiedButNotExecutable:
                'verified, but an earlier nonce is still pending — ordered delivery requires you to execute those first.',
        }
        throw new Error(
            `ExecutionState is ${state ?? 'unknown'}: ${why[state ?? ''] ?? 'refusing to proceed.'} ` +
                `Set STARKNET_FORCE=true to override.`
        )
    }

    // The endpoint pulls `value` from the executor with `transfer_from`, so a non-zero
    // value needs an allowance from your account to the endpoint. Zero value needs none.
    if (value > 0n) {
        console.log('\n--- approve STRK allowance for the endpoint ---')
        console.log('native token  :', nativeToken)
        if (SIMULATE) {
            console.log(`(skipped in simulate) would approve ${value} to ${endpoint}`)
            console.log('NOTE: the lz_receive dry-run below will likely fail on allowance until this is sent.')
        } else {
            runSncast([
                ...globals,
                '--wait',
                'invoke',
                '--url',
                rpc,
                '--contract-address',
                nativeToken,
                '--function',
                'approve',
                '--calldata',
                endpoint,
                ...u256(value),
            ])
        }
    }

    const calldata = [
        ...origin,
        receiver,
        ...u256(BigInt(guid)),
        ...byteArray(message),
        ...byteArray(''), // extra_data: the executor supplies none for a plain lzReceive
        ...u256(value),
    ]

    console.log('\n--- endpoint.lz_receive() ---')
    console.log('calldata      :', calldata.join(' '))
    const out = runSncast([
        ...globals,
        ...(SIMULATE ? [] : ['--wait']),
        'invoke',
        '--url',
        rpc,
        '--contract-address',
        endpoint,
        '--function',
        'lz_receive',
        '--calldata',
        ...calldata,
        ...(SIMULATE ? ['--dry-run'] : []),
    ])

    if (SIMULATE) {
        console.log('\nDry-run complete — fee estimated above, nothing was sent.')
        console.log('Run `make broadcast-starknet` to deliver.')
        return
    }
    const hash = out.match(/0x[0-9a-fA-F]{60,66}/g)?.slice(-1)[0]
    console.log('\n--- broadcast result ---')
    if (hash) console.log('explorer      :', `https://voyager.online/tx/${hash}`)
    console.log('scan          :', `https://layerzeroscan.com/tx/${txHash}`)
}

main().catch((err: unknown) => {
    console.error(err instanceof Error ? err.message : err)
    process.exit(1)
})
