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

    uint256 internal creatorFeeShare;
    uint256 internal registryFeeShare;
    uint256 internal totalFeeShare;

    error AssetAlreadyExists();
    error AssetNotFound();

    event AssetCreated(bytes32 indexed assetId, address indexed asset, uint256 subscriptionPrice, address tokenAddress, address indexed owner);

    /// @notice Initializes the registry with fee shares. Caller becomes owner.
    /// @param _creatorFeeShare Share of subscription payments allocated to asset creators.
    /// @param _registryFeeShare Share of subscription payments allocated to the registry.
    constructor(uint256 _creatorFeeShare, uint256 _registryFeeShare) Ownable(msg.sender) {
        creatorFeeShare = _creatorFeeShare;
        registryFeeShare = _registryFeeShare;
        totalFeeShare = creatorFeeShare + registryFeeShare;
    }

    function createAsset(bytes32 _assetId, uint256 _subscriptionPrice, address _tokenAddress, address _owner) external onlyOwner returns (address)
    {

        if (assets[_assetId] != address(0)) {
            revert AssetAlreadyExists();    
        }

        Asset asset = new Asset(_assetId, _subscriptionPrice, _tokenAddress, _owner);
        assets[_assetId] = address(asset);

        emit AssetCreated(_assetId, address(asset), _subscriptionPrice, _tokenAddress, _owner);

        return address(asset);
    }

    function viewAsset(bytes32 _assetId) external view returns (bool)
    {
        return assets[_assetId] != address(0);
    }

    function getAsset(bytes32 _assetId) public view returns (address)
    {
        address asset = assets[_assetId];
        
        if (asset == address(0)) {
            revert AssetNotFound();
        }
        
        return asset;
    }

    /// @notice Checks whether a user has an active subscription for the given asset.
    /// @param _assetId Asset identifier.
    /// @param _user User address.
    /// @return True if the user's subscription for that asset is active.
    function _viewSubscription(bytes32 _assetId, address _user) internal view returns (bool)
    {
        address asset = getAsset(_assetId);

        return IAsset(asset).viewSubscription(_user);
    }
    
    function viewSubscription(bytes32 _assetId) external view returns (bool)
    {
        return _viewSubscription(_assetId, msg.sender);
    }

    function viewSubscription(bytes32 _assetId, address _user) external onlyOwner view returns (bool)
    {
        return _viewSubscription(_assetId, _user);
    }

    /// @notice Returns the subscription expiry timestamp for the given user for the given asset.
    /// @param _assetId Asset identifier.
    /// @param _user User address.
    /// @return Expiry timestamp in seconds; 0 if no subscription.
    function _getSubscription(bytes32 _assetId, address _user) internal view returns (uint256)
    {
        address asset = getAsset(_assetId);
        
        return IAsset(asset).getSubscription(_user);
    }

    function getSubscription(bytes32 _assetId) external view returns (uint256)
    {
        return _getSubscription(_assetId, msg.sender);
    }

    function getSubscription(bytes32 _assetId, address _user) external onlyOwner view returns (uint256)
    {
        return _getSubscription(_assetId, _user);
    }

    function getSubscriptionPrice(bytes32 _assetId, uint256 _duration) external view returns (uint256)
    {
        address asset = getAsset(_assetId);
        
        return IAsset(asset).getSubscriptionPrice(_duration);
    }

    function subscribe(bytes32 _assetId, address _owner, address _spender, uint256 _value, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) external returns (bool)
    {
        address asset = getAsset(_assetId);
        
        return IAsset(asset).subscribe(_owner, _spender, _value, _deadline, _v, _r, _s);
    }

    function updateCreatorFeeShare(uint256 _creatorFeeShare) external onlyOwner {
        creatorFeeShare = _creatorFeeShare;
        totalFeeShare = creatorFeeShare + registryFeeShare;
    }

    function updateRegistryFeeShare(uint256 _registryFeeShare) external onlyOwner {
        registryFeeShare = _registryFeeShare;
        totalFeeShare = creatorFeeShare + registryFeeShare;
    }

    function getCreatorFee(uint256 _value) external view returns (uint256) {
        return (_value * creatorFeeShare) / totalFeeShare;
    }

    function getRegistryFee(uint256 _value) external view returns (uint256) {
        return (_value * registryFeeShare) / totalFeeShare;
    }

    function getOwner() external view returns (address) {
        return this.owner();
    }
}