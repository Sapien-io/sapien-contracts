
const { Alchemy, Network } = require('alchemy-sdk');

const {ALCHEMY_API_KEY, NEAN_CONTRACT_ADDRESS_BASE_SEPOLIA} = process.env;

// provider - Alchemy
const settings = {
    apiKey: ALCHEMY_API_KEY,
    network: Network.BASE_SEPOLIA
}
const alchemy = new Alchemy(settings);


async function main() {
    const abi = [
        {
            "inputs": [
              {
                "internalType": "bytes32",
                "name": "allocationType",
                "type": "bytes32"
              }
            ],
            "name": "releaseTokens",
            "outputs": [],
            "stateMutability": "nonpayable",
            "type": "function"
          }
    ];

    const alchemyProvider = await alchemy.config.getProvider();
    
   
    const contract = new ethers.Contract(NEAN_CONTRACT_ADDRESS_BASE_SEPOLIA, abi, alchemyProvider);

    const data = contract.interface.encodeFunctionData("releaseTokens", ['0x696e766573746f72730000000000000000000000000000000000000000000000']);

    console.log("Data hex value:", data);
}

main();