import { encodeAbiParameters, encodeFunctionData, keccak256, parseAbi, type Address, type Hex, type Transport } from "@flashbots/suave-viem";
import { SuaveTxRequestTypes, type SuaveProvider, type TransactionRequestSuave } from "@flashbots/suave-viem/chains/utils";

export interface IUniswapXOrder {
    tokenIn: Address
    tokenOut: Address
    amount: bigint
    nonce: bigint
    swapper: Address,
    auctionStartTime: bigint,
    auctionEndTime: bigint,
    signature: Hex
}

// Helper class for UniswapXOrders inspired by https://github.com/zeroXbrock/unisuapp/blob/main/intents-lib/limitOrder.ts
export class UniswapXOrder<T extends Transport> implements IUniswapXOrder {
    tokenIn: Address
    tokenOut: Address
    amount: bigint
    nonce: bigint
    swapper: Address
    auctionStartTime: bigint
    auctionEndTime: bigint
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
        this.auctionStartTime = params.auctionStartTime
        this.auctionEndTime = params.auctionEndTime
        this.signature = params.signature

        this.client = client
        this.contractAddress = contractAddress
        this.kettleAddress = kettleAddress
    }

    async createNewOrderTransactionRequest(): Promise<TransactionRequestSuave> {
        const feeData = await this.client.getFeeHistory({blockCount: 1, rewardPercentiles: [51]})
        return {
            to: this.contractAddress,
            confidentialInputs: this.private_createOrderBytes(),
            data: this.newOrderCalldata(),
            kettleAddress: this.kettleAddress,
            gasPrice: feeData.baseFeePerGas[0] || 10000000000n,
            gas: 150000n,
            type: SuaveTxRequestTypes.ConfidentialRequest,
        }
    }

    async finalizeOrderTransactionRequest(): Promise<TransactionRequestSuave> {
        const feeData = await this.client.getFeeHistory({blockCount: 1, rewardPercentiles: [51]})
        return {
            to: this.contractAddress,
            confidentialInputs: this.public_finalizeOrderBytes(),
            data: this.finalizeOrderCalldata(),
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
            {type: 'uint256', name: 'auctionStartTime'},
            {type: 'uint256', name: 'auctionEndTime'},
        ], [
            this.tokenIn,
            this.tokenOut,
            this.amount,
            this.nonce,
            this.swapper,
            this.auctionStartTime,
            this.auctionEndTime,
        ])
    }

    private public_finalizeOrderBytes(): Hex {
        return encodeAbiParameters([{type: 'bytes32', name: 'orderId'}], [this.orderId()]);
    }

    private private_createOrderBytes(): Hex {
        return encodeAbiParameters([
            {type: 'address', name: 'tokenIn'},
            {type: 'address', name: 'tokenOut'},
            {type: 'uint256', name: 'amount'},
            {type: 'uint256', name: 'nonce'},
            {type: 'address', name: 'swapper'},
            {type: 'uint256', name: 'auctionStartTime'},
            {type: 'uint256', name: 'auctionEndTime'},
            {type: 'bytes', name: 'signature'},
        ], [
            this.tokenIn,
            this.tokenOut,
            this.amount,
            this.nonce,
            this.swapper,
            this.auctionStartTime,
            this.auctionEndTime,
            this.signature,
        ])
    }

    private newOrderCalldata(): Hex {
        return encodeFunctionData({
            abi: parseAbi(['function newOrderOffChain() public']),
            functionName: 'newOrderOffChain',
          })
    }

    private finalizeOrderCalldata(): Hex {
        return encodeFunctionData({
            abi: parseAbi(['function finalizeOrderOffChain() public']),
            functionName: 'finalizeOrderOffChain',
          })
    }
}