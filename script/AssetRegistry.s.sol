// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {IAsset} from "../src/IAsset.sol";
import {GameToken} from "../src/GameToken.sol";
import {DeployScript} from "./Deploy.s.sol";
import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

/// @title AssetRegistryScript
/// @notice Scripts for creating assets and subscribing via the AssetRegistry.
/// @dev Usage: run with `./script/run.sh AssetRegistry "<signature>" <args...>`.
///      For address arguments use $(get_address "ContractName") after running `source ./script/utils.sh` to get addresses from deployments.json.
contract AssetRegistryScript is DeployScript {
    AssetRegistry public assetRegistry;
    GameToken public gameToken;

    bytes32 internal constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    error SubscriptionFailed();

    function setUp() public {
        assetRegistry = AssetRegistry(getAddress(".AssetRegistry"));
        gameToken = GameToken(getAddress(".GameToken"));
    }

    /// @notice Creates a new asset in the registry (registry owner only).
    /// @dev Usage: ./script/run.sh AssetRegistry "createAsset(string,uint256)" "<assetId>" <subscriptionPrice>
    function createAsset(string memory _assetId, uint256 _subscriptionPrice) public {
        vm.startBroadcast();
        address asset = assetRegistry.createAsset(keccak256(abi.encodePacked(_assetId)), _subscriptionPrice, address(gameToken), msg.sender);
        console.log(string.concat(_assetId, " Asset created: ", vm.toString(asset)));     
        vm.stopBroadcast();
    }

    /// @notice Subscribes the signer to an asset for the given duration using an ERC-20 permit.
    /// @dev Usage: ./script/run.sh AssetRegistry "subscribe(string,uint256)" "<assetId>" <duration>
    function subscribe(string memory _assetId, uint256 _duration) public {
        vm.startBroadcast();
        
        bytes32 assetIdHash = keccak256(abi.encodePacked(_assetId));
        IAsset asset = IAsset(assetRegistry.getAsset(assetIdHash));

        (uint8 v, bytes32 r, bytes32 s, uint256 deadline, address owner) = signPermit(assetRegistry.getSubscriptionPrice(assetIdHash, _duration), _duration, address(asset));
        
        bool success = assetRegistry.subscribe(assetIdHash, owner, address(asset), asset.getSubscriptionPrice(_duration), deadline, v, r, s);

        if (!success) {
            revert SubscriptionFailed();
        }                

        console.log(string.concat("Subscribed to asset: ", _assetId, " for duration: ", vm.toString(_duration)));        
        console.log(string.concat("Subscription expires at: ", vm.toString(asset.getMySubscription())));

        vm.stopBroadcast();
    }

    /// @notice Signs a permit for subscription payment (helper; usually called internally by subscribe).
    /// @dev Usage: ./script/run.sh AssetRegistry "signPermit(uint256,uint256,address)" <value> <duration> <spender>
    function signPermit(uint256 value, uint256 duration, address spender) public view returns (uint8 v, bytes32 r, bytes32 s, uint256 deadline, address owner) {
        
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        owner = vm.addr(privateKey);

        address tokenAddress = getAddress(".GameToken");
        
        IERC20Permit token = IERC20Permit(tokenAddress);

        uint256 nonce = token.nonces(owner);
        
        deadline = block.timestamp + duration;

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        (v, r, s) = vm.sign(privateKey, digest);

        console.log("v: ", vm.toString(v));
        console.log("r: ", vm.toString(r));
        console.log("s: ", vm.toString(s));
        console.log("deadline: ", vm.toString(deadline));
        console.log("owner: ", owner);
        
        return (v, r, s, deadline, owner);
    }
}