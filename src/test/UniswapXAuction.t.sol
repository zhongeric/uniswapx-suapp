// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "suave-std/Test.sol";
import "suave-std/suavelib/Suave.sol";

contract UniswapXAuctionTest is Test, SuaveEnabled {
    struct RFQRequest {
        address tokenIn;
        string[] webhooks;
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

    function testConfidentialInputsWithStruct() public {
        bytes memory input = abi.encode(RFQRequest({
            tokenIn: address(0),
            webhooks: new string[](0)
        }));
        ctx.setConfidentialInputs(input);

        bytes memory found2 = Suave.confidentialInputs();
        assertEq0(input, found2);
    }
}