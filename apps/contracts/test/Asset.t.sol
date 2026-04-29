// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./Base.t.sol";
import {Asset} from "../src/Asset.sol";
import {IAsset} from "../src/IAsset.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Vm} from "forge-std/Vm.sol";

contract AssetTest is BaseTest {
    function test_getAssetId() public view {
        assertEq(asset.getAssetId(), ASSET_ID);
    }

    function test_getRegistryAddress() public view {
        assertEq(asset.getRegistryAddress(), address(assetRegistry));
    }

    function test_getTokenAddress() public view {
        assertEq(asset.getTokenAddress(), address(testToken));
    }

    function test_getSubscriptionPrice() public view {
        // subscriptionPrice is per-period; total = count * SUBSCRIPTION_PRICE
        uint256 expectedPrice = SUBSCRIPTION_PRICE * 10;
        assertEq(asset.getSubscriptionPrice(10), expectedPrice);
    }

    function test_getSubscriptionDuration_immutable() public view {
        assertEq(asset.getSubscriptionDuration(), SUBSCRIPTION_DURATION);
    }

    function test_getSubscriptionDuration() public view {
        // 3 periods worth of tokens = 3 * SUBSCRIPTION_DURATION seconds
        uint256 value = SUBSCRIPTION_PRICE * 3;
        assertEq(asset.getSubscriptionDuration(value), 3 * SUBSCRIPTION_DURATION);
    }

    function test_getSubscriptionDuration_roundsDown() public view {
        // Value covers 3 whole periods plus a partial period, should floor to 3
        uint256 value = SUBSCRIPTION_PRICE * 4 - 1;
        assertEq(asset.getSubscriptionDuration(value), 3 * SUBSCRIPTION_DURATION);
    }

    function test_getSubscriptionPriceAndDuration() public view {
        (uint256 price, uint256 duration) = asset.getSubscriptionPriceAndDuration(5);
        assertEq(price, SUBSCRIPTION_PRICE * 5);
        assertEq(duration, 5 * SUBSCRIPTION_DURATION);
    }

    function _subscribe(uint256 duration) internal returns (uint256 subscription) {
        address payer = signer;
        address spender = address(asset);
        
        uint256 value = asset.getSubscriptionPrice(duration);

        uint256 deadline = block.timestamp + duration;
        
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);        

        subscription = asset.subscribe(SUBSCRIBER, payer, spender, value, deadline, v, r, s);
        
        return subscription;
    }

    function _subscribeFor(bytes32 subscriber, uint256 duration) internal returns (uint256 subscription) {
        address payer = signer;
        address spender = address(asset);

        uint256 value = asset.getSubscriptionPrice(duration);
        uint256 deadline = block.timestamp + duration;

        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);

        subscription = asset.subscribe(subscriber, payer, spender, value, deadline, v, r, s);

        return subscription;
    }

    function test_subscribe() public {
        uint256 expectedFee = SUBSCRIPTION_PRICE * DURATION;
        uint256 signerBalanceBefore = testToken.balanceOf(signer);
        uint256 assetBalanceBefore = testToken.balanceOf(address(asset));

        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(SUBSCRIBER, block.timestamp, block.timestamp + DURATION, 0, signer);

        uint256 subscription = _subscribe(DURATION);

        assertTrue(subscription > block.timestamp);
        
        assertEq(asset.getSubscription(SUBSCRIBER), subscription);
        assertEq(testToken.balanceOf(address(asset)), assetBalanceBefore + expectedFee, "Asset should receive expected fee");
        assertEq(testToken.balanceOf(signer), signerBalanceBefore - expectedFee, "Signer balance should decrease by expected fee");
    }

    function test_subscribe_multiple() public {
        uint256 deadline = block.timestamp;
        uint256 count = 10;

        for (uint256 i = 0; i < count; i++) {
            vm.expectEmit(true, true, true, true);
            if (i == 0) {
                emit Asset.SubscriptionAdded(SUBSCRIBER, deadline, deadline + DURATION, i, signer);
            } else {
                emit Asset.SubscriptionExtended(SUBSCRIBER, deadline + DURATION);
            }
            _subscribe(DURATION);
            deadline += DURATION;
        }

        assertEq(asset.getSubscription(SUBSCRIBER), block.timestamp + (DURATION * count));
    }

    function test_subscribe_multiple_subscriptionPrice() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        
        _subscribe(DURATION);

        uint256 value = asset.getSubscriptionPrice(DURATION);

        vm.startPrank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        vm.stopPrank();

        _subscribe(DURATION);

        value += asset.getSubscriptionPrice(DURATION);

        assertEq(value, 3 * (SUBSCRIPTION_PRICE * DURATION));
        assertEq(testToken.balanceOf(signer), tokenBalance - value);
    }

    function test_claimCreatorFee() public {
        test_subscribe();

        uint256 value = asset.getSubscriptionPrice(DURATION);
        vm.warp(block.timestamp + DURATION);

        vm.startPrank(assetOwner);
        uint256 creatorFee = assetRegistry.getCreatorFee(value);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(SUBSCRIBER, creatorFee);
        uint256 claimedCreatorFee = asset.claimCreatorFee(SUBSCRIBER);
        vm.stopPrank();

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), claimedCreatorFee);
    }

    function test_claimCreatorFee_multiple() public {
        test_subscribe_multiple();

        vm.prank(signer);
        uint256 endTime = asset.getSubscription(SUBSCRIBER);
        uint256 value = asset.getSubscriptionPrice(endTime - block.timestamp);
        vm.warp(endTime);

        vm.startPrank(assetOwner);

        uint256 creatorFee = assetRegistry.getCreatorFee(value);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(SUBSCRIBER, creatorFee);
        
        uint256 claimedCreatorFee = asset.claimCreatorFee(SUBSCRIBER);
        
        vm.stopPrank();
        
        assertEq(claimedCreatorFee, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), claimedCreatorFee);
    }

    function test_claimCreatorFee_multiple_subscriptionPrice() public {
        uint256 tokenBalance = testToken.balanceOf(assetOwner);
        
        _subscribe(DURATION);

        uint256 value = asset.getSubscriptionPrice(DURATION);

        vm.startPrank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        vm.stopPrank();

        _subscribe(DURATION);
        
        value += asset.getSubscriptionPrice(DURATION);

        uint256 creatorFee = assetRegistry.getCreatorFee(value);

        vm.warp(block.timestamp + (DURATION * 2));

        vm.startPrank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(SUBSCRIBER, creatorFee);
        uint256 claimedCreatorFee = asset.claimCreatorFee(SUBSCRIBER);
        vm.stopPrank();

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), tokenBalance + claimedCreatorFee);
    }

    function test_claimCreatorFee_midSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(assetOwner);
        test_subscribe();
        
        uint256 value = asset.getSubscriptionPrice(DURATION);
        vm.warp(block.timestamp + (DURATION / 2));
    
        vm.startPrank(assetOwner);
        uint256 creatorFee = assetRegistry.getCreatorFee(value) / 2;
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(SUBSCRIBER, creatorFee);
        uint256 claimedCreatorFee = asset.claimCreatorFee(SUBSCRIBER);
        vm.stopPrank();

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), tokenBalance + claimedCreatorFee);
    }

    function test_claimCreatorFee_multiple_creatorFeeShare() public {
        
        uint256 registryFeeShare = assetRegistry.getRegistryFeeShare();
        uint256 tokenBalance = testToken.balanceOf(assetOwner);

        _subscribe(DURATION);

        vm.prank(registryOwner);
        assetRegistry.updateRegistryFeeShare(40);

        uint256 endTime = _subscribe(DURATION);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 creatorFee = assetRegistry.getCreatorFee(value) + (value - ((value * registryFeeShare) / 100));
        vm.warp(endTime);

        vm.prank(assetOwner);
        uint256 claimedCreatorFee = asset.claimCreatorFee(SUBSCRIBER);

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), tokenBalance + claimedCreatorFee);
    }

    function test_claimCreatorFee_multiple_registryFeeShare() public {
        uint256 registryFeeShare = assetRegistry.getRegistryFeeShare();
        uint256 tokenBalance = testToken.balanceOf(assetOwner);

        _subscribe(DURATION);

        vm.prank(registryOwner);
        assetRegistry.updateRegistryFeeShare(50);

        uint256 endTime = _subscribe(DURATION);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 creatorFee = assetRegistry.getCreatorFee(value) + (value - ((value * registryFeeShare) / 100));
        vm.warp(endTime);

        vm.prank(assetOwner);
        uint256 claimedCreatorFee = asset.claimCreatorFee(SUBSCRIBER);

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), tokenBalance + claimedCreatorFee);
    }

    function test_claimCreatorFee_startOfNextSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(assetOwner);
        
        uint256 endTime = _subscribe(DURATION);
        
        uint256 value = asset.getSubscriptionPrice(DURATION);
        
        _subscribe(DURATION);

        vm.warp(endTime);
        
        vm.startPrank(assetOwner);
        uint256 creatorFee = assetRegistry.getCreatorFee(value);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(SUBSCRIBER, creatorFee);
        uint256 claimedCreatorFee = asset.claimCreatorFee(SUBSCRIBER);
        vm.stopPrank();

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), tokenBalance + claimedCreatorFee);
    }

    function test_setSubscriptionPrice() public {
        uint256 newPrice = 200;

        vm.startPrank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionPriceUpdated(newPrice);
        asset.setSubscriptionPrice(newPrice);
        vm.stopPrank();

        assertEq(asset.getSubscriptionPrice(1), newPrice);
    }

    function test_revokeSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION));

        vm.prank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRevoked(SUBSCRIBER);
        asset.revokeSubscription(SUBSCRIBER);

        assertEq(testToken.balanceOf(signer), tokenBalance);
        assertEq(asset.getSubscription(SUBSCRIBER), 0);
    }

    function test_revokeSubscription_multiple() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        test_subscribe_multiple();

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION * 10));

        vm.prank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRevoked(SUBSCRIBER);
        asset.revokeSubscription(SUBSCRIBER);

        assertEq(testToken.balanceOf(signer), tokenBalance);
        assertEq(asset.getSubscription(SUBSCRIBER), 0);
    }

    function test_revokeSubscription_midSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        for (uint256 i = 0; i < 2; i++) _subscribe(DURATION);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        vm.warp(block.timestamp + DURATION + (DURATION / 2));

        vm.prank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRevoked(SUBSCRIBER);
        asset.revokeSubscription(SUBSCRIBER);

        assertEq(testToken.balanceOf(signer), tokenBalance - (value + (value / 2)));
        // With SUBSCRIPTION_DURATION=1 every second is a refundable period, so the full remaining
        // half-duration is refunded; subscription is immediately marked cancelled, returns 0
        assertEq(asset.getSubscription(SUBSCRIBER), 0);
        assertFalse(asset.isSubscriptionActive(SUBSCRIBER));
    }

    function test_revokeSubscription_endOfSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.warp(block.timestamp + DURATION);
        vm.prank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRevoked(SUBSCRIBER);
        asset.revokeSubscription(SUBSCRIBER);

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION));
        assertEq(asset.getSubscription(SUBSCRIBER), block.timestamp);
    }

    function test_revokeSubscription_multiple_subscriptionPrice() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        _subscribe(DURATION);

        vm.prank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRevoked(SUBSCRIBER);
        asset.revokeSubscription(SUBSCRIBER);

        assertEq(asset.getSubscription(SUBSCRIBER), 0);
        assertEq(testToken.balanceOf(signer), tokenBalance);
    }

    function test_isMySubscriptionActive() public {
        test_subscribe();
        vm.prank(signer);
        assertTrue(asset.isSubscriptionActive(SUBSCRIBER));

        vm.prank(assetOwner);
        asset.revokeSubscription(SUBSCRIBER);

        vm.prank(signer);
        assertFalse(asset.isSubscriptionActive(SUBSCRIBER));
    }

    function test_isMySubscriptionActive_cancelSubscription() public {
        test_subscribe();
        vm.prank(signer);
        assertTrue(asset.isSubscriptionActive(SUBSCRIBER));

        vm.prank(address(assetRegistry));
        asset.cancelSubscription(SUBSCRIBER);

        vm.prank(signer);
        assertFalse(asset.isSubscriptionActive(SUBSCRIBER));
    }

    function test_subscribe_invalidSpender() public {
        address payer = signer;
        address spender = address(1); // Wrong spender - must be address(asset)
        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 deadline = block.timestamp + DURATION;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, address(asset), value, deadline);

        vm.expectRevert(Asset.InvalidSpender.selector);
        asset.subscribe(SUBSCRIBER, payer, spender, value, deadline, v, r, s);
    }

    function test_subscribe_permitFailed() public {
        address payer = signer;
        address spender = address(asset);
        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 deadline = block.timestamp + DURATION;
        // Use invalid signature - wrong v, r, s
        (uint8 v, bytes32 r, bytes32 s) = (0, bytes32(0), bytes32(0));

        vm.expectRevert(Asset.PermitFailed.selector);
        asset.subscribe(SUBSCRIBER, payer, spender, value, deadline, v, r, s);
    }

    function test_subscribe_insufficientFunds() public {
        address payer = signer;
        address spender = address(asset);
        uint256 value = SUBSCRIPTION_PRICE - 1; // Below subscriptionPrice, rounds to 0
        uint256 deadline = block.timestamp + DURATION;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);

        vm.expectRevert(Asset.InsufficientFunds.selector);
        asset.subscribe(SUBSCRIBER, payer, spender, value, deadline, v, r, s);
    }

    function test_setSubscriptionPrice_unauthorized() public {
        vm.prank(UNAUTHORIZED);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, UNAUTHORIZED));
        asset.setSubscriptionPrice(200);
    }

    function test_revokeSubscription_unauthorized() public {
        test_subscribe();
        vm.prank(UNAUTHORIZED);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, UNAUTHORIZED));
        asset.revokeSubscription(SUBSCRIBER);
    }

    function test_revokeSubscription_noSubscription() public {
        vm.prank(assetOwner);
        vm.expectRevert(Asset.SubscriptionNotFound.selector);
        asset.revokeSubscription(SUBSCRIBER);
    }

    function test_cancelSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION));

        vm.prank(address(assetRegistry));
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionCancelled(SUBSCRIBER);
        asset.cancelSubscription(SUBSCRIBER);

        assertEq(testToken.balanceOf(signer), tokenBalance);
        assertEq(asset.getSubscription(SUBSCRIBER), 0);
    }

    function test_cancelSubscription_multiple() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        test_subscribe_multiple();

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION * 10));

        vm.prank(address(assetRegistry));
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionCancelled(SUBSCRIBER);
        asset.cancelSubscription(SUBSCRIBER);

        assertEq(testToken.balanceOf(signer), tokenBalance);
        assertEq(asset.getSubscription(SUBSCRIBER), 0);
    }

    function test_cancelSubscription_midSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        for (uint256 i = 0; i < 2; i++) _subscribe(DURATION);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        vm.warp(block.timestamp + DURATION + (DURATION / 2));

        vm.prank(address(assetRegistry));
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionCancelled(SUBSCRIBER);
        asset.cancelSubscription(SUBSCRIBER);

        assertEq(testToken.balanceOf(signer), tokenBalance - (value + (value / 2)));
        // With SUBSCRIPTION_DURATION=1 every remaining second is a refundable period, so full
        // remaining half-duration is refunded; subscription is immediately marked cancelled, returns 0
        assertEq(asset.getSubscription(SUBSCRIBER), 0);
        assertFalse(asset.isSubscriptionActive(SUBSCRIBER));
    }

    function test_cancelSubscription_endOfSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.warp(block.timestamp + DURATION);
        vm.prank(address(assetRegistry));
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionCancelled(SUBSCRIBER);
        asset.cancelSubscription(SUBSCRIBER);

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION));
        assertEq(asset.getSubscription(SUBSCRIBER), block.timestamp);
    }

    function test_cancelSubscription_multiple_subscriptionPrice() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        _subscribe(DURATION);

        vm.prank(address(assetRegistry));
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionCancelled(SUBSCRIBER);
        asset.cancelSubscription(SUBSCRIBER);

        assertEq(asset.getSubscription(SUBSCRIBER), 0);
        assertEq(testToken.balanceOf(signer), tokenBalance);
    }

    function test_cancelSubscription_noSubscription() public {
        vm.prank(address(assetRegistry));
        vm.expectRevert(Asset.SubscriptionNotFound.selector);
        asset.cancelSubscription(SUBSCRIBER);
    }

    function test_cancelSubscription_unauthorized() public {
        uint256 tokenBalance = testToken.balanceOf(signer);

        test_subscribe();

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(Asset.OnlyRegistryUnauthorizedAccount.selector);
        asset.cancelSubscription(SUBSCRIBER);

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION));
    }

    // Cancel a subscriber with two records in different states (active + future) at different prices.
    // Active record: forfeit started periods, refund remaining whole periods at its own price.
    // Future record: fully refunded at its own price; delete record.
    function test_cancelSubscription_multipleNonces_mixedStates() public {
        uint256 originalPrice = SUBSCRIPTION_PRICE;
        uint256 doubledPrice = SUBSCRIPTION_PRICE * 2;
        uint256 tokenBalance = testToken.balanceOf(signer);

        // Record 0: active, paid at original price
        // SUBSCRIPTION_DURATION=1 means every second is a new period, so we subscribe for DURATION periods
        _subscribe(DURATION);

        // Bump price → next subscribe creates a new nonce queued at end of record 0
        vm.prank(assetOwner);
        asset.setSubscriptionPrice(doubledPrice);

        // Record 1: future (starts at T0 + DURATION), paid at doubled price
        _subscribe(DURATION);

        uint256 paidRecord0 = DURATION * originalPrice;
        uint256 paidRecord1 = DURATION * doubledPrice;
        assertEq(
            testToken.balanceOf(signer),
            tokenBalance - paidRecord0 - paidRecord1,
            "both records charged upfront"
        );

        // Warp half-way into record 0
        vm.warp(block.timestamp + DURATION / 2);

        vm.prank(address(assetRegistry));
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionCancelled(SUBSCRIBER);
        asset.cancelSubscription(SUBSCRIBER);

        // Subscription is immediately inactive and reads as cleared
        assertFalse(asset.isSubscriptionActive(SUBSCRIBER));
        assertEq(asset.getSubscription(SUBSCRIBER), 0);

        // Refund:
        //   record 0 (active): (DURATION/2 seconds remaining) / SUBSCRIPTION_DURATION (=1) periods at original price
        //   record 1 (future): full DURATION periods at doubled price
        uint256 refund0 = (DURATION / 2) * originalPrice;
        uint256 refund1 = paidRecord1;
        uint256 expectedCharged = paidRecord0 + paidRecord1 - refund0 - refund1;

        assertEq(
            testToken.balanceOf(signer),
            tokenBalance - expectedCharged,
            "only first half of record 0 forfeited"
        );
    }

    function test_claimCreatorFee_unauthorized() public {
        test_subscribe();
        vm.warp(block.timestamp + DURATION);

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, UNAUTHORIZED));
        asset.claimCreatorFee(SUBSCRIBER);
    }

    function test_claimRegistryFee_unauthorized() public {
        test_subscribe();
        vm.warp(block.timestamp + DURATION);

        vm.prank(registryOwner);
        vm.expectRevert(Asset.OnlyRegistryUnauthorizedAccount.selector);
        asset.claimRegistryFee(SUBSCRIBER);
    }

    function test_feeSplit() public {
        uint256 creatorBalance = testToken.balanceOf(assetOwner);
        uint256 registryBalance = testToken.balanceOf(registryOwner);
        test_subscribe();

        uint256 value = asset.getSubscriptionPrice(DURATION);
        (uint256 creatorFee, uint256 registryFee) = assetRegistry.getFees(value);

        vm.warp(block.timestamp + DURATION);

        vm.prank(assetOwner);
        uint256 claimedCreatorFee = asset.claimCreatorFee(SUBSCRIBER);

        vm.prank(address(assetRegistry));
        uint256 claimedRegistryFee = asset.claimRegistryFee(SUBSCRIBER);

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(claimedRegistryFee, registryFee);
        assertEq(testToken.balanceOf(assetOwner), creatorBalance + creatorFee);
        assertEq(testToken.balanceOf(registryOwner), registryBalance + registryFee);
    }

    function test_getSubscription_nonexistentSubscriber() public view {
        bytes32 unknownSubscriber = keccak256("unknown");
        assertEq(asset.getSubscription(unknownSubscriber), 0);
    }

    function test_isSubscriptionActive_nonexistentSubscriber() public view {
        bytes32 unknownSubscriber = keccak256("unknown");
        assertFalse(asset.isSubscriptionActive(unknownSubscriber));
    }

    function test_subscribe_expiredDeadline() public {
        address payer = signer;
        address spender = address(asset);
        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 deadline = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);

        vm.expectRevert(Asset.PermitFailed.selector);
        asset.subscribe(SUBSCRIBER, payer, spender, value, deadline, v, r, s);
    }

    function test_claimCreatorFee_zeroClaimable() public {
        _subscribe(DURATION);
        uint256 assetOwnerBalanceBefore = testToken.balanceOf(assetOwner);

        vm.prank(assetOwner);
        uint256 claimed = asset.claimCreatorFee(SUBSCRIBER);

        assertEq(claimed, 0);
        assertEq(testToken.balanceOf(assetOwner), assetOwnerBalanceBefore);
    }

    function test_claimRegistryFee_zeroClaimable() public {
        _subscribe(DURATION);
        uint256 registryOwnerBalanceBefore = testToken.balanceOf(registryOwner);

        vm.prank(address(assetRegistry));
        uint256 claimed = asset.claimRegistryFee(SUBSCRIBER);

        assertEq(claimed, 0);
        assertEq(testToken.balanceOf(registryOwner), registryOwnerBalanceBefore);
    }

    function test_claimCreatorFee_subscriberWithNoSubscription() public {
        bytes32 neverSubscribed = keccak256("never_subscribed");
        uint256 assetOwnerBalanceBefore = testToken.balanceOf(assetOwner);

        vm.prank(assetOwner);
        uint256 claimed = asset.claimCreatorFee(neverSubscribed);

        assertEq(claimed, 0);
        assertEq(testToken.balanceOf(assetOwner), assetOwnerBalanceBefore);
    }

    function test_claimRegistryFee_subscriberWithNoSubscription() public {
        bytes32 neverSubscribed = keccak256("never_subscribed");
        uint256 registryOwnerBalanceBefore = testToken.balanceOf(registryOwner);

        vm.prank(address(assetRegistry));
        uint256 claimed = asset.claimRegistryFee(neverSubscribed);

        assertEq(claimed, 0);
        assertEq(testToken.balanceOf(registryOwner), registryOwnerBalanceBefore);
    }

    // --- Subscription extension: new nonce when conditions differ ---

    function test_subscribe_newNonce_differentPrice() public {
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(SUBSCRIBER, block.timestamp, block.timestamp + DURATION, 0, signer);
        _subscribe(DURATION);

        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);

        uint256 newStart = block.timestamp + DURATION;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(SUBSCRIBER, newStart, newStart + DURATION, 1, signer);
        _subscribe(DURATION);
    }

    function test_subscribe_newNonce_feeShareChanged() public {
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(SUBSCRIBER, block.timestamp, block.timestamp + DURATION, 0, signer);
        _subscribe(DURATION);

        vm.prank(registryOwner);
        assetRegistry.updateRegistryFeeShare(50);

        uint256 newStart = block.timestamp + DURATION;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(SUBSCRIBER, newStart, newStart + DURATION, 1, signer);
        _subscribe(DURATION);
    }

    function test_subscribe_newNonce_differentPayer() public {
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(SUBSCRIBER, block.timestamp, block.timestamp + DURATION, 0, signer);
        _subscribe(DURATION);

        uint256 key2 = vm.deriveKey(MNEMONIC, 1);
        address payer2 = vm.addr(key2);
        testToken.mint(payer2, 1e30);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 deadline = block.timestamp + DURATION * 2;
        uint256 nonce2 = testToken.nonces(payer2);
        bytes32 permitHash = keccak256(abi.encode(PERMIT_TYPEHASH, payer2, address(asset), value, nonce2, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", testToken.DOMAIN_SEPARATOR(), permitHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key2, digest);

        uint256 newStart = block.timestamp + DURATION;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(SUBSCRIBER, newStart, newStart + DURATION, 1, payer2);
        asset.subscribe(SUBSCRIBER, payer2, address(asset), value, deadline, v, r, s);
    }

    // --- Batch claimCreatorFee ---

    function test_claimCreatorFee_batch() public {
        bytes32 subscriber2 = keccak256("subscriber_2");
        _subscribe(DURATION);
        _subscribeFor(subscriber2, DURATION);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 creatorFeePerSubscriber = assetRegistry.getCreatorFee(value);
        vm.warp(block.timestamp + DURATION);

        bytes32[] memory subs = new bytes32[](2);
        subs[0] = SUBSCRIBER;
        subs[1] = subscriber2;

        uint256 assetOwnerBalanceBefore = testToken.balanceOf(assetOwner);

        vm.startPrank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(SUBSCRIBER, creatorFeePerSubscriber);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(subscriber2, creatorFeePerSubscriber);
        uint256 claimed = asset.claimCreatorFee(subs);
        vm.stopPrank();

        assertEq(claimed, creatorFeePerSubscriber * 2);
        assertEq(testToken.balanceOf(assetOwner), assetOwnerBalanceBefore + claimed);
    }

    function test_claimCreatorFee_batch_unauthorized() public {
        _subscribe(DURATION);
        vm.warp(block.timestamp + DURATION);

        bytes32[] memory subs = new bytes32[](1);
        subs[0] = SUBSCRIBER;

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, UNAUTHORIZED));
        asset.claimCreatorFee(subs);
    }

    function test_claimCreatorFee_batch_skipsNonExistentSubscribers() public {
        bytes32 neverSubscribed = keccak256("never_subscribed");
        _subscribe(DURATION);
        vm.warp(block.timestamp + DURATION);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 creatorFee = assetRegistry.getCreatorFee(value);

        bytes32[] memory subs = new bytes32[](2);
        subs[0] = SUBSCRIBER;
        subs[1] = neverSubscribed;

        uint256 assetOwnerBalanceBefore = testToken.balanceOf(assetOwner);

        vm.prank(assetOwner);
        uint256 claimed = asset.claimCreatorFee(subs);

        assertEq(claimed, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), assetOwnerBalanceBefore + claimed);
    }

    function test_claimCreatorFee_batch_skipsZeroFee() public {
        bytes32 subscriber2 = keccak256("subscriber_2");
        _subscribe(DURATION);
        _subscribeFor(subscriber2, DURATION);

        bytes32[] memory subs = new bytes32[](2);
        subs[0] = SUBSCRIBER;
        subs[1] = subscriber2;

        uint256 assetOwnerBalanceBefore = testToken.balanceOf(assetOwner);

        vm.prank(assetOwner);
        uint256 claimed = asset.claimCreatorFee(subs);

        assertEq(claimed, 0);
        assertEq(testToken.balanceOf(assetOwner), assetOwnerBalanceBefore);
    }

    // --- Batch claimRegistryFee ---

    function test_claimRegistryFee_batch() public {
        bytes32 subscriber2 = keccak256("subscriber_2");
        _subscribe(DURATION);
        _subscribeFor(subscriber2, DURATION);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 registryFeePerSubscriber = assetRegistry.getRegistryFee(value);
        vm.warp(block.timestamp + DURATION);

        bytes32[] memory subs = new bytes32[](2);
        subs[0] = SUBSCRIBER;
        subs[1] = subscriber2;

        uint256 registryOwnerBalanceBefore = testToken.balanceOf(registryOwner);

        vm.startPrank(address(assetRegistry));
        uint256 claimed = asset.claimRegistryFee(subs);
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
        vm.expectRevert(Asset.OnlyRegistryUnauthorizedAccount.selector);
        asset.claimRegistryFee(subs);
    }

    function test_claimRegistryFee_batch_skipsNonExistentSubscribers() public {
        bytes32 neverSubscribed = keccak256("never_subscribed");
        _subscribe(DURATION);
        vm.warp(block.timestamp + DURATION);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 registryFee = assetRegistry.getRegistryFee(value);

        bytes32[] memory subs = new bytes32[](2);
        subs[0] = SUBSCRIBER;
        subs[1] = neverSubscribed;

        uint256 registryOwnerBalanceBefore = testToken.balanceOf(registryOwner);

        vm.prank(address(assetRegistry));
        uint256 claimed = asset.claimRegistryFee(subs);

        assertEq(claimed, registryFee);
        assertEq(testToken.balanceOf(registryOwner), registryOwnerBalanceBefore + claimed);
    }

    function test_claimRegistryFee_batch_skipsZeroFee() public {
        bytes32 subscriber2 = keccak256("subscriber_2");
        _subscribe(DURATION);
        _subscribeFor(subscriber2, DURATION);

        bytes32[] memory subs = new bytes32[](2);
        subs[0] = SUBSCRIBER;
        subs[1] = subscriber2;

        uint256 registryOwnerBalanceBefore = testToken.balanceOf(registryOwner);

        vm.prank(address(assetRegistry));
        uint256 claimed = asset.claimRegistryFee(subs);

        assertEq(claimed, 0);
        assertEq(testToken.balanceOf(registryOwner), registryOwnerBalanceBefore);
    }

    // --- Expired subscription creates a new nonce (no in-place extension) ---

    function test_subscribe_expiredSubscription_createsNewNonce() public {
        uint256 endTime = _subscribe(DURATION);

        // Let the subscription fully expire
        vm.warp(endTime + 1);

        // Re-subscribe with the same payer, price and fee share — since the subscription expired,
        // startTime (block.timestamp) != subscription.endTime, so no in-place extension occurs.
        uint256 newEnd = block.timestamp + DURATION;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(SUBSCRIBER, block.timestamp, newEnd, 1, signer);
        uint256 returnedEnd = _subscribe(DURATION);

        assertEq(returnedEnd, newEnd);
        assertEq(asset.getSubscription(SUBSCRIBER), newEnd);
    }

    // --- Claim tracking resets correctly after all subscriptions are revoked ---

    function test_claimCreatorFee_afterRevokeAndResubscribe() public {
        // Subscribe and immediately revoke: subscription hasn't elapsed so it is fully deleted
        // (startTime == block.timestamp satisfies the "not yet started" branch in _removeSubscription).
        // This also clears all claim-tracking state (creatorClaimedAtNonces/Timestamps, etc.).
        _subscribe(DURATION);
        vm.prank(assetOwner);
        asset.revokeSubscription(SUBSCRIBER);
        assertEq(asset.getSubscription(SUBSCRIBER), 0);

        // Re-subscribe at a different price to prove claim tracking starts fresh with a new nonce 0.
        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        uint256 endTime = _subscribe(DURATION);
        vm.warp(endTime);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 expectedFee = assetRegistry.getCreatorFee(value);

        vm.prank(assetOwner);
        uint256 claimed = asset.claimCreatorFee(SUBSCRIBER);
        assertEq(claimed, expectedFee);
    }

    function test_claimRegistryFee_afterRevokeAndResubscribe() public {
        // Subscribe and immediately revoke for a clean full-deletion and tracking reset.
        _subscribe(DURATION);
        vm.prank(assetOwner);
        asset.revokeSubscription(SUBSCRIBER);
        assertEq(asset.getSubscription(SUBSCRIBER), 0);

        // Re-subscribe from scratch; claim tracking must have been reset.
        uint256 endTime = _subscribe(DURATION);
        vm.warp(endTime);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 expectedFee = assetRegistry.getRegistryFee(value);

        vm.prank(address(assetRegistry));
        uint256 claimed = asset.claimRegistryFee(SUBSCRIBER);
        assertEq(claimed, expectedFee);
    }
}

// ─── Hourly-period asset: subscribe/extend/round-down tests ──────────────────

contract AssetHourlyTest is BaseTest {
    uint256 internal constant HOUR = 3600;
    IAsset internal hourlyAsset;
    bytes32 internal constant HOURLY_ASSET_ID = keccak256(abi.encodePacked("hourly_asset_id"));

    function setUp() public override {
        super.setUp();
        vm.startPrank(registryOwner);
        hourlyAsset = IAsset(assetRegistry.createAsset(HOURLY_ASSET_ID, SUBSCRIPTION_PRICE, HOUR, address(testToken), assetOwner));
        vm.stopPrank();
    }

    function _subscribeHourly(uint256 count) internal returns (uint256 endTime) {
        address payer = signer;
        address spender = address(hourlyAsset);
        uint256 value = hourlyAsset.getSubscriptionPrice(count);
        uint256 deadline = block.timestamp + 1;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);
        endTime = hourlyAsset.subscribe(SUBSCRIBER, payer, spender, value, deadline, v, r, s);
    }

    function test_hourly_getSubscriptionDuration_immutable() public view {
        assertEq(hourlyAsset.getSubscriptionDuration(), HOUR);
    }

    function test_hourly_getSubscriptionDuration_wholePeriods() public view {
        uint256 value = SUBSCRIPTION_PRICE * 3;
        assertEq(hourlyAsset.getSubscriptionDuration(value), 3 * HOUR);
    }

    function test_hourly_getSubscriptionDuration_roundsDown() public view {
        // Add a half-period worth of tokens — should still round down to 3 periods
        uint256 value = SUBSCRIPTION_PRICE * 3 + (SUBSCRIPTION_PRICE / 2);
        assertEq(hourlyAsset.getSubscriptionDuration(value), 3 * HOUR);
    }

    function test_hourly_getSubscriptionPriceAndDuration() public view {
        (uint256 price, uint256 duration) = hourlyAsset.getSubscriptionPriceAndDuration(5);
        assertEq(price, SUBSCRIPTION_PRICE * 5);
        assertEq(duration, 5 * HOUR);
    }

    function test_hourly_subscribe_fullPeriods() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = _subscribeHourly(3);
        assertEq(endTime, startTime + 3 * HOUR);
        assertEq(hourlyAsset.getSubscription(SUBSCRIBER), startTime + 3 * HOUR);
    }

    function test_hourly_subscribe_valueRoundedDown() public {
        // Pay for 3.5 periods; only 3 full periods charged and subscribed
        address payer = signer;
        address spender = address(hourlyAsset);
        uint256 fullValue = SUBSCRIPTION_PRICE * 3;
        uint256 halfPeriodCost = SUBSCRIPTION_PRICE / 2;
        uint256 value = fullValue + halfPeriodCost;
        uint256 deadline = block.timestamp + 4 * HOUR;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);

        uint256 signerBalanceBefore = testToken.balanceOf(signer);
        uint256 endTime = hourlyAsset.subscribe(SUBSCRIBER, payer, spender, value, deadline, v, r, s);

        assertEq(endTime, block.timestamp + 3 * HOUR, "Subscribed for 3 full hours only");
        assertEq(testToken.balanceOf(signer), signerBalanceBefore - fullValue, "Only 3 hours charged");
    }

    function test_hourly_subscribe_insufficientFunds_lessThanOnePeriod() public {
        address payer = signer;
        address spender = address(hourlyAsset);
        uint256 value = SUBSCRIPTION_PRICE - 1; // Just under one period cost
        uint256 deadline = block.timestamp + HOUR;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);

        vm.expectRevert(Asset.InsufficientFunds.selector);
        hourlyAsset.subscribe(SUBSCRIBER, payer, spender, value, deadline, v, r, s);
    }

    function test_hourly_extend_samePayer() public {
        _subscribeHourly(3); // ends at T0 + 3*HOUR
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionExtended(SUBSCRIBER, block.timestamp + 6 * HOUR);
        _subscribeHourly(3); // extends by 3 hours, should end at T0 + 6*HOUR
        assertEq(hourlyAsset.getSubscription(SUBSCRIBER), block.timestamp + 6 * HOUR);
    }

    function test_hourly_newNonce_afterPriceChange() public {
        _subscribeHourly(3); // nonce 0, ends at T0 + 3*HOUR

        vm.prank(assetOwner);
        hourlyAsset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);

        uint256 newStart = block.timestamp + 3 * HOUR;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(SUBSCRIBER, newStart, newStart + 3 * HOUR, 1, signer);
        _subscribeHourly(3); // nonce 1, starts at T0 + 3 * HOUR with new price
    }

    // Mid-period claims: only fully-passed periods are payable, no dust loss.
    // Uses relative warps (block.timestamp + delta) rather than captured-timestamp +
    // delta to avoid via_ir optimizer rewriting the captured local at the warp call site.
    function test_hourly_claimCreatorFee_midPeriod() public {
        _subscribeHourly(3); // 3 periods of 1 hour each, paid 3 * SUBSCRIPTION_PRICE

        uint256 creatorShare = (SUBSCRIPTION_PRICE * 70) / 100; // 70% creator share per period
        uint256 ownerBalanceBefore = testToken.balanceOf(assetOwner);

        // +30 min (mid period 1): no full period elapsed → claim 0
        vm.warp(block.timestamp + 1800);
        vm.prank(assetOwner);
        assertEq(hourlyAsset.claimCreatorFee(SUBSCRIBER), 0, "no full period yet");

        // +1 hour (now at 90 min total, mid period 2): period 1 fully passed → 1 period
        vm.warp(block.timestamp + 3600);
        vm.prank(assetOwner);
        assertEq(hourlyAsset.claimCreatorFee(SUBSCRIBER), creatorShare, "1 period after 90 min");

        // +29 min 59 sec (now at 119 min 59 sec, last second of period 2): no new full period
        vm.warp(block.timestamp + 1799);
        vm.prank(assetOwner);
        assertEq(hourlyAsset.claimCreatorFee(SUBSCRIBER), 0, "still inside period 2");

        // +60 min 1 sec (now at 3 hours = subscription end): periods 2 and 3 now fully passed
        vm.warp(block.timestamp + 3601);
        vm.prank(assetOwner);
        assertEq(hourlyAsset.claimCreatorFee(SUBSCRIBER), 2 * creatorShare, "remaining 2 periods");

        // Total claimed equals creator's share of full payment — no dust
        assertEq(testToken.balanceOf(assetOwner), ownerBalanceBefore + 3 * creatorShare);
    }

    // Subscribe → cancel mid-period → subscribe again → cancel mid-period again.
    // Each cancel forfeits exactly one in-progress period. After everything expires,
    // total accrued fee across creator + registry equals 2 * SUBSCRIPTION_PRICE.
    function test_hourly_cancelTwice_feeIsTwoPeriods() public {
        // First subscribe (record 0): 3 hours
        _subscribeHourly(3);

        // Mid period 1 of record 0 (30 min in): cancel — forfeits period 1, refunds periods 2 & 3.
        // After cancel, record 0's truncated endTime = T0 + 1h.
        vm.warp(block.timestamp + 1800);
        vm.prank(address(assetRegistry));
        hourlyAsset.cancelSubscription(SUBSCRIBER);
        assertFalse(hourlyAsset.isSubscriptionActive(SUBSCRIBER));

        // Re-subscribe (record 1): _subscribe sees the cancelled record at nonce 0 and bumps to nonce 1.
        // New record's startTime = max(now, oldRecord.endTime) = T0 + 1h. Block.timestamp is still T0 + 30 min.
        _subscribeHourly(3);

        // Warp 1h further so block.timestamp = T0 + 1h 30 min — i.e. 30 min into period 1 of record 1
        vm.warp(block.timestamp + 3600);
        vm.prank(address(assetRegistry));
        hourlyAsset.cancelSubscription(SUBSCRIBER);
        assertFalse(hourlyAsset.isSubscriptionActive(SUBSCRIBER));

        // Warp far past everything so all periods are eligible to be claimed
        vm.warp(block.timestamp + 100 * HOUR);

        uint256 creatorShare = (SUBSCRIPTION_PRICE * 70) / 100;
        uint256 registrySharePerPeriod = SUBSCRIPTION_PRICE - creatorShare;

        vm.prank(assetOwner);
        uint256 creatorClaimed = hourlyAsset.claimCreatorFee(SUBSCRIBER);

        vm.prank(address(assetRegistry));
        uint256 registryClaimed = hourlyAsset.claimRegistryFee(SUBSCRIBER);

        // Each cancel charged exactly one period worth of fees → 2 periods total
        assertEq(creatorClaimed, 2 * creatorShare, "creator share = 2 periods");
        assertEq(registryClaimed, 2 * registrySharePerPeriod, "registry share = 2 periods");
        assertEq(creatorClaimed + registryClaimed, 2 * SUBSCRIPTION_PRICE, "total fee = 2 * subscriptionPrice");
    }
}

// ─── Cancel / revoke with subscriptionDuration = 3 months ────────────────────

contract AssetPeriodicCancelTest is BaseTest {
    // subscriptionDuration = 3 months = 90 days
    uint256 internal constant PERIOD_SIZE = 7_776_000;
    // 1 "month" used for scenario offsets = PERIOD_SIZE / 3
    uint256 internal constant MONTH = PERIOD_SIZE / 3;

    bytes32 internal constant PERIODIC_ASSET_ID = keccak256(abi.encodePacked("periodic_asset_id"));

    function setUp() public override {
        super.setUp();
        vm.startPrank(registryOwner);
        asset = IAsset(assetRegistry.createAsset(PERIODIC_ASSET_ID, SUBSCRIPTION_PRICE, PERIOD_SIZE, address(testToken), assetOwner));
        vm.stopPrank();
    }

    function _subscribePeriods(uint256 count) internal returns (uint256 endTime) {
        address payer = signer;
        address spender = address(asset);
        uint256 value = asset.getSubscriptionPrice(count);
        uint256 deadline = block.timestamp + count * PERIOD_SIZE + 1;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);
        endTime = asset.subscribe(SUBSCRIBER, payer, spender, value, deadline, v, r, s);
    }

    // Scenario 1: cancel at month 2: refund 2 periods, fee 1 period (period 1)
    function test_cancel_scenario1_atMonth2() public {
        uint256 startTime = block.timestamp;
        uint256 signerBalanceBefore = testToken.balanceOf(signer);
        _subscribePeriods(3);

        vm.warp(startTime + 2 * MONTH);
        vm.prank(address(assetRegistry));
        asset.cancelSubscription(SUBSCRIBER);

        assertFalse(asset.isSubscriptionActive(SUBSCRIBER));
        assertEq(asset.getSubscription(SUBSCRIBER), 0);

        uint256 charged = 1 * SUBSCRIPTION_PRICE; // 1 period
        assertEq(testToken.balanceOf(signer), signerBalanceBefore - charged, "Only period 1 charged");

        // Claim after period 1 fully elapsed
        vm.warp(startTime + PERIOD_SIZE + 1);
        uint256 creatorFee = charged * (100 - assetRegistry.getRegistryFeeShare()) / 100;
        vm.prank(assetOwner);
        assertEq(asset.claimCreatorFee(SUBSCRIBER), creatorFee, "Creator fee for period 1");
    }

    // Scenario 2: cancel at month 4: refund 1 period (period 3), fee 2 periods (periods 1+2)
    function test_cancel_scenario2_atMonth4() public {
        uint256 startTime = block.timestamp;
        uint256 signerBalanceBefore = testToken.balanceOf(signer);
        _subscribePeriods(3);

        vm.warp(startTime + 4 * MONTH);
        vm.prank(address(assetRegistry));
        asset.cancelSubscription(SUBSCRIBER);

        assertFalse(asset.isSubscriptionActive(SUBSCRIBER));
        assertEq(asset.getSubscription(SUBSCRIBER), 0);

        uint256 charged = 2 * SUBSCRIPTION_PRICE; // periods 1+2
        assertEq(testToken.balanceOf(signer), signerBalanceBefore - charged, "Periods 1 and 2 charged");

        // Claim after period 2 fully elapsed
        vm.warp(startTime + 2 * PERIOD_SIZE + 1);
        uint256 creatorFee = charged * (100 - assetRegistry.getRegistryFeeShare()) / 100;
        vm.prank(assetOwner);
        assertEq(asset.claimCreatorFee(SUBSCRIBER), creatorFee, "Creator fee for periods 1+2");
    }

    // Scenario 3: cancel at month 7: refund 0, fee 9 months (all 3 periods)
    function test_cancel_scenario3_atMonth7() public {
        uint256 startTime = block.timestamp;
        uint256 signerBalanceBefore = testToken.balanceOf(signer);
        uint256 totalPayment = asset.getSubscriptionPrice(3);
        _subscribePeriods(3);

        vm.warp(startTime + 7 * MONTH);
        vm.prank(address(assetRegistry));
        asset.cancelSubscription(SUBSCRIBER);

        assertFalse(asset.isSubscriptionActive(SUBSCRIBER));
        assertEq(asset.getSubscription(SUBSCRIBER), 0);
        assertEq(testToken.balanceOf(signer), signerBalanceBefore - totalPayment, "No refund - all 3 periods started");

        // Claim after all 3 periods elapsed
        vm.warp(startTime + 3 * PERIOD_SIZE + 1);
        uint256 creatorFee = totalPayment * (100 - assetRegistry.getRegistryFeeShare()) / 100;
        vm.prank(assetOwner);
        assertEq(asset.claimCreatorFee(SUBSCRIBER), creatorFee, "Creator fee for all 3 periods");
    }

    // Cancel immediately (startTime == block.timestamp is treated as future, full refund, no fee)
    function test_cancel_futureSubscription_fullRefund() public {
        uint256 signerBalanceBefore = testToken.balanceOf(signer);
        _subscribePeriods(3);

        vm.prank(address(assetRegistry));
        asset.cancelSubscription(SUBSCRIBER);

        assertFalse(asset.isSubscriptionActive(SUBSCRIBER));
        assertEq(asset.getSubscription(SUBSCRIBER), 0);
        assertEq(testToken.balanceOf(signer), signerBalanceBefore, "Full refund - no period started");

        // Nothing to claim
        vm.prank(assetOwner);
        assertEq(asset.claimCreatorFee(SUBSCRIBER), 0);
    }

    // Revoke at month 2 — same refund as cancel scenario 1, different caller
    function test_revoke_scenario1_atMonth2() public {
        uint256 startTime = block.timestamp;
        uint256 signerBalanceBefore = testToken.balanceOf(signer);
        _subscribePeriods(3);

        vm.warp(startTime + 2 * MONTH);

        uint256 charged = 1 * SUBSCRIPTION_PRICE;

        vm.prank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRevoked(SUBSCRIBER);
        asset.revokeSubscription(SUBSCRIBER);

        assertFalse(asset.isSubscriptionActive(SUBSCRIBER));
        assertEq(testToken.balanceOf(signer), signerBalanceBefore - charged, "Period 1 charged");
    }

    // Subscribe 3 periods, cancel at month 4, then claim creator fee covering periods 1+2 (6 months)
    function test_claimCreatorFee_afterCancel() public {
        uint256 startTime = block.timestamp;
        _subscribePeriods(3);

        vm.warp(startTime + 4 * MONTH);
        vm.prank(address(assetRegistry));
        asset.cancelSubscription(SUBSCRIBER);

        // Warp to end of period 2 so _claimable captures both started periods
        vm.warp(startTime + 2 * PERIOD_SIZE + 1);

        uint256 feeBase = 2 * SUBSCRIPTION_PRICE; // 2 periods worth
        uint256 expectedCreatorFee = feeBase * (100 - assetRegistry.getRegistryFeeShare()) / 100;

        vm.prank(assetOwner);
        uint256 claimed = asset.claimCreatorFee(SUBSCRIBER);
        assertEq(claimed, expectedCreatorFee, "Creator fee covers periods 1 and 2");
    }
}
