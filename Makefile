# Makefile

include .env
export

CONTRACT_NAME := ProfileContract
SCRIPT_NAME   := DeployProfileContract.s.sol
SCRIPT_PATH   := script/$(SCRIPT_NAME):DeployProfileContract

.PHONY: deploy verify

tdeploy:
	forge script $(SCRIPT_PATH) \
		--rpc-url http://127.0.0.1:8545 \
		--account dummy \
		--broadcast \
		--legacy

deploy:
	forge script $(SCRIPT_PATH) \
		--rpc-url $(TESTNET2_RPC_URL) \
		--account dummy \
		--broadcast \
		--legacy

verify:
	$(eval BROADCAST_FILE := $(shell find broadcast/$(SCRIPT_NAME) -name run-latest.json | head -n 1))
	$(eval CONTRACT := $(shell jq -r '.transactions[] | select(.contractName == "$(CONTRACT_NAME)") | .contractAddress' $(BROADCAST_FILE)))
	@echo "Broadcast file: $(BROADCAST_FILE)"
	@echo "Verifying $(CONTRACT_NAME) at $(CONTRACT)"
	forge verify-contract $(CONTRACT) $(CONTRACT_NAME) \
		--verifier-url $(TESTNET2_API_URL) \
		--api-key $(CORESCAN_TESTNET2_API_KEY) \
		--watch