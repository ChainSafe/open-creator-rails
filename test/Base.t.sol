// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {GameToken} from "../src/GameToken.sol";

contract BaseTest is Test {
    GameToken public gameToken;

    bytes32 internal constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    string internal constant MNEMONIC = "test test test test test test test test test test test junk";

    address internal signer;
    uint256 internal key;

    function setUp() public virtual {
        gameToken = new GameToken();

        key = vm.deriveKey(MNEMONIC, 0);
        signer = vm.addr(key);

        vm.startPrank(signer);

        gameToken.mint(signer, 1000000000000000000000000000000000000000);
    }

    function getPermit(address owner, address spender, uint256 value, uint256 deadline) public view returns (uint8 v, bytes32 r, bytes32 s) {
        
        uint256 nonce = gameToken.nonces(owner);

        bytes32 hash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", gameToken.DOMAIN_SEPARATOR(), hash)
        );

        (v, r, s) = vm.sign(key, digest);

        return (v, r, s);
    }
}