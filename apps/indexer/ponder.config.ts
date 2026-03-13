import { getAbiItem  } from "viem";
import { createConfig, factory } from "ponder";

import { 
  AssetABI, 
  AssetRegistryABI,
  sepoliaDeployments
} from "@open-creator-rails/config";

// 2. Extract the event strictly
const AssetCreatedEvent = getAbiItem({ 
  abi: AssetRegistryABI, 
  name: "AssetCreated" 
});

const sepoliaRegistryAddresses = sepoliaDeployments.map((d: any) => d.address as `0x${string}`);

export default createConfig({
  chains: {
    sepolia: {
      id: 11155111,
      rpc: process.env.PONDER_RPC_URL_11155111,
    },
  },
  contracts: {
    AssetRegistry: {
      chain: "sepolia",
      abi: AssetRegistryABI,
      address: sepoliaRegistryAddresses,
      startBlock: 10299077
    },
    Asset: {
      chain: "sepolia",
      abi: AssetABI,
      address: factory({
        address: sepoliaRegistryAddresses,
        event: AssetCreatedEvent,
        parameter: "asset",
      }),
      startBlock: 10299077
    }
  },
});
