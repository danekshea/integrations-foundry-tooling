# Load environment variables from .env file
include .env
export $(shell sed 's/=.*//' .env)

# Needed to make sure the recipe always runs, otherwise it will see the broadcast folder and not run it
.PHONY: simulate-v1 broadcast-v1 broadcast-v1-force \
        simulate-v2 simulate-v2-compose broadcast-v2 broadcast-v2-compose broadcast-v2-force

# ============================================
# LayerZero V1 Targets (for retrying stored payloads)
# ============================================
simulate-v1:
	forge script script/lzReceiveV1.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) -vvvv

broadcast-v1:
	forge script script/lzReceiveV1.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) --broadcast -vvvv

broadcast-v1-force:
	forge script script/lzReceiveV1.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) --broadcast --legacy --skip-simulation --with-gas-price 6000000000 -vvvv

# ============================================
# LayerZero V2 Targets
# ============================================
simulate-v2:
	forge script script/lzReceiveV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) -vvvv

simulate-v2-compose:
	forge script script/lzComposeV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) -vvvv

broadcast-v2:
	forge script script/lzReceiveV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) --broadcast -vvvv

broadcast-v2-compose:
	forge script script/lzComposeV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) --broadcast -vvvv

broadcast-v2-force:
	forge script script/lzReceiveV2.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) --broadcast --legacy --skip-simulation --with-gas-price 6000000000 -vvvv
