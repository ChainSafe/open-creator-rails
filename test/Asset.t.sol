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
        uint256 expectedPrice = SUBSCRIPTION_PRICE * 10;
        assertEq(asset.getSubscriptionPrice(10), expectedPrice);
    }

    function _subscribe(uint256 duration) internal returns (uint256 subscription) {
        address payer = signer;
        address spender = address(asset);

        uint256 value = asset.getSubscriptionPrice(duration);

        uint256 deadline = block.timestamp + duration;

        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);

        subscription = asset.subscribe(_subscriber, payer, spender, value, deadline, v, r, s);

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
        uint256 expectedFee = SUBSCRIPTION_PRICE * DURATION;
        uint256 signerBalanceBefore = testToken.balanceOf(signer);
        uint256 assetBalanceBefore = testToken.balanceOf(address(asset));

        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(
            _subscriber,
            block.timestamp,
            block.timestamp + DURATION,
            signer,
            SUBSCRIPTION_PRICE,
            assetRegistry.getRegistryFeeShare()
        );

        uint256 subscription = _subscribe(DURATION);

        assertTrue(subscription > block.timestamp);

        assertEq(asset.getSubscription(_subscriber), subscription);
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

        for (uint256 i = 0; i < count; i++) {
            vm.expectEmit(true, true, true, true);
            if (i == 0) {
                emit Asset.SubscriptionAdded(
                    _subscriber,
                    deadline,
                    deadline + DURATION,
                    signer,
                    SUBSCRIPTION_PRICE,
                    assetRegistry.getRegistryFeeShare()
                );
            } else {
                emit Asset.SubscriptionExtended(_subscriber, deadline + DURATION);
            }
            _subscribe(DURATION);
            deadline += DURATION;
        }

        assertEq(asset.getSubscription(_subscriber), block.timestamp + (DURATION * count));
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
        emit Asset.CreatorFeeClaimed(_subscriber, creatorFee);
        uint256 claimedCreatorFee = asset.claimCreatorFee(_subscriber);
        vm.stopPrank();

        assertEq(claimedCreatorFee, creatorFee);
        assertEq(testToken.balanceOf(assetOwner), claimedCreatorFee);
    }

    function test_claimCreatorFee_multiple() public {
        test_subscribe_multiple();

        vm.prank(signer);
        uint256 endTime = asset.getSubscription(_subscriber);
        uint256 value = asset.getSubscriptionPrice(endTime - block.timestamp);
        vm.warp(endTime);

        vm.startPrank(assetOwner);

        uint256 creatorFee = assetRegistry.getCreatorFee(value);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(_subscriber, creatorFee);

        uint256 claimedCreatorFee = asset.claimCreatorFee(_subscriber);

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
        emit Asset.CreatorFeeClaimed(_subscriber, creatorFee);
        uint256 claimedCreatorFee = asset.claimCreatorFee(_subscriber);
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
        emit Asset.CreatorFeeClaimed(_subscriber, creatorFee);
        uint256 claimedCreatorFee = asset.claimCreatorFee(_subscriber);
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
        uint256 claimedCreatorFee = asset.claimCreatorFee(_subscriber);

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
        uint256 claimedCreatorFee = asset.claimCreatorFee(_subscriber);

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
        emit Asset.CreatorFeeClaimed(_subscriber, creatorFee);
        uint256 claimedCreatorFee = asset.claimCreatorFee(_subscriber);
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
        emit Asset.SubscriptionRevoked(_subscriber, 0, 0);
        asset.revokeSubscription(_subscriber);

        assertEq(testToken.balanceOf(signer), tokenBalance);
        assertEq(asset.getSubscription(_subscriber), 0);
    }

    function test_revokeSubscription_multiple() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        test_subscribe_multiple();

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION * 10));

        vm.prank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRevoked(_subscriber, 0, 0);
        asset.revokeSubscription(_subscriber);

        assertEq(testToken.balanceOf(signer), tokenBalance);
        assertEq(asset.getSubscription(_subscriber), 0);
    }

    function test_revokeSubscription_midSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        for (uint256 i = 0; i < 2; i++) {
            _subscribe(DURATION);
        }

        uint256 value = asset.getSubscriptionPrice(DURATION);
        vm.warp(block.timestamp + DURATION + (DURATION / 2));

        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);

        assertEq(testToken.balanceOf(signer), tokenBalance - (value + (value / 2)));
        assertEq(asset.getSubscription(_subscriber), block.timestamp);
    }

    function test_revokeSubscription_endOfSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.warp(block.timestamp + DURATION);
        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION));
        assertEq(asset.getSubscription(_subscriber), block.timestamp);
    }

    function test_revokeSubscription_multiple_subscriptionPrice() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        _subscribe(DURATION);

        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);

        assertEq(asset.getSubscription(_subscriber), 0);
        assertEq(testToken.balanceOf(signer), tokenBalance);
    }

    function test_isMySubscriptionActive() public {
        test_subscribe();
        vm.prank(signer);
        assertTrue(asset.isSubscriptionActive(_subscriber));

        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);

        vm.prank(signer);
        assertFalse(asset.isSubscriptionActive(_subscriber));
    }

    function test_isMySubscriptionActive_cancelSubscription() public {
        test_subscribe();
        vm.prank(signer);
        assertTrue(asset.isSubscriptionActive(_subscriber));

        _cancelAsSubscriber();

        vm.prank(signer);
        assertFalse(asset.isSubscriptionActive(_subscriber));
    }

    function test_subscribe_invalidSpender() public {
        address payer = signer;
        address spender = address(1); // Wrong spender - must be address(asset)
        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 deadline = block.timestamp + DURATION;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, address(asset), value, deadline);

        vm.expectRevert(Asset.InvalidSpender.selector);
        asset.subscribe(_subscriber, payer, spender, value, deadline, v, r, s);
    }

    function test_subscribe_permitFailed() public {
        address payer = signer;
        address spender = address(asset);
        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 deadline = block.timestamp + DURATION;
        // Use invalid signature - wrong v, r, s
        (uint8 v, bytes32 r, bytes32 s) = (0, bytes32(0), bytes32(0));

        vm.expectRevert(Asset.PermitFailed.selector);
        asset.subscribe(_subscriber, payer, spender, value, deadline, v, r, s);
    }

    function test_subscribe_insufficientFunds() public {
        address payer = signer;
        address spender = address(asset);
        uint256 value = SUBSCRIPTION_PRICE - 1; // Below subscriptionPrice, rounds to 0
        uint256 deadline = block.timestamp + DURATION;
        (uint8 v, bytes32 r, bytes32 s) = getPermit(payer, spender, value, deadline);

        vm.expectRevert(Asset.InsufficientFunds.selector);
        asset.subscribe(_subscriber, payer, spender, value, deadline, v, r, s);
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
        _subscribe(DURATION);

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION));

        _cancelAsSubscriber();

        assertEq(testToken.balanceOf(signer), tokenBalance);
        assertEq(asset.getSubscription(_subscriber), 0);
    }

    function test_cancelSubscription_multiple() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        test_subscribe_multiple();

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION * 10));

        _cancelAsSubscriber();

        assertEq(testToken.balanceOf(signer), tokenBalance);
        assertEq(asset.getSubscription(_subscriber), 0);
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
        assertEq(asset.getSubscription(_subscriber), block.timestamp);
    }

    function test_cancelSubscription_endOfSubscription() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.warp(block.timestamp + DURATION);
        _cancelAsSubscriber();

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION));
        assertEq(asset.getSubscription(_subscriber), block.timestamp);
    }

    function test_cancelSubscription_multiple_subscriptionPrice() public {
        uint256 tokenBalance = testToken.balanceOf(signer);
        _subscribe(DURATION);

        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        _subscribe(DURATION);

        _cancelAsSubscriber();

        assertEq(asset.getSubscription(_subscriber), 0);
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

        assertEq(testToken.balanceOf(signer), tokenBalance - asset.getSubscriptionPrice(DURATION));
    }

    function test_cancelSubscription_sameSubscriberIdDifferentAddressesIndependent() public {
        address otherAddress = vm.addr(otherKey);
        bytes32 otherSubscriber = _subscriberHash(SUBSCRIBER_ID, otherAddress);

        _subscribe(DURATION);
        _subscribeFor(otherSubscriber, DURATION);

        bytes memory signerSignature = getCancellationSignature(SUBSCRIBER_ID, signer);
        bytes memory otherSignature = _getCancellationSignatureWithKey(SUBSCRIBER_ID, otherAddress, otherKey);

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, signerSignature);

        assertEq(asset.getSubscription(_subscriber), 0);
        assertTrue(asset.isSubscriptionActive(otherSubscriber));

        vm.prank(otherAddress);
        asset.cancelSubscription(SUBSCRIBER_ID, otherSignature);
        assertEq(asset.getSubscription(otherSubscriber), 0);
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
        assertEq(asset.getSubscription(_subscriber), 0);

        vm.prank(signer);
        vm.expectRevert(Asset.SubscriptionNotFound.selector);
        asset.cancelSubscription(SUBSCRIBER_ID, signature);
    }

    function test_cancelSubscription_doesNotAffectOtherAddressWithSameSubscriberId() public {
        address otherAddress = vm.addr(otherKey);
        bytes32 otherSubscriber = _subscriberHash(SUBSCRIBER_ID, otherAddress);

        _subscribe(DURATION);
        _subscribeFor(otherSubscriber, DURATION);

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, getCancellationSignature(SUBSCRIBER_ID, signer));

        assertEq(asset.getSubscription(_subscriber), 0);
        assertTrue(asset.isSubscriptionActive(otherSubscriber));
    }

    function test_cancelSubscription_doesNotAffectOtherSubscriberIdSameAddress() public {
        bytes32 otherSubscriber = _subscriberHash(OTHER_SUBSCRIBER_ID, signer);

        _subscribe(DURATION);
        _subscribeFor(otherSubscriber, DURATION);

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, getCancellationSignature(SUBSCRIBER_ID, signer));

        assertEq(asset.getSubscription(_subscriber), 0);
        assertTrue(asset.isSubscriptionActive(otherSubscriber));
    }

    function test_cancelSubscription_withActiveMultiNonceSubscriptions_refundsCorrectly() public {
        uint256 tokenBalance = testToken.balanceOf(signer);

        _subscribe(DURATION);
        _subscribe(DURATION);
        _subscribe(DURATION);

        vm.prank(signer);
        asset.cancelSubscription(SUBSCRIBER_ID, getCancellationSignature(SUBSCRIBER_ID, signer));

        assertEq(asset.getSubscription(_subscriber), 0);
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
        _subscribe(DURATION);

        vm.prank(assetOwner);
        vm.expectEmit(true, false, false, false);
        emit Asset.SubscriptionRemoved(_subscriber);
        asset.revokeSubscription(_subscriber);
    }

    function test_cancelSubscription_emitsSubscriptionRemoved_whenFullyDeleted() public {
        _subscribe(DURATION);

        bytes memory signature = getCancellationSignature(SUBSCRIBER_ID, signer);

        vm.prank(signer);
        vm.expectEmit(true, false, false, false);
        emit Asset.SubscriptionRemoved(_subscriber);
        asset.cancelSubscription(SUBSCRIBER_ID, signature);
    }

    function test_claimCreatorFee_unauthorized() public {
        test_subscribe();
        vm.warp(block.timestamp + DURATION);

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, UNAUTHORIZED));
        asset.claimCreatorFee(_subscriber);
    }

    function test_claimRegistryFee_unauthorized() public {
        test_subscribe();
        vm.warp(block.timestamp + DURATION);

        vm.prank(registryOwner);
        vm.expectRevert(Asset.OnlyRegistryUnauthorizedAccount.selector);
        asset.claimRegistryFee(_subscriber);
    }

    function test_feeSplit() public {
        uint256 creatorBalance = testToken.balanceOf(assetOwner);
        uint256 registryBalance = testToken.balanceOf(registryOwner);
        test_subscribe();

        uint256 value = asset.getSubscriptionPrice(DURATION);
        (uint256 creatorFee, uint256 registryFee) = assetRegistry.getFees(value);

        vm.warp(block.timestamp + DURATION);

        vm.prank(assetOwner);
        uint256 claimedCreatorFee = asset.claimCreatorFee(_subscriber);

        vm.prank(address(assetRegistry));
        uint256 claimedRegistryFee = asset.claimRegistryFee(_subscriber);

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
        asset.subscribe(_subscriber, payer, spender, value, deadline, v, r, s);
    }

    function test_claimCreatorFee_zeroClaimable() public {
        _subscribe(DURATION);
        uint256 assetOwnerBalanceBefore = testToken.balanceOf(assetOwner);

        vm.prank(assetOwner);
        uint256 claimed = asset.claimCreatorFee(_subscriber);

        assertEq(claimed, 0);
        assertEq(testToken.balanceOf(assetOwner), assetOwnerBalanceBefore);
    }

    function test_claimRegistryFee_zeroClaimable() public {
        _subscribe(DURATION);
        uint256 registryOwnerBalanceBefore = testToken.balanceOf(registryOwner);

        vm.prank(address(assetRegistry));
        uint256 claimed = asset.claimRegistryFee(_subscriber);

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
            _subscriber,
            block.timestamp,
            block.timestamp + DURATION,
            signer,
            SUBSCRIPTION_PRICE,
            assetRegistry.getRegistryFeeShare()
        );
        _subscribe(DURATION);

        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);

        uint256 newStart = block.timestamp + DURATION;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRenewed(
            _subscriber,
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
            _subscriber,
            block.timestamp,
            block.timestamp + DURATION,
            signer,
            SUBSCRIPTION_PRICE,
            assetRegistry.getRegistryFeeShare()
        );
        _subscribe(DURATION);

        vm.prank(registryOwner);
        assetRegistry.updateRegistryFeeShare(50);

        uint256 newStart = block.timestamp + DURATION;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRenewed(_subscriber, newStart, newStart + DURATION, 1, signer, SUBSCRIPTION_PRICE, 50);
        _subscribe(DURATION);
    }

    function test_subscribe_newNonce_differentPayer() public {
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(
            _subscriber,
            block.timestamp,
            block.timestamp + DURATION,
            signer,
            SUBSCRIPTION_PRICE,
            assetRegistry.getRegistryFeeShare()
        );
        _subscribe(DURATION);

        address payer2 = vm.addr(otherKey);
        testToken.mint(payer2, 1e30);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 deadline = block.timestamp + DURATION * 2;
        uint256 nonce2 = testToken.nonces(payer2);
        bytes32 permitHash = keccak256(abi.encode(PERMIT_TYPEHASH, payer2, address(asset), value, nonce2, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", testToken.DOMAIN_SEPARATOR(), permitHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherKey, digest);

        uint256 newStart = block.timestamp + DURATION;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRenewed(
            _subscriber,
            newStart,
            newStart + DURATION,
            1,
            payer2,
            SUBSCRIPTION_PRICE,
            assetRegistry.getRegistryFeeShare()
        );
        asset.subscribe(_subscriber, payer2, address(asset), value, deadline, v, r, s);
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
        subs[0] = _subscriber;
        subs[1] = subscriber2;

        uint256 assetOwnerBalanceBefore = testToken.balanceOf(assetOwner);

        vm.startPrank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.CreatorFeeClaimed(_subscriber, creatorFeePerSubscriber);
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
        subs[0] = _subscriber;

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
        _subscribe(DURATION);
        _subscribeFor(subscriber2, DURATION);

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
        _subscribe(DURATION);
        _subscribeFor(subscriber2, DURATION);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 registryFeePerSubscriber = assetRegistry.getRegistryFee(value);
        vm.warp(block.timestamp + DURATION);

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
        _subscribe(DURATION);
        vm.warp(block.timestamp + DURATION);

        bytes32[] memory subs = new bytes32[](1);
        subs[0] = _subscriber;

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
        _subscribe(DURATION);
        _subscribeFor(subscriber2, DURATION);

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
        uint256 endTime = _subscribe(DURATION);

        // Let the subscription fully expire
        vm.warp(endTime + 1);

        // Re-subscribe with the same payer, price and fee share — since the subscription expired,
        // startTime (block.timestamp) != subscription.endTime, so no in-place extension occurs.
        uint256 newEnd = block.timestamp + DURATION;
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRenewed(
            _subscriber, block.timestamp, newEnd, 1, signer, SUBSCRIPTION_PRICE, assetRegistry.getRegistryFeeShare()
        );
        uint256 returnedEnd = _subscribe(DURATION);

        assertEq(returnedEnd, newEnd);
        assertEq(asset.getSubscription(_subscriber), newEnd);
    }

    // --- Claim tracking resets correctly after all subscriptions are revoked ---

    function test_claimCreatorFee_afterRevokeAndResubscribe() public {
        // Subscribe and immediately revoke: subscription hasn't elapsed so it is fully deleted
        // (startTime == block.timestamp satisfies the "not yet started" branch in _removeSubscription).
        // This also clears all claim-tracking state (creatorClaimedAtNonces/Timestamps, etc.).
        _subscribe(DURATION);
        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);
        assertEq(asset.getSubscription(_subscriber), 0);

        // Re-subscribe at a different price to prove claim tracking starts fresh with a new nonce 0.
        vm.prank(assetOwner);
        asset.setSubscriptionPrice(SUBSCRIPTION_PRICE * 2);
        uint256 endTime = _subscribe(DURATION);
        vm.warp(endTime);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 expectedFee = assetRegistry.getCreatorFee(value);

        vm.prank(assetOwner);
        uint256 claimed = asset.claimCreatorFee(_subscriber);
        assertEq(claimed, expectedFee);
    }

    function test_claimRegistryFee_afterRevokeAndResubscribe() public {
        // Subscribe and immediately revoke for a clean full-deletion and tracking reset.
        _subscribe(DURATION);
        vm.prank(assetOwner);
        asset.revokeSubscription(_subscriber);
        assertEq(asset.getSubscription(_subscriber), 0);

        // Re-subscribe from scratch; claim tracking must have been reset.
        uint256 endTime = _subscribe(DURATION);
        vm.warp(endTime);

        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 expectedFee = assetRegistry.getRegistryFee(value);

        vm.prank(address(assetRegistry));
        uint256 claimed = asset.claimRegistryFee(_subscriber);
        assertEq(claimed, expectedFee);
    }
}
