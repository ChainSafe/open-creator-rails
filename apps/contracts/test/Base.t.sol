// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TestToken} from "../src/TestToken.sol";
import {IAsset} from "../src/IAsset.sol";
import {IAssetRegistry} from "../src/IAssetRegistry.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";

contract BaseTest is Test {

    TestToken internal testToken;
    IAsset internal asset;
    IAssetRegistry internal assetRegistry;


    bytes32 internal constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    string internal constant MNEMONIC = "test test test test test test test test test test test junk";

    bytes32 internal constant ASSET_ID = keccak256(abi.encodePacked("asset_id"));
    bytes32 internal constant SUBSCRIBER = keccak256(abi.encodePacked("subscriber_id"));
    uint256 internal constant SUBSCRIPTION_PRICE = 100000000;
    uint256 internal constant DURATION = 3600;

    address internal constant UNAUTHORIZED = address(403);

    address internal assetOwner;
    address internal registryOwner;

    address internal signer;
    uint256 internal key;

    function setUp() public virtual {
        testToken = new TestToken();

        key = vm.deriveKey(MNEMONIC, 0);
        signer = vm.addr(key);

        vm.startPrank(signer);

        testToken.mint(signer, 1000000000000000000000000000000000000000);

        registryOwner = address(1);
        assetOwner = address(2);

        vm.startPrank(registryOwner);
        assetRegistry = new AssetRegistry(70, 30);
        asset = IAsset(assetRegistry.createAsset(ASSET_ID, SUBSCRIPTION_PRICE, address(testToken), assetOwner));
        vm.stopPrank();
    }

    function getPermit(address owner, address spender, uint256 value, uint256 deadline) public view returns (uint8 v, bytes32 r, bytes32 s) {
        
        uint256 nonce = testToken.nonces(owner);

        bytes32 hash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", testToken.DOMAIN_SEPARATOR(), hash)
        );

        (v, r, s) = vm.sign(key, digest);

        return (v, r, s);
    }
}