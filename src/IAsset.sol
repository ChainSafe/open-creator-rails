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

    /// @notice Returns a subscriber's subscription expiry timestamp.
    /// @param subscriber Subscriber hash to query (recommended canonical form:
    ///        keccak256(abi.encode(subscriberId, subscriberAddress))).
    /// @return Expiry timestamp; 0 if no subscription.
    function getSubscription(bytes32 subscriber) external view returns (uint256);

    /// @notice Checks whether a subscriber has an active subscription.
    /// @param subscriber Subscriber hash to check (recommended canonical form:
    ///        keccak256(abi.encode(subscriberId, subscriberAddress))).
    /// @return True if the subscriber's subscription is active.
    function isSubscriptionActive(bytes32 subscriber) external view returns (bool);

    /// @notice Subscribes using ERC-2612 permit: payer signs permit,
    ///         then payment is pulled and subscription is attributed to `subscriber`.
    /// @param subscriber Subscriber hash to subscribe (recommended canonical form:
    ///        keccak256(abi.encode(subscriberId, subscriberAddress))).
    /// @param payer Subscription payer and subscription refund beneficiary.
    /// @param spender Must be this asset contract for the permit to be accepted.
    /// @param value Permit allowance / payment amount (will be rounded down to subscription price units).
    /// @param deadline Permit signature expiry.
    /// @param v Signature recovery id.
    /// @param r Signature r.
    /// @param s Signature s.
    /// @return Subscription expiry in Unix timestamp.
    function subscribe(
        bytes32 subscriber,
        address payer,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256);

    /// @notice Claims the creator fee for a subscriber. Callable only by the asset owner.
    ///         Updates and emits claim cursor metadata (`claimedAtTimestamp`, `claimedAtNonce`) in
    ///         `CreatorFeeClaimed` to support deterministic indexer continuation.
    /// @param subscriber Subscriber hash whose creator fee to claim.
    /// @return claimedAmount The amount of creator fee claimed.
    function claimCreatorFee(bytes32 subscriber) external returns (uint256 claimedAmount);

    /// @notice Claims the creator fee for multiple subscribers. Callable only by the asset owner.
    ///         Emits `CreatorFeeClaimed` per subscriber with per-subscriber claim cursor metadata,
    ///         then emits `CreatorFeeClaimedBatch` once with the aggregate amount.
    /// @param subscribers Array of subscriber hashes whose creator fee to claim.
    /// @return totalClaimedAmount The total amount of creator fee claimed across all subscribers.
    function claimCreatorFee(bytes32[] calldata subscribers) external returns (uint256 totalClaimedAmount);

    /// @notice Claims the registry fee for a subscriber. Callable only by the registry contract.
    ///         Returns claim cursor metadata so callers can emit or persist synchronized claim progress.
    /// @param subscriber Subscriber hash whose registry fee to claim.
    /// @return claimedAmount The amount of registry fee claimed.
    /// @return claimedAtTimestamp The timestamp used as the upper claim bound for this call.
    /// @return claimedAtNonce The subscription nonce reached while computing the claim.
    function claimRegistryFee(bytes32 subscriber) external returns (uint256 claimedAmount, uint256 claimedAtTimestamp, uint256 claimedAtNonce);

    /// @notice Claims the registry fee for multiple subscribers. Callable only by the registry contract.
    /// @param subscribers Array of subscriber hashes whose registry fee to claim.
    /// @return totalClaimedAmount The total amount of registry fee claimed across all subscribers.
    function claimRegistryFee(bytes32[] calldata subscribers) external returns (uint256 totalClaimedAmount);

    /// @notice Revokes a subscriber's subscription. Callable only by the asset owner.
    /// @param subscriber Subscriber hash whose subscription to revoke.
    function revokeSubscription(bytes32 subscriber) external;

    /// @notice Cancels your subscription for subscriber hash derived from `(subscriberId, msg.sender)`.
    /// @param subscriberId Human-readable subscriber ID used in `keccak256(abi.encode(subscriberId, msg.sender))`.
    /// @param signature Signature by msg.sender over the cancellation payload.
    function cancelSubscription(string memory subscriberId, bytes memory signature) external;
}
