#!/bin/bash

# Electron Icon Generator (Bash + ImageMagick)
# 生成 Electron 应用所需的各种尺寸图标

set -e

# 配置
SOURCE_LOGO="public/logo.png"
OUTPUT_DIR="build/icons"
BORDER_RADIUS=64

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查 ImageMagick 是否安装
if ! command -v convert &> /dev/null; then
    echo -e "${RED}错误: ImageMagick 未安装${NC}"
    echo "请安装 ImageMagick:"
    echo "  macOS:   brew install imagemagick"
    echo "  Ubuntu:  sudo apt-get install imagemagick"
    echo "  Windows: choco install imagemagick"
    exit 1
fi

# 检查源文件是否存在
if [ ! -f "$SOURCE_LOGO" ]; then
    echo -e "${RED}错误: 找不到源图标 $SOURCE_LOGO${NC}"
    exit 1
fi

echo "🎨 Electron Icon Generator (ImageMagick)"
echo "========================================"
echo "源文件: $SOURCE_LOGO"
echo "输出目录: $OUTPUT_DIR"
echo ""

# 创建输出目录
mkdir -p "$OUTPUT_DIR/windows"
mkdir -p "$OUTPUT_DIR/macos"
mkdir -p "$OUTPUT_DIR/linux"
mkdir -p "$OUTPUT_DIR/common"
mkdir -p "public/icons"

# 函数：生成圆角图标
generate_rounded_icon() {
    local size=$1
    local output=$2
    local radius=$((size * 15 / 100)) # 15% 圆角
    [ $radius -lt 8 ] && radius=8 # 最小 8px

    convert "$SOURCE_LOGO" \
        -resize ${size}x${size} \
        \( +clone -alpha extract \
            -draw "fill black polygon 0,0 0,$radius $radius,0 fill white circle $radius,$radius $radius,0" \
            \( +clone -flip \) -compose Multiply -composite \
            \( +clone -flop \) -compose Multiply -composite \
        \) \
        -alpha off -compose CopyOpacity -composite "$output"

    echo -e "${GREEN}✓${NC} 生成: $(basename $output) (${size}x${size})"
}

# Windows 图标
echo "生成 Windows 图标..."
convert "$SOURCE_LOGO" -resize 256x256 -define icon:auto-resize=16,32,48,256 "$OUTPUT_DIR/windows/icon.ico"
echo -e "${GREEN}✓${NC} 生成: icon.ico"

# macOS 图标
echo ""
echo "生成 macOS 图标..."
MACOS_SIZES=(16 32 64 128 256 512 1024)
for size in "${MACOS_SIZES[@]}"; do
    generate_rounded_icon $size "$OUTPUT_DIR/macos/icon_${size}x${size}.png"
done
echo -e "${YELLOW}提示: 使用 iconutil 将 PNG 转换为 .icns${NC}"

# Linux 图标
echo ""
echo "生成 Linux 图标..."
LINUX_SIZES=(16 24 32 48 64 128 256 512)
for size in "${LINUX_SIZES[@]}"; do
    generate_rounded_icon $size "$OUTPUT_DIR/linux/${size}x${size}.png"
done

# 通用图标
echo ""
echo "生成通用图标..."
COMMON_SIZES=(32 64 128 256 512 1024)
for size in "${COMMON_SIZES[@]}"; do
    generate_rounded_icon $size "$OUTPUT_DIR/common/${size}x${size}.png"
done

# 应用内图标
echo ""
echo "生成应用内图标..."
APP_SIZES=(32 64 128 256 512)
for size in "${APP_SIZES[@]}"; do
    generate_rounded_icon $size "public/icons/icon-${size}x${size}.png"
done

# Favicon
echo ""
generate_rounded_icon 32 "public/favicon.png"

echo ""
echo -e "${GREEN}✅ 所有图标生成完成！${NC}"
echo ""
echo "📝 下一步:"
echo "  1. 对于 macOS: 使用 iconutil 生成 .icns"
echo "     $ cd build/icons/macos && iconutil -c icns ."
echo "  2. 在 package.json 中配置:"
echo '     "build": { "icon": "build/icons/icon.ico" }'
echo "  3. 对于 electron-builder: 添加到配置文件"
