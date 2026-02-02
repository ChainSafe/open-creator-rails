// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";
import {IAsset} from "../src/IAsset.sol";
import {DeployScript} from "./Deploy.s.sol";
import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract SubscribeScript is DeployScript {

    bytes32 internal constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function signPermit(uint256 value, uint256 duration) public view returns (uint8 v, bytes32 r, bytes32 s, uint256 deadline, address owner) {
        
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        owner = vm.addr(privateKey);

        address tokenAddress = getAddress(".GameToken");
        
        IERC20Permit token = IERC20Permit(tokenAddress);

        address spender = getAddress(".Asset");

        uint256 nonce = token.nonces(owner);
        
        deadline = block.timestamp + duration;

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        (v, r, s) = vm.sign(privateKey, digest);

        console.log("v: ", vm.toString(v));
        console.log("r: ", vm.toString(r));
        console.log("s: ", vm.toString(s));
        console.log("deadline: ", vm.toString(deadline));
        console.log("owner: ", owner);
        
        return (v, r, s, deadline, owner);
    }

    function subscribe(uint256 value, uint256 duration) public {
        vm.startBroadcast();
        
        (uint8 v, bytes32 r, bytes32 s, uint256 deadline, address owner) = signPermit(value, duration);
        
        address spender = getAddress(".Asset");
        
        IAsset asset = IAsset(spender);
        
        asset.subscribe(owner, spender, value, deadline, v, r, s);
        
        vm.stopBroadcast();
    }
}