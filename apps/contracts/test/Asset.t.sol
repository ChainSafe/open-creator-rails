// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./Base.t.sol";
import {Asset} from "../src/Asset.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

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
        uint256 expectedPrice = SUBSCRIPTION_PRICE * 10;
        assertEq(asset.getSubscriptionPrice(10), expectedPrice);
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
            emit Asset.SubscriptionAdded(SUBSCRIBER, deadline, deadline + DURATION, i, signer);
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
        
        (, uint256 registryFeeShare, uint256 totalFeeShare) = assetRegistry.getFeeShares();
        uint256 tokenBalance = testToken.balanceOf(assetOwner);

        _subscribe(DURATION);

        vm.prank(registryOwner);
        assetRegistry.updateCreatorFeeShare(60);

        uint256 endTime = _subscribe(DURATION);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 creatorFee = assetRegistry.getCreatorFee(value) + (value - ((value * registryFeeShare) / totalFeeShare));
        vm.warp(endTime);

        vm.prank(assetOwner);
        uint256 claimedCreatorFee = asset.claimCreatorFee(SUBSCRIBER);

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), tokenBalance + claimedCreatorFee);
    }

    function test_claimCreatorFee_multiple_registryFeeShare() public {
        (, uint256 registryFeeShare, uint256 totalFeeShare) = assetRegistry.getFeeShares();
        uint256 tokenBalance = testToken.balanceOf(assetOwner);

        _subscribe(DURATION);

        vm.prank(registryOwner);
        assetRegistry.updateRegistryFeeShare(50);

        uint256 endTime = _subscribe(DURATION);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 creatorFee = assetRegistry.getCreatorFee(value) + (value - ((value * registryFeeShare) / totalFeeShare));
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
        asset.revokeSubscription(SUBSCRIBER);

        assertEq(testToken.balanceOf(signer), tokenBalance - (value + (value / 2)));
        assertEq(asset.getSubscription(SUBSCRIBER), block.timestamp);
    }

    function test_revokeSubscription_endOfSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.warp(block.timestamp + DURATION);
        vm.prank(assetOwner);
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

        vm.prank(signer);
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

        vm.prank(signer);
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

        vm.prank(signer);
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

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER);

        assertEq(testToken.balanceOf(signer), tokenBalance - (value + (value / 2)));
        assertEq(asset.getSubscription(SUBSCRIBER), block.timestamp);
    }

    function test_cancelSubscription_endOfSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.warp(block.timestamp + DURATION);
        vm.prank(signer);
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

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER);

        assertEq(asset.getSubscription(SUBSCRIBER), 0);
        assertEq(testToken.balanceOf(signer), tokenBalance);
    }

    function test_cancelSubscription_noSubscription() public {
        vm.prank(signer);
        vm.expectRevert(Asset.SubscriptionNotFound.selector);
        asset.cancelSubscription(SUBSCRIBER);
    }

    function test_cancelSubscription_unauthorized() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        uint256 tokenBalanceUnauthorized = testToken.balanceOf(UNAUTHORIZED);
        
        test_subscribe();
        
        vm.prank(UNAUTHORIZED);
        asset.cancelSubscription(SUBSCRIBER);

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION));
        assertEq(testToken.balanceOf(UNAUTHORIZED), tokenBalanceUnauthorized);
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
}