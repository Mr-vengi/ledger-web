/**
 * Script to copy Tamil fonts from assets to functions directory
 * Run this before deploying: node copy-fonts.js
 */

const fs = require('fs');
const path = require('path');

const sourceDir = path.join(__dirname, '..', 'assets', 'icon', 'fonts');
const targetDir = path.join(__dirname, 'fonts');

const fonts = [
  'NotoSansTamil-Regular.ttf',
  'NotoSansTamil-Bold.ttf',
];

// Create fonts directory if it doesn't exist
if (!fs.existsSync(targetDir)) {
  fs.mkdirSync(targetDir, { recursive: true });
  console.log('✅ Created fonts directory:', targetDir);
}

// Copy fonts
let copied = 0;
fonts.forEach(font => {
  const sourcePath = path.join(sourceDir, font);
  const targetPath = path.join(targetDir, font);
  
  if (fs.existsSync(sourcePath)) {
    fs.copyFileSync(sourcePath, targetPath);
    console.log(`✅ Copied ${font}`);
    copied++;
  } else {
    console.warn(`⚠️  Font not found: ${sourcePath}`);
  }
});

if (copied === fonts.length) {
  console.log(`\n✅ Successfully copied ${copied} font file(s) to functions/fonts/`);
  console.log('   Ready for deployment!');
} else {
  console.warn(`\n⚠️  Only copied ${copied} of ${fonts.length} font files`);
  console.warn('   Some fonts may be missing');
}

