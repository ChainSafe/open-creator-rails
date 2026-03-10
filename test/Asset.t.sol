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
        address owner = signer;
        address spender = address(asset);
        
        uint256 value = asset.getSubscriptionPrice(duration);

        uint256 deadline = block.timestamp + duration;
        
        (uint8 v, bytes32 r, bytes32 s) = getPermit(owner, spender, value, deadline);        

        subscription = asset.subscribe(owner, spender, value, deadline, v, r, s);
        
        return subscription;
    }

    function test_subscribe() public {
        uint256 expectedFee = SUBSCRIPTION_PRICE * DURATION;
        uint256 signerBalanceBefore = testToken.balanceOf(signer);
        uint256 assetBalanceBefore = testToken.balanceOf(address(asset));

        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(signer, block.timestamp, block.timestamp + DURATION, 0);

        uint256 subscription = _subscribe(DURATION);

        assertTrue(subscription > block.timestamp);
        vm.prank(signer);
        assertEq(asset.getMySubscription(), subscription);
        assertEq(testToken.balanceOf(address(asset)), assetBalanceBefore + expectedFee, "Asset should receive expected fee");
        assertEq(testToken.balanceOf(signer), signerBalanceBefore - expectedFee, "Signer balance should decrease by expected fee");
    }

    function test_subscribe_multiple() public {
        uint256 deadline = block.timestamp;
        uint256 count = 10;

        for (uint256 i = 0; i < count; i++) {
            vm.expectEmit(true, true, true, true);
            emit Asset.SubscriptionAdded(signer, deadline, deadline + DURATION, i);
            _subscribe(DURATION);
            deadline += DURATION;
        }

        vm.prank(signer);
        assertEq(asset.getMySubscription(), block.timestamp + (DURATION * count));
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
        emit Asset.CreatorFeeClaimed(signer, creatorFee);
        uint256 claimedCreatorFee = asset.claimCreatorFee(signer);
        vm.stopPrank();

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), claimedCreatorFee);
    }

    function test_claimCreatorFee_multiple() public {
        test_subscribe_multiple();

        vm.prank(signer);
        uint256 endTime = asset.getMySubscription();
        uint256 value = asset.getSubscriptionPrice(endTime - block.timestamp);
        vm.warp(endTime);

        vm.startPrank(assetOwner);

        uint256 creatorFee = assetRegistry.getCreatorFee(value);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(signer, creatorFee);
        
        uint256 claimedCreatorFee = asset.claimCreatorFee(signer);
        
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
        emit Asset.CreatorFeeClaimed(signer, creatorFee);
        uint256 claimedCreatorFee = asset.claimCreatorFee(signer);
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
        emit Asset.CreatorFeeClaimed(signer, creatorFee);
        uint256 claimedCreatorFee = asset.claimCreatorFee(signer);
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
        uint256 claimedCreatorFee = asset.claimCreatorFee(signer);

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
        uint256 claimedCreatorFee = asset.claimCreatorFee(signer);

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
        emit Asset.CreatorFeeClaimed(signer, creatorFee);
        uint256 claimedCreatorFee = asset.claimCreatorFee(signer);
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
        emit Asset.SubscriptionRevoked(signer);
        asset.revokeSubscription(signer);

        assertEq(testToken.balanceOf(signer), tokenBalance);
        vm.prank(signer);
        assertEq(asset.getMySubscription(), 0);
    }

    function test_revokeSubscription_multiple() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        test_subscribe_multiple();

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION * 10));

        vm.prank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRevoked(signer);
        asset.revokeSubscription(signer);

        assertEq(testToken.balanceOf(signer), tokenBalance);
        vm.prank(signer);
        assertEq(asset.getMySubscription(), 0);
    }

    function test_revokeSubscription_midSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        for (uint256 i = 0; i < 2; i++) _subscribe(DURATION);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        vm.warp(block.timestamp + DURATION + (DURATION / 2));

        vm.prank(assetOwner);
        asset.revokeSubscription(signer);

        assertEq(testToken.balanceOf(signer), tokenBalance - (value + (value / 2)));
        vm.prank(signer);
        assertEq(asset.getMySubscription(), block.timestamp);
    }

    function test_revokeSubscription_endOfSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.warp(block.timestamp + DURATION);
        vm.prank(assetOwner);
        asset.revokeSubscription(signer);

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION));
        vm.prank(signer);
        assertEq(asset.getMySubscription(), block.timestamp);
    }

    function test_revokeSubscription_multiple_subscriptionPrice() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        _subscribe(DURATION);

        vm.prank(assetOwner);
        asset.revokeSubscription(signer);

        vm.prank(signer);
        assertEq(asset.getMySubscription(), 0);
        assertEq(testToken.balanceOf(signer), tokenBalance);
    }

    function test_isMySubscriptionActive() public {
        test_subscribe();
        vm.prank(signer);
        assertTrue(asset.isMySubscriptionActive());

        vm.prank(assetOwner);
        asset.revokeSubscription(signer);

        vm.prank(signer);
        assertFalse(asset.isMySubscriptionActive());
    }

    function test_isMySubscriptionActive_cancelSubscription() public {
        test_subscribe();
        vm.prank(signer);
        assertTrue(asset.isMySubscriptionActive());

        vm.prank(signer);
        asset.cancelSubscription();

        vm.prank(signer);
        assertFalse(asset.isMySubscriptionActive());
    }

    function test_unauthorized() public {
        vm.startPrank(UNAUTHORIZED);
        vm.expectRevert(Asset.OnlyRegistryOrOwnerUnauthorizedAccount.selector);
        asset.getSubscription(signer);
        vm.expectRevert(Asset.OnlyRegistryOrOwnerUnauthorizedAccount.selector);
        asset.isSubscriptionActive(signer);
        vm.stopPrank();
    }

    function test_subscribe_invalidSpender() public {
        address owner = signer;
        address spender = address(1); // Wrong spender - must be address(asset)
        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 deadline = block.timestamp + DURATION;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(owner, address(asset), value, deadline);

        vm.expectRevert(Asset.InvalidSpender.selector);
        asset.subscribe(owner, spender, value, deadline, v, r, s);
    }

    function test_subscribe_permitFailed() public {
        address owner = signer;
        address spender = address(asset);
        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 deadline = block.timestamp + DURATION;
        // Use invalid signature - wrong v, r, s
        (uint8 v, bytes32 r, bytes32 s) = (0, bytes32(0), bytes32(0));

        vm.expectRevert(Asset.PermitFailed.selector);
        asset.subscribe(owner, spender, value, deadline, v, r, s);
    }

    function test_subscribe_insufficientFunds() public {
        address owner = signer;
        address spender = address(asset);
        uint256 value = SUBSCRIPTION_PRICE - 1; // Below subscriptionPrice, rounds to 0
        uint256 deadline = block.timestamp + DURATION;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(owner, spender, value, deadline);

        vm.expectRevert(Asset.InsufficientFunds.selector);
        asset.subscribe(owner, spender, value, deadline, v, r, s);
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
        asset.revokeSubscription(signer);
    }

    function test_revokeSubscription_noSubscription() public {
        vm.prank(assetOwner);
        vm.expectRevert(Asset.SubscriptionNotFound.selector);
        asset.revokeSubscription(signer);
    }

    function test_cancelSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION));

        vm.prank(signer);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionCancelled(signer);
        asset.cancelSubscription();

        assertEq(testToken.balanceOf(signer), tokenBalance);
        vm.prank(signer);
        assertEq(asset.getMySubscription(), 0);
    }

    function test_cancelSubscription_multiple() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        test_subscribe_multiple();

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION * 10));

        vm.prank(signer);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionCancelled(signer);
        asset.cancelSubscription();

        assertEq(testToken.balanceOf(signer), tokenBalance);
        vm.prank(signer);
        assertEq(asset.getMySubscription(), 0);
    }

    function test_cancelSubscription_midSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        for (uint256 i = 0; i < 2; i++) _subscribe(DURATION);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        vm.warp(block.timestamp + DURATION + (DURATION / 2));

        vm.prank(signer);
        asset.cancelSubscription();

        assertEq(testToken.balanceOf(signer), tokenBalance - (value + (value / 2)));
        vm.prank(signer);
        assertEq(asset.getMySubscription(), block.timestamp);
    }

    function test_cancelSubscription_endOfSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.warp(block.timestamp + DURATION);
        vm.prank(signer);
        asset.cancelSubscription();

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION));
        vm.prank(signer);
        assertEq(asset.getMySubscription(), block.timestamp);
    }

    function test_cancelSubscription_multiple_subscriptionPrice() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        _subscribe(DURATION);

        vm.prank(signer);
        asset.cancelSubscription();

        vm.prank(signer);
        assertEq(asset.getMySubscription(), 0);
        assertEq(testToken.balanceOf(signer), tokenBalance);
    }

    function test_cancelSubscription_noSubscription() public {
        vm.prank(signer);
        vm.expectRevert(Asset.SubscriptionNotFound.selector);
        asset.cancelSubscription();
    }

    function test_claimCreatorFee_unauthorized() public {
        test_subscribe();
        vm.warp(block.timestamp + DURATION);

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, UNAUTHORIZED));
        asset.claimCreatorFee(signer);
    }

    function test_claimRegistryFee_unauthorized() public {
        test_subscribe();
        vm.warp(block.timestamp + DURATION);

        vm.prank(registryOwner);
        vm.expectRevert(Asset.OnlyRegistryUnauthorizedAccount.selector);
        asset.claimRegistryFee(signer);
    }

    function test_feeSplit() public {
        uint256 creatorBalance = testToken.balanceOf(assetOwner);
        uint256 registryBalance = testToken.balanceOf(registryOwner);
        test_subscribe();

        uint256 value = asset.getSubscriptionPrice(DURATION);
        (uint256 creatorFee, uint256 registryFee) = assetRegistry.getFees(value);

        vm.warp(block.timestamp + DURATION);

        vm.prank(assetOwner);
        uint256 claimedCreatorFee = asset.claimCreatorFee(signer);

        vm.prank(address(assetRegistry));
        uint256 claimedRegistryFee = asset.claimRegistryFee(signer);

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(claimedRegistryFee, registryFee);
        assertEq(testToken.balanceOf(assetOwner), creatorBalance + creatorFee);
        assertEq(testToken.balanceOf(registryOwner), registryBalance + registryFee);
    }
}