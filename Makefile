

deploy-sepolia :;
	forge script script/DeployBaseSepolia.s.sol:DeployBaseSepolia \
	--account 0x09F4897735f3Ec9Af6C2dda49d97D454B7dD1e59 \
	--rpc-url ${RPC_URL} \
	--broadcast \
	--verify
	-vvvv



deploy-local :;
	@./script/deploy-local.sh

verify-local :; forge test --match-contract LocalDeploymentVerification --fork-url http://localhost:8545

coverage :; forge coverage --ir-minimum


lint :; npx solhint "src/**/*.sol" > solhint-report.txt

build :; forge clean && forge build > build-report.txt

verify :; halmos --match-path "test/formal/*.t.sol"