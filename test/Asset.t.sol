// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Asset} from "../src/Asset.sol";
import {BaseTest} from "./Base.t.sol";

contract AssetTest is BaseTest {
    Asset public asset;

    string internal constant ASSET_ID = "asset_id";
    uint256 internal constant SUBSCRIPTION_PRICE = 100000000;

    address internal owner;

    function setUp() public override {
        super.setUp();

        owner = signer;
        asset = new Asset(keccak256(abi.encodePacked(ASSET_ID)), SUBSCRIPTION_PRICE, address(gameToken), owner);
    }

    function test_getAssetId() public view {
        assertEq(asset.getAssetId(), keccak256(abi.encodePacked(ASSET_ID)));
    }

    function test_getSubscriptionPrice() public view {
        assertEq(asset.getSubscriptionPrice(10), SUBSCRIPTION_PRICE * 10);
    }

    function test_subscribe() public {
        
        uint256 duration = 3600;

        address spender = address(asset);
        
        uint256 value = asset.getSubscriptionPrice(duration);

        uint256 deadline = block.timestamp + duration;
        
        (uint8 v, bytes32 r, bytes32 s) = getPermit(owner, spender, value, deadline);        
        
        bool success = asset.subscribe(owner, spender, value, deadline, v, r, s);
        
        assertTrue(success);

        assertEq(asset.getMySubscription(), deadline);
    }

    function test_revokeSubscription() public {
        
        test_subscribe();

        bool success = asset.revokeSubscription(owner);
        
        assertTrue(success);

        assertEq(asset.getMySubscription(), 0);
    }

    function test_viewSubscription() public {
        
        test_subscribe();

        assertEq(asset.viewMySubscription(), true);

        test_revokeSubscription();

        assertEq(asset.viewMySubscription(), false);
    }

    function test_unauthorized() public {
        vm.startPrank(address(1));

        vm.expectRevert(Asset.Unauthorized.selector);
        asset.getSubscription(address(1));

        vm.expectRevert(Asset.Unauthorized.selector);
        asset.viewSubscription(address(1));

        vm.stopPrank();
    }
}