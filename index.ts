import {http, parseEther, type Hex} from '@flashbots/suave-viem';
import {getSuaveWallet, type TransactionRequestSuave, getSuaveProvider, type TransactionReceiptSuave, SuaveTxTypes} from '@flashbots/suave-viem/chains/utils'

import dotenv from 'dotenv';
import { UniswapXOrder } from './uniswapx-lib/UniswapXOrder';
import { UniswapXAuction } from './uniswapx-lib/UnsiwapXAuction';
import { SuaveRevert } from './uniswapx-lib/SuaveRevert';
dotenv.config();

if(!process.env.PRIVATE_KEY) {
    console.error('PRIVATE_KEY not found in .env file');
    process.exit(1);
}

const SUAVE_RPC_URL = 'https://rpc.rigil.suave.flashbots.net';
// Change this to a private key with rETH you get from https://faucet.rigil.suave.flashbots.net/
const PRIVATE_KEY = `0x${process.env.PRIVATE_KEY}` as any
const PUBLIC_KEY = "0x60f554A11db413470Bf2Db7c9241DE67D69Eb91d"

const AUCTION_ADDRESS = "0x28fF0277F6a3AAc5C771A5Cc79Ed59Db07aB4869"
const RIGIL_KETTLE_ADDRESS = "0x03493869959c866713c33669ca118e774a30a0e5"

const wallet = getSuaveWallet({
    transport: http(SUAVE_RPC_URL),
    privateKey: PRIVATE_KEY,
}).extend((client) => ({
    async sendTransaction(tx: TransactionRequestSuave): Promise<Hex> {
        try {
            return await client.sendTransaction(tx);
        } catch (e) {
            throw new SuaveRevert(e as Error);
        }
    },
}));

console.log("suaveWallet", wallet.account.address);
const suaveProvider = getSuaveProvider(
	http(SUAVE_RPC_URL),
);

const uniswapXAuction = new UniswapXAuction(
    {
        cosignerKey: PRIVATE_KEY
    },
    suaveProvider,
    AUCTION_ADDRESS,
    RIGIL_KETTLE_ADDRESS,
)

const registerCosignerKeyTx: TransactionRequestSuave = await uniswapXAuction.registerCosignerKeyTransactionRequest();
console.log(`registerCosignerKeyTx: `, registerCosignerKeyTx);
const registerCosignerKeyTxHash: Hex = await wallet.sendTransaction(registerCosignerKeyTx);
console.log(`registerCosignerKeyTxHash: `, registerCosignerKeyTxHash);

const uniswapXOrder = new UniswapXOrder(
    {
        tokenIn: "0x0000000000000000000000000000000000000000",
        tokenOut: "0x0000000000000000000000000000000000000001",
        amount: 0n,
        nonce: 0n,
        swapper: PUBLIC_KEY,
        signature: "0x",
    },
    suaveProvider,
    AUCTION_ADDRESS,
    RIGIL_KETTLE_ADDRESS,
);

const tx: TransactionRequestSuave = await uniswapXOrder.toTransactionRequest();
console.log(`tx: `, tx);
const txHash: Hex = await wallet.sendTransaction(tx);
console.log(`txHash: `, txHash);

let ccrReceipt: TransactionReceiptSuave | null = null;

let fails = 0;
for (let i = 0; i < 10; i++) {
	try {
			ccrReceipt = await suaveProvider.waitForTransactionReceipt({
				hash: txHash,
			});
			console.log("ccrReceipt logs", ccrReceipt.logs);
			break;
		} catch (e) {
			console.warn("error", e);
			if (++fails >= 10) {
				throw new Error("failed to get receipt: timed out");
			}
		}
	}
	if (!ccrReceipt) {
		throw new Error("no receipt (this should never happen)");
	}

	const txRes = await suaveProvider.getTransaction({ hash: txHash });
	console.log("txRes", txRes);

if (txRes.type !== SuaveTxTypes.Suave) {
	throw new Error("expected SuaveTransaction type (0x50)");
}

