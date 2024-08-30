import { encodeAbiParameters, encodeFunctionData, keccak256, parseAbi, type Address, type Hex, type Transport } from "@flashbots/suave-viem";
import { SuaveTxRequestTypes, type SuaveProvider, type TransactionRequestSuave } from "@flashbots/suave-viem/chains/utils";

export interface IUniswapXOrder {
    tokenIn: Address
    tokenOut: Address
    amount: bigint
    nonce: bigint
    swapper: Address
    signature: Hex
}

// Helper class for UniswapXOrders inspired by https://github.com/zeroXbrock/unisuapp/blob/main/intents-lib/limitOrder.ts
export class UniswapXOrder<T extends Transport> implements IUniswapXOrder {
    tokenIn: Address
    tokenOut: Address
    amount: bigint
    nonce: bigint
    swapper: Address
    signature: Hex

     // client configs
     client: SuaveProvider<T>
     contractAddress: Address
     kettleAddress: Address

    constructor(params: IUniswapXOrder, client: SuaveProvider<T>, contractAddress: Address, kettleAddress: Address) {
        this.tokenIn = params.tokenIn
        this.tokenOut = params.tokenOut
        this.amount = params.amount
        this.nonce = params.nonce
        this.swapper = params.swapper
        this.signature = params.signature

        this.client = client
        this.contractAddress = contractAddress
        this.kettleAddress = kettleAddress
    }

    // TODO: ideally we'd extend PublicClient to create LimitOrders, then we could
    // just use the class' client instance
    async toTransactionRequest(): Promise<TransactionRequestSuave> {
        const feeData = await this.client.getFeeHistory({blockCount: 1, rewardPercentiles: [51]})
        return {
            to: this.contractAddress,
            confidentialInputs: this.privateBytes(),
            data: this.newOrderCalldata(),
            kettleAddress: this.kettleAddress,
            gasPrice: feeData.baseFeePerGas[0] || 10000000000n,
            gas: 150000n,
            type: SuaveTxRequestTypes.ConfidentialRequest,
        }
    }

    orderId(): Hex {
        return keccak256(this.publicBytes())
    }

    // encoded struct PublicUniswapXOrder
    private publicBytes(): Hex {
        return encodeAbiParameters([
            {type: 'address', name: 'tokenIn'},
            {type: 'address', name: 'tokenOut'},
            {type: 'uint256', name: 'amount'},
            {type: 'uint256', name: 'nonce'},
            {type: 'address', name: 'swapper'},
        ], [
            this.tokenIn,
            this.tokenOut,
            this.amount,
            this.nonce,
            this.swapper,
        ])
    }

    private privateBytes(): Hex {
        return encodeAbiParameters([
            {type: 'address', name: 'tokenIn'},
            {type: 'address', name: 'tokenOut'},
            {type: 'uint256', name: 'amount'},
            {type: 'uint256', name: 'nonce'},
            {type: 'address', name: 'swapper'},
            {type: 'bytes', name: 'signature'},
        ], [
            this.tokenIn,
            this.tokenOut,
            this.amount,
            this.nonce,
            this.swapper,
            this.signature,
        ])
    }

    private newOrderCalldata(): Hex {
        return encodeFunctionData({
            abi: parseAbi(['function offchain() public']),
            functionName: 'offchain',
          })
    }
}