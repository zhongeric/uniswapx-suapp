import { encodeAbiParameters, encodeFunctionData, keccak256, parseAbi, type Address, type Hex, type Transport } from "@flashbots/suave-viem";
import { SuaveTxRequestTypes, type SuaveProvider, type TransactionRequestSuave } from "@flashbots/suave-viem/chains/utils";

interface IUniswapXAuction {
    cosignerKey: Hex
}

// helper class to handle adding cosigner keys, registering webhooks, etc.
export class UniswapXAuction<T extends Transport> {
    cosignerKey: Hex
    // client configs
    client: SuaveProvider<T>
    contractAddress: Address
    kettleAddress: Address

    constructor(params: IUniswapXAuction, client: SuaveProvider<T>, contractAddress: Address, kettleAddress: Address) {
        this.cosignerKey = params.cosignerKey
        this.client = client
        this.contractAddress = contractAddress
        this.kettleAddress = kettleAddress
    }

    async registerCosignerKeyTransactionRequest(): Promise<TransactionRequestSuave> {
        const feeData = await this.client.getFeeHistory({blockCount: 1, rewardPercentiles: [51]})
        return {
            to: this.contractAddress,
            confidentialInputs: this.cosignerKey,
            data: this.registerCosignerKeyCalldata(),
            kettleAddress: this.kettleAddress,
            gasPrice: feeData.baseFeePerGas[0] || 10000000000n,
            gas: 150000n,
            type: SuaveTxRequestTypes.ConfidentialRequest,
        }
    }

    private registerCosignerKeyCalldata(): Hex {
        return encodeFunctionData({
            abi: parseAbi(['function registerPrivateKeyOffchain() public']),
            functionName: 'registerPrivateKeyOffchain',
          })
    }
}