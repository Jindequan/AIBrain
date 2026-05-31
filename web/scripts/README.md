# 图标生成脚本使用说明

## 功能

这个脚本会从 `public/logo.png` 生成 Electron 应用所需的所有尺寸的圆角图标。

## 使用方法

### 1. 安装依赖

```bash
npm install
```

### 2. 运行脚本

```bash
npm run icons
```

## 输出结构

生成的图标会保存在 `build/icons/` 目录下：

```
build/icons/
├── windows/
│   └── icon.ico          # Windows 应用图标
├── macos/
│   ├── icon_16x16.png
│   ├── icon_32x32.png
│   ├── icon_64x64.png
│   ├── icon_128x128.png
│   ├── icon_256x256.png
│   ├── icon_512x512.png
│   └── icon_1024x1024.png
├── linux/
│   ├── 16x16.png
│   ├── 24x24.png
│   ├── 32x32.png
│   ├── 48x48.png
│   ├── 64x64.png
│   ├── 128x128.png
│   ├── 256x256.png
│   └── 512x512.png
└── common/
    ├── 32x32.png
    ├── 64x64.png
    ├── 128x128.png
    ├── 256x256.png
    ├── 512x512.png
    └── 1024x1024.png

public/icons/
├── icon-32x32.png
├── icon-64x64.png
├── icon-128x128.png
├── icon-256x256.png
└── icon-512x512.png
```

## 平台特定格式

### Windows .ico 生成

脚本会生成 Windows 所需的各个尺寸的 PNG 文件，但需要额外一步来生成 .ico 文件：

**在线工具：**
- https://convertio.co/png-ico/
- https://www.icoconverter.com/

**命令行工具：**
```bash
# 安装 png2ico
brew install png2ico  # macOS

# 生成 .ico 文件
png2ico build/icons/windows/icon.ico \
  build/icons/windows/16x16.png \
  build/icons/windows/32x32.png \
  build/icons/windows/48x48.png \
  build/icons/windows/256x256.png
```

### macOS .icns 生成

脚本会生成 macOS 所需的各个尺寸的 PNG 文件，但需要额外一步来生成 .icns 文件：

### 在 macOS 上：

```bash
cd build/icons/macos
iconutil -c icns .
```

这会生成 `icon.icns` 文件。

### 在 Linux/Windows 上：

可以使用在线工具或安装 `libicns` 工具。

## 在 Electron 中使用

### electron-builder 配置

在 `package.json` 或 `electron-builder.yml` 中添加：

```json
{
  "build": {
    "icon": "build/icons/icon.ico",
    "mac": {
      "icon": "build/icons/macos/icon.icns"
    },
    "linux": {
      "icon": "build/icons/linux"
    }
  }
}
```

### Electron 主进程

在主进程中设置窗口图标：

```javascript
// main.cjs
const path = require('path');
const { BrowserWindow } = require('electron');

function createWindow() {
  const win = new BrowserWindow({
    icon: path.join(__dirname, 'build/icons/common/256x256.png'),
    // ... 其他配置
  });
}
```

## 自定义配置

可以修改 `scripts/generate-icons.js` 中的配置：

```javascript
const CONFIG = {
  sourceLogo: path.join(rootDir, 'public', 'logo.png'),
  outputDir: path.join(rootDir, 'build', 'icons'),
  borderRadius: 64,  // 调整圆角大小
  sizes: {
    // ... 自定义尺寸
  }
};
```

## 技术细节

- 使用 `sharp` 库进行图像处理
- 圆角半径动态计算：`size * 0.15`（最小 8px）
- 支持多种平台和尺寸
- 自动创建输出目录

## 故障排除

### 如果遇到 sharp 安装问题

```bash
# 删除 node_modules 和 package-lock.json
rm -rf node_modules package-lock.json

# 重新安装
npm install
```

### 如果生成的图标质量不佳

确保 `public/logo.png` 是高分辨率的（建议至少 1024x1024）。

## 注意事项

- 原始 logo.png 应该是正方形的
- 建议使用 PNG 格式
- 建议分辨率至少 1024x1024
- 生成的图标文件已添加到 .gitignore
