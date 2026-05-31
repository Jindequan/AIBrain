#!/usr/bin/env node

/**
 * Electron Icon Generator
 * 生成 Electron 应用所需的各种尺寸图标
 */

import sharp from 'sharp';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.join(__dirname, '..');

// 配置
const CONFIG = {
  sourceLogo: path.join(rootDir, 'public', 'logo.png'),
  outputDir: path.join(rootDir, 'build', 'icons'),
  borderRadius: 64, // 圆角半径
  sizes: {
    // Windows (.ico)
    windows: [16, 32, 48, 256],
    // macOS (.icns)
    macos: [16, 32, 64, 128, 256, 512, 1024],
    // Linux (.png)
    linux: [16, 24, 32, 48, 64, 128, 256, 512],
    // Windows Store
    windowsStore: [50, 150, 310, 310],
    // 通用
    common: [32, 64, 128, 256, 512, 1024]
  }
};

// 确保输出目录存在
function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

// 添加圆角
async function addRoundedCorners(image, size, radius) {
  const roundedRadius = Math.max(8, Math.min(radius, Math.floor(size * 0.15))); // 动态圆角，最小8px

  // 创建圆角蒙版
  const svg = `
    <svg width="${size}" height="${size}">
      <rect x="0" y="0" width="${size}" height="${size}" rx="${roundedRadius}" ry="${roundedRadius}" fill="white"/>
    </svg>
  `;

  const mask = Buffer.from(svg);

  return image
    .resize(size, size, { fit: 'cover', position: 'center' })
    .composite([
      {
        input: await sharp(mask).resize(size, size).toBuffer(),
        blend: 'dest-in'
      }
    ]);
}

// 生成 PNG 图标
async function generatePNG(size, outputPath) {
  try {
    const image = sharp(CONFIG.sourceLogo);
    const roundedImage = await addRoundedCorners(image, size, CONFIG.borderRadius);
    await roundedImage.png().toFile(outputPath);
    console.log(`✓ Generated: ${path.basename(outputPath)} (${size}x${size})`);
  } catch (error) {
    console.error(`✗ Error generating ${outputPath}:`, error.message);
  }
}

// 生成 Windows PNG 图标
async function generateWindowsIcons() {
  const winDir = path.join(CONFIG.outputDir, 'windows');
  ensureDir(winDir);

  const sizes = CONFIG.sizes.windows;

  for (const size of sizes) {
    const outputPath = path.join(winDir, `${size}x${size}.png`);
    await generatePNG(size, outputPath);
  }

  console.log(`✓ Generated Windows icons (${sizes.join(', ')}px)`);
  console.log(`  Note: Use png2ico or online tool to convert to .ico`);
}

// 生成 ICNS 文件 (macOS)
async function generateICNS() {
  const icnsDir = path.join(CONFIG.outputDir, 'macos');
  ensureDir(icnsDir);

  const sizes = CONFIG.sizes.macos;

  // 生成各个尺寸的 PNG
  for (const size of sizes) {
    const outputPath = path.join(icnsDir, `icon_${size}x${size}.png`);
    await generatePNG(size, outputPath);
  }

  console.log(`✓ Generated macOS icons (${sizes.join(', ')}px)`);
  console.log(`  Note: Use iconutil or external tool to convert to .icns`);
}

// 生成 Linux 图标
async function generateLinuxIcons() {
  const linuxDir = path.join(CONFIG.outputDir, 'linux');
  ensureDir(linuxDir);

  const sizes = CONFIG.sizes.linux;

  for (const size of sizes) {
    const outputPath = path.join(linuxDir, `${size}x${size}.png`);
    await generatePNG(size, outputPath);
  }
}

// 生成通用图标集
async function generateCommonIcons() {
  const commonDir = path.join(CONFIG.outputDir, 'common');
  ensureDir(commonDir);

  const sizes = CONFIG.sizes.common;

  for (const size of sizes) {
    const outputPath = path.join(commonDir, `${size}x${size}.png`);
    await generatePNG(size, outputPath);
  }
}

// 生成应用内图标
async function generateAppIcons() {
  const appDir = path.join(rootDir, 'public', 'icons');
  ensureDir(appDir);

  const sizes = [32, 64, 128, 256, 512];

  for (const size of sizes) {
    const outputPath = path.join(appDir, `icon-${size}x${size}.png`);
    await generatePNG(size, outputPath);
  }

  // 生成 favicon
  const faviconPath = path.join(rootDir, 'public', 'favicon.png');
  await generatePNG(32, faviconPath);
}

// 主函数
async function main() {
  console.log('🎨 Electron Icon Generator');
  console.log('================================');
  console.log(`Source: ${CONFIG.sourceLogo}`);
  console.log(`Output: ${CONFIG.outputDir}`);
  console.log('');

  try {
    // 检查源文件是否存在
    if (!fs.existsSync(CONFIG.sourceLogo)) {
      throw new Error(`Source logo not found: ${CONFIG.sourceLogo}`);
    }

    // 确保输出目录存在
    ensureDir(CONFIG.outputDir);

    // 生成各类图标
    console.log('Generating Windows icons...');
    await generateWindowsIcons();

    console.log('\nGenerating macOS icons...');
    await generateICNS();

    console.log('\nGenerating Linux icons...');
    await generateLinuxIcons();

    console.log('\nGenerating common icons...');
    await generateCommonIcons();

    console.log('\nGenerating app icons...');
    await generateAppIcons();

    console.log('\n✅ All icons generated successfully!');
    console.log('\n📝 Next steps:');
    console.log('  1. For macOS: Use iconutil to convert .png to .icns');
    console.log('     $ iconutil -c icns build/icons/macos');
    console.log('  2. Update package.json: "build": { "icon": "build/icons/icon.ico" }');
    console.log('  3. For electron-builder: Add to config');

  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
}

// 运行
main();
