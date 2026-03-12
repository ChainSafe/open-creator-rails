// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";

// Test token for testing the asset registry and asset contracts
// It supports permit for testing the asset contract
// THIS IS NOT FOR PRODUCTION USE
contract TestToken is ERC20, ERC20Permit {

    string internal constant NAME = "Test Token";
    string internal constant SYMBOL = "TEST";
    
    constructor() ERC20(NAME, SYMBOL) ERC20Permit(NAME) {}

    // Mint tokens to an address, anyone can mint
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    // Decimals is 6
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}