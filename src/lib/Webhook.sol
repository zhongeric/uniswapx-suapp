// SPDX-License-Identifier: Unlicense
// inspired by https://github.com/flashbots/suave-std/blob/main/src/protocols/ChatGPT.sol
pragma solidity ^0.8.13;

import "suave-std/suavelib/Suave.sol";
import "solady/src/utils/JSONParserLib.sol";
import "solady/src/utils/LibString.sol";

/// @notice Webhook is a library with utilities to make requests to provided webhooks.
contract Webhook {
    using JSONParserLib for *;

    struct RFQRequest {
        address tokenIn;
        address tokenOut;
    }

    /// @notice constructor to create a Webhook instance.
    constructor() {}

    function get() public returns (string memory) {
        Suave.HttpRequest memory request;
        request.method = "GET";
        request.url = "https://mock-mm-zhongerics-projects.vercel.app/api/quote";
        request.headers = new string[](1);
        request.headers[0] = "Content-Type: application/json";

        bytes memory output = Suave.doHTTPRequest(request);

        // decode responses
        JSONParserLib.Item memory item = string(output).parse();
        string memory result = item.at('"quote"').value();

        return result;
    }

    /**
     * Notify registered webhooks via a standard json rpc schema
     */
    function post(string memory endpoint, bytes memory data) public {
        Suave.HttpRequest memory request;
        request.method = "POST";
        request.url = endpoint;
        request.headers = new string[](1);
        request.headers[0] = "Content-Type: application/json";
        request.body = abi.encodePacked(
            '{"jsonrpc":"2.0","method":"uniswapx_wonOrder,"params":[{"data":"',
            LibString.toHexString(data),
            '"},"latest"],"id":1}'
        );

        Suave.doHTTPRequest(request);
    }

    function trimQuotes(string memory input) private pure returns (string memory) {
        bytes memory inputBytes = bytes(input);
        require(
            inputBytes.length >= 2 && inputBytes[0] == '"' && inputBytes[inputBytes.length - 1] == '"', "Invalid input"
        );

        bytes memory result = new bytes(inputBytes.length - 2);

        for (uint256 i = 1; i < inputBytes.length - 1; i++) {
            result[i - 1] = inputBytes[i];
        }

        return string(result);
    }
}
