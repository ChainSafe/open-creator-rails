// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTest} from "./Base.t.sol";
import {Asset} from "../src/Asset.sol";

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
        assertEq(asset.getSubscriptionPrice(10), SUBSCRIPTION_PRICE * 10);
    }

    function test_subscribe() public {

        vm.startPrank(signer);
        bool hasSubscription = asset.viewMySubscription();
        vm.stopPrank();
        if (hasSubscription) {
            return;
        }
        
        address owner = signer;
        address spender = address(asset);
        
        uint256 value = asset.getSubscriptionPrice(DURATION);

        uint256 deadline = block.timestamp + DURATION;
        
        (uint8 v, bytes32 r, bytes32 s) = getPermit(owner, spender, value, deadline);        
        
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionAdded(owner, deadline);

        uint256 subscription = asset.subscribe(owner, spender, value, deadline, v, r, s);
        
        assertTrue(subscription > block.timestamp);

        vm.startPrank(signer);
        assertEq(asset.getMySubscription(), subscription);
        vm.stopPrank();
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
        
        test_subscribe();

        vm.startPrank(assetOwner);
        vm.expectEmit(true, true, true, true);
        emit Asset.SubscriptionRevoked(signer);
        bool success = asset.revokeSubscription(signer);
        vm.stopPrank();

        assertTrue(success);

        vm.startPrank(signer);
        assertEq(asset.getMySubscription(), 0);
        vm.stopPrank();
    }

    function test_viewSubscription() public {
        
        test_subscribe();

        vm.startPrank(signer);
        assertEq(asset.viewMySubscription(), true);
        vm.stopPrank();

        test_revokeSubscription();

        vm.startPrank(signer);
        assertEq(asset.viewMySubscription(), false);
        vm.stopPrank();
    }

    function test_unauthorized() public {
        vm.startPrank(address(403));

        vm.expectRevert(Asset.OnlyRegistryOrOwnerUnauthorizedAccount.selector);
        asset.getSubscription(signer);

        vm.expectRevert(Asset.OnlyRegistryOrOwnerUnauthorizedAccount.selector);
        asset.viewSubscription(signer);

        vm.stopPrank();
    }

    function test_feeSplit() public {
        uint256 creatorBalance = testToken.balanceOf(assetOwner);
        uint256 registryBalance = testToken.balanceOf(registryOwner);
        
        test_subscribe();

        uint256 value = SUBSCRIPTION_PRICE * DURATION;

        uint256 creatorFee = assetRegistry.getCreatorFee(value);
        uint256 registryFee = assetRegistry.getRegistryFee(value);

        assertEq(testToken.balanceOf(assetOwner), creatorBalance + creatorFee);
        assertEq(testToken.balanceOf(registryOwner), registryBalance + registryFee);
    }
}