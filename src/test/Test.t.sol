// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

contract TestEncode is Test {

    struct RFQRequest {
        address tokenIn;
        string[] webhooks;
    }

    function setUp() public {

    }

    event Log(bytes data);

    function testEncodeStringArray() public {
        string[] memory webhooks = new string[](2);
        webhooks[0] = "A";
        webhooks[1] = "B";

        emit Log(abi.encode(webhooks));
    }

    function testEncodeStruct() public {
        string[] memory webhooks = new string[](2);
        webhooks[0] = "webhook1";
        webhooks[1] = "webhook2";

        RFQRequest memory rfqRequest = RFQRequest({
            tokenIn: address(0),
            webhooks: webhooks
        });
        emit Log(abi.encode(rfqRequest));
    }
}