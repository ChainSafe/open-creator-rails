// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./Base.t.sol";
import {Asset} from "../src/Asset.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract AssetTest is BaseTest {
    string internal constant OTHER_SUBSCRIBER_ID = "other_subscriber_id";

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

    function test_getSubscriptionPriceAndDuration() public view {
        (uint256 price, uint256 duration) = asset.getSubscriptionPriceAndDuration(5);
        assertEq(price, SUBSCRIPTION_PRICE * 5);
        assertEq(duration, 5 * SUBSCRIPTION_DURATION);
    }

    function _subscribe(uint256 count) internal returns (uint256 subscription) {
        address payer = signer;
        address spender = address(asset);

        uint256 value = asset.getSubscriptionPrice(count);

        uint256 deadline = block.timestamp;

        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);

        subscription = asset.subscribe(_subscriber, payer, spender, count, deadline, v, r, s);

        return subscription;
    }

    function _subscribeFor(bytes32 subscriber, uint256 count) internal returns (uint256 subscription) {
        address payer = signer;
        address spender = address(asset);

        uint256 value = asset.getSubscriptionPrice(count);
        uint256 deadline = block.timestamp;

        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);

        subscription = asset.subscribe(subscriber, payer, spender, count, deadline, v, r, s);

        return subscription;
    }

    function _cancelAsSubscriber() internal {
        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer);
        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, signature);
    }

    function _subscriberHash(string memory subscriberId, address subscriberAddress) internal pure returns (bytes32) {
        return keccak256(abi.encode(subscriberId, subscriberAddress));
    }

    function _getCancellationSignatureWithKey(string memory subscriberId, address subscriberAddress, uint256 signingKey)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 subscriber = keccak256(abi.encode(subscriberId, subscriberAddress));
        bytes32 hash = keccak256(abi.encodePacked(block.chainid, address(asset), subscriber));
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function test_subscribe() public {
        uint256 expectedFee = SUBSCRIPTION_PRICE;
        uint256 signerBalanceBefore = testToken.balanceOf(signer);
        uint256 assetBalanceBefore = testToken.balanceOf(address(asset));

        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(
            _subscriber,
            block.timestamp,
            block.timestamp + SUBSCRIPTION_DURATION,
            signer,
            SUBSCRIPTION_PRICE,
            assetRegistry.getRegistryFeeShare()
        );

        uint256 subscription = _subscribe(1);

        assertTrue(subscription > block.timestamp);

        assertEq(asset.getSubscriptionExpiration(_subscriber), subscription);
        assertEq(
            testToken.balanceOf(address(asset)), assetBalanceBefore + expectedFee, "Asset should receive expected fee"
        );
        assertEq(
            testToken.balanceOf(signer),
            signerBalanceBefore - expectedFee,
            "Signer balance should decrease by expected fee"
        );
    }

    function test_subscribe_multiple() public {
        uint256 startTime = block.timestamp;

        for (uint256 i = 0; i < COUNT; i++) {
            vm.expectEmit(true, true, true, true);
            if (i == 0) {
                emit Asset.SubscriptionAdded(
                    _subscriber,
                    startTime,
                    startTime + SUBSCRIPTION_DURATION,
                    signer,
                    SUBSCRIPTION_PRICE,
                    assetRegistry.getRegistryFeeShare()
                );
            } else {
                emit Asset.SubscriptionExtended(_subscriber, startTime + SUBSCRIPTION_DURATION * (i + 1));
            }
            _subscribe(1);
        }

        assertEq(asset.getSubscriptionExpiration(_subscriber), block.timestamp + (SUBSCRIPTION_DURATION * COUNT));
    }

    function test_subscribe_multiple_subscriptionPrice() public {
        uint256 tokenBalance = testToken.balanceOf(signer);

        _subscribe(COUNT);

        uint256 value = asset.getSubscriptionPrice(COUNT);

        vm.startPrank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        vm.stopPrank();

        _subscribe(COUNT);

        value += asset.getSubscriptionPrice(COUNT);

        assertEq(value, 3 * (SUBSCRIPTION_PRICE * COUNT));
        assertEq(testToken.balanceOf(signer), tokenBalance - value);
    }

    function test_claimCreatorFee() public {
        test_subscribe();

        uint256 value = asset.getSubscriptionPrice(1);
        vm.warp(block.timestamp + SUBSCRIPTION_DURATION);

        vm.startPrank(assetOwner);
        uint256 creatorFee = value * (100 - REGISTRY_FEE_SHARE) / 100;
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(_subscriber, creatorFee, block.timestamp, 0);
        uint256 claimedCreatorFee = asset.claimCreatorFee(_subscriber);
        vm.stopPrank();

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), claimedCreatorFee);
    }

    function test_claimCreatorFee_multiple() public {
        test_subscribe_multiple();

        vm.prank(signer);
        uint256 endTime = asset.getSubscriptionExpiration(_subscriber);
        uint256 value = asset.getSubscriptionPrice(COUNT);
        vm.warp(endTime);

        vm.startPrank(assetOwner);

        uint256 creatorFee = value * (100 - REGISTRY_FEE_SHARE) / 100; // 70% creator fee share
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(_subscriber, creatorFee, block.timestamp, 0);

        uint256 claimedCreatorFee = asset.claimCreatorFee(_subscriber);

        vm.stopPrank();

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), claimedCreatorFee);
    }

    function test_claimCreatorFee_multiple_subscriptionPrice() public {
        uint256 tokenBalance = testToken.balanceOf(assetOwner);

        _subscribe(1);

        uint256 value = asset.getSubscriptionPrice(1);

        vm.startPrank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        vm.stopPrank();

        _subscribe(1);

        value += asset.getSubscriptionPrice(1);

        uint256 creatorFee = value * (100 - REGISTRY_FEE_SHARE) / 100; // 70% creator fee share

        vm.warp(block.timestamp + (SUBSCRIPTION_DURATION * 2));

        vm.startPrank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(_subscriber, creatorFee, block.timestamp, 1);
        uint256 claimedCreatorFee = asset.claimCreatorFee(_subscriber);
        vm.stopPrank();

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), tokenBalance + claimedCreatorFee);
    }

    function test_claimCreatorFee_midSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(assetOwner);
        test_subscribe();

        vm.warp(block.timestamp + (SUBSCRIPTION_DURATION / 2));

        vm.startPrank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(_subscriber, 0, 0, 0);
        uint256 claimedCreatorFee = asset.claimCreatorFee(_subscriber);
        vm.stopPrank();

        assertEq(claimedCreatorFee, 0);
        assertEq(testToken.balanceOf(assetOwner), tokenBalance);
    }

    function test_claimCreatorFee_multiple_creatorFeeShare() public {
        // creator fee share is 70%
        uint256 tokenBalance = testToken.balanceOf(assetOwner);

        _subscribe(COUNT);

        vm.prank(registryOwner);
        assetRegistry.updateRegistryFeeShare(40); // creator fee share is now 60%

        uint256 endTime = _subscribe(COUNT);

        uint256 value = asset.getSubscriptionPrice(COUNT);
        uint256 creatorFee = value * (100 - REGISTRY_FEE_SHARE) / 100 + value * 60 / 100;
        vm.warp(endTime);

        vm.prank(assetOwner);
        uint256 claimedCreatorFee = asset.claimCreatorFee(_subscriber);

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), tokenBalance + claimedCreatorFee);
    }

    function test_claimCreatorFee_multiple_registryFeeShare() public {
        uint256 tokenBalance = testToken.balanceOf(assetOwner);

        _subscribe(COUNT);

        vm.prank(registryOwner);
        assetRegistry.updateRegistryFeeShare(50);

        uint256 endTime = _subscribe(COUNT);

        uint256 value = asset.getSubscriptionPrice(COUNT);
        uint256 creatorFee = value * (100 - REGISTRY_FEE_SHARE) / 100 + value * 50 / 100;
        vm.warp(endTime);

        vm.prank(assetOwner);
        uint256 claimedCreatorFee = asset.claimCreatorFee(_subscriber);

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), tokenBalance + claimedCreatorFee);
    }

    function test_claimCreatorFee_startOfNextSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(assetOwner);

        uint256 endTime = _subscribe(1);

        uint256 value = asset.getSubscriptionPrice(1);

        _subscribe(1);

        vm.warp(endTime);

        vm.startPrank(assetOwner);
        uint256 creatorFee = value * (100 - REGISTRY_FEE_SHARE) / 100;
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(_subscriber, creatorFee, block.timestamp, 0);
        uint256 claimedCreatorFee = asset.claimCreatorFee(_subscriber);
        vm.stopPrank();

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), tokenBalance + claimedCreatorFee);
    }

    /// @dev Single subscription (one nonce) spanning COUNT periods: claim after 2 full periods, then after all 5,
    ///      ensuring `claimedAtTimestamp` grid snapping does not double-count or skip.
    function test_claimCreatorFee_incrementalMultiPeriodSingleNonce() public {
        uint256 tokenBalance = testToken.balanceOf(assetOwner);

        _subscribe(COUNT);

        uint256 endTime = asset.getSubscriptionExpiration(_subscriber);
        uint256 startTime = endTime - COUNT * SUBSCRIPTION_DURATION;

        uint256 perPeriodCreator = SUBSCRIPTION_PRICE * (100 - REGISTRY_FEE_SHARE) / 100;

        vm.warp(startTime + 2 * SUBSCRIPTION_DURATION);

        vm.startPrank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(_subscriber, 2 * perPeriodCreator, startTime + 2 * SUBSCRIPTION_DURATION, 0);
        uint256 firstClaim = asset.claimCreatorFee(_subscriber);
        vm.stopPrank();

        assertEq(firstClaim, 2 * perPeriodCreator);

        vm.warp(endTime);

        vm.startPrank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(_subscriber, 3 * perPeriodCreator, endTime, 0);
        uint256 secondClaim = asset.claimCreatorFee(_subscriber);
        vm.stopPrank();

        assertEq(secondClaim, 3 * perPeriodCreator);
        assertEq(testToken.balanceOf(assetOwner), tokenBalance + COUNT * perPeriodCreator);

        vm.startPrank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(_subscriber, 0, endTime, 0);
        uint256 thirdClaim = asset.claimCreatorFee(_subscriber);
        vm.stopPrank();

        assertEq(thirdClaim, 0);
    }

    function test_claimRegistryFee_incrementalMultiPeriodSingleNonce() public {
        uint256 tokenBalance = testToken.balanceOf(registryOwner);

        _subscribe(COUNT);

        uint256 endTime = asset.getSubscriptionExpiration(_subscriber);
        uint256 startTime = endTime - COUNT * SUBSCRIPTION_DURATION;

        uint256 perPeriodRegistry = SUBSCRIPTION_PRICE * REGISTRY_FEE_SHARE / 100;

        vm.warp(startTime + 2 * SUBSCRIPTION_DURATION);

        vm.prank(address(assetRegistry));
        (uint256 firstClaim,,) = asset.claimRegistryFee(_subscriber);

        assertEq(firstClaim, 2 * perPeriodRegistry);

        vm.warp(endTime);

        vm.prank(address(assetRegistry));
        (uint256 secondClaim,,) = asset.claimRegistryFee(_subscriber);

        assertEq(secondClaim, 3 * perPeriodRegistry);
        assertEq(testToken.balanceOf(registryOwner), tokenBalance + COUNT * perPeriodRegistry);

        vm.prank(address(assetRegistry));
        (uint256 thirdClaim,,) = asset.claimRegistryFee(_subscriber);

        assertEq(thirdClaim, 0);
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
        _subscribe(1);

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(1));

        vm.prank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRevoked(_subscriber, 0, 0);
        asset.revokeSubscription(_subscriber);

        assertEq(testToken.balanceOf(signer), tokenBalance);
        assertEq(asset.getSubscriptionExpiration(_subscriber), 0);
        assertTrue(asset.isSubscriberRevoked(_subscriber));
        assertFalse(asset.isSubscriptionActive(_subscriber));
    }

    function test_revokeSubscription_multiple() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        test_subscribe_multiple();

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(COUNT));

        vm.prank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRevoked(_subscriber, 0, 0);
        asset.revokeSubscription(_subscriber);

        assertEq(testToken.balanceOf(signer), tokenBalance);
        assertEq(asset.getSubscriptionExpiration(_subscriber), 0);
        assertTrue(asset.isSubscriberRevoked(_subscriber));
        assertFalse(asset.isSubscriptionActive(_subscriber));
    }

    function test_revokeSubscription_midSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        for (uint256 i = 0; i < 3; i++) {
            _subscribe(1);
        }

        uint256 value = asset.getSubscriptionPrice(1);
        uint256 newTimestamp = block.timestamp + SUBSCRIPTION_DURATION + (SUBSCRIPTION_DURATION / 2);
        vm.warp(newTimestamp);

        vm.prank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRevoked(_subscriber, 0, newTimestamp);
        asset.revokeSubscription(_subscriber);

        uint256 fullValue = value * 3;
        uint256 dustDuration = SUBSCRIPTION_DURATION / 2;
        uint256 dust = (dustDuration * value) / SUBSCRIPTION_DURATION;

        uint256 returnable = fullValue - (value + dust);

        assertEq(testToken.balanceOf(signer), tokenBalance - fullValue + returnable);
        // Revocation refunds all remaining value including mid-period dust (unlike cancellation which only refunds whole future periods)
        // endTime is truncated to the current timestamp, immediately terminating the subscription
        assertEq(asset.getSubscriptionExpiration(_subscriber), newTimestamp);
        assertTrue(asset.isSubscriptionExpired(_subscriber));
        assertTrue(asset.isSubscriberRevoked(_subscriber));
        assertFalse(asset.isSubscriptionActive(_subscriber));
    }

    function test_revokeSubscription_endOfSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(1);

        vm.warp(block.timestamp + SUBSCRIPTION_DURATION);
        vm.prank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRevoked(_subscriber, 0, block.timestamp);
        asset.revokeSubscription(_subscriber);

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(1));
        assertEq(asset.getSubscriptionExpiration(_subscriber), block.timestamp);
        assertTrue(asset.isSubscriberRevoked(_subscriber));
        assertFalse(asset.isSubscriptionActive(_subscriber));
    }

    function test_revokeSubscription_multiple_subscriptionPrice() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(1);

        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        _subscribe(1);

        vm.prank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRevoked(_subscriber, 0, 0);
        asset.revokeSubscription(_subscriber);

        assertEq(asset.getSubscriptionExpiration(_subscriber), 0);
        assertEq(testToken.balanceOf(signer), tokenBalance);
        assertTrue(asset.isSubscriberRevoked(_subscriber));
        assertFalse(asset.isSubscriptionActive(_subscriber));
    }

    function test_isMySubscriptionExpired() public {
        test_subscribe();
        vm.prank(signer);
        assertFalse(asset.isSubscriptionExpired(_subscriber));

        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);

        vm.prank(signer);
        assertTrue(asset.isSubscriptionExpired(_subscriber));
        assertTrue(asset.isSubscriberRevoked(_subscriber));
        assertFalse(asset.isSubscriptionActive(_subscriber));
    }

    function test_isMySubscriptionExpired_cancelSubscription() public {
        test_subscribe();
        vm.prank(signer);
        assertFalse(asset.isSubscriptionExpired(_subscriber));

        _cancelAsSubscriber();

        vm.prank(signer);
        assertTrue(asset.isSubscriptionExpired(_subscriber));
    }

    function test_isMySubscriptionExpired_cancelSubscription_midPeriod() public {
        test_subscribe();
        vm.prank(signer);
        assertFalse(asset.isSubscriptionExpired(_subscriber));

        vm.warp(block.timestamp + (SUBSCRIPTION_DURATION / 2));

        _cancelAsSubscriber();

        vm.prank(signer);
        assertFalse(asset.isSubscriptionExpired(_subscriber));
    }

    function test_subscribe_invalidSpender() public {
        address payer = signer;
        address spender = address(1); // Wrong spender - must be address(asset)
        uint256 value = asset.getSubscriptionPrice(COUNT);
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, address(asset), value, deadline);

        vm.expectRevert(Asset.InvalidSpender.selector);
        asset.subscribe(_subscriber, payer, spender, COUNT, deadline, v, r, s);
    }

    function test_subscribe_permitFailed() public {
        address payer = signer;
        address spender = address(asset);
        uint256 deadline = block.timestamp;
        // Use invalid signature - wrong v, r, s
        (uint8 v, bytes32 r, bytes32 s) = (0, bytes32(0), bytes32(0));

        vm.expectRevert(Asset.PermitFailed.selector);
        asset.subscribe(_subscriber, payer, spender, COUNT, deadline, v, r, s);
    }

    function test_subscribe_insufficientFunds() public {
        address payer = signer;
        address spender = address(asset);
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, 0, deadline);

        vm.expectRevert(Asset.InsufficientFunds.selector);
        asset.subscribe(_subscriber, payer, spender, 0, deadline, v, r, s);
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
        asset.revokeSubscription(_subscriber);
    }

    function test_revokeSubscription_noSubscription() public {
        vm.prank(assetOwner);
        vm.expectRevert(Asset.SubscriptionNotFound.selector);
        asset.revokeSubscription(_subscriber);
    }

    function test_cancelSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(1);

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(1));

        _cancelAsSubscriber();

        assertEq(testToken.balanceOf(signer), tokenBalance);
        assertEq(asset.getSubscriptionExpiration(_subscriber), 0);
    }

    function test_cancelSubscription_multiple() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        test_subscribe_multiple();

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(COUNT));

        _cancelAsSubscriber();

        assertEq(testToken.balanceOf(signer), tokenBalance);
        assertEq(asset.getSubscriptionExpiration(_subscriber), 0);
    }

    function test_cancelSubscription_midSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        for (uint256 i = 0; i < 3; i++) {
            _subscribe(1);
        }

        uint256 value = asset.getSubscriptionPrice(1);
        vm.warp(block.timestamp + SUBSCRIPTION_DURATION + (SUBSCRIPTION_DURATION / 2));

        _cancelAsSubscriber();

        assertEq(testToken.balanceOf(signer), tokenBalance - value * 2);
        // The first two periods are not refunded since they have already passed or started
        // The remaining half-period is refunded and endTime is truncated to the end of the current period.
        // Subscription stays active until that point.
        assertEq(asset.getSubscriptionExpiration(_subscriber), block.timestamp + (SUBSCRIPTION_DURATION / 2));
        assertFalse(asset.isSubscriptionExpired(_subscriber));
    }

    function test_cancelSubscription_endOfSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(1);

        vm.warp(block.timestamp + SUBSCRIPTION_DURATION);
        _cancelAsSubscriber();

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(1));
        assertEq(asset.getSubscriptionExpiration(_subscriber), block.timestamp);
    }

    function test_cancelSubscription_multiple_subscriptionPrice() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(1);

        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        _subscribe(1);

        _cancelAsSubscriber();

        assertEq(asset.getSubscriptionExpiration(_subscriber), 0);
        assertEq(testToken.balanceOf(signer), tokenBalance);
    }

    function test_cancelSubscription_noSubscription() public {
        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer);

        vm.prank(signer);
        vm.expectRevert(Asset.SubscriptionNotFound.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, signature);
    }

    function test_cancelSubscription_unauthorized() public {
        uint256 tokenBalance = testToken.balanceOf(signer);

        test_subscribe();

        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer);

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(Asset.InvalidSignature.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, signature);

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(1));
    }

    // Cancel a subscriber with two records in different states (active + future) at different prices.
    // Active record: forfeit started periods, refund remaining whole periods at its own price.
    // Future record: fully refunded at its own price; delete record.
    function test_cancelSubscription_multipleNonces_mixedStates() public {
        uint256 originalPrice = SUBSCRIPTION_PRICE;
        uint256 doubledPrice = SUBSCRIPTION_PRICE * 2;
        uint256 tokenBalance = testToken.balanceOf(signer);

        // Record 0: active, paid at original price
        _subscribe(1);

        // Bump price → next subscribe creates a new nonce queued at end of record 0
        vm.prank(assetOwner);
        asset.setSubscriptionPrice(doubledPrice);

        // Record 1: future (starts at T0 + COUNT), paid at doubled price
        _subscribe(1);

        uint256 paidRecord0 = originalPrice;
        uint256 paidRecord1 = doubledPrice;
        assertEq(testToken.balanceOf(signer), tokenBalance - paidRecord0 - paidRecord1, "both records charged upfront");

        // Warp half-way into record 0
        vm.warp(block.timestamp + SUBSCRIPTION_DURATION / 2);

        _cancelAsSubscriber();

        // Active record is truncated to end of current period,
        // future record is deleted.
        assertFalse(asset.isSubscriptionExpired(_subscriber));
        assertEq(asset.getSubscriptionExpiration(_subscriber), block.timestamp + SUBSCRIPTION_DURATION / 2);

        // Refund:
        //   record 0 (active): 0
        //   record 1 (future): full period at doubled price
        uint256 refund0 = 0;
        uint256 refund1 = paidRecord1;
        uint256 expectedCharged = paidRecord0 + paidRecord1 - refund0 - refund1;

        assertEq(testToken.balanceOf(signer), tokenBalance - expectedCharged, "only record 0 forfeited");
    }

    function test_cancelSubscription_sameSubscriberIdDifferentAddress_storesIndependently() public {
        address otherAddress = vm.addr(otherKey);
        bytes32 otherSubscriber = _subscriberHash(SUBSCRIBER_ID, otherAddress);

        _subscribe(COUNT);
        _subscribeFor(otherSubscriber, COUNT);

        bytes memory signerSignature = getCancellationSignature(SUBSCRIBER_ID, signer);
        bytes memory otherSignature = _getCancellationSignatureWithKey(SUBSCRIBER_ID, otherAddress, otherKey);

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, signerSignature);

        assertEq(asset.getSubscriptionExpiration(_subscriber), 0);
        assertFalse(asset.isSubscriptionExpired(otherSubscriber));

        vm.prank(otherAddress);
        asset.cancelSubscription(SUBSCRIBER_ID, otherSignature);
        assertEq(asset.getSubscriptionExpiration(otherSubscriber), 0);
    }

    function test_cancelSubscription_reverts_invalidSignature_whenWrongAddressUsesSignersProof() public {
        test_subscribe();

        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer);

        address otherAddress = vm.addr(otherKey);
        vm.prank(otherAddress);
        vm.expectRevert(Asset.InvalidSignature.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, signature);
    }

    function test_cancelSubscription_reverts_invalidSignature_whenSignedByDifferentKey() public {
        test_subscribe();

        bytes memory badSignature = _getCancellationSignatureWithKey(SUBSCRIBER_ID, signer, otherKey);

        vm.prank(signer);
        vm.expectRevert(Asset.InvalidSignature.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, badSignature);
    }

    function test_cancelSubscription_reverts_invalidSignature_whenSignatureForDifferentSubscriberHash() public {
        test_subscribe();

        bytes memory badSignature = getCancellationSignature(OTHER_SUBSCRIBER_ID, signer);

        vm.prank(signer);
        vm.expectRevert(Asset.InvalidSignature.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, badSignature);
    }

    function test_cancelSubscription_secondCall_reverts_subscriptionNotFound() public {
        test_subscribe();

        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer);

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, signature);
        assertEq(asset.getSubscriptionExpiration(_subscriber), 0);

        vm.prank(signer);
        vm.expectRevert(Asset.SubscriptionNotFound.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, signature);
    }

    function test_cancelSubscription_doesNotAffectOtherAddressWithSameSubscriberId() public {
        address otherAddress = vm.addr(otherKey);
        bytes32 otherSubscriber = _subscriberHash(SUBSCRIBER_ID, otherAddress);

        _subscribe(1);
        _subscribeFor(otherSubscriber, 1);

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, getCancellationSignature(SUBSCRIBER_ID, signer));

        assertEq(asset.getSubscriptionExpiration(_subscriber), 0);
        assertFalse(asset.isSubscriptionExpired(otherSubscriber));
    }

    function test_cancelSubscription_doesNotAffectOtherSubscriberIdSameAddress() public {
        bytes32 otherSubscriber = _subscriberHash(OTHER_SUBSCRIBER_ID, signer);

        _subscribe(1);
        _subscribeFor(otherSubscriber, 1);

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, getCancellationSignature(SUBSCRIBER_ID, signer));

        assertEq(asset.getSubscriptionExpiration(_subscriber), 0);
        assertFalse(asset.isSubscriptionExpired(otherSubscriber));
    }

    function test_cancelSubscription_withActiveMultiNonceSubscriptions_refundsCorrectly() public {
        uint256 tokenBalance = testToken.balanceOf(signer);

        _subscribe(1);
        _subscribe(1);
        _subscribe(1);

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, getCancellationSignature(SUBSCRIBER_ID, signer));

        assertEq(asset.getSubscriptionExpiration(_subscriber), 0);
        assertEq(testToken.balanceOf(signer), tokenBalance);
    }

    function test_cancelSubscription_emitsSubscriptionCancelled_withExpectedSubscriberHash() public {
        test_subscribe();

        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer);

        vm.prank(signer);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionCancelled(_subscriber, 0, 0);
        asset.cancelSubscription(SUBSCRIBER_ID, signature);
    }

    function test_revokeSubscription_emitsSubscriptionRemoved_whenFullyDeleted() public {
        _subscribe(1);

        vm.prank(assetOwner);
        vm.expectEmit(true, false, false, false);
        emit Asset.SubscriptionRemoved(_subscriber);
        asset.revokeSubscription(_subscriber);
    }

    function test_cancelSubscription_emitsSubscriptionRemoved_whenFullyDeleted() public {
        _subscribe(1);

        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer);

        vm.prank(signer);
        vm.expectEmit(true, false, false, false);
        emit Asset.SubscriptionRemoved(_subscriber);
        asset.cancelSubscription(SUBSCRIBER_ID, signature);
    }

    function test_claimCreatorFee_unauthorized() public {
        test_subscribe();
        vm.warp(block.timestamp + SUBSCRIPTION_DURATION);

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, UNAUTHORIZED));
        asset.claimCreatorFee(_subscriber);
    }

    function test_claimRegistryFee_unauthorized() public {
        test_subscribe();
        vm.warp(block.timestamp + SUBSCRIPTION_DURATION);

        vm.prank(registryOwner);
        vm.expectRevert(Asset.OnlyRegistryUnauthorizedAccount.selector);
        asset.claimRegistryFee(_subscriber);
    }

    function test_feeSplit() public {
        uint256 creatorBalance = testToken.balanceOf(assetOwner);
        uint256 registryBalance = testToken.balanceOf(registryOwner);
        test_subscribe();

        uint256 value = asset.getSubscriptionPrice(1);
        (uint256 creatorFee, uint256 registryFee) = assetRegistry.getFees(value);
        assertEq(creatorFee, value * (100 - REGISTRY_FEE_SHARE) / 100);
        assertEq(registryFee, value * REGISTRY_FEE_SHARE / 100);

        vm.warp(block.timestamp + SUBSCRIPTION_DURATION);

        vm.prank(assetOwner);
        uint256 claimedCreatorFee = asset.claimCreatorFee(_subscriber);

        vm.prank(address(assetRegistry));
        (uint256 claimedRegistryFee,,) = asset.claimRegistryFee(_subscriber);

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(claimedRegistryFee, registryFee);
        assertEq(testToken.balanceOf(assetOwner), creatorBalance + creatorFee);
        assertEq(testToken.balanceOf(registryOwner), registryBalance + registryFee);
    }

    function test_getSubscriptionExpiration_nonexistentSubscriber() public view {
        bytes32 unknownSubscriber = keccak256("unknown");
        assertEq(asset.getSubscriptionExpiration(unknownSubscriber), 0);
    }

    function test_isSubscriptionExpired_nonexistentSubscriber() public view {
        bytes32 unknownSubscriber = keccak256("unknown");
        assertTrue(asset.isSubscriptionExpired(unknownSubscriber));
    }

    function test_isSubscriptionExpired_naturalExpiry() public {
        uint256 endTime = _subscribe(1);

        assertFalse(asset.isSubscriptionExpired(_subscriber));

        vm.warp(endTime);
        assertTrue(asset.isSubscriptionExpired(_subscriber));
    }

    function test_isSubscriptionExpired_oneSecondBeforeEndTime() public {
        uint256 endTime = _subscribe(1);

        vm.warp(endTime - 1);
        assertFalse(asset.isSubscriptionExpired(_subscriber));
    }

    function test_isSubscriptionExpired_atExactEndTimeBoundary() public {
        // _isSubscriptionExpired uses `<= block.timestamp`, so endTime itself is expired
        uint256 endTime = _subscribe(1);

        vm.warp(endTime);
        assertTrue(asset.isSubscriptionExpired(_subscriber));
    }

    function test_isSubscriptionExpired_afterCancelMidPeriod_atTruncatedEndTime() public {
        _subscribe(1);

        // Cancel halfway through — endTime is left unchanged since no full future period exists
        uint256 elapsed = SUBSCRIPTION_DURATION / 2;
        vm.warp(block.timestamp + elapsed);
        _cancelAsSubscriber();

        uint256 truncatedEndTime = asset.getSubscriptionExpiration(_subscriber);
        assertFalse(asset.isSubscriptionExpired(_subscriber));

        // At the truncated endTime the subscription must be expired
        vm.warp(truncatedEndTime);
        assertTrue(asset.isSubscriptionExpired(_subscriber));
    }

    function test_isSubscriptionExpired_reflectsLatestNonce_afterResubscribe() public {
        uint256 endTime = _subscribe(1);

        // Let the subscription fully expire
        vm.warp(endTime + 1);
        assertTrue(asset.isSubscriptionExpired(_subscriber));

        // Re-subscribe — this creates a new nonce; isSubscriptionExpired should reflect the new endTime
        _subscribe(1);
        assertFalse(asset.isSubscriptionExpired(_subscriber));
    }

    function test_subscribe_expiredDeadline() public {
        address payer = signer;
        address spender = address(asset);
        uint256 value = asset.getSubscriptionPrice(COUNT);
        uint256 deadline = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);

        vm.expectRevert(Asset.PermitFailed.selector);
        asset.subscribe(_subscriber, payer, spender, 1, deadline, v, r, s);
    }

    function test_claimCreatorFee_zeroClaimable() public {
        _subscribe(1);
        uint256 assetOwnerBalanceBefore = testToken.balanceOf(assetOwner);

        vm.prank(assetOwner);
        uint256 claimed = asset.claimCreatorFee(_subscriber);

        assertEq(claimed, 0);
        assertEq(testToken.balanceOf(assetOwner), assetOwnerBalanceBefore);
    }

    function test_claimRegistryFee_zeroClaimable() public {
        _subscribe(1);
        uint256 registryOwnerBalanceBefore = testToken.balanceOf(registryOwner);

        vm.prank(address(assetRegistry));
        (uint256 claimed,,) = asset.claimRegistryFee(_subscriber);

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
        (uint256 claimed,,) = asset.claimRegistryFee(neverSubscribed);

        assertEq(claimed, 0);
        assertEq(testToken.balanceOf(registryOwner), registryOwnerBalanceBefore);
    }

    // --- Subscription extension: new nonce when conditions differ ---

    function test_subscribe_newNonce_differentPrice() public {
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(
            _subscriber,
            block.timestamp,
            block.timestamp + SUBSCRIPTION_DURATION,
            signer,
            SUBSCRIPTION_PRICE,
            REGISTRY_FEE_SHARE
        );
        _subscribe(1);

        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);

        uint256 newStart = block.timestamp + SUBSCRIPTION_DURATION;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRenewed(
            _subscriber,
            newStart,
            newStart + SUBSCRIPTION_DURATION,
            1,
            signer,
            SUBSCRIPTION_PRICE * 2,
            REGISTRY_FEE_SHARE
        );
        _subscribe(1);
    }

    function test_subscribe_newNonce_feeShareChanged() public {
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(
            _subscriber,
            block.timestamp,
            block.timestamp + SUBSCRIPTION_DURATION,
            signer,
            SUBSCRIPTION_PRICE,
            REGISTRY_FEE_SHARE
        );
        _subscribe(1);

        vm.prank(registryOwner);
        assetRegistry.updateRegistryFeeShare(50);

        uint256 newStart = block.timestamp + SUBSCRIPTION_DURATION;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRenewed(
            _subscriber, newStart, newStart + SUBSCRIPTION_DURATION, 1, signer, SUBSCRIPTION_PRICE, 50
        );
        _subscribe(1);
    }

    function test_subscribe_newNonce_differentPayer() public {
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(
            _subscriber,
            block.timestamp,
            block.timestamp + SUBSCRIPTION_DURATION,
            signer,
            SUBSCRIPTION_PRICE,
            REGISTRY_FEE_SHARE
        );
        _subscribe(1);

        address payer2 = vm.addr(otherKey);
        testToken.mint(payer2, 1e30);

        uint256 value = asset.getSubscriptionPrice(1);
        uint256 deadline = block.timestamp;
        uint256 nonce2 = testToken.nonces(payer2);
        bytes32 permitHash = keccak256(abi.encode(PERMIT_TYPEHASH, payer2, address(asset), value, nonce2, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", testToken.DOMAIN_SEPARATOR(), permitHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherKey, digest);

        uint256 newStart = block.timestamp + SUBSCRIPTION_DURATION;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRenewed(
            _subscriber, newStart, newStart + SUBSCRIPTION_DURATION, 1, payer2, SUBSCRIPTION_PRICE, REGISTRY_FEE_SHARE
        );
        asset.subscribe(_subscriber, payer2, address(asset), 1, deadline, v, r, s);
    }

    // --- Batch claimCreatorFee ---

    function test_claimCreatorFee_batch() public {
        bytes32 subscriber2 = keccak256("subscriber_2");
        _subscribe(1);
        _subscribeFor(subscriber2, 1);

        uint256 value = asset.getSubscriptionPrice(1);
        uint256 creatorFeePerSubscriber = value * (100 - REGISTRY_FEE_SHARE) / 100;
        vm.warp(block.timestamp + SUBSCRIPTION_DURATION);

        bytes32[] memory subs = new bytes32[](2);
        subs[0] = _subscriber;
        subs[1] = subscriber2;

        uint256 assetOwnerBalanceBefore = testToken.balanceOf(assetOwner);

        vm.startPrank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(_subscriber, creatorFeePerSubscriber, block.timestamp, 0);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(subscriber2, creatorFeePerSubscriber, block.timestamp, 0);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimedBatch(subs, creatorFeePerSubscriber * 2);
        uint256 claimed = asset.claimCreatorFee(subs);
        vm.stopPrank();

        assertEq(claimed, creatorFeePerSubscriber * 2);
        assertEq(testToken.balanceOf(assetOwner), assetOwnerBalanceBefore + claimed);
    }

    function test_claimCreatorFee_batch_unauthorized() public {
        _subscribe(COUNT);
        vm.warp(block.timestamp + COUNT);

        bytes32[] memory subs = new bytes32[](1);
        subs[0] = _subscriber;

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, UNAUTHORIZED));
        asset.claimCreatorFee(subs);
    }

    function test_claimCreatorFee_batch_skipsNonExistentSubscribers() public {
        bytes32 neverSubscribed = keccak256("never_subscribed");
        _subscribe(1);
        vm.warp(block.timestamp + SUBSCRIPTION_DURATION);

        uint256 value = asset.getSubscriptionPrice(1);
        uint256 creatorFee = value * (100 - REGISTRY_FEE_SHARE) / 100;

        bytes32[] memory subs = new bytes32[](2);
        subs[0] = _subscriber;
        subs[1] = neverSubscribed;

        uint256 assetOwnerBalanceBefore = testToken.balanceOf(assetOwner);

        vm.prank(assetOwner);
        uint256 claimed = asset.claimCreatorFee(subs);

        assertEq(claimed, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), assetOwnerBalanceBefore + claimed);
    }

    function test_claimCreatorFee_batch_skipsZeroFee() public {
        bytes32 subscriber2 = keccak256("subscriber_2");
        _subscribe(COUNT);
        _subscribeFor(subscriber2, COUNT);

        bytes32[] memory subs = new bytes32[](2);
        subs[0] = _subscriber;
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
        _subscribe(1);
        _subscribeFor(subscriber2, 1);

        uint256 value = asset.getSubscriptionPrice(1);
        uint256 registryFeePerSubscriber = value * REGISTRY_FEE_SHARE / 100;
        vm.warp(block.timestamp + SUBSCRIPTION_DURATION);

        bytes32[] memory subs = new bytes32[](2);
        subs[0] = _subscriber;
        subs[1] = subscriber2;

        uint256 registryOwnerBalanceBefore = testToken.balanceOf(registryOwner);

        vm.startPrank(address(assetRegistry));
        uint256 claimed = asset.claimRegistryFee(subs);
        vm.stopPrank();

        assertEq(claimed, registryFeePerSubscriber * 2);
        assertEq(testToken.balanceOf(registryOwner), registryOwnerBalanceBefore + claimed);
    }

    function test_claimRegistryFee_batch_unauthorized() public {
        _subscribe(COUNT);
        vm.warp(block.timestamp + COUNT);

        bytes32[] memory subs = new bytes32[](1);
        subs[0] = _subscriber;

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(Asset.OnlyRegistryUnauthorizedAccount.selector);
        asset.claimRegistryFee(subs);
    }

    function test_claimRegistryFee_batch_skipsNonExistentSubscribers() public {
        bytes32 neverSubscribed = keccak256("never_subscribed");
        _subscribe(1);
        vm.warp(block.timestamp + SUBSCRIPTION_DURATION);

        uint256 value = asset.getSubscriptionPrice(1);
        uint256 registryFee = value * REGISTRY_FEE_SHARE / 100;

        bytes32[] memory subs = new bytes32[](2);
        subs[0] = _subscriber;
        subs[1] = neverSubscribed;

        uint256 registryOwnerBalanceBefore = testToken.balanceOf(registryOwner);

        vm.prank(address(assetRegistry));
        uint256 claimed = asset.claimRegistryFee(subs);

        assertEq(claimed, registryFee);
        assertEq(testToken.balanceOf(registryOwner), registryOwnerBalanceBefore + claimed);
    }

    function test_claimRegistryFee_batch_skipsZeroFee() public {
        bytes32 subscriber2 = keccak256("subscriber_2");
        _subscribe(COUNT);
        _subscribeFor(subscriber2, COUNT);

        bytes32[] memory subs = new bytes32[](2);
        subs[0] = _subscriber;
        subs[1] = subscriber2;

        uint256 registryOwnerBalanceBefore = testToken.balanceOf(registryOwner);

        vm.prank(address(assetRegistry));
        uint256 claimed = asset.claimRegistryFee(subs);

        assertEq(claimed, 0);
        assertEq(testToken.balanceOf(registryOwner), registryOwnerBalanceBefore);
    }

    // --- Expired subscription creates a new nonce (no in-place extension) ---

    function test_subscribe_expiredSubscription_createsNewNonce() public {
        uint256 endTime = _subscribe(1);

        // Let the subscription fully expire
        vm.warp(endTime + 1);

        // Re-subscribe with the same payer, price and fee share — since the subscription expired,
        // startTime (block.timestamp) != subscription.endTime, so no in-place extension occurs.
        uint256 newEnd = block.timestamp + SUBSCRIPTION_DURATION;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRenewed(
            _subscriber, block.timestamp, newEnd, 1, signer, SUBSCRIPTION_PRICE, assetRegistry.getRegistryFeeShare()
        );
        uint256 returnedEnd = _subscribe(1);

        assertEq(returnedEnd, newEnd);
        assertEq(asset.getSubscriptionExpiration(_subscriber), newEnd);
    }

    // --- Claim tracking resets correctly after all subscriptions are revoked ---

    function test_claimCreatorFee_afterRevokeAndResubscribe() public {
        // Subscribe and immediately revoke: subscription hasn't elapsed so it is fully deleted
        // (startTime == block.timestamp satisfies the "not yet started" branch in _removeSubscription).
        // This also clears all claim-tracking state (creatorClaimedAtNonces/Timestamps, etc.).
        _subscribe(1);
        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);
        assertEq(asset.getSubscriptionExpiration(_subscriber), 0);
        assertTrue(asset.isSubscriberRevoked(_subscriber));

        // Revocation now acts as a ban — must unrevoke before the subscriber can re-subscribe.
        vm.prank(assetOwner);
        asset.unrevokeSubscription(_subscriber);

        // Re-subscribe at a different price to prove claim tracking starts fresh with a new nonce 0.
        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        uint256 endTime = _subscribe(1);
        vm.warp(endTime);

        uint256 value = asset.getSubscriptionPrice(1);
        uint256 expectedFee = value * (100 - REGISTRY_FEE_SHARE) / 100;

        vm.prank(assetOwner);
        uint256 claimed = asset.claimCreatorFee(_subscriber);
        assertEq(claimed, expectedFee);
    }

    // --- Revocation ban behavior ---

    function test_revokeSubscription_alreadyRevoked() public {
        _subscribe(1);
        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);

        vm.prank(assetOwner);
        vm.expectRevert(Asset.SubscriptionAlreadyRevoked.selector);
        asset.revokeSubscription(_subscriber);
    }

    function test_subscribe_reverts_whenSubscriberRevoked() public {
        _subscribe(1);
        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);
        assertTrue(asset.isSubscriberRevoked(_subscriber));

        address payer = signer;
        address spender = address(asset);
        uint256 value = asset.getSubscriptionPrice(1);
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);

        vm.expectRevert(Asset.OnlyUnrevokedUnauthorizedSubscriber.selector);
        asset.subscribe(_subscriber, payer, spender, 1, deadline, v, r, s);
    }

    function test_cancelSubscription_reverts_whenRevoked() public {
        _subscribe(1);
        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);
        assertTrue(asset.isSubscriberRevoked(_subscriber));

        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer);
        vm.prank(signer);
        vm.expectRevert(Asset.OnlyUnrevokedUnauthorizedSubscriber.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, signature);
    }

    function test_subscribe_afterUnrevoke_succeeds() public {
        _subscribe(1);
        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);
        assertTrue(asset.isSubscriberRevoked(_subscriber));

        vm.prank(assetOwner);
        asset.unrevokeSubscription(_subscriber);
        assertFalse(asset.isSubscriberRevoked(_subscriber));

        uint256 endTime = _subscribe(1);
        assertTrue(endTime > block.timestamp);
        assertTrue(asset.isSubscriptionActive(_subscriber));
    }

    function test_cancelSubscription_doesNotBanSubscriber() public {
        _subscribe(1);
        _cancelAsSubscriber();

        // Cancellation does not impose a ban — subscriber can immediately re-subscribe
        assertFalse(asset.isSubscriberRevoked(_subscriber));

        uint256 endTime = _subscribe(1);
        assertTrue(endTime > block.timestamp);
        assertTrue(asset.isSubscriptionActive(_subscriber));
    }

    // --- Unrevoking ---

    function test_unrevokeSubscription() public {
        _subscribe(1);

        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);
        assertTrue(asset.isSubscriberRevoked(_subscriber));

        vm.prank(assetOwner);
        vm.expectEmit(true, false, false, false);
        emit Asset.SubscriptionUnrevoked(_subscriber);
        asset.unrevokeSubscription(_subscriber);

        assertFalse(asset.isSubscriberRevoked(_subscriber));
    }

    function test_unrevokeSubscription_unauthorized() public {
        _subscribe(1);
        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, UNAUTHORIZED));
        asset.unrevokeSubscription(_subscriber);
    }

    function test_unrevokeSubscription_notRevoked() public {
        _subscribe(1);
        vm.prank(assetOwner);
        vm.expectRevert(Asset.SubscriptionNotRevoked.selector);
        asset.unrevokeSubscription(_subscriber);
    }

    // --- isSubscriptionActive ---

    function test_isSubscriptionActive_activeSubscription() public {
        _subscribe(1);
        assertTrue(asset.isSubscriptionActive(_subscriber));
    }

    function test_isSubscriptionActive_expiredSubscription() public {
        _subscribe(1);
        vm.warp(block.timestamp + SUBSCRIPTION_DURATION + 1);
        assertFalse(asset.isSubscriptionActive(_subscriber));
    }

    function test_isSubscriptionActive_revokedSubscription() public {
        _subscribe(1);
        vm.warp(block.timestamp + SUBSCRIPTION_DURATION / 2);

        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);

        // Revocation immediately ends the subscription and bans the subscriber
        assertFalse(asset.isSubscriptionActive(_subscriber));
        assertTrue(asset.isSubscriberRevoked(_subscriber));
    }

    function test_isSubscriptionActive_nonexistentSubscriber() public view {
        bytes32 unknownSubscriber = keccak256("unknown_active");
        assertFalse(asset.isSubscriptionActive(unknownSubscriber));
    }

    function test_isSubscriptionActive_midSubscription_notRevoked() public {
        _subscribe(1);
        vm.warp(block.timestamp + SUBSCRIPTION_DURATION / 2);
        assertTrue(asset.isSubscriptionActive(_subscriber));
    }

    // --- isSubscriberRevoked ---

    function test_isSubscriberRevoked_nonexistentSubscriber() public view {
        bytes32 unknownSubscriber = keccak256("unknown_revoked");
        assertFalse(asset.isSubscriberRevoked(unknownSubscriber));
    }

    function test_isSubscriberRevoked_afterRevokeAndUnrevoke() public {
        _subscribe(1);
        assertFalse(asset.isSubscriberRevoked(_subscriber));

        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);
        assertTrue(asset.isSubscriberRevoked(_subscriber));

        vm.prank(assetOwner);
        asset.unrevokeSubscription(_subscriber);
        assertFalse(asset.isSubscriberRevoked(_subscriber));
    }

    // --- Revoke vs cancel refund difference ---

    function test_revokeSubscription_refundsDust_midPeriod() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(1);

        // Warp to a quarter through the period
        uint256 elapsed = SUBSCRIPTION_DURATION / 4;
        vm.warp(block.timestamp + elapsed);

        // Revocation refunds proportionally: total paid minus the elapsed portion (including dust)
        uint256 elapsedDust = (elapsed * SUBSCRIPTION_PRICE) / SUBSCRIPTION_DURATION;
        uint256 expectedRefund = SUBSCRIPTION_PRICE - elapsedDust;

        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);

        assertEq(testToken.balanceOf(signer), tokenBalance - SUBSCRIPTION_PRICE + expectedRefund);
        assertTrue(asset.isSubscriptionExpired(_subscriber));
        assertTrue(asset.isSubscriberRevoked(_subscriber));
        assertFalse(asset.isSubscriptionActive(_subscriber));
    }

    function test_cancelSubscription_noRefund_whenNullFullPeriodRemaining() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(1);

        // Warp to a quarter through the period — less than one full period remains
        vm.warp(block.timestamp + SUBSCRIPTION_DURATION / 4);

        _cancelAsSubscriber();

        // Cancellation only refunds whole future periods; no refund here since < 1 full period remains
        assertEq(testToken.balanceOf(signer), tokenBalance - SUBSCRIPTION_PRICE);
        // Subscription stays active until the original endTime (no truncation since no periods were refunded)
        assertFalse(asset.isSubscriptionExpired(_subscriber));
        assertFalse(asset.isSubscriberRevoked(_subscriber));
    }

    function test_claimRegistryFee_afterRevokeAndResubscribe() public {
        // Subscribe and immediately revoke for a clean full-deletion and tracking reset.
        _subscribe(1);
        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);
        assertEq(asset.getSubscriptionExpiration(_subscriber), 0);
        assertTrue(asset.isSubscriberRevoked(_subscriber));

        // Revocation now acts as a ban — must unrevoke before the subscriber can re-subscribe.
        vm.prank(assetOwner);
        asset.unrevokeSubscription(_subscriber);

        // Re-subscribe from scratch; claim tracking must have been reset.
        uint256 endTime = _subscribe(1);
        vm.warp(endTime);

        uint256 value = asset.getSubscriptionPrice(1);
        uint256 expectedFee = value * REGISTRY_FEE_SHARE / 100;

        vm.prank(address(assetRegistry));
        (uint256 claimed,,) = asset.claimRegistryFee(_subscriber);
        assertEq(claimed, expectedFee);
    }
}
