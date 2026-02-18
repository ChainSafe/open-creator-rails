// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AssetRegistry.sol";
import "../src/Asset.sol";
import "../src/GameToken.sol";

contract DeployForLocalIndexerTest is Script {
    function run() external {
        // Use anvil default account (set in env before running)
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // 1. Deploy GameToken
        GameToken gameToken = new GameToken();

        // Optionally mint some tokens to deployer if GameToken has mint()
        gameToken.mint(deployer, 1_000_000e18);

        console.log("GameToken deployed at:", address(gameToken));

        // 2. Deploy AssetRegistry (AssetContract in the indexer naming)
        uint256 creatorFeeShare = 7000;
        uint256 registryFeeShare = 3000;

        AssetRegistry registry = new AssetRegistry(
            creatorFeeShare,
            registryFeeShare
        );

        console.log("AssetRegistry (AssetContract) deployed at:", address(registry));

        // 3. Create a Game Asset via createAsset
        bytes32 gameAssetId = bytes32(uint256(0x01)); // arbitrary id
        uint256 subscriptionPrice = 1e18;             // 1 token (assuming 18 decimals)
        address tokenAddress = address(gameToken);
        address gameAssetOwner = deployer;

        address gameAssetAddress = registry.createAsset(
            gameAssetId,
            subscriptionPrice,
            tokenAddress,
            gameAssetOwner
        );

        console.log("GameAsset created with assetId:");
        console.logBytes32(gameAssetId);
        console.log("GameAsset (Asset) deployed at:", gameAssetAddress);

        // 3a. Update fee shares on the registry to emit CreatorFeeShareUpdated and RegistryFeeShareUpdated
        registry.updateCreatorFeeShare(6000);
        registry.updateRegistryFeeShare(4000);

        // 3b. Update subscription price on the asset to emit SubscriptionPriceUpdated
        Asset gameAsset = Asset(gameAssetAddress);
        uint256 newSubscriptionPrice = 2e18;
        gameAsset.setSubscriptionPrice(newSubscriptionPrice);

        // 3c. Create a subscription via permit to emit SubscriptionAdded
        _subscribeViaPermit(gameToken, gameAsset, deployerKey, deployer, 10e18);

        // 3d. Revoke the subscription to emit SubscriptionRevoked
        bool revoked = gameAsset.revokeSubscription(deployer);
        console.log("SubscriptionRevoked emitted, success:", revoked);

        // 4. Sanity: retrieve the asset with getAsset
        address lookedUpAsset = registry.getAsset(gameAssetId);
        console.log("getAsset(gameAssetId) returned:", lookedUpAsset);

        // 5. Extra events for the indexer

        // 5a. OwnershipTransferred on the registry
        address newRegistryOwner = address(0xBEEF);
        registry.transferOwnership(newRegistryOwner);
        console.log("Registry ownership transferred to:", newRegistryOwner);

        // 5b. OwnershipTransferred on the GameAsset
        address newGameAssetOwner = address(0xCAFE);
        gameAsset.transferOwnership(newGameAssetOwner);
        console.log("GameAsset ownership transferred to:", newGameAssetOwner);

        // (Optional extension)
        // If GameToken supports ERC20Permit and you want to emit SubscriptionAdded,
        // you can implement a permit + subscribe call here to generate those events.

        vm.stopBroadcast();
    }

    function _subscribeViaPermit(
        GameToken gameToken,
        Asset gameAsset,
        uint256 deployerKey,
        address user,
        uint256 value
    ) internal {
        address subscriptionUser = user;
        address subscriptionSpender = address(gameAsset);
        uint256 subscriptionValue = value;
        uint256 deadline = block.timestamp + 1 hours;

        // Build EIP-2612 permit digest for GameToken
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                subscriptionUser,
                subscriptionSpender,
                subscriptionValue,
                gameToken.nonces(subscriptionUser),
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                gameToken.DOMAIN_SEPARATOR(),
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digest);

        bool subscribed = gameAsset.subscribe(
            subscriptionUser,
            subscriptionSpender,
            subscriptionValue,
            deadline,
            v,
            r,
            s
        );

        console.log("SubscriptionAdded emitted, success:", subscribed);
    }
}