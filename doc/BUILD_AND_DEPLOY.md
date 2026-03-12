# toxee 构建与部署
> 语言 / Language: [中文](BUILD_AND_DEPLOY.md) | [English](BUILD_AND_DEPLOY.en.md)


本文档提供 toxee 的详细构建步骤、各平台构建说明、依赖安装指南和常见错误解决方案。

## 目录

- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [详细构建步骤](#详细构建步骤)
- [各平台构建说明](#各平台构建说明)
- [依赖安装](#依赖安装)
- [常见错误解决](#常见错误解决)

## 环境要求

### 必需工具

- **Flutter SDK**: >= 3.22
- **Dart SDK**: >= 3.5
- **CMake**: >= 3.4.1
- **Git**: 用于克隆依赖

### 平台特定要求

#### macOS

- **Xcode**: 最新版本（用于构建 macOS/iOS）
- **Command Line Tools**: `xcode-select --install`
- **Homebrew**: 用于安装依赖库

#### Linux

- **GCC**: >= 10 或 **Clang**: >= 12
- **GTK3 开发库**: `libgtk-3-dev`
- **pkg-config**: 用于依赖管理

#### Windows

- **Visual Studio 2019** 或更高版本
- **CMake**: 通过 Visual Studio 安装或独立安装
- **vcpkg**: 用于依赖管理（可选）

#### Android

- **Android SDK**: 通过 Android Studio 安装
- **Android NDK**: 用于原生代码编译
- **Java JDK**: >= 11

#### iOS

- **Xcode**: 最新版本（仅限 macOS）
- **CocoaPods**: `sudo gem install cocoapods`

## 快速开始

### macOS 一键构建和运行

```bash
cd toxee
bash run_toxee.sh
```

这个脚本会自动：
1. 构建 Tim2Tox（包括 FFI 库，使用 DEBUG 模式）
2. 构建 IRC 客户端库（如果需要，使用 DEBUG 模式）
3. 构建 Flutter macOS 应用（DEBUG 模式）
4. 将动态库（`libtim2tox_ffi.dylib` 和 `libirc_client.dylib`）打包到应用 bundle
5. 复制并修复 libsodium 依赖路径（使用 `@loader_path`）
6. 启动应用并实时显示日志

**构建模式**: 使用 DEBUG 模式构建，包含完整的调试符号，便于调试崩溃问题。

**日志文件**:
- `build/native_build.log` - C++ 构建日志
- `build/flutter_build.log` - Flutter 构建日志
- `build/flutter_client.log` - 应用运行时日志（符号链接到沙盒目录的实际日志文件）

**实际日志位置**: 
- `~/Library/Containers/com.example.toxee/Data/Library/Application Support/com.example.toxee/flutter_client.log`

### 跨平台构建

```bash
# 构建所有支持的平台
./build_all.sh

# 构建特定平台
./build_all.sh --platform macos
./build_all.sh --platform linux
./build_all.sh --platform windows
./build_all.sh --platform android
./build_all.sh --platform ios
```

## 详细构建步骤

### 步骤 1: 安装依赖

#### macOS

```bash
# 安装 Homebrew（如果未安装）
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 安装 libsodium
brew install libsodium

# 安装 Flutter（如果未安装）
brew install --cask flutter
```

#### Linux

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    cmake \
    libsodium-dev \
    libgtk-3-dev \
    pkg-config

# Fedora/RHEL
sudo dnf install -y \
    gcc-c++ \
    cmake \
    libsodium-devel \
    gtk3-devel \
    pkg-config
```

#### Windows

```bash
# 使用 vcpkg 安装依赖
vcpkg install libsodium:x64-windows
```

### 步骤 2: 构建 Tim2Tox

```bash
cd ../tim2tox

# 使用构建脚本
./build.sh

# 或手动构建
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_FFI=ON
make -j$(nproc)  # Linux
make -j$(sysctl -n hw.ncpu)  # macOS
```

构建产物：
- `build/ffi/libtim2tox_ffi.dylib` (macOS)
- `build/ffi/libtim2tox_ffi.so` (Linux)
- `build/ffi/tim2tox_ffi.dll` (Windows)

### 步骤 3: 构建 Flutter 应用

```bash
cd ../toxee

# 获取依赖
flutter pub get

# 构建 macOS
flutter build macos --debug

# 构建 Linux
flutter build linux --debug

# 构建 Windows
flutter build windows --debug

# 构建 Android
flutter build apk --debug

# 构建 iOS
flutter build ios --debug
```

### 步骤 4: 复制动态库（macOS/Linux/Windows）

#### macOS

```bash
# 复制 FFI 库到应用 bundle
cp ../tim2tox/build/ffi/libtim2tox_ffi.dylib \
   build/macos/Build/Products/Debug/toxee.app/Contents/MacOS/

# 复制 IRC 库（如果需要）
cp ../tim2tox/example/build/libirc_client.dylib \
   build/macos/Build/Products/Debug/toxee.app/Contents/MacOS/

# 修复动态库路径
install_name_tool -change \
    /opt/homebrew/lib/libsodium.23.dylib \
    @loader_path/libsodium.23.dylib \
    build/macos/Build/Products/Debug/toxee.app/Contents/MacOS/libtim2tox_ffi.dylib
```

#### Linux

```bash
# 复制 FFI 库
cp ../tim2tox/build/ffi/libtim2tox_ffi.so \
   build/linux/x64/debug/bundle/lib/

# 设置库搜索路径
export LD_LIBRARY_PATH=$PWD/build/linux/x64/debug/bundle/lib:$LD_LIBRARY_PATH
```

#### Windows

```bash
# 复制 FFI 库
copy ..\tim2tox\build\ffi\tim2tox_ffi.dll \
     build\windows\x64\runner\Debug\
```

## 各平台构建说明

### macOS

#### 构建配置

- **架构**: x86_64 和 arm64（通用二进制）
- **最低版本**: macOS 10.14
- **动态库**: `.dylib` 格式

#### 特殊处理

- 使用 `install_name_tool` 修复动态库路径
- 将动态库打包到应用 bundle 的 `Contents/MacOS/` 目录
- 处理 libsodium 依赖路径

#### 运行

```bash
# 直接运行
open build/macos/Build/Products/Debug/toxee.app

# 或使用命令行
./build/macos/Build/Products/Debug/toxee.app/Contents/MacOS/toxee
```

### Linux

#### 构建配置

- **架构**: x86_64
- **动态库**: `.so` 格式
- **GTK**: 需要 GTK3 开发库

#### 特殊处理

- 设置 `LD_LIBRARY_PATH` 环境变量
- 确保所有依赖库在可访问路径

#### 运行

```bash
# 设置库路径
export LD_LIBRARY_PATH=$PWD/build/linux/x64/debug/bundle/lib:$LD_LIBRARY_PATH

# 运行
./build/linux/x64/debug/bundle/toxee
```

### Windows

#### 构建配置

- **架构**: x64
- **动态库**: `.dll` 格式
- **编译器**: MSVC 2019 或更高版本

#### 特殊处理

- 将 DLL 复制到可执行文件目录
- 确保所有依赖 DLL 在同一目录

#### 运行

```bash
# 在 PowerShell 中
.\build\windows\x64\runner\Debug\toxee.exe
```

### Android

#### 构建配置

- **最低 SDK**: API 21 (Android 5.0)
- **目标 SDK**: 最新版本
- **架构**: arm64-v8a, armeabi-v7a, x86_64

#### 特殊处理

- 使用 Android NDK 编译原生代码
- 将 `.so` 库打包到 APK 的 `lib/` 目录
- 配置 `AndroidManifest.xml` 权限

#### 构建

```bash
flutter build apk --debug
# 或
flutter build apk --release
```

### iOS

#### 构建配置

- **最低版本**: iOS 12.0
- **架构**: arm64（真机）或 x86_64（模拟器）
- **动态库**: Framework 格式

#### 特殊处理

- 使用 CocoaPods 管理依赖
- 配置 `Info.plist` 权限
- 处理代码签名

#### 构建

```bash
# 安装 CocoaPods 依赖
cd ios
pod install
cd ..

# 构建
flutter build ios --debug
```

## 依赖安装

### libsodium

#### macOS

```bash
brew install libsodium
```

#### Linux

```bash
# Ubuntu/Debian
sudo apt-get install libsodium-dev

# Fedora/RHEL
sudo dnf install libsodium-devel
```

#### Windows

```bash
# 使用 vcpkg
vcpkg install libsodium:x64-windows
```

### Flutter SDK

#### 安装

```bash
# macOS/Linux
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:`pwd`/flutter/bin"

# 或使用包管理器
# macOS
brew install --cask flutter

# Linux (Snap)
sudo snap install flutter --classic
```

#### 验证

```bash
flutter doctor
```

### CMake

#### macOS

```bash
brew install cmake
```

#### Linux

```bash
# Ubuntu/Debian
sudo apt-get install cmake

# Fedora/RHEL
sudo dnf install cmake
```

#### Windows

从 [CMake 官网](https://cmake.org/download/) 下载安装程序。

## 常见错误解决

### 构建错误

#### 错误: 找不到 libsodium

**症状**:
```
fatal error: 'sodium.h' file not found
```

**解决**:
```bash
# macOS
brew install libsodium

# Linux
sudo apt-get install libsodium-dev

# 检查安装位置
# macOS: /opt/homebrew/lib 或 /usr/local/lib
# Linux: /usr/lib 或 /usr/local/lib
```

#### 错误: CMake 配置失败

**症状**:
```
CMake Error: Could not find a package configuration file
```

**解决**:
- 检查 CMake 版本: `cmake --version` (需要 >= 3.4.1)
- 检查依赖库是否已安装
- 清理构建目录: `rm -rf build` 然后重新构建

#### 错误: 链接错误

**症状**:
```
undefined reference to `tox_*'
```

**解决**:
- 检查 `CMakeLists.txt` 中的链接配置
- 确保所有依赖库都已正确链接
- 检查库的搜索路径

### Flutter 构建错误

#### 错误: 依赖解析失败

**症状**:
```
Error: Could not resolve the package 'tim2tox_dart'
```

**解决**:
```bash
# 清理并重新获取依赖
flutter clean
flutter pub get
```

#### 错误: 平台配置错误

**症状**:
```
Error: No valid Android SDK found
```

**解决**:
```bash
# 运行 Flutter doctor
flutter doctor

# 安装缺失的组件
flutter doctor --android-licenses
```

#### 错误: 代码生成错误

**症状**:
```
Error: The getter 'xxx' isn't defined
```

**解决**:
```bash
# 重新生成代码
flutter pub run build_runner build --delete-conflicting-outputs
```

### 运行时错误

#### 错误: 动态库加载失败

**症状**:
```
dlopen failed: library not found
```

**解决**:

**macOS**:
```bash
# 检查动态库路径
otool -L libtim2tox_ffi.dylib

# 修复路径
install_name_tool -change \
    /old/path/libsodium.dylib \
    @loader_path/libsodium.dylib \
    libtim2tox_ffi.dylib
```

**Linux**:
```bash
# 检查依赖
ldd libtim2tox_ffi.so

# 设置库路径
export LD_LIBRARY_PATH=/path/to/libs:$LD_LIBRARY_PATH
```

**Windows**:
- 确保所有 DLL 在可执行文件目录
- 检查 PATH 环境变量

#### 错误: 符号未找到

**症状**:
```
Symbol not found: DartInitDartApiDL
```

**解决**:
- 检查函数是否使用 `extern "C"` 声明
- 检查 CMakeLists.txt 中的导出配置
- 使用 `nm` 或 `objdump` 检查符号导出

#### 错误: 回调不触发

**症状**: 注册的回调没有被调用

**解决**:
- 确保 `DartInitDartApiDL` 和 `DartRegisterSendPort` 已调用
- 检查 `IsDartPortRegistered()` 返回值
- 查看日志输出确认回调是否被调用

### 网络问题

#### 错误: Tox 无法连接

**症状**: 应用启动后无法连接到 Tox 网络

**解决**:
- 检查网络连接
- 检查防火墙设置
- 验证 Bootstrap 节点配置
- 查看日志: `build/flutter_client.log`

#### 错误: Bootstrap 节点连接失败

**症状**: 日志显示 "bootstrap nodes queued" 但无法连接

**解决**:
- 检查 Bootstrap 节点列表是否有效
- 验证网络权限配置
- 检查 libsodium 是否正确打包

### 性能问题

#### 问题: 应用启动慢

**解决**:
- 检查动态库加载时间
- 优化初始化流程
- 使用延迟加载

#### 问题: 消息发送慢

**解决**:
- 检查网络连接状态
- 优化消息序列化
- 使用批量发送

## 调试技巧

### 启用详细日志

在 `run_toxee.sh` 中，日志文件位于：
- `build/native_build.log` - C++ 构建日志
- `build/flutter_build.log` - Flutter 构建日志
- `build/flutter_client.log` - 应用运行时日志

### 检查动态库依赖

**macOS**:
```bash
otool -L libtim2tox_ffi.dylib
```

**Linux**:
```bash
ldd libtim2tox_ffi.so
```

**Windows**:
```bash
dumpbin /DEPENDENTS tim2tox_ffi.dll
```

### 验证函数符号

**macOS/Linux**:
```bash
nm -D libtim2tox_ffi.dylib | grep Dart
```

**Windows**:
```bash
dumpbin /EXPORTS tim2tox_ffi.dll
```

### 查看应用日志

```bash
# macOS
tail -f build/flutter_client.log

# Linux
tail -f build/flutter_client.log

# 或直接在终端运行应用查看输出
```

## 相关文档

- [集成指南](INTEGRATION_GUIDE.md) - 如何集成 Tim2Tox
- [故障排除](TROUBLESHOOTING.md) - 更多故障排除技巧
- [主 README](../README.md) - 项目概述

