// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Asset} from "../src/Asset.sol";
import {GameToken} from "../src/GameToken.sol";

contract AssetTest is Test {
    Asset public asset;
    GameToken public gameToken;

    string internal constant ASSET_ID = "asset_id";
    bytes32 internal constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    uint256 internal constant SUBSCRIPTION_PRICE = 100000000;

    address internal owner;
    uint256 internal key;
    string internal constant MNEMONIC = "test test test test test test test test test test test junk";

    function setUp() public {
        gameToken = new GameToken();
        asset = new Asset(keccak256(abi.encodePacked(ASSET_ID)), SUBSCRIPTION_PRICE, address(gameToken));
        
        key = vm.deriveKey(MNEMONIC, 0);
        owner = vm.addr(key);

        gameToken.mint(owner, 1000000000000000000000000000000000000000);
    }

    function test_getAssetId() public {
        assertEq(asset.getAssetId(), keccak256(abi.encodePacked(ASSET_ID)));
    }

    function test_getSubscriptionPrice() public {
        assertEq(asset.getSubscriptionPrice(10), SUBSCRIPTION_PRICE * 10);
    }

    function test_subscribe() public {
        
        uint256 duration = 3600;

        address spender = address(asset);
        
        uint256 value = asset.getSubscriptionPrice(duration);

        uint256 deadline = block.timestamp + duration;
        
        uint256 nonce = gameToken.nonces(owner);

        bytes32 hash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", gameToken.DOMAIN_SEPARATOR(), hash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);        
        
        asset.subscribe(owner, spender, value, deadline, v, r, s);

        assertEq(asset.getSubscription(owner), deadline);
    }

    function test_revokeSubscription() public {
        
        test_subscribe();

        asset.revokeSubscription(owner);

        assertEq(asset.getSubscription(owner), 0);
    }

    function test_viewSubscription() public {
        
        test_subscribe();

        assertEq(asset.viewSubscription(owner), true);

        test_revokeSubscription();

        assertEq(asset.viewSubscription(owner), false);
    }
}