// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AssetRegistry} from "../src/AssetRegistry.sol";
import {Asset} from "../src/Asset.sol";
import {IAsset} from "../src/IAsset.sol";
import {BaseTest} from "./Base.t.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract AssetRegistryTest is BaseTest {

    function _subscribe(uint256 duration) internal returns (uint256 subscription) {
        test_createAsset();

        address payer = signer;
        address spender = address(asset);
        uint256 value = asset.getSubscriptionPrice(duration);
        uint256 deadline = block.timestamp + duration;

        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);

        vm.startPrank(signer);
        subscription = assetRegistry.subscribe(ASSET_ID, SUBSCRIBER, payer, spender, value, deadline, v, r, s);
        vm.stopPrank();

        return subscription;
    }

    function _subscribeFor(bytes32 subscriber, uint256 duration) internal returns (uint256 subscription) {
        test_createAsset();

        address payer = signer;
        address spender = address(asset);
        uint256 value = asset.getSubscriptionPrice(duration);
        uint256 deadline = block.timestamp + duration;

        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);

        vm.startPrank(signer);
        subscription = assetRegistry.subscribe(ASSET_ID, subscriber, payer, spender, value, deadline, v, r, s);
        vm.stopPrank();

        return subscription;
    }

    function setUp() public override {
        super.setUp();

        vm.startPrank(registryOwner);
        assetRegistry = new AssetRegistry(30);
        vm.stopPrank();
    }

    function test_createAsset() public {
        
        if (assetRegistry.viewAsset(ASSET_ID)) {
            return;
        }

        vm.startPrank(registryOwner);
        vm.expectEmit(true, false, true, true);
        emit AssetRegistry.AssetCreated(ASSET_ID, address(0), SUBSCRIPTION_PRICE, address(testToken), assetOwner);
        asset = IAsset(assetRegistry.createAsset(ASSET_ID, SUBSCRIPTION_PRICE, address(testToken), assetOwner));
        vm.stopPrank();
        
        assertEq(asset.getAssetId(), ASSET_ID);
        assertEq(address(asset), assetRegistry.getAsset(ASSET_ID));
    }

    function test_getAsset() public {
        test_createAsset();

        asset = IAsset(assetRegistry.getAsset(ASSET_ID));
        assertEq(asset.getAssetId(), ASSET_ID);
    }

    function test_subscribe() public {
        test_createAsset();

        address payer = signer;
        address spender = address(asset);
        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 deadline = block.timestamp + DURATION;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);

        uint256 subscription = assetRegistry.subscribe(ASSET_ID, SUBSCRIBER, payer, spender, value, deadline, v, r, s);

        assertTrue(subscription > block.timestamp);
        assertEq(assetRegistry.getSubscription(ASSET_ID, SUBSCRIBER), subscription);
    }

    function test_isMySubscriptionActive() public {
        test_createAsset();
        assertFalse(assetRegistry.isSubscriptionActive(ASSET_ID, SUBSCRIBER));

        test_subscribe();
        assertTrue(assetRegistry.isSubscriptionActive(ASSET_ID, SUBSCRIBER));
    }

    function test_getSubscription() public {
        test_createAsset();
        assertEq(assetRegistry.getSubscription(ASSET_ID, SUBSCRIBER), 0);

        test_subscribe();
        assertTrue(assetRegistry.getSubscription(ASSET_ID, SUBSCRIBER) > block.timestamp);
    }

    function test_getSubscriptionPrice() public {
        test_createAsset();

        assertEq(assetRegistry.getSubscriptionPrice(ASSET_ID, 10), asset.getSubscriptionPrice(10));
    }

    function test_updateFeeShare() public {
        vm.startPrank(registryOwner);
        assetRegistry.updateRegistryFeeShare(20);
        vm.stopPrank();

        (uint256 creatorFee, uint256 registryFee) = assetRegistry.getFees(100_000_000);
        assertEq(creatorFee, 80_000_000);
        assertEq(registryFee, 20_000_000);
    }

    function test_updateRegistryFeeShare_emitsEvent() public {
        vm.prank(registryOwner);
        vm.expectEmit(true, true, true, true);
        emit AssetRegistry.RegistryFeeShareUpdated(20);
        assetRegistry.updateRegistryFeeShare(20);
    }

    function test_getOwner() public view {
        assertEq(assetRegistry.getOwner(), registryOwner);
    }

    function test_createAsset_assetAlreadyExists() public {
        test_createAsset();

        vm.startPrank(registryOwner);
        vm.expectRevert(AssetRegistry.AssetAlreadyExists.selector);
        assetRegistry.createAsset(ASSET_ID, SUBSCRIPTION_PRICE, address(testToken), assetOwner);
        vm.stopPrank();
    }

    function test_getAsset_assetNotFound() public {
        bytes32 nonexistentId = keccak256("nonexistent");

        vm.expectRevert(AssetRegistry.AssetNotFound.selector);
        assetRegistry.getAsset(nonexistentId);
    }

    function test_createAsset_invalidOwner() public {
        vm.prank(registryOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        assetRegistry.createAsset(ASSET_ID, SUBSCRIPTION_PRICE, address(testToken), address(0));
    }

    function test_constructor_registryFeeShareOutOfBounds() public {
        vm.expectRevert(AssetRegistry.RegistryFeeShareOutOfBounds.selector);
        new AssetRegistry(101);
    }

    function test_updateRegistryFeeShare_registryFeeShareOutOfBounds() public {
        vm.prank(registryOwner);
        vm.expectRevert(AssetRegistry.RegistryFeeShareOutOfBounds.selector);
        assetRegistry.updateRegistryFeeShare(101);
    }

    function test_createAsset_invalidTokenAddress() public {
        vm.prank(registryOwner);
        vm.expectRevert(Asset.InvalidTokenAddress.selector);
        assetRegistry.createAsset(ASSET_ID, SUBSCRIPTION_PRICE, address(0), assetOwner);
    }

    function test_getSubscriptionPrice_assetNotFound() public {
        bytes32 nonexistentId = keccak256("nonexistent");

        vm.expectRevert(AssetRegistry.AssetNotFound.selector);
        assetRegistry.getSubscriptionPrice(nonexistentId, 10);
    }

    function test_claimRegistryFee_unauthorized() public {
        test_createAsset();
        test_subscribe();
        vm.warp(block.timestamp + DURATION);

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, UNAUTHORIZED));
        assetRegistry.claimRegistryFee(ASSET_ID, SUBSCRIBER);
    }

    function test_createAsset_unauthorized() public {
        vm.prank(UNAUTHORIZED);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, UNAUTHORIZED));
        assetRegistry.createAsset(ASSET_ID, SUBSCRIPTION_PRICE, address(testToken), assetOwner);
    }

    function test_updateRegistryFeeShare_unauthorized() public {
        vm.prank(UNAUTHORIZED);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, UNAUTHORIZED));
        assetRegistry.updateRegistryFeeShare(20);
    }

    function test_isSubscriptionActive_withUser_ownerCanCall() public {
        test_createAsset();
        test_subscribe();

        vm.prank(registryOwner);
        assertTrue(assetRegistry.isSubscriptionActive(ASSET_ID, SUBSCRIBER));
    }

    function test_getSubscription_withUser_ownerCanCall() public {
        test_createAsset();
        test_subscribe();

        vm.prank(registryOwner);
        assertTrue(assetRegistry.getSubscription(ASSET_ID, SUBSCRIBER) > block.timestamp);
    }

    function test_claimRegistryFee() public {
        uint256 tokenBalance = testToken.balanceOf(registryOwner);
        test_subscribe();

        uint256 value = assetRegistry.getSubscriptionPrice(ASSET_ID, DURATION);
        uint256 registryFee = assetRegistry.getRegistryFee(value);
        vm.warp(block.timestamp + DURATION);

        vm.prank(registryOwner);
        vm.expectEmit(true, true, true, true);
        emit AssetRegistry.RegistryFeeClaimed(SUBSCRIBER, registryFee);
        assetRegistry.claimRegistryFee(ASSET_ID, SUBSCRIBER);

        assertEq(testToken.balanceOf(registryOwner), tokenBalance + registryFee);
    }

    function test_claimRegistryFee_multiple() public {
        uint256 tokenBalance = testToken.balanceOf(registryOwner);
        for (uint256 i = 0; i < 10; i++) _subscribe(DURATION);

        uint256 endTime = assetRegistry.getSubscription(ASSET_ID, SUBSCRIBER);
        uint256 value = assetRegistry.getSubscriptionPrice(ASSET_ID, endTime - block.timestamp);
        uint256 registryFee = assetRegistry.getRegistryFee(value);
        vm.warp(endTime);

        vm.prank(registryOwner);
        vm.expectEmit(true, true, true, true);
        emit AssetRegistry.RegistryFeeClaimed(SUBSCRIBER, registryFee);
        assetRegistry.claimRegistryFee(ASSET_ID, SUBSCRIBER);

        assertEq(testToken.balanceOf(registryOwner), tokenBalance + registryFee);
    }

    function test_claimRegistryFee_multiple_creatorFeeShare() public {
        
        uint256 registryFeeShare = assetRegistry.getRegistryFeeShare();
        uint256 tokenBalance = testToken.balanceOf(registryOwner);

        _subscribe(DURATION);

        vm.prank(registryOwner);
        assetRegistry.updateRegistryFeeShare(40);

        uint256 endTime = _subscribe(DURATION);

        uint256 value = assetRegistry.getSubscriptionPrice(ASSET_ID, DURATION);
        uint256 registryFee = assetRegistry.getRegistryFee(value) + ((value * registryFeeShare) / 100);
        vm.warp(endTime);

        vm.prank(registryOwner);
        uint256 claimedRegistryFee = assetRegistry.claimRegistryFee(ASSET_ID, SUBSCRIBER);

        assertEq(claimedRegistryFee, registryFee);
        assertEq(testToken.balanceOf(registryOwner), tokenBalance + claimedRegistryFee);
    }

    function test_claimRegistryFee_multiple_registryFeeShare() public {
        uint256 registryFeeShare = assetRegistry.getRegistryFeeShare();
        uint256 tokenBalance = testToken.balanceOf(registryOwner);

        _subscribe(DURATION);

        vm.prank(registryOwner);
        assetRegistry.updateRegistryFeeShare(50);

        uint256 endTime = _subscribe(DURATION);

        uint256 value = assetRegistry.getSubscriptionPrice(ASSET_ID, DURATION);
        uint256 registryFee = assetRegistry.getRegistryFee(value) + ((value * registryFeeShare) / 100);
        vm.warp(endTime);

        vm.prank(registryOwner);
        uint256 claimedRegistryFee = assetRegistry.claimRegistryFee(ASSET_ID, SUBSCRIBER);

        assertEq(claimedRegistryFee, registryFee);
        assertEq(testToken.balanceOf(registryOwner), tokenBalance + claimedRegistryFee);
    }

    function test_claimRegistryFee_multiple_subscriptionPrice() public {
        uint256 tokenBalance = testToken.balanceOf(registryOwner);
        _subscribe(DURATION);

        uint256 value = assetRegistry.getSubscriptionPrice(ASSET_ID, DURATION);

        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        _subscribe(DURATION);

        value += assetRegistry.getSubscriptionPrice(ASSET_ID, DURATION);
        uint256 registryFee = assetRegistry.getRegistryFee(value);
        vm.warp(block.timestamp + (DURATION * 2));

        vm.prank(registryOwner);
        vm.expectEmit(true, true, true, true);
        emit AssetRegistry.RegistryFeeClaimed(SUBSCRIBER, registryFee);
        assetRegistry.claimRegistryFee(ASSET_ID, SUBSCRIBER);

        assertEq(testToken.balanceOf(registryOwner), tokenBalance + registryFee);
    }

    function test_claimRegistryFee_midSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(registryOwner);
        _subscribe(DURATION);

        uint256 value = assetRegistry.getSubscriptionPrice(ASSET_ID, DURATION);
        uint256 registryFee = assetRegistry.getRegistryFee(value) / 2;
        vm.warp(block.timestamp + (DURATION / 2));

        vm.prank(registryOwner);
        vm.expectEmit(true, true, true, true);
        emit AssetRegistry.RegistryFeeClaimed(SUBSCRIBER, registryFee);
        assetRegistry.claimRegistryFee(ASSET_ID, SUBSCRIBER);

        assertEq(testToken.balanceOf(registryOwner), tokenBalance + registryFee);
    }

    function test_claimRegistryFee_startOfNextSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(registryOwner);
        uint256 endTime = _subscribe(DURATION);
        uint256 value = assetRegistry.getSubscriptionPrice(ASSET_ID, DURATION);

        _subscribe(DURATION);

        vm.warp(endTime);

        uint256 registryFee = assetRegistry.getRegistryFee(value);
        vm.prank(registryOwner);
        vm.expectEmit(true, true, true, true);
        emit AssetRegistry.RegistryFeeClaimed(SUBSCRIBER, registryFee);
        assetRegistry.claimRegistryFee(ASSET_ID, SUBSCRIBER);

        assertEq(testToken.balanceOf(registryOwner), tokenBalance + registryFee);
    }

    function test_viewAsset_nonexistent() public view {
        bytes32 nonexistentId = keccak256("nonexistent");
        assertFalse(assetRegistry.viewAsset(nonexistentId));
    }

    function test_viewAsset_existent() public {
        test_createAsset();
        assertTrue(assetRegistry.viewAsset(ASSET_ID));
    }

    function test_getCreatorFeeShare() public view {
        assertEq(assetRegistry.getCreatorFeeShare(), 70);
    }

    function test_getRegistryFeeShare() public view {
        assertEq(assetRegistry.getRegistryFeeShare(), 30);
    }

    function test_getCreatorFee() public view {
        uint256 value = 100_000_000;
        uint256 creatorFee = assetRegistry.getCreatorFee(value);
        uint256 registryFee = assetRegistry.getRegistryFee(value);
        assertEq(creatorFee + registryFee, value);
        assertEq(creatorFee, 70_000_000);
    }

    function test_getRegistryFee() public view {
        uint256 value = 100_000_000;
        assertEq(assetRegistry.getRegistryFee(value), 30_000_000);
    }

    function test_subscribe_assetNotFound() public {
        bytes32 nonexistentId = keccak256("nonexistent");
        address payer = signer;
        address spender = address(asset);
        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 deadline = block.timestamp + DURATION;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);

        vm.expectRevert(AssetRegistry.AssetNotFound.selector);
        assetRegistry.subscribe(nonexistentId, SUBSCRIBER, payer, spender, value, deadline, v, r, s);
    }

    function test_isSubscriptionActive_assetNotFound() public {
        bytes32 nonexistentId = keccak256("nonexistent");
        vm.expectRevert(AssetRegistry.AssetNotFound.selector);
        assetRegistry.isSubscriptionActive(nonexistentId, SUBSCRIBER);
    }

    function test_getSubscription_assetNotFound() public {
        bytes32 nonexistentId = keccak256("nonexistent");
        vm.expectRevert(AssetRegistry.AssetNotFound.selector);
        assetRegistry.getSubscription(nonexistentId, SUBSCRIBER);
    }

    function test_claimRegistryFee_assetNotFound() public {
        bytes32 nonexistentId = keccak256("nonexistent");
        vm.prank(registryOwner);
        vm.expectRevert(AssetRegistry.AssetNotFound.selector);
        assetRegistry.claimRegistryFee(nonexistentId, SUBSCRIBER);
    }

    // --- getFeeShares ---

    function test_getFeeShares() public view {
        (uint256 creatorFeeShare, uint256 registryFeeShare) = assetRegistry.getFeeShares();
        assertEq(creatorFeeShare, 70);
        assertEq(registryFeeShare, 30);
        assertEq(creatorFeeShare + registryFeeShare, 100);
    }

    // --- Batch claimRegistryFee ---

    function test_claimRegistryFee_batch() public {
        bytes32 subscriber2 = keccak256("subscriber_2");
        _subscribe(DURATION);
        _subscribeFor(subscriber2, DURATION);

        uint256 value = assetRegistry.getSubscriptionPrice(ASSET_ID, DURATION);
        uint256 registryFeePerSubscriber = assetRegistry.getRegistryFee(value);
        vm.warp(block.timestamp + DURATION);

        bytes32[] memory subs = new bytes32[](2);
        subs[0] = SUBSCRIBER;
        subs[1] = subscriber2;

        uint256 registryOwnerBalanceBefore = testToken.balanceOf(registryOwner);

        vm.startPrank(registryOwner);
        // Batch claims emit a single RegistryFeeClaimedBatch event (not per-subscriber RegistryFeeClaimed).
        vm.expectEmit(true, false, false, true);
        emit AssetRegistry.RegistryFeeClaimedBatch(ASSET_ID, subs, registryFeePerSubscriber * 2);
        uint256 claimed = assetRegistry.claimRegistryFee(ASSET_ID, subs);
        vm.stopPrank();

        assertEq(claimed, registryFeePerSubscriber * 2);
        assertEq(testToken.balanceOf(registryOwner), registryOwnerBalanceBefore + claimed);
    }

    function test_claimRegistryFee_batch_unauthorized() public {
        _subscribe(DURATION);
        vm.warp(block.timestamp + DURATION);

        bytes32[] memory subs = new bytes32[](1);
        subs[0] = SUBSCRIBER;

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, UNAUTHORIZED));
        assetRegistry.claimRegistryFee(ASSET_ID, subs);
    }

    function test_claimRegistryFee_batch_assetNotFound() public {
        bytes32 nonexistentId = keccak256("nonexistent");

        bytes32[] memory subs = new bytes32[](1);
        subs[0] = SUBSCRIBER;

        vm.prank(registryOwner);
        vm.expectRevert(AssetRegistry.AssetNotFound.selector);
        assetRegistry.claimRegistryFee(nonexistentId, subs);
    }

    // --- cancelSubscription ---

    function test_cancelSubscription() public {
        uint256 tokenBalanceBefore = testToken.balanceOf(signer);
        _subscribe(DURATION);

        assertEq(testToken.balanceOf(signer), tokenBalanceBefore - asset.getSubscriptionPrice(DURATION));

        vm.prank(registryOwner);
        assetRegistry.cancelSubscription(ASSET_ID, SUBSCRIBER);

        assertFalse(assetRegistry.isSubscriptionActive(ASSET_ID, SUBSCRIBER));
        assertEq(testToken.balanceOf(signer), tokenBalanceBefore);
    }

    function test_cancelSubscription_unauthorized() public {
        _subscribe(DURATION);

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, UNAUTHORIZED));
        assetRegistry.cancelSubscription(ASSET_ID, SUBSCRIBER);
    }

    function test_cancelSubscription_assetNotFound() public {
        bytes32 nonexistentId = keccak256("nonexistent");

        vm.prank(registryOwner);
        vm.expectRevert(AssetRegistry.AssetNotFound.selector);
        assetRegistry.cancelSubscription(nonexistentId, SUBSCRIBER);
    }

    // --- RegistryFeeClaimedBatch event on batch claimRegistryFee ---

    function test_claimRegistryFee_batch_emitsRegistryFeeClaimedBatch() public {
        bytes32 subscriber2 = keccak256("subscriber_2");
        _subscribe(DURATION);
        _subscribeFor(subscriber2, DURATION);
        vm.warp(block.timestamp + DURATION);

        bytes32[] memory subs = new bytes32[](2);
        subs[0] = SUBSCRIBER;
        subs[1] = subscriber2;

        uint256 value = assetRegistry.getSubscriptionPrice(ASSET_ID, DURATION);
        uint256 totalFee = assetRegistry.getRegistryFee(value) * 2;

        vm.prank(registryOwner);
        vm.expectEmit(true, true, true, true);
        emit AssetRegistry.RegistryFeeClaimedBatch(ASSET_ID, subs, totalFee);
        assetRegistry.claimRegistryFee(ASSET_ID, subs);
    }

    function test_claimRegistryFee_batch_emitsRegistryFeeClaimedBatch_zeroFee() public {
        _subscribe(DURATION);

        bytes32[] memory subs = new bytes32[](1);
        subs[0] = SUBSCRIBER;

        // Nothing is claimable yet — totalAmount should be 0.
        vm.prank(registryOwner);
        vm.expectEmit(true, true, true, true);
        emit AssetRegistry.RegistryFeeClaimedBatch(ASSET_ID, subs, 0);
        uint256 claimed = assetRegistry.claimRegistryFee(ASSET_ID, subs);

        assertEq(claimed, 0);
    }

    // --- Expired subscription creates a new nonce (integration via registry) ---

    function test_subscribe_expiredSubscription_createsNewNonce_viaRegistry() public {
        uint256 endTime = _subscribe(DURATION);

        vm.warp(endTime + 1);

        // Re-subscribe with same terms after expiry — should produce a new nonce, not extend.
        uint256 newEnd = block.timestamp + DURATION;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(SUBSCRIBER, block.timestamp, newEnd, 1, signer);
        _subscribe(DURATION);

        assertEq(assetRegistry.getSubscription(ASSET_ID, SUBSCRIBER), newEnd);
    }

}