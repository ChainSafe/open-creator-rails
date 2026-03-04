// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAsset} from "./IAsset.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAssetRegistry} from "./IAssetRegistry.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

/// @title Asset
/// @notice Implementation of IAsset: a subscription-gated asset with permit-based ERC20 payment.
///         Deployed by the asset registry; subscription revenue is split between creator (owner) and registry.
contract Asset is Ownable, ReentrancyGuard, IAsset {
    using EnumerableSet for EnumerableSet.AddressSet;
    bytes32 internal immutable ASSET_ID;
    address internal immutable REGISTRY_ADDRESS;

    IAssetRegistry internal immutable ASSET_REGISTRY;

    address internal immutable TOKEN_ADDRESS;
    IERC20 internal immutable TOKEN_CONTRACT;
    IERC20Permit internal immutable TOKEN_PERMIT_CONTRACT;

    mapping(bytes32 => Subscription) internal subscriptions;
    mapping(address => uint256) internal nonces;

    mapping(address => uint256) internal creatorClaimedAt;
    mapping(address => uint256) internal registryClaimedAt;

    EnumerableSet.AddressSet internal subscribers;

    uint256 internal subscriptionPrice;

    struct Subscription {
        uint256 startTime;
        uint256 endTime;
        uint256 subscriptionPrice;
    }

    error InvalidOwner();
    error InvalidTokenAddress();
    error InvalidSpender();
    error PermitFailed();
    error SubscriptionFailed();
    error InsufficientFunds();
    error CreatorClaimFailed();
    error RegistryClaimFailed();
    error SubscriptionNotFound();
    error SubscriptionRevocationFailed();
    error SubscriptionCancellationFailed();
    error OnlyRegistryUnauthorizedAccount();
    error OnlyRegistryOrOwnerUnauthorizedAccount();

    event SubscriptionAdded(address indexed user, uint256 indexed startTime, uint256 indexed endTime, uint256 nonce);
    event CreatorFeeClaimed(address indexed user, uint256 amount);
    event SubscriptionPriceUpdated(uint256 newSubscriptionPrice);
    event SubscriptionRevoked(address indexed user);
    event SubscriptionCancelled(address indexed user);
    
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

    function _getSubscription(address user) internal view returns (uint256) {
        
        return subscriptions[_hash(user, nonces[user])].endTime;
    }

    function getSubscription(address user) external onlyRegistryOrOwner view returns (uint256) {
        return _getSubscription(user);
    }

    function getMySubscription() external view returns (uint256) {
        return _getSubscription(msg.sender);
    }

    function _viewSubscription(address user) internal view returns (bool) {
        return _getSubscription(user) > block.timestamp;
    }

    function viewMySubscription() external view returns (bool) {
        return _viewSubscription(msg.sender);
    }

    function viewSubscription(address user) external onlyRegistryOrOwner view returns (bool) {
        return _viewSubscription(user);
    }

    function subscribe(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external nonReentrant returns (uint256) {

        if (spender != address(this)) {
            revert InvalidSpender();
        }
        
        try TOKEN_PERMIT_CONTRACT.permit(owner, address(this), value, deadline, v, r, s) {
            
            value -= value % subscriptionPrice;

            if (value < subscriptionPrice) {
                revert InsufficientFunds();
            }

            bool success = TOKEN_CONTRACT.transferFrom(owner, address(this), value);

            if (!success) {
                revert SubscriptionFailed();
            }
        }
        catch {
            revert PermitFailed();
        }

        uint256 duration = value / subscriptionPrice;

        uint256 startTime = block.timestamp;

        uint256 nonce = nonces[owner];

        bytes32 id = _hash(owner, nonce);

        if (subscribers.contains(owner)) {
            
            Subscription memory subscription = subscriptions[id];

            // If the previous subscription is still active, use the end time of the previous subscription's Expiry as the new Subscription's start time
            startTime = Math.max(startTime, subscription.endTime);

            nonce = ++nonces[owner];

            id = _hash(owner, nonce);
        }

        uint256 endTime = startTime + duration;

        subscriptions[id] = Subscription({startTime: startTime, endTime: endTime, subscriptionPrice: subscriptionPrice});

        subscribers.add(owner);

        emit SubscriptionAdded(owner, startTime, endTime, nonce);

        return endTime;
    }

    function _claimable(address subscriber, uint256 claimedAt) internal view returns (uint256) {
        
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

            claimable += (endTime - startTime) * subscription.subscriptionPrice;
        }

        return claimable;
    }

    function claimCreatorFee(address subscriber) onlyOwner external nonReentrant returns (uint256 creatorFee) {
        
        uint256 claimable = _claimable(subscriber, creatorClaimedAt[subscriber]);
        
        creatorFee = ASSET_REGISTRY.getCreatorFee(claimable);
        
        bool success = TOKEN_CONTRACT.transfer(owner(), creatorFee);

        if (!success) {
            revert CreatorClaimFailed();
        }

        creatorClaimedAt[subscriber] = block.timestamp;

        emit CreatorFeeClaimed(subscriber, creatorFee);

        return creatorFee;
    }

    function claimRegistryFee(address subscriber) onlyRegistry external nonReentrant returns (uint256 registryFee) {
        
        uint256 claimable = _claimable(subscriber, registryClaimedAt[subscriber]);

        registryFee = ASSET_REGISTRY.getRegistryFee(claimable);

        bool success = TOKEN_CONTRACT.transfer(ASSET_REGISTRY.getOwner(), registryFee);
        
        if (!success) {
            revert RegistryClaimFailed();
        }

        registryClaimedAt[subscriber] = block.timestamp;

        return registryFee;
    }

    function _removeSubscription(address user) internal nonReentrant returns (bool) {
        
        if (!subscribers.contains(user)) {
            revert SubscriptionNotFound();
        }
        
        uint256 nonce = nonces[user];

        uint256 returnable = 0;

        uint256 deleted = 0;

        for (uint256 i = 0; i < nonce + 1; i++) {
            
            bytes32 id = _hash(user, i);
            
            Subscription memory subscription = subscriptions[id];

            // If the subscription has not started yet, delete it, add the returnable amount to the returnable total and update the nonce
            if (subscription.startTime >= block.timestamp) {
                
                returnable += (subscription.endTime - subscription.startTime) * subscription.subscriptionPrice;

                delete subscriptions[id];

                deleted++;
            }

            // If the subscription is active, add the returnable amount to the returnable total and update the subscription
            else if (subscription.endTime > block.timestamp) {
               returnable += (subscription.endTime - block.timestamp) * subscription.subscriptionPrice;

               subscriptions[id].endTime = block.timestamp;
            }
        }

        // If the user has deleted all of their subscriptions, delete the nonce and remove the user from the subscribers set
        if (deleted == nonce + 1) {
            delete nonces[user];    
            subscribers.remove(user);
        }
        // If the user has subscriptions left, decrement the nonce by the number of deleted subscriptions
        else{
            nonces[user] -= deleted;
        }

        return returnable == 0 || TOKEN_CONTRACT.transfer(user, returnable);
    }

    function revokeSubscription(address user) external onlyOwner {
        bool success = _removeSubscription(user);

        if (!success) {
            revert SubscriptionRevocationFailed();
        }

        emit SubscriptionRevoked(user);
    }

    function cancelSubscription() external {

        address user = msg.sender;

        bool success = _removeSubscription(user);

        if (!success) {
            revert SubscriptionCancellationFailed();
        }

        emit SubscriptionCancelled(user);
    }

    function _hash(address a, uint256 b) internal pure returns (bytes32 result) {
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            result := keccak256(0x00, 0x40)
        }
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

    modifier onlyRegistryOrOwner() {
        _onlyRegistryOrOwner();
        _;
    }
    
    function _onlyRegistryOrOwner() internal view {
         if (msg.sender != REGISTRY_ADDRESS && msg.sender != owner()) {
             revert OnlyRegistryOrOwnerUnauthorizedAccount();
         }
     }
}