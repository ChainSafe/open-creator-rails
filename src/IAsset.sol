// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAsset {
    
    function getAssetId() external view returns (bytes32);
    
    function getSubscriptionPrice(uint256 duration) external view returns (uint256);
    
    function getMySubscription() external view returns (uint256);

    function getSubscription(address user) external view returns (uint256);
    
    function viewMySubscription() external view returns (bool);

    function viewSubscription(address user) external view returns (bool);
    
    function subscribe(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s) external returns (bool);
    
    function revokeSubscription(address user) external returns (bool);
}