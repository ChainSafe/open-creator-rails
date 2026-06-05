// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IAsset} from "./IAsset.sol";
import {Asset} from "./Asset.sol";
import {IAssetRegistry} from "./IAssetRegistry.sol";

/// @title AssetRegistry
/// @notice Implementation of IAssetRegistry: deploys and indexes Asset contracts by id, forwards
///         subscription queries and subscribe calls to the correct asset, and manages creator vs registry fee shares.
contract AssetRegistry is Ownable, IAssetRegistry {
    mapping(bytes32 => address) public assets;

    uint256 internal registryFeeShare;

    error AssetAlreadyExists();
    error AssetNotFound();
    error RegistryFeeShareOutOfBounds();
    error OnlyAssetUnauthorizedAccount();
    error OnlyUnrevokedUnauthorizedSubscriber();

    event AssetCreated(
        bytes32 indexed assetId,
        address indexed assetAddress,
        uint256 subscriptionPrice,
        uint256 subscriptionDuration,
        address tokenAddress,
        address indexed owner
    );
    event RegistryFeeShareUpdated(uint256 newRegistryFeeShare);
    event RegistryFeeClaimed(
        bytes32 indexed assetId,
        bytes32 indexed subscriber,
        uint256 amount,
        uint256 claimedAtTimestamp,
        uint256 claimedAtNonce
    );
    event RegistryFeeClaimedBatch(bytes32 indexed assetId, bytes32[] indexed subscribers, uint256 totalAmount);

    /// @notice Initializes the registry with fee shares. Caller becomes owner.
    /// @param _registryFeeShare Share percentage of subscription payments allocated to the registry (0 - 100).
    constructor(uint256 _registryFeeShare) Ownable(msg.sender) {
        if (_registryFeeShare > 100) {
            revert RegistryFeeShareOutOfBounds();
        }

        registryFeeShare = _registryFeeShare;

        emit RegistryFeeShareUpdated(registryFeeShare);
    }

    function createAsset(
        bytes32 _assetId,
        uint256 _subscriptionPrice,
        uint256 _subscriptionDuration,
        address _tokenAddress,
        address _owner
    ) external onlyOwner returns (address) {
        if (assets[_assetId] != address(0)) {
            revert AssetAlreadyExists();
        }

        Asset asset = new Asset(_assetId, _subscriptionPrice, _subscriptionDuration, _tokenAddress, _owner);
        assets[_assetId] = address(asset);

        emit AssetCreated(_assetId, address(asset), _subscriptionPrice, _subscriptionDuration, _tokenAddress, _owner);

        return address(asset);
    }

    function viewAsset(bytes32 _assetId) external view returns (bool) {
        return assets[_assetId] != address(0);
    }

    function getAsset(bytes32 _assetId) public view returns (address) {
        address asset = assets[_assetId];

        if (asset == address(0)) {
            revert AssetNotFound();
        }

        return asset;
    }

    function isSubscriptionExpired(bytes32 _assetId, bytes32 _subscriber) external view returns (bool) {
        address asset = getAsset(_assetId);

        return IAsset(asset).isSubscriptionExpired(_subscriber);
    }

    function getSubscriptionExpiration(bytes32 _assetId, bytes32 _subscriber) external view returns (uint256) {
        address asset = getAsset(_assetId);

        return IAsset(asset).getSubscriptionExpiration(_subscriber);
    }

    function getSubscriptionPrice(bytes32 _assetId, uint256 _count) external view returns (uint256) {
        address asset = getAsset(_assetId);

        return IAsset(asset).getSubscriptionPrice(_count);
    }

    function getSubscriptionDuration(bytes32 _assetId) external view returns (uint256) {
        address asset = getAsset(_assetId);

        return IAsset(asset).getSubscriptionDuration();
    }

    function getSubscriptionPriceAndDuration(bytes32 _assetId, uint256 _count)
        external
        view
        returns (uint256 price, uint256 duration)
    {
        address asset = getAsset(_assetId);

        return IAsset(asset).getSubscriptionPriceAndDuration(_count);
    }

    function isSubscriberRevoked(bytes32 _assetId, bytes32 _subscriber) external view returns (bool) {
        address asset = getAsset(_assetId);

        return IAsset(asset).isSubscriberRevoked(_subscriber);
    }

    function isSubscriptionActive(bytes32 _assetId, bytes32 _subscriber) external view returns (bool) {
        address asset = getAsset(_assetId);
        return IAsset(asset).isSubscriptionActive(_subscriber);
    }

    function subscribe(
        bytes32 _assetId,
        bytes32 _subscriber,
        address _payer,
        address _spender,
        uint256 _count,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external onlyUnrevoked(_assetId, _subscriber) returns (uint256) {
        address asset = getAsset(_assetId);
        return IAsset(asset).subscribe(_subscriber, _payer, _spender, _count, _deadline, _v, _r, _s);
    }

    function getCreatorFeeShare() external view returns (uint256) {
        return 100 - registryFeeShare;
    }

    function getRegistryFeeShare() external view returns (uint256) {
        return registryFeeShare;
    }

    function getFeeShares() external view returns (uint256, uint256) {
        return (100 - registryFeeShare, registryFeeShare);
    }

    function updateRegistryFeeShare(uint256 _registryFeeShare) external onlyOwner {
        if (_registryFeeShare > 100) {
            revert RegistryFeeShareOutOfBounds();
        }
        registryFeeShare = _registryFeeShare;
        emit RegistryFeeShareUpdated(registryFeeShare);
    }

    function getCreatorFee(uint256 _value) external view returns (uint256) {
        return _value - getRegistryFee(_value);
    }

    function getRegistryFee(uint256 _value) public view returns (uint256) {
        return (_value * registryFeeShare) / 100;
    }

    function getFees(uint256 _value) external view returns (uint256 creatorFee, uint256 registryFee) {
        registryFee = getRegistryFee(_value);

        creatorFee = _value - registryFee;

        return (creatorFee, registryFee);
    }

    function claimRegistryFee(bytes32 _assetId, bytes32 _subscriber) external onlyOwner returns (uint256) {
        address asset = getAsset(_assetId);

        (uint256 claimedAmount, uint256 claimedAtTimestamp, uint256 claimedAtNonce) =
            IAsset(asset).claimRegistryFee(_subscriber);

        emit RegistryFeeClaimed(_assetId, _subscriber, claimedAmount, claimedAtTimestamp, claimedAtNonce);

        return claimedAmount;
    }

    function claimRegistryFee(bytes32 _assetId, bytes32[] calldata _subscribers)
        external
        onlyOwner
        returns (uint256 totalClaimedAmount)
    {
        address asset = getAsset(_assetId);
        totalClaimedAmount = IAsset(asset).claimRegistryFee(_subscribers);
        emit RegistryFeeClaimedBatch(_assetId, _subscribers, totalClaimedAmount);
        return totalClaimedAmount;
    }

    function emitRegistryFeeClaimedEvent(
        bytes32 _assetId,
        bytes32 _subscriber,
        uint256 claimedAmount,
        uint256 claimedAtTimestamp,
        uint256 claimedAtNonce
    ) external onlyAsset(_assetId) {
        emit RegistryFeeClaimed(_assetId, _subscriber, claimedAmount, claimedAtTimestamp, claimedAtNonce);
    }

    function getOwner() external view returns (address) {
        return owner();
    }

    modifier onlyAsset(bytes32 _assetId) {
        _onlyAsset(_assetId);
        _;
    }

    function _onlyAsset(bytes32 _assetId) internal view {
        if (msg.sender != getAsset(_assetId)) {
            revert OnlyAssetUnauthorizedAccount();
        }
    }

    modifier onlyUnrevoked(bytes32 _assetId, bytes32 _subscriber) {
        _onlyUnrevoked(_assetId, _subscriber);
        _;
    }

    function _onlyUnrevoked(bytes32 _assetId, bytes32 _subscriber) internal view {
        if (IAsset(getAsset(_assetId)).isSubscriberRevoked(_subscriber)) {
            revert OnlyUnrevokedUnauthorizedSubscriber();
        }
    }
}
