#!/bin/bash

# iOS 开发环境检查脚本

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_check() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
        return 0
    else
        echo -e "${RED}✗${NC} $2"
        return 1
    fi
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

echo "=========================================="
echo "iOS 开发环境检查报告"
echo "=========================================="
echo ""

# 检查 Xcode
echo "1. Xcode 安装检查"
if command -v xcodebuild &> /dev/null; then
    XCODE_VERSION=$(xcodebuild -version | head -n 1)
    print_check 0 "Xcode: $XCODE_VERSION"
else
    print_check 1 "Xcode 未安装"
fi
echo ""

# 检查 CocoaPods
echo "2. CocoaPods 安装检查"
if command -v pod &> /dev/null; then
    POD_VERSION=$(pod --version 2>/dev/null || echo "未知")
    print_check 0 "CocoaPods: $POD_VERSION"
else
    print_check 1 "CocoaPods 未安装"
fi
echo ""

# 检查环境变量
echo "3. 环境变量检查"
if [ -n "$LANG" ] && [ "$LANG" = "en_US.UTF-8" ]; then
    print_check 0 "LANG: $LANG"
else
    print_check 1 "LANG 未设置为 UTF-8 (当前: ${LANG:-未设置})"
    print_info "请运行: export LANG=en_US.UTF-8"
fi
echo ""

# 检查 Flutter
echo "4. Flutter 安装检查"
if command -v flutter &> /dev/null; then
    FLUTTER_VERSION=$(flutter --version | head -n 1)
    print_check 0 "Flutter: $FLUTTER_VERSION"
else
    print_check 1 "Flutter 未安装"
fi
echo ""

# 检查项目依赖
echo "5. 项目依赖检查"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

if [ -f "pubspec.lock" ]; then
    print_check 0 "Flutter 依赖已安装"
else
    print_check 1 "Flutter 依赖未安装 (需要运行: flutter pub get)"
fi

if [ -d "ios/Pods" ]; then
    print_check 0 "CocoaPods 依赖已安装"
else
    print_check 1 "CocoaPods 依赖未安装 (需要运行: cd ios && pod install)"
fi
echo ""

# 检查 Xcode 项目
echo "6. Xcode 项目检查"
if [ -f "ios/Runner.xcworkspace/contents.xcworkspacedata" ]; then
    print_check 0 "Xcode 工作空间存在"
else
    print_check 1 "Xcode 工作空间不存在"
fi

if [ -f "ios/Runner/Info.plist" ]; then
    if grep -q "NSAppTransportSecurity" ios/Runner/Info.plist; then
        print_check 0 "Info.plist 权限配置正确"
    else
        print_check 1 "Info.plist 缺少网络权限配置"
    fi
else
    print_check 1 "Info.plist 不存在"
fi
echo ""

# 检查 iOS 模拟器
echo "7. iOS 模拟器检查"
SIMULATORS=$(xcrun simctl list devices available 2>/dev/null | grep -c "iPhone\|iPad" || echo "0")
if [ "$SIMULATORS" -gt 0 ]; then
    print_check 0 "找到 $SIMULATORS 个可用模拟器"
    print_info "可用模拟器列表:"
    xcrun simctl list devices available 2>/dev/null | grep -E "iPhone|iPad" | head -5 | sed 's/^/  /'
else
    print_check 1 "未找到可用模拟器"
    print_info "请在 Xcode > Preferences > Components 中下载 iOS 模拟器"
fi
echo ""

# 检查 Flutter iOS 工具链
echo "8. Flutter iOS 工具链检查"
IOS_STATUS=$(flutter doctor 2>&1 | grep -A 2 "Xcode" | grep -c "✓" || echo "0")
if [ "$IOS_STATUS" -gt 0 ]; then
    print_check 0 "Flutter iOS 工具链正常"
else
    print_check 1 "Flutter iOS 工具链有问题"
    print_info "运行 'flutter doctor -v' 查看详细信息"
fi
echo ""

# 总结
echo "=========================================="
echo "检查完成"
echo "=========================================="
echo ""
echo "如果所有项目都显示 ✓，说明环境已准备完成！"
echo ""
echo "下一步："
echo "1. 打开 Xcode 项目: open ios/Runner.xcworkspace"
echo "2. 配置签名: Xcode > Runner > Signing & Capabilities"
echo "3. 运行应用: flutter run -d ios"
echo ""

