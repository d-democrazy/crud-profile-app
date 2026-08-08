# Makefile

include .env
export

CONTRACT_NAME := ProfileContractOp
SCRIPT_NAME   := DeployProfileContractOp.s.sol
SCRIPT_PATH   := script/$(SCRIPT_NAME):DeployProfileContractOp

.PHONY: deploy verify tdeploy setup-wallet tcall call tsend send \
        get-profile get-all-profile set-profile update-profile delete-profile

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
		--verifier-url $(TESTNET2_API_ENDPOINT) \
		--api-key $(CORESCAN_TESTNET2_API_KEY) \
		--watch

setup-wallet:
	@echo "Creating a new encrypted keystore wallet..."
	cast wallet new ~/.foundry/keystores/dummy
	@echo "Wallet saved. Use 'make deploy' to deploy with it."

# --- Contract interaction (cast) ---------------------------------------
#
# Friendly action names arrive as the Makefile's *second* command-line word:
#   make tcall get-profile
#   make tsend set-profile ARGS='("Name","Role","Bio",5)'

ACTION := $(word 2,$(MAKECMDGOALS))

# Auto-resolve the deployed address from the broadcast JSON, same lookup `verify` uses
define resolve_address
$(eval BROADCAST_FILE := $(shell find broadcast/$(SCRIPT_NAME)/$(1) -name run-latest.json | head -n 1))
$(eval CONTRACT_ADDRESS := $(shell jq -r '.transactions[] | select(.contractName == "$(CONTRACT_NAME)") | .contractAddress' $(BROADCAST_FILE)))
endef

# Swallow the action word itself so `make tcall get-profile` doesn't
# also try (and fail) to build a target literally named `get-profile`
get-profile get-all-profile set-profile update-profile delete-profile:
	@:

tcall:
	$(call resolve_address,31337)
	@case "$(ACTION)" in \
		get-profile)     cast call $(CONTRACT_ADDRESS) "getProfile(address)" $(or $(ADDRESS),$(shell cast wallet address --account dummy)) --rpc-url http://127.0.0.1:8545 ;; \
		get-all-profile) cast call $(CONTRACT_ADDRESS) "getAllProfiles()" --rpc-url http://127.0.0.1:8545 ;; \
		*) echo "make tcall: unknown action '$(ACTION)' (use get-profile | get-all-profile)"; exit 1 ;; \
	esac

call:
	$(call resolve_address,$(TESTNET2_CHAIN_ID))
	@case "$(ACTION)" in \
		get-profile)     cast call $(CONTRACT_ADDRESS) "getProfile(address)" $(or $(ADDRESS),$(shell cast wallet address --account dummy)) --rpc-url $(TESTNET2_RPC_URL) ;; \
		get-all-profile) cast call $(CONTRACT_ADDRESS) "getAllProfiles()" --rpc-url $(TESTNET2_RPC_URL) ;; \
		*) echo "make call: unknown action '$(ACTION)' (use get-profile | get-all-profile)"; exit 1 ;; \
	esac

tsend:
	$(call resolve_address,31337)
	@case "$(ACTION)" in \
		set-profile)     cast send $(CONTRACT_ADDRESS) "setProfile((string,string,string,uint8))" "$(ARGS)" --rpc-url http://127.0.0.1:8545 --account dummy --legacy ;; \
		update-profile)  cast send $(CONTRACT_ADDRESS) "updateProfile((string,string,string,uint8))" "$(ARGS)" --rpc-url http://127.0.0.1:8545 --account dummy --legacy ;; \
		delete-profile)  cast send $(CONTRACT_ADDRESS) "deleteProfile()" --rpc-url http://127.0.0.1:8545 --account dummy --legacy ;; \
		*) echo "make tsend: unknown action '$(ACTION)' (use set-profile | update-profile | delete-profile)"; exit 1 ;; \
	esac

send:
	$(call resolve_address,$(TESTNET2_CHAIN_ID))
	@case "$(ACTION)" in \
		set-profile)     cast send $(CONTRACT_ADDRESS) "setProfile((string,string,string,uint8))" "$(ARGS)" --rpc-url $(TESTNET2_RPC_URL) --account dummy --legacy ;; \
		update-profile)  cast send $(CONTRACT_ADDRESS) "updateProfile((string,string,string,uint8))" "$(ARGS)" --rpc-url $(TESTNET2_RPC_URL) --account dummy --legacy ;; \
		delete-profile)  cast send $(CONTRACT_ADDRESS) "deleteProfile()" --rpc-url $(TESTNET2_RPC_URL) --account dummy --legacy ;; \
		*) echo "make send: unknown action '$(ACTION)' (use set-profile | update-profile | delete-profile)"; exit 1 ;; \
	esac