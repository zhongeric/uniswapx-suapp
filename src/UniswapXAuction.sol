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
    uint256 auctionStartTime;
    uint256 auctionEndTime;
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

contract UniswapXAuction is Suapp {
    Suave.DataId webhookRecord;
    Suave.DataId cosignerKeyRecord;
    Suave.DataId orderSignaturesRecord;

    string public PRIVATE_KEY = "KEY";

    event WebhookNameRegistered(string name);

    struct OrderBid {
        uint256 quote;
        address filler;
    }

    mapping(bytes32 orderId => UniswapXOrder) private _orders;
    mapping(bytes32 orderId => OrderBid) private _orderBids;

    event RFQResponse(string quote);
    event LogOrderId(bytes32 orderId);
    event WinningQuote(uint256 quote);
    event LogBytes(bytes data);

    event RevealCosignedOrder(CosignedUniswapXOrder order);

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
    function updateWebhookOnchain(Suave.DataId _webhookRecord) public {
        webhookRecord = _webhookRecord;
    }

    /// @notice registers a webhook to the submitting filler
    function registerWebhookOffchain() public returns (bytes memory) {
        bytes memory rpcData = Context.confidentialInputs();

        address[] memory peekers = new address[](1);
        peekers[0] = address(this);
        address[] memory setters = new address[](2);
        setters[0] = address(this);
        setters[1] = msg.sender;

        Suave.DataRecord memory record = Suave.newDataRecord(0, peekers, setters, "webhook_url");
        Suave.confidentialStore(record.id, LibString.toHexString(uint256(uint160(msg.sender))), rpcData);

        return abi.encodeWithSelector(this.updateWebhookOnchain.selector, record.id);
    }

    function newOrderOnchain(Suave.DataId _orderSignaturesRecord) external payable emitOffchainLogs {
        orderSignaturesRecord = _orderSignaturesRecord;
    }

    function newOrderOffChain(bytes memory data) external returns (bytes memory) {
        require(Suave.isConfidential(), "Execution must be confidential");

        // bytes memory data = Context.confidentialInputs();
        UniswapXOrder memory order = abi.decode(data, (UniswapXOrder));

        // remove the signature from the order
        bytes memory signature = order.signature;
        order.signature = bytes("");

        bytes32 orderId = _getOrderId(order);

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
            signature
        );

        return abi.encodeWithSelector(this.newOrderOnchain.selector, record.id);
    }

    function bidOrderOffchain() external {
        require(Suave.isConfidential(), "Execution must be confidential");

        bytes memory data = Context.confidentialInputs();
        (bytes32 orderId, uint256 quote) = abi.decode(data, (bytes32, uint256));

        require(block.timestamp >= _orders[orderId].auctionStartTime, "Auction has not started yet");
        require(block.timestamp < _orders[orderId].auctionEndTime, "Auction has ended for order");

        // register new bid if better than last
        if (quote > _orderBids[orderId].quote) {
            OrderBid memory bid = OrderBid(quote, msg.sender);
            _orderBids[orderId] = bid;
        }
    }

    function finalizeOrderOffChain() external {
        // TODO: require confidential?

        bytes memory data = Context.confidentialInputs();
        (bytes32 orderId) = abi.decode(data, (bytes32));

        require(block.timestamp >= _orders[orderId].auctionEndTime, "Order cannot be finalized yet");

        OrderBid memory winningBid = _orderBids[orderId];
        bytes memory rpcData =
            Suave.confidentialRetrieve(webhookRecord, LibString.toHexString(uint256(uint160(winningBid.filler))));
        string memory endpoint = bytesToString(rpcData);

        CosignerData memory cosignerData = CosignerData({amountOverride: winningBid.quote});
        CosignedUniswapXOrder memory cosignedOrder = _cosignOrder(orderId, cosignerData);

        Webhook webhook = new Webhook();
        webhook.post(endpoint, encode(cosignedOrder));

        emit RevealCosignedOrder(cosignedOrder);
    }

    function _cosignOrder(bytes32 orderId, CosignerData memory cosignerData)
        internal
        returns (CosignedUniswapXOrder memory cosignedOrder)
    {
        UniswapXOrder memory publicOrder = _orders[orderId];
        bytes memory foundSignature =
            Suave.confidentialRetrieve(orderSignaturesRecord, LibString.toHexString(uint256(orderId)));
        publicOrder.signature = foundSignature;

        // Sign over the orderId using the stored cosignerKey
        bytes memory cosignerKey = Suave.confidentialRetrieve(cosignerKeyRecord, PRIVATE_KEY);
        string memory cosignerKeyString = bytesToString(cosignerKey);

        bytes memory digest = bytes.concat(orderId); // TODO: sign over cosigner data
        bytes memory cosignature = Suave.signMessage(digest, Suave.CryptoSignature.SECP256, cosignerKeyString);

        cosignedOrder =
            CosignedUniswapXOrder({order: publicOrder, cosignature: cosignature, cosignerData: cosignerData});
    }

    // Returns the order ID used to look up a uniswapX order.
    function _getOrderId(UniswapXOrder memory order) internal pure returns (bytes32 orderId) {
        orderId = keccak256(
            abi.encode(
                order.tokenIn,
                order.tokenOut,
                order.amount,
                order.nonce,
                order.swapper,
                order.auctionStartTime,
                order.auctionEndTime
            )
        );
    }

    /// @notice simple hacky encoding
    function encode(CosignedUniswapXOrder memory order) public pure returns (bytes memory) {
        return (
            abi.encode(
                order.order,
                order.cosignerData
            )
        );
    }

    function bytesToString(bytes memory data) internal pure returns (string memory) {
        uint256 length = data.length;
        bytes memory chars = new bytes(length);

        for (uint256 i = 0; i < length; i++) {
            chars[i] = data[i];
        }

        return string(chars);
    }

    function _stringToUint(string memory s) internal pure returns (uint256) {
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
