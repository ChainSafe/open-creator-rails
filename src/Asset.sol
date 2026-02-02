// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAsset} from "./IAsset.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Asset is Ownable, IAsset {
    bytes32 internal immutable ASSET_ID;
    uint256 internal immutable SUBSCRIPTION_PRICE;
    address internal immutable TOKEN_ADDRESS;

    mapping(address => uint256) internal subscriptions;
        
    error InvalidSpender();
    error PermitFailed();
    error SubscriptionFailed();

    event SubscriptionAdded(address indexed user, uint256 expiresAt);
    event SubscriptionRevoked(address indexed user);
    
    constructor(bytes32 _assetId, uint256 _subscriptionPrice, address _tokenAddress) Ownable(msg.sender) {
        ASSET_ID = _assetId;
        SUBSCRIPTION_PRICE = _subscriptionPrice;
        TOKEN_ADDRESS = _tokenAddress;
    }

    function getAssetId() external view returns (bytes32) {
        return ASSET_ID;
    }

    function getSubscriptionPrice(uint256 duration) external view returns (uint256) {
        return SUBSCRIPTION_PRICE * duration;
    }

    function getSubscription(address user) external view returns (uint256) {
        return subscriptions[user];
    }

    function viewSubscription(address user) external view returns (bool) {
        return subscriptions[user] > block.timestamp;
    }

    function subscribe(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external returns (bool) {
        
        if (spender != address(this)) {
            revert InvalidSpender();
        }
        
        IERC20Permit tokenPermit = IERC20Permit(TOKEN_ADDRESS);
        IERC20 tokenContract = IERC20(TOKEN_ADDRESS); 

        try tokenPermit.permit(owner, address(this), value, deadline, v, r, s) {
            
            value -= value % SUBSCRIPTION_PRICE;

            bool success = tokenContract.transferFrom(owner, this.owner(), value);
            
            if (!success) {
                revert SubscriptionFailed();
            }
        }
        catch {
            revert PermitFailed();
        }

        uint256 duration = value / SUBSCRIPTION_PRICE;

        subscriptions[owner] = block.timestamp + duration;

        emit SubscriptionAdded(owner, subscriptions[owner]);

        return true;
    }

    function revokeSubscription(address user) external onlyOwner returns (bool) {
        uint256 duration = subscriptions[user];
        if (duration == 0) {
            return false;
        }
        delete subscriptions[user];
        emit SubscriptionRevoked(user);
        return true;
    }
}