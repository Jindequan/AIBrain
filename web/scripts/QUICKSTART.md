# 快速开始

## 方式一：使用 Node.js 脚本（推荐）

### 1. 安装依赖

```bash
npm install
```

### 2. 生成图标

```bash
npm run icons
```

**优点：**
- 跨平台兼容
- 无需额外安装工具
- 更灵活的配置

**缺点：**
- 需要安装 sharp 依赖

---

## 方式二：使用 Bash 脚本

### 1. 安装 ImageMagick

**macOS:**
```bash
brew install imagemagick
```

**Ubuntu/Debian:**
```bash
sudo apt-get install imagemagick
```

**Windows:**
```bash
choco install imagemagick
```

### 2. 生成图标

```bash
npm run icons:bash
```

**优点：**
- 快速直接
- 无需 Node.js 依赖

**缺点：**
- 需要安装 ImageMagick

---

## 使用建议

- **开发环境：** 使用 Node.js 脚本（`npm run icons`）
- **CI/CD：** 使用 Bash 脚本（`npm run icons:bash`）
- **生产构建：** 任选其一，确保在打包前运行

## 输出文件

两种方式生成的图标完全相同，位于：

- `build/icons/` - 应用图标
- `public/icons/` - 应用内图标
- `public/favicon.png` - 网站图标

## 故障排除

### Node.js 脚本问题

如果 sharp 安装失败：

```bash
npm install --verbose
```

### Bash 脚本问题

检查 ImageMagick 是否安装：

```bash
convert --version
```

## 下一步

生成图标后，参考 `scripts/README.md` 了解如何在 Electron 中使用这些图标。
