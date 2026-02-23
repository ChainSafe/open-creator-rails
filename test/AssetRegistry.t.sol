// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AssetRegistry} from "../src/AssetRegistry.sol";
import {IAsset} from "../src/IAsset.sol";
import {BaseTest} from "./Base.t.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract AssetRegistryTest is BaseTest {

    function setUp() public override {
        super.setUp();

        vm.startPrank(registryOwner);
        assetRegistry = new AssetRegistry(70, 30);
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

        address owner = signer;
        address spender = address(asset);
        uint256 value = asset.getSubscriptionPrice(DURATION);
        uint256 deadline = block.timestamp + DURATION;

        (uint8 v, bytes32 r, bytes32 s) = getPermit(owner, spender, value, deadline);        

        uint256 subscription = assetRegistry.subscribe(ASSET_ID, owner, spender, value, deadline, v, r, s);
        
        assertTrue(subscription > block.timestamp);

        vm.startPrank(signer);
        assertEq(asset.getMySubscription(), subscription);
        vm.stopPrank();
    }

    function test_viewSubscription() public {
        test_createAsset();
        
        vm.startPrank(signer);
        assertEq(assetRegistry.viewSubscription(ASSET_ID), false);
        vm.stopPrank();
        
        test_subscribe();
        
        vm.startPrank(signer);
        assertEq(assetRegistry.viewSubscription(ASSET_ID), true);
        vm.stopPrank();
    }

    function test_getSubscription() public {
        test_createAsset();

        vm.startPrank(signer);
        assertEq(assetRegistry.getSubscription(ASSET_ID), 0);
        vm.stopPrank();
        
        test_subscribe();
        
        vm.startPrank(signer);
        assertTrue(assetRegistry.getSubscription(ASSET_ID) > block.timestamp);
        vm.stopPrank();
    }

    function test_getSubscriptionPrice() public {
        test_createAsset();

        assertEq(assetRegistry.getSubscriptionPrice(ASSET_ID, 10), asset.getSubscriptionPrice(10));
    }

    function test_updateFeeShare() public {
        vm.startPrank(registryOwner);
        assetRegistry.updateCreatorFeeShare(80);
        assetRegistry.updateRegistryFeeShare(20);
        vm.stopPrank();

        assertEq(assetRegistry.getCreatorFee(100000000), 80000000);
        assertEq(assetRegistry.getRegistryFee(100000000), 20000000);
    }

    function test_updateCreatorFeeShare_emitsEvent() public {
        vm.startPrank(registryOwner);

        vm.expectEmit(true, true, true, true);
        emit AssetRegistry.CreatorFeeShareUpdated(80);
        assetRegistry.updateCreatorFeeShare(80);

        vm.stopPrank();
    }

    function test_updateRegistryFeeShare_emitsEvent() public {
        vm.startPrank(registryOwner);

        vm.expectEmit(true, true, true, true);
        emit AssetRegistry.RegistryFeeShareUpdated(20);
        assetRegistry.updateRegistryFeeShare(20);

        vm.stopPrank();
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

    function test_createAsset_unauthorized() public {
        vm.startPrank(address(403));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(403)));
        assetRegistry.createAsset(ASSET_ID, SUBSCRIPTION_PRICE, address(testToken), assetOwner);
        vm.stopPrank();
    }

    function test_updateCreatorFeeShare_unauthorized() public {
        vm.startPrank(address(403));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(403)));
        assetRegistry.updateCreatorFeeShare(80);
        vm.stopPrank();
    }

    function test_updateRegistryFeeShare_unauthorized() public {
        vm.startPrank(address(403));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(403)));
        assetRegistry.updateRegistryFeeShare(20);
        vm.stopPrank();
    }

    function test_viewSubscription_withUser_ownerCanCall() public {
        test_createAsset();
        test_subscribe();

        vm.startPrank(registryOwner);
        assertTrue(assetRegistry.viewSubscription(ASSET_ID, signer));
        vm.stopPrank();
    }

    function test_viewSubscription_withUser_unauthorized() public {
        test_createAsset();

        vm.startPrank(address(403));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(403)));
        assetRegistry.viewSubscription(ASSET_ID, signer);
        vm.stopPrank();
    }

    function test_getSubscription_withUser_ownerCanCall() public {
        test_createAsset();
        test_subscribe();

        vm.startPrank(registryOwner);
        assertTrue(assetRegistry.getSubscription(ASSET_ID, signer) > block.timestamp);
        vm.stopPrank();
    }

    function test_getSubscription_withUser_unauthorized() public {
        test_createAsset();

        vm.startPrank(address(403));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(403)));
        assetRegistry.getSubscription(ASSET_ID, signer);
        vm.stopPrank();
    }
}