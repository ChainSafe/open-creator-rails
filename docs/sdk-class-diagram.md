# SDK Class Diagram

This document captures the current high-level SDK architecture and how the runtime components collaborate.

```mermaid
classDiagram
direction TB

class Sdk {
  <<Singleton>>
  +IIndexerProvider IndexerProvider
  +IWalletProvider WalletProvider
  + EventHandler: IEventHandler
  +IAsset[] Assets
  +Initialize(EthereumAddress[] assets) Promise
  +AddAsset(EthereumAddress asset) Promise~IAsset~
  +GetAsset(string assetId, EthereumAddress? registryAddress = null) IAsset
  +static DeployRegistry(decimal registryFeeShare) AssetRegistryService
  +static GetAssetRegistry(EthereumAddress address) AssetRegistryService
}

class IIndexerProvider {
  <<interface>>
  +string IndexerUrl
  +GetAsset(string assetIdHash, EthereumAddress registryAddress) Promise~AssetDto~
}

class IWalletProvider {
  <<interface>>
  +BigInteger ChainId
  +int ConnectedAccountIndex
  +EthereumAddress ConnectedAccount
  +Connect(int index = 0) Promise~address~
  +SignTypedData~T,TDomain~(T message, TypedData~TDomain~ typedData) EthECDSASignature
  +Disconnect() Promise
}

class IEventHandler {
  <<interface>>
  +Subscribe~T~(EthereumAddress address, IWeb3 web3, EventDelegate~T~ callback) void //Where T is the specific event data
}

class IAsset {
  <<interface>>
  +string AssetId
  +string AssetIdHash // 32 length
  +EthereumAddress Address
  +BigInteger SubscriptionPrice
  +EthereumAddress Owner
  +EthereumAddress TokenAddress
  +Subscription[] Subscriptions
  +EthereumAddress RegistryAddress
  +AssetService AssetService
  +PermitService PermitService
  +AssetRegistryService AssetRegistryService
  
  %% For subscriber
  +Promise~DateTime~ GetSubscriptionExpiration(string subscriberId)
  +Promise~bool~ IsSubscriptionExpired(string subscriberId)
  +Promise~bool~ IsSubscriberRevoked(string subscriberId)
  +Promise~bool~ IsSubscriptionActive(string subscriberId)
  +Promise CancelSubscription(string subscriberId)
  +Promise~DateTime~ Subscribe(string subscriberId, TimeSpan duration)

  %% For asset owner
  +Promise SetSubscriptionPrice(BigInteger newSubscriptionPrice)
  +Promise~BigInteger~ ClaimCreatorFee(string subscriberId)
  +Promise~BigInteger~ ClaimCreatorFee(string[] subscriberIds)
  +Promise RevokeSubscription(string subscriberId)
  +Promise UnrevokeSubscription(string subscriberId)
}

class PonderIndexerProvider {
  +string IndexerUrl
  +Query~T~(string query) Promise~T~
  +GetAsset(string assetIdHash, EthereumAddress registryAddress) UniTask~AssetDto~
}

class EmbeddedWalletProvider {
  +Wallet Wallet
  +string RpcUrl
  +BigInteger ChainId
  +int ConnectedAccountIndex
  +EthereumAddress ConnectedAccount
  +Connect(int index = 0) Promise~Web3~
  +SignTypedData~T,TDomain~(...) EthECDSASignature
  +Disconnect() Promise
}

class AssetService {
  <<generated from Asset.sol ABI>>
}
class PermitService {
  <<generated from ERC20Permit.sol ABI>>
}
class AssetRegistryService {
  <<generated from AssetRegistry.sol ABI>>
}

Sdk --> IIndexerProvider : holds reference
Sdk --> IWalletProvider : holds reference
Sdk --> IEventHandler : holds reference
Sdk --> IAsset : manages collection
Sdk ..> AssetRegistryService : static factory return type

PonderIndexerProvider ..|> IIndexerProvider
EmbeddedWalletProvider ..|> IWalletProvider

IAsset --> AssetService : uses
IAsset --> PermitService : uses
IAsset --> AssetRegistryService : uses
IAsset ..> IIndexerProvider : refresh/query state
IAsset ..> IWalletProvider : fetch chainId and connected account
IAsset ..> IEventHandler : Smart Contract event subscriptions
IAsset ..> Sdk : receives Web3/init context
```

## Class Roles

- `Sdk`: the singleton orchestration entry point. It owns references to provider abstractions and the in-memory asset collection, and exposes helper factory methods for registry-level contract services.
- `IIndexerProvider`: abstraction for indexer reads. Implementations are responsible for looking up asset state from indexed chain data.
- `IWalletProvider`: abstraction for account connectivity and EIP-712 signing. It provides chain/account context used by write flows.
- `IEventHandler`: abstraction for contract event subscriptions. It attaches event delegates to contract addresses and typed event DTOs.
- `IAsset`: runtime asset abstraction combining identity, on-chain state projections, contract services, and subscriber/owner operations.
- `PonderIndexerProvider`: concrete indexer implementation of `IIndexerProvider`, backed by query-based indexer requests.
- `EmbeddedWalletProvider`: concrete wallet implementation of `IWalletProvider`, backed by an embedded HD wallet and RPC connection.
- `AssetService`, `PermitService`, `AssetRegistryService`: generated ABI service clients used by `IAsset` and `Sdk` for on-chain interactions.

## Relationship Notes

- `Sdk` depends on interfaces (`IIndexerProvider`, `IWalletProvider`, `IEventHandler`, `IAsset`) instead of concrete classes, so implementations can be swapped without changing orchestration logic.
- `PonderIndexerProvider` and `EmbeddedWalletProvider` realize their respective interfaces, giving concrete transport/signing behavior.
- `IAsset` composes three generated service clients to separate asset contract calls, permit/token calls, and registry calls.
- `IAsset` queries indexer state through `IIndexerProvider`, uses wallet context through `IWalletProvider`, and delegates event wiring to `IEventHandler`.
- `Sdk` manages `IAsset` instances and provides lifecycle/init context consumed by each asset.
