// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import "suave-std/Suapp.sol";
import "suave-std/Context.sol";
import "suave-std/Gateway.sol";
import "suave-std/suavelib/Suave.sol";
import {Webhook} from "./lib/Webhook.sol";

contract UniswapXAuction is Suapp {
    Suave.DataId webhookRecord;

    event WebhookNameRegistered(string name);

    function updateWebhookOnchain(Suave.DataId _webhookRecord) public emitOffchainLogs {
        webhookRecord = _webhookRecord;
    }

    function registerWebhookOffchain(string memory WEBHOOK_NAME) public returns (bytes memory) {
        bytes memory rpcData = Context.confidentialInputs();

        address[] memory peekers = new address[](1);
        peekers[0] = address(this);
        address [] memory setters = new address[](2);
        setters[0] = address(this);
        setters[1] = msg.sender;

        Suave.DataRecord memory record = Suave.newDataRecord(0, peekers, setters, "webhook_url");
        Suave.confidentialStore(record.id, WEBHOOK_NAME, rpcData);

        emit WebhookNameRegistered(WEBHOOK_NAME);

        return abi.encodeWithSelector(this.updateWebhookOnchain.selector, record.id);
    }

    event RFQResponse(string quote);
    event WinningQuote(uint256 quote);

    function onchain() external payable emitOffchainLogs {}

    function offchain() external returns (bytes memory) {
        // An offchain request must contain which webhooks to call
        bytes memory data = Context.confidentialInputs();
        uint256 bestQuote = 0;
        for(uint i = 0; i < 5; i++) {
            // bytes memory rpcData = Suave.confidentialRetrieve(webhookRecord, WEBHOOK_NAMES[i]);
            // string memory endpoint = bytesToString(rpcData);

            Webhook webhook = new Webhook();

            string memory response = webhook.get();
            uint256 quote = stringToUint(response);
            if(quote > bestQuote) {
                bestQuote = quote;
            }

            emit RFQResponse(response);
        }
        emit WinningQuote(bestQuote);
        
        return abi.encodeWithSelector(this.onchain.selector);
    }

    function bytesToString(bytes memory data) internal pure returns (string memory) {
        uint256 length = data.length;
        bytes memory chars = new bytes(length);

        for(uint i = 0; i < length; i++) {
            chars[i] = data[i];
        }

        return string(chars);
    }

    function stringToUint(string memory s) public pure returns (uint) {
        bytes memory b = bytes(s);
        uint result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            uint256 c = uint256(uint8(b[i]));
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            }
        }
        return result;
    }
}