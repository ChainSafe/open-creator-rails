// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IAssetRegistry
/// @notice Interface for the asset registry: creates and indexes subscription assets, routes subscription
///         queries and subscribe calls by asset id, and defines fee splits (creator vs registry).
interface IAssetRegistry {
    /// @notice Deploys a new Asset contract and registers it under the given id. Callable only by registry owner.
    /// @param _assetId Unique identifier for the asset.
    /// @param _subscriptionPrice Price per subscription duration.
    /// @param _subscriptionDuration Fixed period length in seconds; subscriptions must be whole multiples.
    /// @param _tokenAddress ERC20 (with permit) used for subscription payments.
    /// @param _owner Creator/owner of the new asset.
    /// @return The address of the newly deployed Asset contract.
    function createAsset(
        bytes32 _assetId,
        uint256 _subscriptionPrice,
        uint256 _subscriptionDuration,
        address _tokenAddress,
        address _owner
    ) external returns (address);

    /// @notice Checks whether an asset is registered for the given id.
    /// @param _assetId Asset identifier to check.
    /// @return True if an asset exists for _assetId.
    function viewAsset(bytes32 _assetId) external view returns (bool);

    /// @notice Returns the contract address of the asset for the given id. Throws if not found.
    /// @param _assetId Asset identifier to look up.
    /// @return The address of the Asset contract. Throws if not found.
    function getAsset(bytes32 _assetId) external view returns (address);

    /// @notice Checks whether a subscriber hash has an active subscription for the given asset.
    /// @param _assetId Asset identifier.
    /// @param _subscriber Subscriber hash (recommended canonical form:
    ///        keccak256(abi.encode(subscriberId, subscriberAddress))).
    /// @return True if the subscriber's subscription for that asset is active.
    function isSubscriptionActive(bytes32 _assetId, bytes32 _subscriber) external view returns (bool);

    /// @notice Returns the subscription expiry timestamp for the given subscriber hash for the given asset.
    /// @param _assetId Asset identifier.
    /// @param _subscriber Subscriber hash (recommended canonical form:
    ///        keccak256(abi.encode(subscriberId, subscriberAddress))).
    /// @return Expiry timestamp in seconds; 0 if no subscription.
    function getSubscription(bytes32 _assetId, bytes32 _subscriber) external view returns (uint256);

    /// @notice Returns the total price for a given number of subscription periods for the given asset.
    /// @param _assetId Asset identifier.
    /// @param _count Number of periods.
    /// @return Total price for the number of periods.
    function getSubscriptionPrice(bytes32 _assetId, uint256 _count) external view returns (uint256);

    /// @notice Returns the asset's fixed subscription period length in seconds.
    /// @param _assetId Asset identifier.
    /// @return Period length in seconds.
    function getSubscriptionDuration(bytes32 _assetId) external view returns (uint256);

    /// @notice Returns the total duration in seconds covered by value for the given asset,
    ///         rounded down to whole periods.
    /// @param _assetId Asset identifier.
    /// @param _value Payment amount in token units.
    /// @return Total duration in seconds (whole periods only).
    function getSubscriptionDuration(bytes32 _assetId, uint256 _value) external view returns (uint256);

    /// @notice Returns both price and duration for a given number of periods for the given asset.
    /// @param _assetId Asset identifier.
    /// @param _count Number of periods.
    /// @return price Total cost.
    /// @return duration Total duration in seconds (whole periods only).
    function getSubscriptionPriceAndDuration(bytes32 _assetId, uint256 _count)
        external
        view
        returns (uint256 price, uint256 duration);

    /// @notice Subscribes a subscriber hash to the asset using ERC-2612 permit; forwards to the asset contract.
    ///         The payer signs the permit and is the refund beneficiary on cancel/revoke.
    /// @param _assetId Asset identifier.
    /// @param _subscriber Subscriber hash (recommended canonical form:
    ///        keccak256(abi.encode(subscriberId, subscriberAddress))).
    /// @param _payer Payer; signs the permit and receives refunds on cancel/revoke.
    /// @param _spender Must be the asset contract address for the permit.
    /// @param _value Permit allowance / payment amount.
    /// @param _deadline Permit signature expiry.
    /// @param _v Signature v.
    /// @param _r Signature r.
    /// @param _s Signature s.
    /// @return Subscription expiry in Unix timestamp.
    function subscribe(
        bytes32 _assetId,
        bytes32 _subscriber,
        address _payer,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (uint256);

    /// @notice Returns the creator fee share.
    /// @return creatorFeeShare The creator fee share.
    function getCreatorFeeShare() external view returns (uint256);

    /// @notice Returns the registry fee share.
    /// @return registryFeeShare The registry fee share.
    function getRegistryFeeShare() external view returns (uint256);

    /// @notice Returns the creator and registry fee shares.
    /// @return creatorFeeShare The creator fee share.
    /// @return registryFeeShare The registry fee share.
    function getFeeShares() external view returns (uint256 creatorFeeShare, uint256 registryFeeShare);

    /// @notice Updates the registry's share of subscription fees. Callable only by registry owner.
    /// @param _registryFeeShare New registry fee share (0 - 100).
    function updateRegistryFeeShare(uint256 _registryFeeShare) external;

    /// @notice Returns the creator fee for a given payment value.
    /// @param _value Total payment value.
    /// @return creatorFee The creator fee.
    function getCreatorFee(uint256 _value) external view returns (uint256);

    /// @notice Returns the registry fee for a given payment value.
    /// @param _value Total payment value.
    /// @return registryFee The registry fee.
    function getRegistryFee(uint256 _value) external view returns (uint256);

    /// @notice Returns the creator and registry fees for a given payment value.
    /// @param _value Total payment value.
    /// @return creatorFee The creator fee.
    /// @return registryFee The registry fee.
    function getFees(uint256 _value) external view returns (uint256 creatorFee, uint256 registryFee);

    /// @notice Claims the registry fee for a subscriber hash. Callable only by the Registry owner.
    /// @param _assetId Asset identifier.
    /// @param _subscriber Subscriber hash.
    /// @return The amount of registry fee claimed.
    function claimRegistryFee(bytes32 _assetId, bytes32 _subscriber) external returns (uint256);

    /// @notice Claims the registry fee for multiple subscriber hashes. Callable only by the Registry owner.
    /// @param _assetId Asset identifier.
    /// @param _subscribers Array of subscriber hashes.
    /// @return The amount of registry fee claimed.
    function claimRegistryFee(bytes32 _assetId, bytes32[] calldata _subscribers) external returns (uint256);

    /// @notice Returns the owner of the registry (e.g. for receiving registry fees).
    /// @return The registry owner address.
    function getOwner() external view returns (address);
}
