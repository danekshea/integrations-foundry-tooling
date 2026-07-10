/**
 * lzReceiveSolana.ts — manually execute (deliver) a stuck LayerZero message whose
 * destination is Solana, by acting as the executor yourself.
 *
 * This is the Solana counterpart to the EVM `lzReceiveV2.s.sol` forge script. It is
 * driven by the same `.env` convention: set `SOURCE_CHAIN_TX_HASH` (+ `MAINNET`) and
 * every other parameter (guid, message, sender, receiver, nonce, srcEid, dstEid,
 * option value) is fetched automatically from the LayerZero Scan API.
 *
 * Why this exists: when an EVM→Solana transfer is verified but the LZ executor's own
 * delivery reverts — most commonly `InsufficientBalance (6014 / 0x177e)` in the
 * executor's PostExecute because the source send used `value: 0` and it can't cover
 * the recipient's ATA rent — you cannot change the options on the already-sent packet.
 * But `lzReceive` on Solana is permissionless, so you can build and submit the
 * delivery yourself as the fee payer, funding the ATA rent + fees from your own SOL.
 * The executor's `fee_limit` guard never runs on a self-submitted transaction.
 *
 * Usage (via Makefile):
 *   make simulate-solana    # dry-run: simulateTransaction, prints logs + err, no send
 *   make broadcast-solana   # actually sign + submit, spends your SOL
 *
 * Env:
 *   SOURCE_CHAIN_TX_HASH   (required) source-chain tx hash of the failed message
 *   MAINNET                (default true) selects scan + default RPC network
 *   SOLANA_RPC_URL         (optional) defaults to public mainnet/devnet endpoint
 *   SOLANA_KEYPAIR         (optional) fee-payer keypair, defaults to ~/.config/solana/id.json
 *   SOLANA_VALUE_LAMPORTS  (optional) override the lamports you fund for delivery
 *   SOLANA_COMPUTE_UNITS   (optional) CU limit, default 200000
 *   SIMULATE               (set by `make simulate-solana`) true => dry-run only
 */
import 'dotenv/config'
import { readFileSync } from 'fs'
import { homedir } from 'os'

import {
    AddressLookupTableInput,
    Context,
    Instruction,
    RpcConfirmTransactionResult,
    Signer,
    TransactionBuilder,
    WrappedInstruction,
    createSignerFromKeypair,
} from '@metaplex-foundation/umi'
import { base58 } from '@metaplex-foundation/umi/serializers'
import { createUmi } from '@metaplex-foundation/umi-bundle-defaults'
import { fromWeb3JsInstruction, toWeb3JsInstruction } from '@metaplex-foundation/umi-web3js-adapters'
import * as web3 from '@solana/web3.js'

import { ExecutorProgram } from '@layerzerolabs/lz-solana-sdk-v2/umi'

const MAINNET = (process.env.MAINNET ?? 'true').toLowerCase() === 'true'
const SIMULATE = (process.env.SIMULATE ?? 'false').toLowerCase() === 'true'

const SCAN_BASE = MAINNET ? 'https://scan.layerzero-api.com' : 'https://scan-testnet.layerzero-api.com'
const DEFAULT_RPC = MAINNET ? 'https://api.mainnet-beta.solana.com' : 'https://api.devnet.solana.com'
const SOLANA_EIDS = new Set([30168, 40168])

// ATA rent (~2,039,280 lamports) + fees + buffer. Used when the source options
// carried too little `value` to cover destination account creation.
const FLOOR_LAMPORTS = 2_500_000n

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

/** Left-pad an address (EVM 20-byte hex, or any <=32-byte hex) to a 0x bytes32 string. */
function hexlify32(addr: string): string {
    const hex = addr.toLowerCase().replace(/^0x/, '')
    if (hex.length > 64) throw new Error(`address too long for bytes32: ${addr}`)
    return '0x' + hex.padStart(64, '0')
}

async function main(): Promise<void> {
    const txHash = process.env.SOURCE_CHAIN_TX_HASH
    if (!txHash) throw new Error('SOURCE_CHAIN_TX_HASH is required (set it in .env)')

    const d = await fetchMessage(txHash)
    const { srcEid, dstEid, nonce } = d.pathway
    if (!SOLANA_EIDS.has(dstEid)) {
        throw new Error(
            `Destination EID ${dstEid} is not Solana (expected 30168/40168). ` +
                `For EVM destinations use the forge make targets (e.g. make broadcast-v2).`
        )
    }

    const sender = d.pathway.sender.address
    const receiver = d.pathway.receiver.address
    const guid = d.guid
    const message = d.source.tx.payload
    const optionValue = BigInt(d.source.tx.options?.lzReceive?.value ?? '0')

    const override = process.env.SOLANA_VALUE_LAMPORTS ? BigInt(process.env.SOLANA_VALUE_LAMPORTS) : undefined
    const value = override ?? (optionValue > FLOOR_LAMPORTS ? optionValue : FLOOR_LAMPORTS)

    console.log('--- LayerZero Solana lzReceive ---')
    console.log('mode          :', SIMULATE ? 'SIMULATE (dry-run)' : 'BROADCAST')
    console.log('source tx     :', txHash)
    console.log('srcEid        :', srcEid)
    console.log('dstEid        :', dstEid, '(Solana)')
    console.log('sender        :', sender)
    console.log('receiver      :', receiver)
    console.log('nonce         :', nonce)
    console.log('guid          :', guid)
    console.log('option value  :', optionValue.toString(), 'lamports (from source send)')
    console.log('value funded  :', value.toString(), 'lamports', override ? '(overridden)' : '')

    const rpc = process.env.SOLANA_RPC_URL ?? DEFAULT_RPC
    const connection = new web3.Connection(rpc, 'confirmed')
    const umi = createUmi(connection)

    const keypairPath = process.env.SOLANA_KEYPAIR ?? `${homedir()}/.config/solana/id.json`
    const secret = JSON.parse(readFileSync(keypairPath, 'utf-8')) as number[]
    const keypair = web3.Keypair.fromSecretKey(Uint8Array.from(secret))
    umi.payer = createSignerFromKeypair(umi, umi.eddsa.createKeypairFromSecretKey(keypair.secretKey))
    console.log('fee payer     :', keypair.publicKey.toBase58())
    console.log('rpc           :', rpc)

    const computeUnits = Number(process.env.SOLANA_COMPUTE_UNITS ?? '200000')

    const executor = new ExecutorProgram.Executor()
    const { instructions, signers, addressLookupTables } = await executor.execute(umi.rpc, umi.payer, {
        packet: {
            version: 1,
            nonce: String(nonce),
            srcEid,
            sender: hexlify32(sender),
            dstEid,
            receiver,
            guid,
            message,
            payload: guid + message.slice(2),
        },
        value,
        extraData: new Uint8Array(0),
    })

    if (SIMULATE) {
        await simulate(connection, keypair.publicKey, instructions, addressLookupTables, computeUnits)
        return
    }

    const result = await sendAndConfirm(
        umi,
        instructions.map((ix: Instruction, index: number) => ({
            instruction: ix,
            signers: index === 0 ? signers : [],
            bytesCreatedOnChain: 0,
        })),
        [umi.payer, ...signers],
        computeUnits,
        addressLookupTables
    )
    console.log('--- broadcast result ---')
    console.log('signature :', result.signature)
    console.log('confirmed :', JSON.stringify(result.result))
    console.log('explorer  :', `https://solscan.io/tx/${result.signature}`)
}

/**
 * Dry-run: convert the umi instructions to web3.js, build a v0 transaction with the
 * SDK-provided address lookup tables, and simulate it. Surfaces the same on-chain
 * error (e.g. custom program error 0x177e) you'd hit on a real send, without landing
 * a transaction or spending SOL.
 */
async function simulate(
    connection: web3.Connection,
    payer: web3.PublicKey,
    instructions: Instruction[],
    addressLookupTables: AddressLookupTableInput[],
    computeUnits: number
): Promise<void> {
    const cuIx = web3.ComputeBudgetProgram.setComputeUnitLimit({ units: computeUnits })
    const web3Ixs = [cuIx, ...instructions.map((ix: Instruction) => toWeb3JsInstruction(ix))]

    const alts = (
        await Promise.all(
            addressLookupTables.map(
                async (a: AddressLookupTableInput) =>
                    (await connection.getAddressLookupTable(new web3.PublicKey(a.publicKey))).value
            )
        )
    ).filter((x: web3.AddressLookupTableAccount | null): x is web3.AddressLookupTableAccount => x != null)

    const { blockhash } = await connection.getLatestBlockhash()
    const msg = new web3.TransactionMessage({
        payerKey: payer,
        recentBlockhash: blockhash,
        instructions: web3Ixs,
    }).compileToV0Message(alts)
    const vtx = new web3.VersionedTransaction(msg)

    const sim = await connection.simulateTransaction(vtx, { sigVerify: false, replaceRecentBlockhash: true })
    console.log('--- simulation result ---')
    console.log('err            :', JSON.stringify(sim.value.err))
    console.log('computeUnits   :', sim.value.unitsConsumed)
    console.log('logs           :')
    ;(sim.value.logs ?? []).forEach((l: string) => console.log('  ' + l))
    if (sim.value.err) {
        console.error('\nSimulation reverted — inspect the logs above (e.g. 0x177e = InsufficientBalance 6014).')
        process.exitCode = 1
    } else {
        console.log('\nSimulation succeeded — run `make broadcast-solana` to deliver.')
    }
}

/**
 * Sends and confirms a transaction containing one or more wrapped instructions.
 * First signer is the fee payer; the rest sign the instructions.
 */
export async function sendAndConfirm(
    umi: Context,
    instructions: WrappedInstruction | WrappedInstruction[],
    signers: Signer | Signer[],
    computeUnitsLimit = 0,
    addressLookupTables?: AddressLookupTableInput[]
): Promise<{
    signature: string
    result: RpcConfirmTransactionResult
}> {
    if (!Array.isArray(instructions)) {
        instructions = [instructions]
    }
    const feePayer = Array.isArray(signers) ? signers[0] : signers
    if (Array.isArray(signers) && signers.length > 1) {
        // override the signers for each instruction
        const ixSigners = signers.slice(1)
        instructions.forEach((ix: WrappedInstruction) => {
            ix.signers = ixSigners
        })
    }
    if (computeUnitsLimit > 0) {
        const computeUnitsBudgetIX = web3.ComputeBudgetProgram.setComputeUnitLimit({
            units: computeUnitsLimit,
        })
        instructions = [
            {
                instruction: fromWeb3JsInstruction(computeUnitsBudgetIX),
                signers: [],
                bytesCreatedOnChain: 0,
            },
            ...instructions,
        ]
    }
    return new TransactionBuilder(instructions, { feePayer: feePayer, addressLookupTables })
        .sendAndConfirm(umi, {
            send: { preflightCommitment: 'confirmed', commitment: 'confirmed' },
        })
        .then((result: { signature: Uint8Array; result: RpcConfirmTransactionResult }) => {
            return { signature: base58.deserialize(result.signature)[0], result: result.result }
        })
}

main().catch((err: unknown) => {
    console.error(err)
    process.exit(1)
})
