// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract UtilsScript is Script {

    bytes32 internal constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function signPermit(uint256 value, address spender, uint256 duration, address tokenAddress, uint256 privateKey) public view returns (uint8 v, bytes32 r, bytes32 s, uint256 deadline, address owner) {
        
        owner = vm.addr(privateKey);

        IERC20Permit token = IERC20Permit(tokenAddress);

        uint256 nonce = token.nonces(owner);

        deadline = block.timestamp + duration;

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        (v, r, s) = vm.sign(privateKey, digest);

        return (v, r, s, deadline, owner);
    }
}