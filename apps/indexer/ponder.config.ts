import { getAbiItem  } from "viem";
import { createConfig, factory } from "ponder";

import { AssetRegistryAbi } from "./abis/AssetRegistryABI";
import { AssetAbi } from "./abis/AssetABI";

// 2. Extract the event strictly
const AssetCreatedEvent = getAbiItem({ 
  abi: AssetRegistryAbi, 
  name: "AssetCreated" 
});

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
      abi: AssetRegistryAbi,
      address: "0x513972072Ae1985506e2FC3b3d9A46fe0F0eCDB5",
      startBlock: 10299077
    },
    Asset: {
      chain: "sepolia",
      abi: AssetAbi,
      address: factory({
        address: "0x513972072Ae1985506e2FC3b3d9A46fe0F0eCDB5",
        event: AssetCreatedEvent,
        parameter: "asset",
      }),
      startBlock: 10299077
    }
  },
});
