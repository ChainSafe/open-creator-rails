// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AssetRegistry} from "../src/AssetRegistry.sol";
import {IAsset} from "../src/IAsset.sol";
import {BaseTest} from "./Base.t.sol";

contract AssetRegistryTest is BaseTest {
    AssetRegistry public assetRegistry;

    bytes32 internal constant ASSET_ID = keccak256(abi.encodePacked("asset_id"));

    function setUp() public override {
        super.setUp();

        assetRegistry = new AssetRegistry();
    }

    function test_createAsset() public {
        address asset = assetRegistry.createAsset(ASSET_ID, 100000000, address(gameToken), signer);
        assertEq(IAsset(asset).getAssetId(), ASSET_ID);
        assertEq(asset, address(assetRegistry.assets(ASSET_ID)));
    }

    function test_getAsset() public {
        test_createAsset();
        address asset = assetRegistry.getAsset(ASSET_ID);
        assertEq(IAsset(asset).getAssetId(), ASSET_ID);
    }

    function test_subscribe() public {
        if (assetRegistry.assets(ASSET_ID) == address(0)) {
            test_createAsset();
        }
        
        address owner = signer;
        address spender = assetRegistry.getAsset(ASSET_ID);
        uint256 duration = 3600;
        uint256 value = IAsset(spender).getSubscriptionPrice(duration);
        uint256 deadline = block.timestamp + duration;

        (uint8 v, bytes32 r, bytes32 s) = getPermit(owner, spender, value, deadline);        

        bool success = assetRegistry.subscribe(ASSET_ID, owner, spender, value, deadline, v, r, s);
        
        assertTrue(success);

        assertEq(IAsset(spender).getSubscription(owner), deadline);
    }

    function test_viewSubscription() public {
        test_createAsset();
        assertEq(assetRegistry.viewSubscription(ASSET_ID), false);
        test_subscribe();
        assertEq(assetRegistry.viewSubscription(ASSET_ID), true);
    }

    function test_getSubscription() public {
        test_createAsset();
        assertEq(assetRegistry.getSubscription(ASSET_ID), 0);
        test_subscribe();
        assertTrue(assetRegistry.getSubscription(ASSET_ID) > block.timestamp);
    }

    function test_getSubscriptionPrice() public {
        test_createAsset();
        address asset = assetRegistry.getAsset(ASSET_ID);
        assertEq(assetRegistry.getSubscriptionPrice(ASSET_ID, 10), IAsset(asset).getSubscriptionPrice(10));
    }
}