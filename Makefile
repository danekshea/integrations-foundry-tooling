# Load environment variables from .env file
include .env
export $(shell sed 's/=.*//' .env)

# Optional keystore password: if KEYSTORE_PASSWORD is set in env (even to empty),
# pass it to foundry so the keystore prompt is skipped. If unset, foundry prompts.
PASSWORD_OPT = $${KEYSTORE_PASSWORD+--password=$$KEYSTORE_PASSWORD}

# Optional gas estimate multiplier (percentage): set GAS_ESTIMATE_MULTIPLIER in .env
# to add headroom on chains (e.g. Sei) where forge's estimate is too low and the
# broadcast runs out of gas. Empty by default => flag omitted, forge default applies.
GAS_MULT_OPT = $(if $(strip $(GAS_ESTIMATE_MULTIPLIER)),--gas-estimate-multiplier $(GAS_ESTIMATE_MULTIPLIER),)

# Needed to make sure the recipe always runs, otherwise it will see the broadcast folder and not run it
.PHONY: simulate-v1 broadcast-v1 broadcast-v1-force \
        simulate-v2 simulate-v2-zksync simulate-v2-compose simulate-v2-compose-zksync simulate-v2-commit simulate-v2-commit-zksync \
        broadcast-v2 broadcast-v2-zksync broadcast-v2-compose broadcast-v2-compose-zksync broadcast-v2-commit broadcast-v2-commit-zksync \
        broadcast-v2-force broadcast-v2-commit-force \
        simulate-solana broadcast-solana

# ============================================
# LayerZero V1 Targets (for retrying stored payloads)
# ============================================
simulate-v1:
	forge script script/lzReceiveV1.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) -vvvv

broadcast-v1:
	forge script script/lzReceiveV1.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast $(GAS_MULT_OPT) -vvvv

broadcast-v1-force:
	forge script script/lzReceiveV1.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast $(GAS_MULT_OPT) --legacy --skip-simulation --with-gas-price 6000000000 -vvvv

# ============================================
# LayerZero V2 Targets
# ============================================
simulate-v2:
	forge script script/lzReceiveV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) -vvvv

simulate-v2-zksync:
	@echo "=== zksync toolchain versions ==="
	@forge --version
	@cast --version
	@command -v anvil-zksync >/dev/null 2>&1 && anvil-zksync --version || echo "anvil-zksync: (not found in PATH)"
	@echo "================================="
	forge script script/lzReceiveV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --zksync -vvvv

simulate-v2-compose:
	forge script script/lzComposeV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) -vvvv

simulate-v2-compose-zksync:
	@echo "=== zksync toolchain versions ==="
	@forge --version
	@cast --version
	@command -v anvil-zksync >/dev/null 2>&1 && anvil-zksync --version || echo "anvil-zksync: (not found in PATH)"
	@echo "================================="
	forge script script/lzComposeV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --zksync -vvvv

broadcast-v2:
	forge script script/lzReceiveV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast $(GAS_MULT_OPT) -vvvv

broadcast-v2-zksync:
	@echo "=== zksync toolchain versions ==="
	@forge --version
	@cast --version
	@command -v anvil-zksync >/dev/null 2>&1 && anvil-zksync --version || echo "anvil-zksync: (not found in PATH)"
	@echo "================================="
	forge script script/lzReceiveV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast $(GAS_MULT_OPT) --zksync -vvvv

broadcast-v2-compose:
	forge script script/lzComposeV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast $(GAS_MULT_OPT) -vvvv

broadcast-v2-compose-zksync:
	@echo "=== zksync toolchain versions ==="
	@forge --version
	@cast --version
	@command -v anvil-zksync >/dev/null 2>&1 && anvil-zksync --version || echo "anvil-zksync: (not found in PATH)"
	@echo "================================="
	forge script script/lzComposeV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast $(GAS_MULT_OPT) --zksync -vvvv

broadcast-v2-force:
	forge script script/lzReceiveV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast $(GAS_MULT_OPT) --legacy --skip-simulation --with-gas-price 6000000000 -vvvv

simulate-v2-commit:
	forge script script/commitVerificationV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) -vvvv

simulate-v2-commit-zksync:
	@echo "=== zksync toolchain versions ==="
	@forge --version
	@cast --version
	@command -v anvil-zksync >/dev/null 2>&1 && anvil-zksync --version || echo "anvil-zksync: (not found in PATH)"
	@echo "================================="
	forge script script/commitVerificationV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --zksync -vvvv

broadcast-v2-commit:
	forge script script/commitVerificationV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast $(GAS_MULT_OPT) -vvvv

broadcast-v2-commit-zksync:
	@echo "=== zksync toolchain versions ==="
	@forge --version
	@cast --version
	@command -v anvil-zksync >/dev/null 2>&1 && anvil-zksync --version || echo "anvil-zksync: (not found in PATH)"
	@echo "================================="
	forge script script/commitVerificationV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast $(GAS_MULT_OPT) --zksync -vvvv

broadcast-v2-commit-force:
	forge script script/commitVerificationV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast $(GAS_MULT_OPT) --legacy --skip-simulation --with-gas-price 6000000000 -vvvv

# ============================================
# LayerZero Solana Targets (inbound to Solana)
# ============================================
# Self-execute a stuck EVM->Solana message. Params are fetched from LayerZero Scan
# using SOURCE_CHAIN_TX_HASH (+ MAINNET). Signs with SOLANA_KEYPAIR (default
# ~/.config/solana/id.json) and funds ATA rent + fees from your own SOL. See README.
simulate-solana:
	SIMULATE=true node_modules/.bin/ts-node script/lzReceiveSolana.ts

broadcast-solana:
	node_modules/.bin/ts-node script/lzReceiveSolana.ts
