# Load environment variables from .env file
include .env
export $(shell sed 's/=.*//' .env)

simulate:
	forge script script/SimulateReceive.s.sol --rpc-url $(RPC_URL) --account burner

broadcast:
	forge script script/SimulateReceive.s.sol --rpc-url $(RPC_URL) --account burner --broadcast