// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @title DeployScript
/// @notice Base deployment script; typically invoked via deploy.sh, not run.sh. Deploys s Smart Contract and adds it to deployments.json
/// @dev Usage (from repo root):
///      ./script/deploy.sh "<ContractName>" <ConstructorTypes> <ConstructorArgs>
///      ./script/deploy.sh -f "<ContractName>" <ConstructorTypes> <ConstructorArgs>   # force deploy a contract even if it's already deployed
///      For address arguments use $(get_address "ContractName") after running `source ./script/utils.sh` to get addresses from deployments.json.
///      Example: ./script/deploy.sh "AssetRegistry" "uint256,uint256" 80 20
contract DeployScript is Script {

    string internal constant DEPLOYMENTS_FILE = "deployments.json";
    
    function getAddress(string memory contractName) public view returns (address) {    
        return stdJson.readAddress(vm.readFile(DEPLOYMENTS_FILE), contractName);
    }

    /// @notice Generic deployment function that deploys any contract
    /// @param contractName The contract artifact path, e.g., "src/GameToken.sol:GameToken"
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