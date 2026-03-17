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

    error ZeroTotalFeeShare();
    error AssetAlreadyExists();
    error AssetNotFound();

    event AssetCreated(bytes32 indexed assetId, address indexed asset, uint256 subscriptionPrice, address tokenAddress, address indexed owner);
    event CreatorFeeShareUpdated(uint256 newCreatorFeeShare);
    event RegistryFeeShareUpdated(uint256 newRegistryFeeShare);
    event RegistryFeeClaimed(bytes32 indexed subscriber, uint256 amount);

    /// @notice Initializes the registry with fee shares. Caller becomes owner.
    /// @param _creatorFeeShare Share of subscription payments allocated to asset creators.
    /// @param _registryFeeShare Share of subscription payments allocated to the registry.
    constructor(uint256 _creatorFeeShare, uint256 _registryFeeShare) Ownable(msg.sender) {
        creatorFeeShare = _creatorFeeShare;
        registryFeeShare = _registryFeeShare;
        totalFeeShare = creatorFeeShare + registryFeeShare;
        if (totalFeeShare == 0) {
            revert ZeroTotalFeeShare();
        }
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

    function isSubscriptionActive(bytes32 _assetId, bytes32 _subscriber) external view returns (bool)
    {
        address asset = getAsset(_assetId);

        return IAsset(asset).isSubscriptionActive(_subscriber);
    }
    
    function getSubscription(bytes32 _assetId, bytes32 _subscriber) external view returns (uint256)
    {
        address asset = getAsset(_assetId);
        
        return IAsset(asset).getSubscription(_subscriber);
    }

    function getSubscriptionPrice(bytes32 _assetId, uint256 _duration) external view returns (uint256)
    {
        address asset = getAsset(_assetId);
        
        return IAsset(asset).getSubscriptionPrice(_duration);
    }

    function subscribe(bytes32 _assetId, bytes32 _subscriber, address _payer, address _spender, uint256 _value, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) external returns (uint256)
    {
        address asset = getAsset(_assetId);
        
        return IAsset(asset).subscribe(_subscriber, _payer, _spender, _value, _deadline, _v, _r, _s);
    }

    function getCreatorFeeShare() external view returns (uint256) {
        return creatorFeeShare;
    }

    function getRegistryFeeShare() external view returns (uint256) {
        return registryFeeShare;
    }

    function getTotalFeeShare() external view returns (uint256) {
        return totalFeeShare;
    }

    function getFeeShares() external view returns (uint256, uint256, uint256) {
        return (creatorFeeShare, registryFeeShare, totalFeeShare);
    }

    function updateCreatorFeeShare(uint256 _creatorFeeShare) external onlyOwner {
        creatorFeeShare = _creatorFeeShare;
        totalFeeShare = creatorFeeShare + registryFeeShare;
        if (totalFeeShare == 0) {
            revert ZeroTotalFeeShare();
        }
        emit CreatorFeeShareUpdated(creatorFeeShare);
    }

    function updateRegistryFeeShare(uint256 _registryFeeShare) external onlyOwner {
        registryFeeShare = _registryFeeShare;
        totalFeeShare = creatorFeeShare + registryFeeShare;
        if (totalFeeShare == 0) {
            revert ZeroTotalFeeShare();
        }
        emit RegistryFeeShareUpdated(registryFeeShare);
    }

    function getCreatorFee(uint256 _value) external view returns (uint256) {
        return _value - getRegistryFee(_value);
    }

    function getRegistryFee(uint256 _value) public view returns (uint256) {
        return (_value * registryFeeShare) / totalFeeShare;
    }

    function getFees(uint256 _value) external view returns (uint256 creatorFee, uint256 registryFee) {
        

        registryFee = getRegistryFee(_value);
        
        creatorFee = _value - registryFee;

        return (creatorFee, registryFee);
    }

    function claimRegistryFee(bytes32 _assetId, bytes32 _subscriber) external onlyOwner returns (uint256 registryFee) {
        
        address asset = getAsset(_assetId);
        
        registryFee = IAsset(asset).claimRegistryFee(_subscriber);

        emit RegistryFeeClaimed(_subscriber, registryFee);

        return registryFee;
    }

    function getOwner() external view returns (address) {
        return this.owner();
    }
}