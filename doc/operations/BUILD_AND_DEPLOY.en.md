# toxee Build and Deploy
> Language: [Chinese](BUILD_AND_DEPLOY.md) | [English](BUILD_AND_DEPLOY.en.md)

This document provides detailed building steps for toxee, building instructions for each platform, dependency installation guide, and common error solutions. **For build/run failures, startup crashes, or dependency resolution errors**, see [TROUBLESHOOTING.md](../TROUBLESHOOTING.en.md) (FAQ and debugging tips) first.

## Contents

- [Environmental requirements](#environmental-requirements)
- [Quick Start](#quick-start)
- [Detailed build steps](#detailed-build-steps)
- [Building instructions for each platform](#build-instructions-for-each-platform)
- [Dependent installation](#dependency-installation)
- [Common error resolution](#common-error-resolution)

## Environmental requirements

### Required tools

- **Flutter SDK**: >= 3.22
- **Dart SDK**: >= 3.5
- **CMake**: >= 3.4.1
- **Git**: used to clone dependencies

### Platform specific requirements

#### macOS

- **Xcode**: latest version (for building macOS/iOS)
- **Command Line Tools**: `xcode-select --install`
- **Homebrew**: used to install dependent libraries

#### Linux

- **GCC**: >= 10 or **Clang**: >= 12
- **GTK3 development library**: `libgtk-3-dev`
- **pkg-config**: used for dependency management

#### Windows

- **Visual Studio 2019** or higher
- **CMake**: Install via Visual Studio or standalone
- **vcpkg**: used for dependency management (optional)

#### Android

- **Android SDK**: Install via Android Studio
- **Android NDK**: for native code compilation
- **Java JDK**: >= 11

#### iOS

- **Xcode**: latest version (macOS only)
- **CocoaPods**: `sudo gem install cocoapods`

## Quick Start

### macOS One-click build and run

```bash
cd toxee
bash run_toxee.sh
```
This script automatically:
1. Build Tim2Tox (including FFI library, use DEBUG mode)
2. Build the IRC client library (use DEBUG mode if necessary)
3. Build Flutter macOS application (DEBUG mode)
4. Package the dynamic libraries (`libtim2tox_ffi.dylib` and `libirc_client.dylib`) into the application bundle
5. Copy and fix the libsodium dependency path (using `@loader_path`)
6. Start the application and display the log in real time

**Build Mode**: Build using DEBUG mode, including complete debugging symbols to facilitate debugging crash issues.

**Log file**:
- `build/native_build.log` - C++ build log
- `build/flutter_build.log` - Flutter build log
- `build/flutter_client.log` - application runtime log (symlink to actual log file in sandbox directory)

**Actual log location**:
- `~/Library/Containers/com.example.toxee/Data/Library/Application Support/com.example.toxee/flutter_client.log`

### Cross-platform build
```bash
# Build for all supported platforms
./build_all.sh

# Build a specific platform
./build_all.sh --platform macos
./build_all.sh --platform linux
./build_all.sh --platform windows
./build_all.sh --platform android
./build_all.sh --platform ios
```
## Detailed build steps

### Step 1: Install dependencies

#### macOS
```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install libsodium
brew install libsodium

# Install Flutter (if not installed)
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
# Use vcpkg to install dependencies
vcpkg install libsodium:x64-windows
```
### Step 2: Build Tim2Tox
```bash
cd ../tim2tox

# Use build script
./build.sh

# or build manually
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_FFI=ON
make -j$(nproc)  # Linux
make -j$(sysctl -n hw.ncpu)  # macOS
```
Build product:
- `build/ffi/libtim2tox_ffi.dylib` (macOS)
- `build/ffi/libtim2tox_ffi.so` (Linux)
- `build/ffi/tim2tox_ffi.dll` (Windows)

### Step 3: Build the Flutter app
```bash
cd ../toxee

# Get dependencies
flutter pub get

# Build macOS
flutter build macos --debug

# Building Linux
flutter build linux --debug

# Building Windows
flutter build windows --debug

# Build Android
flutter build apk --debug

# Build for iOS
flutter build ios --debug
```
### Step 4: Copy the dynamic library (macOS/Linux/Windows)

#### macOS
```bash
# Copy the FFI library to the application bundle
cp ../tim2tox/build/ffi/libtim2tox_ffi.dylib \
   build/macos/Build/Products/Debug/toxee.app/Contents/MacOS/

# Copy the IRC repository (if needed)
cp ../tim2tox/example/build/libirc_client.dylib \
   build/macos/Build/Products/Debug/toxee.app/Contents/MacOS/

# Fix dynamic library path
install_name_tool -change \
    /opt/homebrew/lib/libsodium.23.dylib \
    @loader_path/libsodium.23.dylib \
    build/macos/Build/Products/Debug/toxee.app/Contents/MacOS/libtim2tox_ffi.dylib
```

#### Linux

```bash
# Copy FFI library
cp ../tim2tox/build/ffi/libtim2tox_ffi.so \
   build/linux/x64/debug/bundle/lib/

# Set library search path
export LD_LIBRARY_PATH=$PWD/build/linux/x64/debug/bundle/lib:$LD_LIBRARY_PATH
```

#### Windows

```bash
# Copy FFI library
copy ..\tim2tox\build\ffi\tim2tox_ffi.dll \
     build\windows\x64\runner\Debug\
```
## Build instructions for each platform

### macOS

#### Build configuration

- **Architecture**: x86_64 and arm64 (universal binary)
- **Minimum version**: macOS 10.14
- **Dynamic library**: `.dylib` format

#### Special handling

- Use `install_name_tool` to fix dynamic library path
- Package the dynamic library into the `Contents/MacOS/` directory of the application bundle
- Handle libsodium dependency path

#### Run
```bash
# Run directly
open build/macos/Build/Products/Debug/toxee.app

# or use command line
./build/macos/Build/Products/Debug/toxee.app/Contents/MacOS/toxee
```
### Linux

#### Build configuration

- **Architecture**: x86_64
- **Dynamic Library**: `.so` format
- **GTK**: requires GTK3 development library

#### Special handling

- Set the `LD_LIBRARY_PATH` environment variable
- Make sure all dependent libraries are in accessible paths

#### Run
```bash
# Set library path
export LD_LIBRARY_PATH=$PWD/build/linux/x64/debug/bundle/lib:$LD_LIBRARY_PATH

# run
./build/linux/x64/debug/bundle/toxee
```
### Windows

#### Build configuration

- **Architecture**: x64
- **Dynamic library**: `.dll` format
- **Compiler**: MSVC 2019 or higher

#### Special handling

- Copy the DLL to the executable directory
- Make sure all dependent DLLs are in the same directory

#### Run
```bash
# In PowerShell
.\build\windows\x64\runner\Debug\toxee.exe
```
### Android

#### Build configuration

- **Minimum SDK**: API 21 (Android 5.0)
- **Target SDK**: latest version
- **Architecture**: arm64-v8a, armeabi-v7a, x86_64

#### Special handling

- Compile native code using Android NDK
- Package the `.so` library into the `lib/` directory of the APK
- Configure `AndroidManifest.xml` permissions

#### Build
```bash
flutter build apk --debug
# or
flutter build apk --release
```
### iOS

#### Build configuration

- **Minimum version**: iOS 12.0
- **Architecture**: arm64 (real machine) or x86_64 (simulator)
- **Dynamic Library**: Framework format

#### Special handling

- Use CocoaPods to manage dependencies
- Configure `Info.plist` permissions
- Handle code signing

#### Build
```bash
# Install CocoaPods dependencies
cd ios
pod install
cd ..

# build
flutter build ios --debug
```
## Dependency installation

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
# Use vcpkg
vcpkg install libsodium:x64-windows
```
### Flutter SDK

#### Installation
```bash
# macOS/Linux
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:`pwd`/flutter/bin"

# Or use a package manager
# macOS
brew install --cask flutter

# Linux (Snap)
sudo snap install flutter --classic
```
#### verify
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

Download the installer from [CMake official website](https://cmake.org/download/).

## Common error resolution

For more build/runtime issues, log analysis, and debugging tips, see [TROUBLESHOOTING.md](TROUBLESHOOTING.en.md).

### Build errors

#### Error: libsodium not found

**Symptoms**:
```
fatal error: 'sodium.h' file not found
```
**solve**:
```bash
# macOS
brew install libsodium

# Linux
sudo apt-get install libsodium-dev

# Check installation location
# macOS: /opt/homebrew/lib or /usr/local/lib
# Linux: /usr/lib or /usr/local/lib
```
#### Error: CMake configuration failed

**Symptoms**:
```
CMake Error: Could not find a package configuration file
```**Solution**:
- Check CMake version: `cmake --version` (requires >= 3.4.1)
- Check whether dependent libraries are installed
- Clean the build directory: `rm -rf build` and rebuild

#### Error: Link error

**Symptoms**:
```
**Solution**:
- Check CMake version: `cmake --version` (requires >= 3.4.1)
- Check whether dependent libraries are installed
- Clean the build directory: `rm -rf build` and rebuild

#### Error: Link error

**Symptoms**:
```

**Solution**:
- Check link configuration in `CMakeLists.txt`
- Make sure all dependent libraries are linked correctly
- Check search paths for libraries

### Flutter build errors

#### Error: Dependency resolution failed

**Symptoms**:
```
**Solution**:
- Check link configuration in `CMakeLists.txt`
- Make sure all dependent libraries are linked correctly
- Check search paths for libraries

### Flutter build errors

#### Error: Dependency resolution failed

**Symptoms**:
```

**Solution**:
```bash
# Clean and re-obtain dependencies
flutter clean
flutter pub get
```
**solve**:
```
Error: No valid Android SDK found
```
#### Error: Platform configuration error

**Symptoms**:
```bash
# Run Flutter doctor
flutter doctor

# Install missing components
flutter doctor --android-licenses
```
**solve**:
```
Error: The getter 'xxx' isn't defined
```
#### Error: Code generation error

**Symptoms**:
```bash
# Regenerate code
flutter pub run build_runner build --delete-conflicting-outputs
```
**solve**:
```
dlopen failed: library not found
```
### Runtime errors

#### Error: Dynamic library loading failed

**Symptoms**:
```bash
# Check dynamic library path
otool -L libtim2tox_ffi.dylib

# repair path
install_name_tool -change \
    /old/path/libsodium.dylib \
    @loader_path/libsodium.dylib \
    libtim2tox_ffi.dylib
```
**Solution**:

**macOS**:
```bash
# Check dependencies
ldd libtim2tox_ffi.so

# Set library path
export LD_LIBRARY_PATH=/path/to/libs:$LD_LIBRARY_PATH
```

**Linux**:
```
Symbol not found: DartInitDartApiDL
```
**Windows**:
- Make sure all DLLs are in the executable directory
- Check the PATH environment variable

#### Error: symbol not found

**Symptoms**:
```bash
otool -L libtim2tox_ffi.dylib
```
**Solution**:
- Check if the function is declared with `extern "C"`
- Check export configuration in CMakeLists.txt
- Check symbol exports using `nm` or `objdump`

#### Error: callback not triggered

**Symptom**: The registered callback is not called

**Solution**:
- Make sure `DartInitDartApiDL` and `DartRegisterSendPort` are called
- Check `IsDartPortRegistered()` return value
- Check the log output to confirm whether the callback was called

### Network problem

#### Error: Tox cannot connect

**Symptom**: The app cannot connect to the Tox network after launching

**Solution**:
- Check network connection
- Check firewall settings
- Verify Bootstrap node configuration
- Check the log: `build/flutter_client.log`

#### Error: Bootstrap node connection failed

**Symptom**: The log shows "bootstrap nodes queued" but cannot connect

**Solution**:
- Check if Bootstrap node list is valid
- Verify network permission configuration
- Check if libsodium is packaged correctly

### Performance issues

#### Problem: Application starts slowly

**Solution**:
- Check dynamic library loading time
- Optimize the initialization process
- Use lazy loading

#### Problem: Message sending is slow

**Solution**:
- Check network connection status
- Optimize message serialization
- Use bulk sending

## Debugging Tips

### Enable detailed logging

In `run_toxee.sh`, the log files are located at:
- `build/native_build.log` - C++ build log
- `build/flutter_build.log` - Flutter build log
- `build/flutter_client.log` - application runtime log

### Check dynamic library dependencies

**macOS**:
```bash
ldd libtim2tox_ffi.so
```

**Linux**:
```bash
dumpbin /DEPENDENTS tim2tox_ffi.dll
```

**Windows**:
```bash
nm -D libtim2tox_ffi.dylib | grep Dart
```
### Verify function symbols

**macOS/Linux**:
```bash
dumpbin /EXPORTS tim2tox_ffi.dll
```

**Windows**:
```bash
# macOS
tail -f build/flutter_client.log

# Linux
tail -f build/flutter_client.log

# Or run the application directly in the terminal to view the output
```
```

## Related documents

- [Troubleshooting](../TROUBLESHOOTING.en.md) - Build/run failures, runtime issues, log analysis (check here first)
- [getting-started.en.md](../getting-started.en.md) - Clone to run in one page
- [Dependency bootstrap](DEPENDENCY_BOOTSTRAP.en.md) - Bootstrap order and options
- [Integration Guide](../integration/INTEGRATION_GUIDE.en.md) - How to integrate Tim2Tox
- [Main README](../../README.md) - Project Overview