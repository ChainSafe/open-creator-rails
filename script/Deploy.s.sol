// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract DeployScript is Script {

    string internal constant DEPLOYMENTS_FILE = "deployments.json";
    
    function getAddress(string memory contractName) public view returns (address) {    
        return stdJson.readAddress(vm.readFile(DEPLOYMENTS_FILE), contractName);
    }

    /// @notice Generic deployment function that deploys any contract
    /// @param contractName The contract artifact path, e.g., "src/Counter.sol:Counter"
    /// @param constructorArgs ABI-encoded constructor arguments (use abi.encode(...))
    /// @return deployedAddress The address of the deployed contract
    function deploy(string memory contractName, bytes memory constructorArgs)
        public
        returns (address deployedAddress)
    {

        vm.startBroadcast();
        if (constructorArgs.length == 0) {
            deployedAddress = deployCode(contractName);
        } else {
            deployedAddress = deployCode(contractName, constructorArgs);
        }
        
        require(deployedAddress != address(0), "Deployment failed");
        
        vm.stopBroadcast();

        return deployedAddress;
    }
}