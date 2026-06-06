# Load environment variables from .env file
include .env
export $(shell sed 's/=.*//' .env)

# Optional keystore password: if KEYSTORE_PASSWORD is set in env (even to empty),
# pass it to foundry so the keystore prompt is skipped. If unset, foundry prompts.
PASSWORD_OPT = $${KEYSTORE_PASSWORD+--password=$$KEYSTORE_PASSWORD}

# Needed to make sure the recipe always runs, otherwise it will see the broadcast folder and not run it
.PHONY: simulate-v1 broadcast-v1 broadcast-v1-force \
        simulate-v2 simulate-v2-zksync simulate-v2-compose simulate-v2-compose-zksync simulate-v2-commit simulate-v2-commit-zksync \
        broadcast-v2 broadcast-v2-zksync broadcast-v2-compose broadcast-v2-compose-zksync broadcast-v2-commit broadcast-v2-commit-zksync \
        broadcast-v2-force broadcast-v2-commit-force

# ============================================
# LayerZero V1 Targets (for retrying stored payloads)
# ============================================
simulate-v1:
	forge script script/lzReceiveV1.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) -vvvv

broadcast-v1:
	forge script script/lzReceiveV1.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast -vvvv

broadcast-v1-force:
	forge script script/lzReceiveV1.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast --legacy --skip-simulation --with-gas-price 6000000000 -vvvv

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
	forge script script/lzReceiveV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast -vvvv

broadcast-v2-zksync:
	@echo "=== zksync toolchain versions ==="
	@forge --version
	@cast --version
	@command -v anvil-zksync >/dev/null 2>&1 && anvil-zksync --version || echo "anvil-zksync: (not found in PATH)"
	@echo "================================="
	forge script script/lzReceiveV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast --zksync -vvvv

broadcast-v2-compose:
	forge script script/lzComposeV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast -vvvv

broadcast-v2-compose-zksync:
	@echo "=== zksync toolchain versions ==="
	@forge --version
	@cast --version
	@command -v anvil-zksync >/dev/null 2>&1 && anvil-zksync --version || echo "anvil-zksync: (not found in PATH)"
	@echo "================================="
	forge script script/lzComposeV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast --zksync -vvvv

broadcast-v2-force:
	forge script script/lzReceiveV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast --legacy --skip-simulation --with-gas-price 6000000000 -vvvv

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
	forge script script/commitVerificationV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast -vvvv

broadcast-v2-commit-zksync:
	@echo "=== zksync toolchain versions ==="
	@forge --version
	@cast --version
	@command -v anvil-zksync >/dev/null 2>&1 && anvil-zksync --version || echo "anvil-zksync: (not found in PATH)"
	@echo "================================="
	forge script script/commitVerificationV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast --zksync -vvvv

broadcast-v2-commit-force:
	forge script script/commitVerificationV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) $(PASSWORD_OPT) --broadcast --legacy --skip-simulation --with-gas-price 6000000000 -vvvv
