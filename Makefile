# Load environment variables from .env file
include .env
export $(shell sed 's/=.*//' .env)

# Needed to make sure the recipe always runs, otherwise it will see the broadcast folder and not run it
.PHONY: simulate broadcast 

simulate:
	forge script script/lzReceive.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) -vvvv

simulate-compose:
	forge script script/lzCompose.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) -vvvv

broadcast:
	forge script script/lzReceive.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) --broadcast -vvvv

broadcast-force:
	forge script script/lzReceive.s.sol --rpc-url $(DESTINATION_CHAIN_RPC_URL) --account $(CAST_ACCOUNT) --broadcast --legacy --skip-simulation --with-gas-price 6000000000 -vvvv
