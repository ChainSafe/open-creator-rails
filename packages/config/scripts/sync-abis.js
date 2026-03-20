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

// Update index.ts: only replace the auto-generated ABI section, preserve the rest
const indexPath = path.join(destDir, 'index.ts');
const START_MARKER = '// --- AUTO-GENERATED ABI EXPORTS (do not edit) ---';
const END_MARKER = '// --- END AUTO-GENERATED ABI EXPORTS ---';
const generatedBlock = `${START_MARKER}\n${indexExports}${END_MARKER}`;

if (fs.existsSync(indexPath)) {
  const existing = fs.readFileSync(indexPath, 'utf8');
  const startIdx = existing.indexOf(START_MARKER);
  const endIdx = existing.indexOf(END_MARKER);

  if (startIdx !== -1 && endIdx !== -1) {
    // Replace only the auto-generated section
    const before = existing.substring(0, startIdx);
    const after = existing.substring(endIdx + END_MARKER.length);
    fs.writeFileSync(indexPath, before + generatedBlock + after);
  } else {
    // Markers not found — prepend the generated block
    fs.writeFileSync(indexPath, generatedBlock + '\n' + existing);
  }
} else {
  fs.writeFileSync(indexPath, generatedBlock + '\n');
}
