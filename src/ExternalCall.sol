// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import "suave-std/Suapp.sol";
import "suave-std/Context.sol";
import "suave-std/Gateway.sol";

interface ERC20 {
    function balanceOf(address) external view returns (uint256);
}

contract ExternalCall is Suapp {
    Suave.DataId rpcRecord;
    string public RPC = "RPC";

    function updateKeyOnchain(Suave.DataId _rpcRecord) public {
        rpcRecord = _rpcRecord;
    }

    function registerKeyOffchain() public returns (bytes memory) {
        bytes memory rpcData = Context.confidentialInputs();

        address[] memory peekers = new address[](1);
        peekers[0] = address(this);

        Suave.DataRecord memory record = Suave.newDataRecord(0, peekers, peekers, "rpc_endpoint");
        Suave.confidentialStore(record.id, RPC, rpcData);

        return abi.encodeWithSelector(this.updateKeyOnchain.selector, record.id);
    }

    event Balance(uint256 value);

    function onchain() external payable emitOffchainLogs {}

    function offchain(address contractAddr, address account) external returns (bytes memory) {
        bytes memory rpcData = Suave.confidentialRetrieve(rpcRecord, RPC);
        string memory endpoint = bytesToString(rpcData);
        
        Gateway gateway = new Gateway(endpoint, contractAddr);
        ERC20 token = ERC20(address(gateway));
        uint256 balance = token.balanceOf(account);
        emit Balance(balance);

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
}