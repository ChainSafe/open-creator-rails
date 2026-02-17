// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {GameToken} from "../src/GameToken.sol";
import {DeployScript} from "./Deploy.s.sol";

/// @title GameTokenScript
/// @notice Scripts for interacting with the deployed GameToken contract.
/// @dev Usage: run with `./script/run.sh GameToken "<signature>" <args...>`.
///      For address arguments you can use $(get_address "ContractName") after running `source ./script/utils.sh` to get addresses from deployments.json.
contract GameTokenScript is DeployScript {
    /// @notice Mints tokens to an address.
    /// @dev Usage: ./script/run.sh GameToken "mint(address,uint256)" <to> <amount>
    ///      Example: ./script/run.sh GameToken "mint(address,uint256)" $(get_address "GameToken") 1000000
    function mint(address to, uint256 amount) public {
        vm.startBroadcast();
        GameToken token = GameToken(getAddress(".GameToken"));
        token.mint(to, amount);
        vm.stopBroadcast();
    }
}