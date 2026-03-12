const fs = require('fs');
const path = require('path');

const contractsOutDir = path.resolve(__dirname, '../../../apps/contracts/out');
const destDir = path.resolve(__dirname, '../src');

// Ensure the destination directory exists
if (!fs.existsSync(destDir)) {
  fs.mkdirSync(destDir, { recursive: true });
}

// Define which contracts to extract
const targets = [
  { file: 'Asset.sol/Asset.json', name: 'AssetABI' },
  { file: 'AssetRegistry.sol/AssetRegistry.json', name: 'AssetRegistryABI' }
];

let indexExports = "";

targets.forEach(target => {
  const sourcePath = path.join(contractsOutDir, target.file);
  
  if (fs.existsSync(sourcePath)) {
    const json = JSON.parse(fs.readFileSync(sourcePath, 'utf8'));
    const tsContent = `export const ${target.name} = ${JSON.stringify(json.abi, null, 2)} as const;\n`;
    
    fs.writeFileSync(path.join(destDir, `${target.name}.ts`), tsContent);
    indexExports += `export * from './${target.name}';\n`;
    
    console.log(`✅ Synced: ${target.name}`);
  } else {
    console.warn(`⚠️ Not found: ${sourcePath}. Did you run 'forge build'?`);
  }
});

fs.writeFileSync(path.join(destDir, 'index.ts'), indexExports);
