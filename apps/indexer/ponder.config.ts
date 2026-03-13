import { getAbiItem  } from "viem";
import { createConfig, factory } from "ponder";

import { 
  AssetABI, 
  AssetRegistryABI,
  sepoliaDeployments,
  localDeployments
} from "@open-creator-rails/config";

// Extract the event strictly
const AssetCreatedEvent = getAbiItem({ 
  abi: AssetRegistryABI, 
  name: "AssetCreated" 
});

const sepoliaRegistryAddresses = sepoliaDeployments.map((d: any) => d.address as `0x${string}`);
const localRegistryAddresses = localDeployments.map((d: any) => d.address as `0x${string}`);

export default createConfig({
  chains: {
    ...(process.env.PONDER_RPC_URL_11155111 ? {
      sepolia: {
        id: 11155111,
        rpc: process.env.PONDER_RPC_URL_11155111,
      }
    } : {}),
    ...(process.env.PONDER_RPC_URL_31337 ? {
      local: {
        id: 31337,
        rpc: process.env.PONDER_RPC_URL_31337,
      }
    } : {}),
  },
  contracts: {
    AssetRegistry: {
      abi: AssetRegistryABI,
      chain: {
        ...(process.env.PONDER_RPC_URL_11155111 ? {
          sepolia: {
            address: sepoliaRegistryAddresses,
            startBlock: 10299077
          }
        } : {}),
        ...(process.env.PONDER_RPC_URL_31337 ? {
          local: {
            address: localRegistryAddresses,
            startBlock: 0
          }
        } : {}),
      }
    },
    Asset: {
      abi: AssetABI,
      chain: {
        ...(process.env.PONDER_RPC_URL_11155111 ? {
          sepolia: {
            address: factory({
              address: sepoliaRegistryAddresses,
              event: AssetCreatedEvent,
              parameter: "asset",
            }),
            startBlock: 10299077
          }
        } : {}),
        ...(process.env.PONDER_RPC_URL_31337 ? {
          local: {
            address: factory({
              address: localRegistryAddresses,
              event: AssetCreatedEvent,
              parameter: "asset",
            }),
            startBlock: 0
          }
        } : {}),
      }
    }
  },
});