// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "../test/Base.t.sol";
import {console2} from "forge-std/console2.sol";

/// @title GasTest
/// @notice Gas scaling benchmarks for Asset claim, revoke, and cancel paths by nonce depth.
///         Scale points: 1, 10, 100, 1_000, 10_000.
/// @dev Not run by default `forge test`. Use `FOUNDRY_PROFILE=gas forge test --isolate`. See docs/gas-benchmarks.md.
contract GasTest is BaseTest {
    string internal constant CLAIM_CREATOR_SUB_ID = "gas-depth-claim-creator";
    string internal constant CLAIM_REGISTRY_SUB_ID = "gas-depth-claim-registry";
    string internal constant REVOKE_SUB_ID = "gas-depth-revoke";
    string internal constant CANCEL_SUB_ID = "gas-depth-cancel";

    // --- Nonce depth: claimCreatorFee(bytes32) ---

    function test_gas_claimCreatorFee_nonceDepth_1() public {
        _gasClaimCreatorFeeNonceDepth(1);
    }

    function test_gas_claimCreatorFee_nonceDepth_10() public {
        _gasClaimCreatorFeeNonceDepth(10);
    }

    function test_gas_claimCreatorFee_nonceDepth_100() public {
        _gasClaimCreatorFeeNonceDepth(100);
    }

    function test_gas_claimCreatorFee_nonceDepth_1000() public {
        _gasClaimCreatorFeeNonceDepth(1000);
    }

    function test_gas_claimCreatorFee_nonceDepth_10000() public {
        _gasClaimCreatorFeeNonceDepth(10_000);
    }

    // --- Nonce depth: claimRegistryFee(bytes32) ---

    function test_gas_claimRegistryFee_nonceDepth_1() public {
        _gasClaimRegistryFeeNonceDepth(1);
    }

    function test_gas_claimRegistryFee_nonceDepth_10() public {
        _gasClaimRegistryFeeNonceDepth(10);
    }

    function test_gas_claimRegistryFee_nonceDepth_100() public {
        _gasClaimRegistryFeeNonceDepth(100);
    }

    function test_gas_claimRegistryFee_nonceDepth_1000() public {
        _gasClaimRegistryFeeNonceDepth(1000);
    }

    function test_gas_claimRegistryFee_nonceDepth_10000() public {
        _gasClaimRegistryFeeNonceDepth(10_000);
    }

    // --- Nonce depth: revokeSubscription ---

    function test_gas_revokeSubscription_nonceDepth_1() public {
        _gasRevokeSubscriptionNonceDepth(1);
    }

    function test_gas_revokeSubscription_nonceDepth_10() public {
        _gasRevokeSubscriptionNonceDepth(10);
    }

    function test_gas_revokeSubscription_nonceDepth_100() public {
        _gasRevokeSubscriptionNonceDepth(100);
    }

    function test_gas_revokeSubscription_nonceDepth_1000() public {
        _gasRevokeSubscriptionNonceDepth(1000);
    }

    function test_gas_revokeSubscription_nonceDepth_10000() public {
        _gasRevokeSubscriptionNonceDepth(10_000);
    }

    // --- Nonce depth: cancelSubscription ---

    function test_gas_cancelSubscription_nonceDepth_1() public {
        _gasCancelSubscriptionNonceDepth(1);
    }

    function test_gas_cancelSubscription_nonceDepth_10() public {
        _gasCancelSubscriptionNonceDepth(10);
    }

    function test_gas_cancelSubscription_nonceDepth_100() public {
        _gasCancelSubscriptionNonceDepth(100);
    }

    function test_gas_cancelSubscription_nonceDepth_1000() public {
        _gasCancelSubscriptionNonceDepth(1000);
    }

    function test_gas_cancelSubscription_nonceDepth_10000() public {
        _gasCancelSubscriptionNonceDepth(10_000);
    }

    // --- Internal helpers ---

    function _depthSub(string memory subId) internal view returns (bytes32) {
        return keccak256(abi.encode(subId, signer));
    }

    /// @dev Builds `depth` sequential subscription nonces by expiring each record before renewing.
    function _buildExpiredNonceDepth(bytes32 subscriber, uint256 depth) internal {
        _subscribeFor(subscriber, 1);

        for (uint256 i = 1; i < depth; i++) {
            uint256 endTime = asset.getSubscriptionExpiration(subscriber);
            vm.warp(endTime + 1);
            _subscribeFor(subscriber, 1);
        }
    }

    /// @dev Builds `depth` stacked nonces (active + future records) for remove/revoke loops.
    function _buildStackedNonceDepth(bytes32 subscriber, uint256 depth) internal {
        _subscribeFor(subscriber, 1);

        for (uint256 i = 1; i < depth; i++) {
            vm.prank(assetOwner);
            asset.setSubscriptionPrice(SUBSCRIPTION_PRICE + (i * 100));
            _subscribeFor(subscriber, 1);
        }
    }

    function _logGas(uint256 scale, uint256 gasUsed) internal pure {
        console2.log("  scale:", scale);
        console2.log("  gas:", gasUsed);
    }

    function _gasClaimCreatorFeeNonceDepth(uint256 depth) internal {
        bytes32 subscriber = _depthSub(CLAIM_CREATOR_SUB_ID);
        _buildExpiredNonceDepth(subscriber, depth);

        uint256 endTime = asset.getSubscriptionExpiration(subscriber);
        vm.warp(endTime + 1);

        vm.prank(assetOwner);
        vm.startSnapshotGas("gas/claimCreatorFee_nonceDepth", vm.toString(depth));
        asset.claimCreatorFee(subscriber);
        uint256 gasUsed = vm.stopSnapshotGas();

        _logGas(depth, gasUsed);
    }

    function _gasClaimRegistryFeeNonceDepth(uint256 depth) internal {
        bytes32 subscriber = _depthSub(CLAIM_REGISTRY_SUB_ID);
        _buildExpiredNonceDepth(subscriber, depth);

        uint256 endTime = asset.getSubscriptionExpiration(subscriber);
        vm.warp(endTime + 1);

        vm.prank(address(assetRegistry));
        vm.startSnapshotGas("gas/claimRegistryFee_nonceDepth", vm.toString(depth));
        asset.claimRegistryFee(subscriber);
        uint256 gasUsed = vm.stopSnapshotGas();

        _logGas(depth, gasUsed);
    }

    function _gasRevokeSubscriptionNonceDepth(uint256 depth) internal {
        bytes32 subscriber = _depthSub(REVOKE_SUB_ID);
        _buildStackedNonceDepth(subscriber, depth);

        vm.prank(assetOwner);
        vm.startSnapshotGas("gas/revokeSubscription_nonceDepth", vm.toString(depth));
        asset.revokeSubscription(subscriber);
        uint256 gasUsed = vm.stopSnapshotGas();

        _logGas(depth, gasUsed);
    }

    function _gasCancelSubscriptionNonceDepth(uint256 depth) internal {
        bytes32 subscriber = _depthSub(CANCEL_SUB_ID);
        string memory subscriberId = CANCEL_SUB_ID;
        _buildStackedNonceDepth(subscriber, depth);

        bytes memory signature = _getCancellationSignatureForId(subscriberId, signer);

        vm.prank(signer);
        vm.startSnapshotGas("gas/cancelSubscription_nonceDepth", vm.toString(depth));
        asset.cancelSubscription(subscriberId, signature);
        uint256 gasUsed = vm.stopSnapshotGas();

        _logGas(depth, gasUsed);
    }

    function _getCancellationSignatureForId(string memory subscriberId, address subscriberAddress)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 subscriber = keccak256(abi.encode(subscriberId, subscriberAddress));
        bytes32 hash = keccak256(abi.encodePacked(block.chainid, address(asset), subscriber));
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _subscribeFor(bytes32 subscriber, uint256 count) internal returns (uint256 subscription) {
        address payer = signer;
        address spender = address(asset);

        uint256 value = asset.getSubscriptionPrice(count);
        uint256 deadline = block.timestamp;

        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);

        subscription = asset.subscribe(subscriber, payer, spender, count, deadline, v, r, s);
    }
}
