// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./Base.t.sol";
import {Asset} from "../src/Asset.sol";
import {IAsset} from "../src/IAsset.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
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

        subscription = asset.subscribe(SUBSCRIBER, payer, spender, count, deadline, v, r, s);

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
        vm.prank(signer);
        uint256 timestamp = asset.commitCancellation(SUBSCRIBER_ID);
        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer, timestamp);

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, signature);
    }

    function _subscriberHash(string memory subscriberId, address subscriberAddress) internal pure returns (bytes32) {
        return keccak256(abi.encode(subscriberId, subscriberAddress));
    }

    function _getCancellationSignatureWithKey(
        string memory subscriberId,
        address subscriberAddress,
        uint256 timestamp,
        uint256 signingKey
    ) internal view returns (bytes memory signature) {
        bytes32 subscriber = keccak256(abi.encode(subscriberId, subscriberAddress));
        bytes32 hash = keccak256(abi.encodePacked(block.chainid, address(asset), timestamp, subscriber));
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function test_subscribe() public {
        uint256 expectedFee = SUBSCRIPTION_PRICE * DURATION;
        uint256 signerBalanceBefore = testToken.balanceOf(signer);
        uint256 assetBalanceBefore = testToken.balanceOf(address(asset));

        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(
            SUBSCRIBER,
            block.timestamp,
            block.timestamp + DURATION,
            0,
            signer,
            SUBSCRIPTION_PRICE,
            assetRegistry.getRegistryFeeShare()
        );

        uint256 subscription = _subscribe(DURATION);

        assertTrue(subscription > block.timestamp);

        assertEq(asset.getSubscription(SUBSCRIBER), subscription);
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
        uint256 deadline = block.timestamp;
        uint256 count = 10;
        uint256 duration = DURATION * count;

        for (uint256 i = 0; i < count; i++) {
            vm.expectEmit(true, true, true, true);
            if (i == 0) {
                emit Asset.SubscriptionAdded(
                    SUBSCRIBER,
                    deadline,
                    deadline + DURATION,
                    i,
                    signer,
                    SUBSCRIPTION_PRICE,
                    assetRegistry.getRegistryFeeShare()
                );
            } else {
                emit Asset.SubscriptionExtended(SUBSCRIBER, deadline + DURATION * (i + 1));
            }
            _subscribe(DURATION);
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
        emit Asset.SubscriptionRevoked(SUBSCRIBER, 0);
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
        emit Asset.SubscriptionRevoked(SUBSCRIBER, 0);
        asset.revokeSubscription(SUBSCRIBER);

        assertEq(testToken.balanceOf(signer), tokenBalance);
        assertEq(asset.getSubscription(SUBSCRIBER), 0);
    }

    function test_revokeSubscription_midSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        for (uint256 i = 0; i < 2; i++) {
            _subscribe(DURATION);
        }

        uint256 value = asset.getSubscriptionPrice(DURATION);
        vm.warp(block.timestamp + DURATION + (DURATION / 2));

        vm.prank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRevoked(SUBSCRIBER, block.timestamp);
        asset.revokeSubscription(SUBSCRIBER);

        assertEq(testToken.balanceOf(signer), tokenBalance - (value + (value / 2)));
        // With SUBSCRIPTION_DURATION=1 every remaining second is a refundable period, so full
        // remaining half-duration is refunded and endTime is truncated to the current timestamp
        // (end of the just completed 1-second period); subscription stays active until that point.
        assertEq(asset.getSubscription(SUBSCRIBER), block.timestamp);
        assertFalse(asset.isSubscriptionActive(SUBSCRIBER));
    }

    function test_revokeSubscription_endOfSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.warp(block.timestamp + DURATION);
        vm.prank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRevoked(SUBSCRIBER, 0);
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
        emit Asset.SubscriptionRevoked(SUBSCRIBER, 0);
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

        _cancelAsSubscriber();

        vm.prank(signer);
        assertFalse(asset.isSubscriptionActive(SUBSCRIBER));
    }

    function test_subscribe_invalidSpender() public {
        address payer = signer;
        address spender = address(1); // Wrong spender - must be address(asset)
        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, address(asset), value, deadline);

        vm.expectRevert(Asset.InvalidSpender.selector);
        asset.subscribe(SUBSCRIBER, payer, spender, DURATION, deadline, v, r, s);
    }

    function test_subscribe_permitFailed() public {
        address payer = signer;
        address spender = address(asset);
        uint256 deadline = block.timestamp;
        // Use invalid signature - wrong v, r, s
        (uint8 v, bytes32 r, bytes32 s) = (0, bytes32(0), bytes32(0));

        vm.expectRevert(Asset.PermitFailed.selector);
        asset.subscribe(SUBSCRIBER, payer, spender, DURATION, deadline, v, r, s);
    }

    function test_subscribe_insufficientFunds() public {
        address payer = signer;
        address spender = address(asset);
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, 0, deadline);

        vm.expectRevert(Asset.InsufficientFunds.selector);
        asset.subscribe(SUBSCRIBER, payer, spender, 0, deadline, v, r, s);
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

        _cancelAsSubscriber();

        assertEq(testToken.balanceOf(signer), tokenBalance);
        assertEq(asset.getSubscription(SUBSCRIBER), 0);
    }

    function test_cancelSubscription_multiple() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        test_subscribe_multiple();

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION * 10));

        _cancelAsSubscriber();

        assertEq(testToken.balanceOf(signer), tokenBalance);
        assertEq(asset.getSubscription(SUBSCRIBER), 0);
    }

    function test_cancelSubscription_midSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        for (uint256 i = 0; i < 2; i++) {
            _subscribe(DURATION);
        }

        uint256 value = asset.getSubscriptionPrice(DURATION);
        vm.warp(block.timestamp + DURATION + (DURATION / 2));

        _cancelAsSubscriber();

        assertEq(testToken.balanceOf(signer), tokenBalance - (value + (value / 2)));
        // With SUBSCRIPTION_DURATION=1 every remaining second is a refundable period, so full
        // remaining half-duration is refunded and endTime is truncated to the current timestamp
        // (end of the just completed 1-second period); subscription stays active until that point.
        assertEq(asset.getSubscription(SUBSCRIBER), block.timestamp);
        assertFalse(asset.isSubscriptionActive(SUBSCRIBER));
    }

    function test_cancelSubscription_endOfSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.warp(block.timestamp + DURATION);
        _cancelAsSubscriber();

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION));
        assertEq(asset.getSubscription(SUBSCRIBER), block.timestamp);
    }

    function test_cancelSubscription_multiple_subscriptionPrice() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        _subscribe(DURATION);

        _cancelAsSubscriber();

        assertEq(asset.getSubscription(SUBSCRIBER), 0);
        assertEq(testToken.balanceOf(signer), tokenBalance);
    }

    function test_cancelSubscription_noSubscription() public {
        vm.prank(signer);
        uint256 timestamp = asset.commitCancellation(SUBSCRIBER_ID);
        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer, timestamp);

        vm.prank(signer);
        vm.expectRevert(Asset.SubscriptionNotFound.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, signature);
    }

    function test_cancelSubscription_unauthorized() public {
        uint256 tokenBalance = testToken.balanceOf(signer);

        test_subscribe();

        vm.prank(UNAUTHORIZED);
        uint256 timestamp = asset.commitCancellation(SUBSCRIBER_ID);
        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer, timestamp);

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(Asset.InvalidSignature.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, signature);

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
        assertEq(testToken.balanceOf(signer), tokenBalance - paidRecord0 - paidRecord1, "both records charged upfront");

        // Warp half-way into record 0
        vm.warp(block.timestamp + DURATION / 2);

        _cancelAsSubscriber();

        // Active record is truncated to end of current period (== block.timestamp here since
        // SUBSCRIPTION_DURATION=1); future record is deleted.
        assertFalse(asset.isSubscriptionActive(SUBSCRIBER));
        assertEq(asset.getSubscription(SUBSCRIBER), block.timestamp);

        // Refund:
        //   record 0 (active): (DURATION/2 seconds remaining) / SUBSCRIPTION_DURATION (=1) periods at original price
        //   record 1 (future): full DURATION periods at doubled price
        uint256 refund0 = (DURATION / 2) * originalPrice;
        uint256 refund1 = paidRecord1;
        uint256 expectedCharged = paidRecord0 + paidRecord1 - refund0 - refund1;

        assertEq(testToken.balanceOf(signer), tokenBalance - expectedCharged, "only first half of record 0 forfeited");
    }

    function test_commitCancellation_setsTimestampForHashedSubscriber() public {
        test_subscribe();

        vm.prank(signer);
        uint256 timestamp = asset.commitCancellation(SUBSCRIBER_ID);
        assertEq(timestamp, block.timestamp);

        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer, timestamp);
        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, signature);

        assertEq(asset.getSubscription(SUBSCRIBER), 0);
    }

    function test_commitCancellation_overwritesPreviousTimestampForSameSubscriber() public {
        test_subscribe();

        vm.prank(signer);
        uint256 timestamp1 = asset.commitCancellation(SUBSCRIBER_ID);

        vm.warp(block.timestamp + 1);
        vm.prank(signer);
        uint256 timestamp2 = asset.commitCancellation(SUBSCRIBER_ID);

        assertTrue(timestamp2 > timestamp1);

        bytes memory oldSignature = getCancellationSignature(SUBSCRIBER_ID, signer, timestamp1);
        vm.prank(signer);
        vm.expectRevert(Asset.InvalidCancellationCommitment.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp1, oldSignature);

        bytes memory newSignature = getCancellationSignature(SUBSCRIBER_ID, signer, timestamp2);
        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp2, newSignature);

        // endTime truncates to end of current period (== block.timestamp with SUBSCRIPTION_DURATION=1)
        assertEq(asset.getSubscription(SUBSCRIBER), block.timestamp);
    }

    function test_commitCancellation_sameSubscriberIdDifferentAddress_storesIndependently() public {
        uint256 otherKey = vm.deriveKey(MNEMONIC, 1);
        address otherAddress = vm.addr(otherKey);
        bytes32 otherSubscriber = _subscriberHash(SUBSCRIBER_ID, otherAddress);

        _subscribe(DURATION);
        _subscribeFor(otherSubscriber, DURATION);

        vm.prank(signer);
        uint256 signerTimestamp = asset.commitCancellation(SUBSCRIBER_ID);
        bytes memory signerSignature = getCancellationSignature(SUBSCRIBER_ID, signer, signerTimestamp);

        vm.prank(otherAddress);
        uint256 otherTimestamp = asset.commitCancellation(SUBSCRIBER_ID);
        bytes memory otherSignature =
            _getCancellationSignatureWithKey(SUBSCRIBER_ID, otherAddress, otherTimestamp, otherKey);

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, signerTimestamp, signerSignature);

        assertEq(asset.getSubscription(SUBSCRIBER), 0);
        assertTrue(asset.isSubscriptionActive(otherSubscriber));

        vm.prank(otherAddress);
        asset.cancelSubscription(SUBSCRIBER_ID, otherTimestamp, otherSignature);
        assertEq(asset.getSubscription(otherSubscriber), 0);
    }

    function test_cancelSubscription_reverts_invalidCommitment_whenNoCommit() public {
        test_subscribe();
        uint256 timestamp = block.timestamp;
        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer, timestamp);

        vm.prank(signer);
        vm.expectRevert(Asset.InvalidCancellationCommitment.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, signature);
    }

    function test_cancelSubscription_reverts_invalidCommitment_whenTimestampMismatch() public {
        test_subscribe();

        vm.prank(signer);
        uint256 committedTimestamp = asset.commitCancellation(SUBSCRIBER_ID);

        uint256 wrongTimestamp = committedTimestamp + 1;
        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer, wrongTimestamp);

        vm.prank(signer);
        vm.expectRevert(Asset.InvalidCancellationCommitment.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, wrongTimestamp, signature);
    }

    function test_cancelSubscription_reverts_invalidCommitment_whenUsingCommitFromDifferentAddress() public {
        test_subscribe();

        vm.prank(signer);
        uint256 timestamp = asset.commitCancellation(SUBSCRIBER_ID);
        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer, timestamp);

        uint256 otherKey = vm.deriveKey(MNEMONIC, 1);
        address otherAddress = vm.addr(otherKey);
        vm.prank(otherAddress);
        vm.expectRevert(Asset.InvalidCancellationCommitment.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, signature);
    }

    function test_cancelSubscription_reverts_invalidCommitment_whenUsingDifferentSubscriberId() public {
        test_subscribe();

        vm.prank(signer);
        uint256 timestamp = asset.commitCancellation(SUBSCRIBER_ID);
        bytes memory signature = getCancellationSignature(OTHER_SUBSCRIBER_ID, signer, timestamp);

        vm.prank(signer);
        vm.expectRevert(Asset.InvalidCancellationCommitment.selector);
        asset.cancelSubscription(OTHER_SUBSCRIBER_ID, timestamp, signature);
    }

    function test_cancelSubscription_reverts_invalidSignature_whenSignedByDifferentKey() public {
        test_subscribe();

        vm.prank(signer);
        uint256 timestamp = asset.commitCancellation(SUBSCRIBER_ID);

        uint256 otherKey = vm.deriveKey(MNEMONIC, 1);
        bytes memory badSignature = _getCancellationSignatureWithKey(SUBSCRIBER_ID, signer, timestamp, otherKey);

        vm.prank(signer);
        vm.expectRevert(Asset.InvalidSignature.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, badSignature);
    }

    function test_cancelSubscription_reverts_invalidSignature_whenSignatureForDifferentTimestamp() public {
        test_subscribe();

        vm.prank(signer);
        uint256 timestamp = asset.commitCancellation(SUBSCRIBER_ID);
        bytes memory badSignature = getCancellationSignature(SUBSCRIBER_ID, signer, timestamp + 1);

        vm.prank(signer);
        vm.expectRevert(Asset.InvalidSignature.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, badSignature);
    }

    function test_cancelSubscription_reverts_invalidSignature_whenSignatureForDifferentSubscriberHash() public {
        test_subscribe();

        vm.prank(signer);
        uint256 timestamp = asset.commitCancellation(SUBSCRIBER_ID);
        bytes memory badSignature = getCancellationSignature(OTHER_SUBSCRIBER_ID, signer, timestamp);

        vm.prank(signer);
        vm.expectRevert(Asset.InvalidSignature.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, badSignature);
    }

    function test_cancelSubscription_reverts_invalidSignature_whenCallerDiffersFromSigner() public {
        test_subscribe();

        vm.prank(UNAUTHORIZED);
        uint256 timestamp = asset.commitCancellation(SUBSCRIBER_ID);
        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer, timestamp);

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(Asset.InvalidSignature.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, signature);
    }

    function test_cancelSubscription_success_deletesCancellationCommitment() public {
        test_subscribe();

        vm.prank(signer);
        uint256 timestamp = asset.commitCancellation(SUBSCRIBER_ID);
        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer, timestamp);

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, signature);
        assertEq(asset.getSubscription(SUBSCRIBER), 0);

        vm.prank(signer);
        vm.expectRevert(Asset.InvalidCancellationCommitment.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, signature);
    }

    function test_cancelSubscription_replayFails_afterSuccessfulCancellation() public {
        test_subscribe();

        vm.prank(signer);
        uint256 timestamp = asset.commitCancellation(SUBSCRIBER_ID);
        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer, timestamp);

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, signature);

        vm.prank(signer);
        vm.expectRevert(Asset.InvalidCancellationCommitment.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, signature);
    }

    function test_cancelSubscription_doesNotAffectOtherAddressWithSameSubscriberId() public {
        uint256 otherKey = vm.deriveKey(MNEMONIC, 1);
        address otherAddress = vm.addr(otherKey);
        bytes32 otherSubscriber = _subscriberHash(SUBSCRIBER_ID, otherAddress);

        _subscribe(DURATION);
        _subscribeFor(otherSubscriber, DURATION);

        vm.prank(signer);
        uint256 timestamp = asset.commitCancellation(SUBSCRIBER_ID);
        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer, timestamp);

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, signature);

        assertEq(asset.getSubscription(SUBSCRIBER), 0);
        assertTrue(asset.isSubscriptionActive(otherSubscriber));
    }

    function test_cancelSubscription_doesNotAffectOtherSubscriberIdSameAddress() public {
        bytes32 otherSubscriber = _subscriberHash(OTHER_SUBSCRIBER_ID, signer);

        _subscribe(DURATION);
        _subscribeFor(otherSubscriber, DURATION);

        vm.prank(signer);
        uint256 timestamp = asset.commitCancellation(SUBSCRIBER_ID);
        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer, timestamp);

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, signature);

        assertEq(asset.getSubscription(SUBSCRIBER), 0);
        assertTrue(asset.isSubscriptionActive(otherSubscriber));
    }

    function test_cancelSubscription_withActiveMultiNonceSubscriptions_refundsCorrectly() public {
        uint256 tokenBalance = testToken.balanceOf(signer);

        _subscribe(DURATION);
        _subscribe(DURATION);
        _subscribe(DURATION);

        vm.prank(signer);
        uint256 timestamp = asset.commitCancellation(SUBSCRIBER_ID);
        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer, timestamp);

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, signature);

        assertEq(asset.getSubscription(SUBSCRIBER), 0);
        assertEq(testToken.balanceOf(signer), tokenBalance);
    }

    function test_cancelSubscription_emitsSubscriptionCancelled_withExpectedSubscriberHash() public {
        test_subscribe();

        vm.prank(signer);
        uint256 timestamp = asset.commitCancellation(SUBSCRIBER_ID);
        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer, timestamp);

        vm.prank(signer);
        vm.expectEmit(true, false, false, true);
        emit Asset.SubscriptionCancelled(SUBSCRIBER, 0);
        asset.cancelSubscription(SUBSCRIBER_ID, timestamp, signature);
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
        asset.subscribe(SUBSCRIBER, payer, spender, 1, deadline, v, r, s);
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
        emit Asset.SubscriptionAdded(
            SUBSCRIBER,
            block.timestamp,
            block.timestamp + DURATION,
            0,
            signer,
            SUBSCRIPTION_PRICE,
            assetRegistry.getRegistryFeeShare()
        );
        _subscribe(DURATION);

        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);

        uint256 newStart = block.timestamp + DURATION;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(
            SUBSCRIBER,
            newStart,
            newStart + DURATION,
            1,
            signer,
            SUBSCRIPTION_PRICE * 2,
            assetRegistry.getRegistryFeeShare()
        );
        _subscribe(DURATION);
    }

    function test_subscribe_newNonce_feeShareChanged() public {
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(
            SUBSCRIBER,
            block.timestamp,
            block.timestamp + DURATION,
            0,
            signer,
            SUBSCRIPTION_PRICE,
            assetRegistry.getRegistryFeeShare()
        );
        _subscribe(DURATION);

        vm.prank(registryOwner);
        assetRegistry.updateRegistryFeeShare(50);

        uint256 newStart = block.timestamp + DURATION;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(SUBSCRIBER, newStart, newStart + DURATION, 1, signer, SUBSCRIPTION_PRICE, 50);
        _subscribe(DURATION);
    }

    function test_subscribe_newNonce_differentPayer() public {
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(
            SUBSCRIBER,
            block.timestamp,
            block.timestamp + DURATION,
            0,
            signer,
            SUBSCRIPTION_PRICE,
            assetRegistry.getRegistryFeeShare()
        );
        _subscribe(DURATION);

        uint256 key2 = vm.deriveKey(MNEMONIC, 1);
        address payer2 = vm.addr(key2);
        testToken.mint(payer2, 1e30);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 deadline = block.timestamp;
        uint256 nonce2 = testToken.nonces(payer2);
        bytes32 permitHash = keccak256(abi.encode(PERMIT_TYPEHASH, payer2, address(asset), value, nonce2, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", testToken.DOMAIN_SEPARATOR(), permitHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key2, digest);

        uint256 newStart = block.timestamp + DURATION;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(
            SUBSCRIBER,
            newStart,
            newStart + DURATION,
            1,
            payer2,
            SUBSCRIPTION_PRICE,
            assetRegistry.getRegistryFeeShare()
        );
        asset.subscribe(SUBSCRIBER, payer2, address(asset), DURATION, deadline, v, r, s);
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
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimedBatch(subs, creatorFeePerSubscriber * 2);
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
        emit Asset.SubscriptionAdded(
            SUBSCRIBER, block.timestamp, newEnd, 1, signer, SUBSCRIPTION_PRICE, assetRegistry.getRegistryFeeShare()
        );
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
