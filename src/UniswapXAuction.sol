// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import "suave-std/Suapp.sol";
import "suave-std/Context.sol";
import "suave-std/Gateway.sol";
import "suave-std/suavelib/Suave.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {Webhook} from "./lib/Webhook.sol";

struct UniswapXOrder {
    address tokenIn;
    address tokenOut;
    uint256 amount;
    uint256 nonce;
    address swapper;
    // Private data
    // - for order execution
    bytes signature;
}

struct CosignerData {
    uint256 amountOverride;
}

struct CosignedUniswapXOrder {
    UniswapXOrder order;
    CosignerData cosignerData;
    bytes cosignature;
}

struct PublicUniswapXOrder {
    address tokenIn;
    address tokenOut;
    uint256 amount;
    uint256 nonce;
    address swapper;
}

contract UniswapXAuction is Suapp {
    Suave.DataId webhookRecord;

    Suave.DataId cosignerKeyRecord;
    string public PRIVATE_KEY = "KEY";

    event WebhookNameRegistered(string name);

    // Offchain/Onchain functions for updating cosigner key

    function updateKeyOnchain(Suave.DataId _cosignerKeyRecord) public {
        cosignerKeyRecord = _cosignerKeyRecord;
    }

    // TODO: restrict access to who can update the cosigner key
    function registerPrivateKeyOffchain() public returns (bytes memory) {
        bytes memory keyData = Context.confidentialInputs();

        address[] memory peekers = new address[](1);
        peekers[0] = address(this);

        Suave.DataRecord memory record = Suave.newDataRecord(0, peekers, peekers, "private_key");
        Suave.confidentialStore(record.id, PRIVATE_KEY, keyData);

        return abi.encodeWithSelector(this.updateKeyOnchain.selector, record.id);
    }

    // Offchain/Onchain functions for updating webhooks

    function updateWebhookOnchain(Suave.DataId _webhookRecord) public emitOffchainLogs {
        webhookRecord = _webhookRecord;
    }

    function registerWebhookOffchain(string memory WEBHOOK_NAME) public returns (bytes memory) {
        bytes memory rpcData = Context.confidentialInputs();

        address[] memory peekers = new address[](1);
        peekers[0] = address(this);
        address[] memory setters = new address[](2);
        setters[0] = address(this);
        setters[1] = msg.sender;

        Suave.DataRecord memory record = Suave.newDataRecord(0, peekers, setters, "webhook_url");
        Suave.confidentialStore(record.id, WEBHOOK_NAME, rpcData);

        emit WebhookNameRegistered(WEBHOOK_NAME);

        return abi.encodeWithSelector(this.updateWebhookOnchain.selector, record.id);
    }

    event RFQResponse(string quote);
    event LogOrderId(bytes32 orderId);
    event WinningQuote(uint256 quote);
    event LogBytes(bytes data);

    event RevealCosignedOrder(CosignedUniswapXOrder order);

    function onchain() external payable emitOffchainLogs {}

    function offchain() external returns (bytes memory) {
        require(Suave.isConfidential(), "Execution must be confidential");

        bytes memory data = Context.confidentialInputs();

        UniswapXOrder memory order = abi.decode(data, (UniswapXOrder));

        // create public order
        PublicUniswapXOrder memory publicOrder = PublicUniswapXOrder({
            tokenIn: order.tokenIn,
            tokenOut: order.tokenOut,
            amount: order.amount,
            nonce: order.nonce,
            swapper: order.swapper
        });
        bytes32 orderId = getOrderId(publicOrder);

        emit LogOrderId(orderId);

        address[] memory allowedPeekers = new address[](1);
        allowedPeekers[0] = address(this);
        address[] memory allowedStores = new address[](1);
        allowedStores[0] = address(this);

        // save the order's signature to CS
        Suave.DataRecord memory record = Suave.newDataRecord(0, allowedPeekers, allowedStores, "order_key");
        Suave.confidentialStore(
            record.id,
            // use the order id as key
            LibString.toHexString(uint256(orderId)),
            order.signature
        );

        uint256 bestQuote = publicOrder.amount;
        for (uint256 i = 0; i < 5; i++) {
            // bytes memory rpcData = Suave.confidentialRetrieve(webhookRecord, webhooks[i]);
            // string memory endpoint = bytesToString(rpcData);

            Webhook webhook = new Webhook();

            string memory response = webhook.get();
            uint256 quote = stringToUint(response);
            if (quote > bestQuote) {
                bestQuote = quote;
            }

            emit RFQResponse(response);
        }
        emit WinningQuote(bestQuote);

        CosignerData memory cosignerData = CosignerData({amountOverride: bestQuote});
        CosignedUniswapXOrder memory cosignedOrder = cosignOrder(record.id, publicOrder, cosignerData);

        emit RevealCosignedOrder(cosignedOrder);

        return abi.encodeWithSelector(this.onchain.selector);
    }

    function cosignOrder(
        Suave.DataId orderIdRecord,
        PublicUniswapXOrder memory publicOrder,
        CosignerData memory cosignerData
    ) internal returns (CosignedUniswapXOrder memory cosignedOrder) {
        bytes32 orderId = getOrderId(publicOrder);
        bytes memory foundSignature = Suave.confidentialRetrieve(orderIdRecord, LibString.toHexString(uint256(orderId)));
        UniswapXOrder memory order = UniswapXOrder({
            tokenIn: publicOrder.tokenIn,
            tokenOut: publicOrder.tokenOut,
            amount: publicOrder.amount,
            nonce: publicOrder.nonce,
            swapper: publicOrder.swapper,
            signature: foundSignature
        });

        // // Sign over the orderId using the stored cosignerKey
        // bytes memory cosignerKey = Suave.confidentialRetrieve(cosignerKeyRecord, PRIVATE_KEY);
        // string memory cosignerKeyString = bytesToString(cosignerKey);

        // bytes memory digest = bytes.concat(orderId); // TODO: sign over cosigner data

        // bytes memory cosignature = Suave.signMessage(digest, Suave.CryptoSignature.SECP256, cosignerKeyString);

        bytes memory cosignature = new bytes(0);

        cosignedOrder = CosignedUniswapXOrder({order: order, cosignature: cosignature, cosignerData: cosignerData});
    }

    // Returns the order ID used to look up a uniswapX order.
    function getOrderId(PublicUniswapXOrder memory order) internal pure returns (bytes32 orderId) {
        orderId = keccak256(abi.encode(order.tokenIn, order.tokenOut, order.amount, order.nonce, order.swapper));
    }

    function bytesToString(bytes memory data) internal pure returns (string memory) {
        uint256 length = data.length;
        bytes memory chars = new bytes(length);

        for (uint256 i = 0; i < length; i++) {
            chars[i] = data[i];
        }

        return string(chars);
    }

    function stringToUint(string memory s) public pure returns (uint256) {
        bytes memory b = bytes(s);
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            uint256 c = uint256(uint8(b[i]));
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            }
        }
        return result;
    }
}
