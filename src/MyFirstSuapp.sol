// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.8;

import "suave-std/Suapp.sol";

contract MyFirstSuapp is Suapp { 
    event OffchainEvent(uint256 num);

    function onchain() public emitOffchainLogs {}

    function offchain() public returns (bytes memory) {
        emit OffchainEvent(1);
        emit OffchainEvent(2);
        
        /* This is where you will write all your compute-heavy,
        off-chain logic to be done in a Kettle */
        return abi.encodeWithSelector(this.onchain.selector);
    }
}