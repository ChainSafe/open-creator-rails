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
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title Asset
/// @notice Implementation of IAsset: a subscription-gated asset with permit-based ERC20 payment.
///         Deployed by the asset registry; subscription revenue is split between creator (owner) and registry.
contract Asset is Ownable, ReentrancyGuard, IAsset {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    bytes32 internal immutable ASSET_ID;
    address internal immutable REGISTRY_ADDRESS;
    uint256 internal immutable SUBSCRIPTION_DURATION;

    IAssetRegistry internal immutable ASSET_REGISTRY;

    address internal immutable TOKEN_ADDRESS;
    IERC20 internal immutable TOKEN_CONTRACT;

    mapping(bytes32 => Subscription) internal subscriptions;
    mapping(bytes32 => uint256) internal nonces;

    mapping(bytes32 => uint256) internal creatorClaimedAtTimestamps;
    mapping(bytes32 => uint256) internal creatorClaimedAtNonces;
    mapping(bytes32 => uint256) internal registryClaimedAtTimestamps;
    mapping(bytes32 => uint256) internal registryClaimedAtNonces;

    EnumerableSet.Bytes32Set internal subscribers;

    uint256 internal subscriptionPrice;

    struct Subscription {
        uint256 startTime;
        uint256 endTime;
        uint256 subscriptionPrice;
        uint256 registryFeeShare;
        address payer;
    }

    error InvalidOwner();
    error InvalidTokenAddress();
    error InvalidSubscriptionDuration();
    error InvalidSpender();
    error PermitFailed();
    error InsufficientFunds();
    error SubscriptionNotFound();
    error SubscriptionRevocationFailed();
    error SubscriptionCancellationFailed();
    error InvalidSignature();
    error OnlyRegistryUnauthorizedAccount();

    event SubscriptionAdded(
        bytes32 indexed subscriber,
        uint256 indexed startTime,
        uint256 indexed endTime,
        address payer,
        uint256 subscriptionPrice,
        uint256 registryFeeShare
    );

    event SubscriptionRenewed(
        bytes32 indexed subscriber,
        uint256 indexed startTime,
        uint256 indexed endTime,
        uint256 nonce,
        address payer,
        uint256 subscriptionPrice,
        uint256 registryFeeShare
    );

    event SubscriptionExtended(bytes32 indexed subscriber, uint256 indexed endTime);
    event CreatorFeeClaimed(bytes32 indexed subscriber, uint256 amount);
    event CreatorFeeClaimedBatch(bytes32[] indexed subscribers, uint256 totalAmount);
    event SubscriptionPriceUpdated(uint256 newSubscriptionPrice);
    event SubscriptionRevoked(bytes32 indexed subscriber, uint256 indexed nonce, uint256 indexed endTime);
    event SubscriptionCancelled(bytes32 indexed subscriber, uint256 indexed nonce, uint256 indexed endTime);
    event SubscriptionRemoved(bytes32 indexed subscriber);

    /// @notice Initializes the asset with id, price, payment token, and owner.
    ///         Callable only by the registry (msg.sender).
    /// @param _assetId Unique identifier for this asset.
    /// @param _subscriptionPrice Price per subscription period.
    /// @param _subscriptionDuration Fixed subscription period length in seconds; subscriptions must be whole multiples.
    /// @param _tokenAddress ERC20 (with permit) used for subscription payments.
    /// @param _owner Creator/owner of the asset; receives creator share of subscription fees.
    constructor(
        bytes32 _assetId,
        uint256 _subscriptionPrice,
        uint256 _subscriptionDuration,
        address _tokenAddress,
        address _owner
    ) Ownable(_owner) {
        if (_subscriptionDuration == 0) {
            revert InvalidSubscriptionDuration();
        }

        ASSET_ID = _assetId;
        subscriptionPrice = _subscriptionPrice;
        SUBSCRIPTION_DURATION = _subscriptionDuration;

        if (_owner == address(0)) {
            revert InvalidOwner();
        }

        if (_tokenAddress == address(0)) {
            revert InvalidTokenAddress();
        }

        TOKEN_ADDRESS = _tokenAddress;

        TOKEN_CONTRACT = IERC20(TOKEN_ADDRESS);

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

    function getSubscriptionPrice(uint256 count) external view returns (uint256) {
        return count * subscriptionPrice;
    }

    function getSubscriptionDuration() external view returns (uint256) {
        return SUBSCRIPTION_DURATION;
    }

    function getSubscriptionPriceAndDuration(uint256 count) external view returns (uint256 price, uint256 duration) {
        price = count * subscriptionPrice;
        duration = count * SUBSCRIPTION_DURATION;
    }

    function _getSubscription(bytes32 subscriber) internal view returns (uint256) {
        bytes32 id = _hash(subscriber, nonces[subscriber]);
        return subscriptions[id].endTime;
    }

    function getSubscription(bytes32 subscriber) external view returns (uint256) {
        return _getSubscription(subscriber);
    }

    function isSubscriptionActive(bytes32 subscriber) external view returns (bool) {
        return _getSubscription(subscriber) > block.timestamp;
    }

    function subscribe(
        bytes32 subscriber,
        address payer,
        address spender,
        uint256 count,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant returns (uint256) {
        if (count == 0) {
            revert InsufficientFunds();
        }

        _validatePermit(payer, spender, count * subscriptionPrice, deadline, v, r, s);

        return _subscribe(subscriber, payer, count);
    }

    function _subscribe(bytes32 subscriber, address payer, uint256 count) internal returns (uint256 endTime) {
        uint256 duration = count * SUBSCRIPTION_DURATION;

        uint256 startTime = block.timestamp;

        uint256 nonce = nonces[subscriber];

        bytes32 id = _hash(subscriber, nonce);

        uint256 registryFeeShare = ASSET_REGISTRY.getRegistryFeeShare();

        if (subscribers.contains(subscriber)) {
            Subscription memory subscription = subscriptions[id];

            // If the previous subscription is still active, use the end time of the previous
            // subscription's Expiry as the new Subscription's start time
            startTime = Math.max(startTime, subscription.endTime);

            // Extend existing subscription if still active and subscription price, registry fee share,
            // and payer are the same.
            if (
                startTime == subscription.endTime && subscription.payer == payer
                    && subscription.subscriptionPrice == subscriptionPrice
                    && subscription.registryFeeShare == registryFeeShare
            ) {
                endTime = subscription.endTime + duration;

                subscriptions[id].endTime = endTime;

                emit SubscriptionExtended(subscriber, endTime);

                return endTime;
            }

            nonce = ++nonces[subscriber];

            id = _hash(subscriber, nonce);

            endTime = _addSubscription(id, subscriber, startTime, duration, registryFeeShare, payer);

            emit SubscriptionRenewed(subscriber, startTime, endTime, nonce, payer, subscriptionPrice, registryFeeShare);

            return endTime;
        }

        endTime = _addSubscription(id, subscriber, startTime, duration, registryFeeShare, payer);

        emit SubscriptionAdded(subscriber, startTime, endTime, payer, subscriptionPrice, registryFeeShare);

        return endTime;
    }

    function _addSubscription(
        bytes32 id,
        bytes32 subscriber,
        uint256 startTime,
        uint256 duration,
        uint256 registryFeeShare,
        address payer
    ) internal returns (uint256) {
        uint256 endTime = startTime + duration;

        subscriptions[id] = Subscription({
            startTime: startTime,
            endTime: endTime,
            subscriptionPrice: subscriptionPrice,
            registryFeeShare: registryFeeShare,
            payer: payer
        });

        subscribers.add(subscriber);

        return endTime;
    }

    function _validatePermit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        if (spender != address(this)) {
            revert InvalidSpender();
        }

        try IERC20Permit(TOKEN_ADDRESS).permit(owner, address(this), value, deadline, v, r, s) {
            SafeERC20.safeTransferFrom(TOKEN_CONTRACT, owner, address(this), value);
        } catch {
            revert PermitFailed();
        }
    }

    function _claimable(
        bytes32 subscriber,
        uint256 claimedAtTimestamp,
        uint256 claimedAtNonce,
        bool isOwner,
        bool isRegistry,
        uint256 timestamp
    ) internal view returns (uint256, uint256, uint256) {
        uint256 claimable = 0;

        uint256 nonce = nonces[subscriber] + 1;

        for (uint256 i = claimedAtNonce; i < nonce; i++) {
            bytes32 id = _hash(subscriber, i);

            Subscription memory subscription = subscriptions[id];

            // If the subscription has not started yet, break the loop since all subsequent
            // subscriptions will also not have started yet
            if (subscription.startTime >= timestamp) {
                break;
            }

            // If the subscription has already been claimed, continue to the next subscription
            if (subscription.endTime <= claimedAtTimestamp) {
                continue;
            }

            claimedAtNonce = i;

            // startTime is aligned to this record's period grid (invariant: claimedAtTimestamp is
            // either 0, a previous snappedEnd on this record's grid, or <= subscription.startTime).
            uint256 startTime = Math.max(subscription.startTime, claimedAtTimestamp);
            uint256 endTime = Math.min(subscription.endTime, timestamp);

            // Count of fully-passed periods since startTime. No dust: endTime may be mid-period
            uint256 count = (endTime - startTime) / SUBSCRIPTION_DURATION;

            if (count == 0) {
                continue;
            }

            uint256 fee = count * subscription.subscriptionPrice;
            uint256 registryFee = (fee * subscription.registryFeeShare) / 100;

            if (isOwner) {
                claimable += (fee - registryFee);
            } else if (isRegistry) {
                claimable += registryFee;
            }

            // Update the new claimed at timestamp to the end time of the last fully-passed period
            claimedAtTimestamp = startTime + count * SUBSCRIPTION_DURATION;
        }

        return (claimable, claimedAtNonce, claimedAtTimestamp);
    }

    function claimCreatorFee(bytes32 subscriber) external onlyOwner nonReentrant returns (uint256 creatorFee) {
        (creatorFee, creatorClaimedAtNonces[subscriber], creatorClaimedAtTimestamps[subscriber]) = _claimable(
            subscriber,
            creatorClaimedAtTimestamps[subscriber],
            creatorClaimedAtNonces[subscriber],
            true,
            false,
            block.timestamp
        );

        if (creatorFee != 0) {
            SafeERC20.safeTransfer(TOKEN_CONTRACT, owner(), creatorFee);
        }

        emit CreatorFeeClaimed(subscriber, creatorFee);

        return creatorFee;
    }

    function claimCreatorFee(bytes32[] calldata _subscribers)
        external
        onlyOwner
        nonReentrant
        returns (uint256 claimed)
    {
        uint256 timestamp = block.timestamp;

        for (uint256 i = 0; i < _subscribers.length; i++) {
            bytes32 subscriber = _subscribers[i];

            if (!subscribers.contains(subscriber)) {
                continue;
            }

            (uint256 creatorFee, uint256 claimedAtNonce, uint256 claimedAtTimestamp) = _claimable(
                subscriber,
                creatorClaimedAtTimestamps[subscriber],
                creatorClaimedAtNonces[subscriber],
                true,
                false,
                timestamp
            );

            // If the creator fee is 0, continue to the next subscriber
            if (creatorFee == 0) {
                continue;
            }

            creatorClaimedAtTimestamps[subscriber] = claimedAtTimestamp;

            creatorClaimedAtNonces[subscriber] = claimedAtNonce;

            emit CreatorFeeClaimed(subscriber, creatorFee);

            claimed += creatorFee;
        }

        if (claimed != 0) {
            SafeERC20.safeTransfer(TOKEN_CONTRACT, owner(), claimed);
        }

        emit CreatorFeeClaimedBatch(_subscribers, claimed);

        return claimed;
    }

    function claimRegistryFee(bytes32 subscriber) external onlyRegistry nonReentrant returns (uint256 registryFee) {
        (registryFee, registryClaimedAtNonces[subscriber], registryClaimedAtTimestamps[subscriber]) = _claimable(
            subscriber,
            registryClaimedAtTimestamps[subscriber],
            registryClaimedAtNonces[subscriber],
            false,
            true,
            block.timestamp
        );

        if (registryFee != 0) {
            SafeERC20.safeTransfer(TOKEN_CONTRACT, ASSET_REGISTRY.getOwner(), registryFee);
        }

        return registryFee;
    }

    function claimRegistryFee(bytes32[] calldata _subscribers)
        external
        onlyRegistry
        nonReentrant
        returns (uint256 claimed)
    {
        uint256 timestamp = block.timestamp;

        for (uint256 i = 0; i < _subscribers.length; i++) {
            bytes32 subscriber = _subscribers[i];

            if (!subscribers.contains(subscriber)) {
                continue;
            }

            (uint256 registryFee, uint256 claimedAtNonce, uint256 claimedAtTimestamp) = _claimable(
                subscriber,
                registryClaimedAtTimestamps[subscriber],
                registryClaimedAtNonces[subscriber],
                false,
                true,
                timestamp
            );

            // If the registry fee is 0, continue to the next subscriber
            if (registryFee == 0) {
                continue;
            }

            registryClaimedAtTimestamps[subscriber] = claimedAtTimestamp;

            registryClaimedAtNonces[subscriber] = claimedAtNonce;

            claimed += registryFee;
        }

        if (claimed != 0) {
            SafeERC20.safeTransfer(TOKEN_CONTRACT, ASSET_REGISTRY.getOwner(), claimed);
        }

        return claimed;
    }

    function _removeSubscription(bytes32 subscriber) internal {
        if (!subscribers.contains(subscriber)) {
            revert SubscriptionNotFound();
        }

        uint256 nonce = nonces[subscriber];

        uint256 length = nonce + 1;

        uint256 deleted = 0;

        uint256 timestamp = block.timestamp;

        for (uint256 i = length; i > 0; i--) {
            bytes32 id = _hash(subscriber, i - 1);

            Subscription memory subscription = subscriptions[id];

            // Skip expired subscriptions — all prior ones will also be expired
            if (subscription.endTime <= timestamp) {
                break;
            }

            uint256 returnable;

            uint256 count;

            // If the subscription has not started yet, return the full refund
            if (subscription.startTime >= timestamp) {
                count = (subscription.endTime - subscription.startTime) / SUBSCRIPTION_DURATION;

                delete subscriptions[id];

                deleted++;
            }
            // If the subscription has started (is active), return the remaining time
            else {
                count = (subscription.endTime - timestamp) / SUBSCRIPTION_DURATION;

                subscriptions[id].endTime = subscription.endTime - (count * SUBSCRIPTION_DURATION);
            }

            returnable = count * subscription.subscriptionPrice;

            if (returnable != 0) {
                SafeERC20.safeTransfer(TOKEN_CONTRACT, subscription.payer, returnable);
            }
        }

        // If the user has deleted all of their subscriptions, delete the nonce and remove the user from the
        // subscribers set
        if (deleted == length) {
            delete nonces[subscriber];
            delete creatorClaimedAtNonces[subscriber];
            delete creatorClaimedAtTimestamps[subscriber];
            delete registryClaimedAtNonces[subscriber];
            delete registryClaimedAtTimestamps[subscriber];
            subscribers.remove(subscriber);

            emit SubscriptionRemoved(subscriber);
        }
        // If the user has subscriptions left, decrement the nonce by the number of deleted subscriptions
        else if (deleted != 0) {
            nonces[subscriber] -= deleted;
        }
    }

    function revokeSubscription(bytes32 subscriber) external onlyOwner nonReentrant {
        _removeSubscription(subscriber);

        uint256 nonce = nonces[subscriber];

        bytes32 id = _hash(subscriber, nonce);

        emit SubscriptionRevoked(subscriber, nonce, subscriptions[id].endTime);
    }

    function cancelSubscription(string memory subscriberId, bytes memory signature) external nonReentrant {
        bytes32 subscriber = _hash(subscriberId, msg.sender);

        bytes32 hash = _hash(block.chainid, address(this), subscriber);

        address signer = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(hash), signature);

        if (signer != msg.sender) {
            revert InvalidSignature();
        }

        _removeSubscription(subscriber);

        uint256 nonce = nonces[subscriber];

        bytes32 id = _hash(subscriber, nonce);

        emit SubscriptionCancelled(subscriber, nonce, subscriptions[id].endTime);
    }

    function _hash(bytes32 a, uint256 b) internal pure returns (bytes32 result) {
        result = keccak256(abi.encode(a, b));
        return result;
    }

    function _hash(string memory a, address b) internal pure returns (bytes32 result) {
        result = keccak256(abi.encode(a, b));
        return result;
    }

    function _hash(uint256 a, address b, bytes32 c) internal pure returns (bytes32 result) {
        result = keccak256(abi.encodePacked(a, b, c));
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
