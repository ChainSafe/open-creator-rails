// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAsset} from "./IAsset.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAssetRegistry} from "./IAssetRegistry.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

/// @title Asset
/// @notice Implementation of IAsset: a subscription-gated asset with permit-based ERC20 payment.
///         Deployed by the asset registry; subscription revenue is split between creator (owner) and registry.
contract Asset is Ownable, ReentrancyGuard, IAsset {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    bytes32 internal immutable ASSET_ID;
    address internal immutable REGISTRY_ADDRESS;

    IAssetRegistry internal immutable ASSET_REGISTRY;

    address internal immutable TOKEN_ADDRESS;
    IERC20 internal immutable TOKEN_CONTRACT;
    IERC20Permit internal immutable TOKEN_PERMIT_CONTRACT;

    mapping(bytes32 => Subscription) internal subscriptions;
    mapping(bytes32 => uint256) internal nonces;

    mapping(bytes32 => uint256) internal creatorClaimedAt;
    mapping(bytes32 => uint256) internal registryClaimedAt;

    EnumerableSet.Bytes32Set internal subscribers;

    uint256 internal subscriptionPrice;

    struct Subscription {
        uint256 startTime;
        uint256 endTime;
        uint256 subscriptionPrice;
        uint256 creatorFeeShare;
        uint256 registryFeeShare;
        uint256 totalFeeShare;
        address payer;
    }

    error InvalidOwner();
    error InvalidTokenAddress();
    error InvalidSpender();
    error PermitFailed();
    error InsufficientFunds();
    error SubscriptionNotFound();
    error SubscriptionRevocationFailed();
    error SubscriptionCancellationFailed();
    error OnlyRegistryUnauthorizedAccount();

    event SubscriptionAdded(bytes32 indexed subscriber, uint256 indexed startTime, uint256 indexed endTime, uint256 nonce, address payer);
    event CreatorFeeClaimed(bytes32 indexed subscriber, uint256 amount);
    event SubscriptionPriceUpdated(uint256 newSubscriptionPrice);
    event SubscriptionRevoked(bytes32 indexed subscriber);
    event SubscriptionCancelled(bytes32 indexed subscriber);
    
    /// @notice Initializes the asset with id, price, payment token, and owner. Callable only by the registry (msg.sender).
    /// @param _assetId Unique identifier for this asset.
    /// @param _subscriptionPrice Price per subscription period in seconds.
    /// @param _tokenAddress ERC20 (with permit) used for subscription payments.
    /// @param _owner Creator/owner of the asset; receives creator share of subscription fees.
    constructor(bytes32 _assetId, uint256 _subscriptionPrice, address _tokenAddress, address _owner) Ownable(_owner) {
        ASSET_ID = _assetId;
        subscriptionPrice = _subscriptionPrice;

        if (_owner == address(0)) {
            revert InvalidOwner();
        }

        if (_tokenAddress == address(0)) {
            revert InvalidTokenAddress();
        }

        TOKEN_ADDRESS = _tokenAddress;

        TOKEN_CONTRACT = IERC20(TOKEN_ADDRESS);
        TOKEN_PERMIT_CONTRACT = IERC20Permit(TOKEN_ADDRESS);

        REGISTRY_ADDRESS = msg.sender;
        ASSET_REGISTRY = IAssetRegistry(REGISTRY_ADDRESS);
    }

    function getAssetId() external view returns (bytes32) {
        return ASSET_ID;
    }

    function getRegistryAddress() external view returns (address) {
        return REGISTRY_ADDRESS;
    }

    function getTokenAddress() external view returns (address) {
        return TOKEN_ADDRESS;
    }

    function setSubscriptionPrice(uint256 newSubscriptionPrice) external onlyOwner {
        subscriptionPrice = newSubscriptionPrice;
        emit SubscriptionPriceUpdated(newSubscriptionPrice);
    }

    function getSubscriptionPrice(uint256 duration) external view returns (uint256) {
        return subscriptionPrice * duration;
    }

    function _getSubscription(bytes32 subscriber) internal view returns (uint256) {
        
        return subscriptions[_hash(subscriber, nonces[subscriber])].endTime;
    }

    function getSubscription(bytes32 subscriber) external view returns (uint256) {
        return _getSubscription(subscriber);
    }

    function isSubscriptionActive(bytes32 subscriber) external view returns (bool) {
        return _getSubscription(subscriber) > block.timestamp;
    }

    function subscribe(bytes32 subscriber, address payer, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external nonReentrant returns (uint256) {

        _validatePermit(payer, spender, value, deadline, v, r, s);

        return _subscribe(subscriber, payer, value);
    }

    function _subscribe(bytes32 subscriber, address payer, uint256 value) internal returns (uint256) {
        uint256 duration = value / subscriptionPrice;

        uint256 startTime = block.timestamp;

        uint256 nonce = nonces[subscriber];

        bytes32 id = _hash(subscriber, nonce);

        if (subscribers.contains(subscriber)) {
            
            Subscription memory subscription = subscriptions[id];

            // If the previous subscription is still active, use the end time of the previous subscription's Expiry as the new Subscription's start time
            startTime = Math.max(startTime, subscription.endTime);

            nonce = ++nonces[subscriber];

            id = _hash(subscriber, nonce);
        }

        uint256 endTime = startTime + duration;

        (uint256 creatorFeeShare, uint256 registryFeeShare, uint256 totalFeeShare) = ASSET_REGISTRY.getFeeShares();

        subscriptions[id] = Subscription({startTime: startTime, endTime: endTime, subscriptionPrice: subscriptionPrice, creatorFeeShare: creatorFeeShare, registryFeeShare: registryFeeShare, totalFeeShare: totalFeeShare, payer: payer});

        subscribers.add(subscriber);

        emit SubscriptionAdded(subscriber, startTime, endTime, nonce, payer);

        return endTime;
    }

    function _validatePermit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) internal {
        if (spender != address(this)) {
            revert InvalidSpender();
        }
        
        try TOKEN_PERMIT_CONTRACT.permit(owner, address(this), value, deadline, v, r, s) {
            
            value -= value % subscriptionPrice;

            if (value < subscriptionPrice) {
                revert InsufficientFunds();
            }

            SafeERC20.safeTransferFrom(TOKEN_CONTRACT, owner, address(this), value);
        }
        catch {
            revert PermitFailed();
        }
    }

    function _claimable(bytes32 subscriber, uint256 claimedAt) internal view returns (uint256) {
        
        uint256 nonce = nonces[subscriber];
        
        uint256 claimable = 0;

        for (uint256 i = 0; i < nonce + 1; i++) {
            
            bytes32 id = _hash(subscriber, i);
            
            Subscription memory subscription = subscriptions[id];

            // If the subscription has not started yet, break the loop since all subsequent subscriptions will also not have started yet
            if (subscription.startTime >= block.timestamp) {
                break;
            }

            // If the subscription has already been claimed, continue to the next subscription
            if (subscription.endTime <= claimedAt) {
                continue;
            }

            uint256 startTime = Math.max(subscription.startTime, claimedAt);

            uint256 endTime = Math.min(subscription.endTime, block.timestamp);

            uint256 fee = (endTime - startTime) * subscription.subscriptionPrice;

            uint256 registryFee = (fee * subscription.registryFeeShare) / subscription.totalFeeShare;

            if (_isOwner()) {
                claimable += (fee - registryFee);
            }
            else if (_isRegistry()) {
                claimable += registryFee;
            }
        }

        return claimable;
    }

    function claimCreatorFee(bytes32 subscriber) onlyOwner external nonReentrant returns (uint256 creatorFee) {
        
        creatorFee = _claimable(subscriber, creatorClaimedAt[subscriber]);
        
        SafeERC20.safeTransfer(TOKEN_CONTRACT, owner(), creatorFee);

        creatorClaimedAt[subscriber] = block.timestamp;

        emit CreatorFeeClaimed(subscriber, creatorFee);

        return creatorFee;
    }

    function claimRegistryFee(bytes32 subscriber) onlyRegistry external nonReentrant returns (uint256 registryFee) {
        
        registryFee = _claimable(subscriber, registryClaimedAt[subscriber]);

        SafeERC20.safeTransfer(TOKEN_CONTRACT, ASSET_REGISTRY.getOwner(), registryFee);

        registryClaimedAt[subscriber] = block.timestamp;

        return registryFee;
    }

    function _removeSubscription(bytes32 subscriber) internal nonReentrant {
        
        if (!subscribers.contains(subscriber)) {
            revert SubscriptionNotFound();
        }
        
        uint256 nonce = nonces[subscriber];

        uint256 deleted = 0;

        for (uint256 i = 0; i < nonce + 1; i++) {
            
            bytes32 id = _hash(subscriber, i);
            
            Subscription memory subscription = subscriptions[id];

            // If caller isn't the assetowner or subscription payer, continue to the next subscription
            if (!_isOwner() && subscription.payer != msg.sender) {
                continue;
            }

            uint256 returnable = 0;

            // If the subscription has not started yet, delete it, add the returnable amount to the returnable total and update the nonce
            if (subscription.startTime >= block.timestamp) {
                
                returnable = (subscription.endTime - subscription.startTime) * subscription.subscriptionPrice;

                delete subscriptions[id];

                deleted++;
            }

            // If the subscription is active, add the returnable amount to the returnable total and update the subscription
            else if (subscription.endTime > block.timestamp) {
               returnable = (subscription.endTime - block.timestamp) * subscription.subscriptionPrice;

               subscriptions[id].endTime = block.timestamp;
            }

            if (returnable != 0) {
                SafeERC20.safeTransfer(TOKEN_CONTRACT, subscription.payer, returnable);
            }
        }

        // If the user has deleted all of their subscriptions, delete the nonce and remove the user from the subscribers set
        if (deleted == nonce + 1) {
            delete nonces[subscriber];    
            subscribers.remove(subscriber);
        }
        // If the user has subscriptions left, decrement the nonce by the number of deleted subscriptions
        else{
            nonces[subscriber] -= deleted;
        }
    }

    function revokeSubscription(bytes32 subscriber) external onlyOwner {
        _removeSubscription(subscriber);

        emit SubscriptionRevoked(subscriber);
    }

    function cancelSubscription(bytes32 subscriber) external {
        _removeSubscription(subscriber);
        
        emit SubscriptionCancelled(subscriber);
    }

    function _hash(bytes32 a, uint256 b) internal pure returns (bytes32 result) {
        result = keccak256(abi.encode(a, b));
        return result;
    }

    function _isOwner() internal view returns (bool) {
        return msg.sender == owner();
    }

    function _isRegistry() internal view returns (bool) {
        return msg.sender == REGISTRY_ADDRESS;
    }

     modifier onlyRegistry() {
        _onlyRegistry();
        _;
    }

    function _onlyRegistry() internal view {
        if (msg.sender != REGISTRY_ADDRESS) {
            revert OnlyRegistryUnauthorizedAccount();
        }
    }
}