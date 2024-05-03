// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "suave-std/Test.sol";
import "suave-std/Context.sol";
import "suave-std/suavelib/Suave.sol";

import {UniswapXOrder} from "../UniswapXAuction.sol";

contract UniswapXAuctionTest is Test, SuaveEnabled {
    event Log(bytes data);

    function testEncodeStringArray() public {
        string[] memory webhooks = new string[](2);
        webhooks[0] = "A";
        webhooks[1] = "B";

        emit Log(abi.encode(webhooks));
    }

    function testConfidentialInputsWithStruct() public {
        UniswapXOrder memory order = UniswapXOrder({
            tokenIn: address(0),
            tokenOut: address(1),
            amount: 100,
            nonce: 1,
            swapper: address(2),
            signature: new bytes(0)
        });
        bytes memory input = abi.encode(order);
        emit Log(input);
        ctx.setConfidentialInputs(input);

        bytes memory found2 = Context.confidentialInputs();
        assertEq0(input, found2);

        UniswapXOrder memory found = abi.decode(found2, (UniswapXOrder));
        assertEq(order.tokenIn, found.tokenIn);
    }
}
