// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {GameToken} from "../src/GameToken.sol";
import {DeployScript} from "./Deploy.s.sol";

contract GameTokenScript is DeployScript {
    function mint(address to, uint256 amount) public {
        vm.startBroadcast();
        GameToken token = GameToken(getAddress(".GameToken"));
        token.mint(to, amount);
        vm.stopBroadcast();
    }
}