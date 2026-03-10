// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IAsset
/// @notice Interface for subscription-based asset access. Assets expose a unique id, subscription pricing,
///         and methods to query or manage subscriptions (including permit-based payment).
interface IAsset {
    /// @notice Returns the unique identifier for this asset.
    /// @return The asset id as a bytes32 value.
    function getAssetId() external view returns (bytes32);

    /// @notice Returns the address of the registry that deployed this asset.
    /// @return The registry address.
    function getRegistryAddress() external view returns (address);

    /// @notice Returns the address of the token contract used for subscription payments.
    /// @return The token contract address. Must be an ERC20 with permit.
    function getTokenAddress() external view returns (address);

    /// @notice Returns the total price for a subscription of the given duration.
    /// @param duration Length of the subscription in seconds.
    /// @return Total price for the duration.
    function getSubscriptionPrice(uint256 duration) external view returns (uint256);

    /// @notice Sets the subscription price for the asset.
    /// @param newSubscriptionPrice New subscription price.
    function setSubscriptionPrice(uint256 newSubscriptionPrice) external;

    /// @notice Returns the caller's current subscription expiry timestamp.
    /// @return Expiry timestamp in seconds; 0 if no active subscription.
    function getMySubscription() external view returns (uint256);

    /// @notice Returns a user's subscription expiry timestamp. Restricted to registry or asset owner.
    /// @param user Address to query.
    /// @return Expiry timestamp; 0 if no subscription.
    function getSubscription(address user) external view returns (uint256);

    /// @notice Checks whether the caller has an active subscription (expiry > block.timestamp).
    /// @return True if the caller's subscription is active.
    function isMySubscriptionActive() external view returns (bool);

    /// @notice Checks whether a user has an active subscription. Restricted to registry or asset owner.
    /// @param user Address to check.
    /// @return True if the user's subscription is active.
    function isSubscriptionActive(address user) external view returns (bool);

    /// @notice Subscribes an owner using ERC-2612 permit: owner signs permit, then payment is pulled and subscription extended.
    /// @param owner Token owner and subscription beneficiary.
    /// @param spender Must be this asset contract for the permit to be accepted.
    /// @param value Permit allowance / payment amount (will be rounded down to subscription price units).
    /// @param deadline Permit signature expiry.
    /// @param v Signature recovery id.
    /// @param r Signature r.
    /// @param s Signature s.
    /// @return Subscription expiry in Unix timestamp.
    function subscribe(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256);


    /// @notice Claims the creator fee for a user. Callable only by the asset owner.
    /// @param user Address whose creator fee to claim.
    /// @return The amount of creator fee claimed.
    function claimCreatorFee(address user) external returns (uint256);

    /// @notice Claims the registry fee for a user. Callable only by the Registry owner.
    /// @param user Address whose registry fee to claim.
    /// @return The amount of registry fee claimed.
    function claimRegistryFee(address user) external returns (uint256);

    /// @notice Revokes a user's subscription. Callable only by the asset owner.
    /// @param user Address whose subscription to revoke.
    function revokeSubscription(address user) external;

    /// @notice Cancels the caller's subscription. Callable only by the subscription owner.
    function cancelSubscription() external;
}