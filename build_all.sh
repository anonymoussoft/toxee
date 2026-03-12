#!/bin/bash

# Cross-platform build script for toxee
# This script builds the application for all supported platforms

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    print_error "Flutter is not installed or not in PATH"
    exit 1
fi

print_info "Flutter version: $(flutter --version | head -n 1)"

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Build tim2tox native library first
print_info "Building tim2tox native library..."
TIM2TOX_DIR="../tim2tox"
if [ -d "$TIM2TOX_DIR" ]; then
    cd "$TIM2TOX_DIR"
    if [ -f "build.sh" ]; then
        ./build.sh
    else
        print_warn "build.sh not found in tim2tox, skipping native library build"
        print_warn "Please build tim2tox manually before building the Flutter app"
    fi
    cd "$SCRIPT_DIR"
else
    print_warn "tim2tox directory not found, skipping native library build"
fi

# Parse command line arguments
BUILD_MODE="release"
PLATFORMS=""
CLEAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            BUILD_MODE="$2"
            shift 2
            ;;
        --platform)
            PLATFORMS="$PLATFORMS $2"
            shift 2
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --mode MODE          Build mode: debug, profile, or release (default: release)"
            echo "  --platform PLATFORM  Build for specific platform: macos, linux, windows, android, ios"
            echo "                       Can be specified multiple times. If not specified, builds for all available platforms."
            echo "  --clean              Clean build before building"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Clean if requested
if [ "$CLEAN" = true ]; then
    print_info "Cleaning build..."
    flutter clean
fi

# Get dependencies
print_info "Getting Flutter dependencies..."
flutter pub get

# Determine which platforms to build
if [ -z "$PLATFORMS" ]; then
    # Build for all available platforms
    PLATFORMS="macos linux windows android ios"
    print_info "Building for all available platforms: $PLATFORMS"
else
    print_info "Building for specified platforms: $PLATFORMS"
fi

# Build for each platform
for PLATFORM in $PLATFORMS; do
    print_info "Building for $PLATFORM ($BUILD_MODE)..."
    
    case $PLATFORM in
        macos)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                flutter build macos --$BUILD_MODE
                print_info "macOS build completed"
            else
                print_warn "Skipping macOS build (not on macOS)"
            fi
            ;;
        linux)
            flutter build linux --$BUILD_MODE
            print_info "Linux build completed"
            ;;
        windows)
            if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
                flutter build windows --$BUILD_MODE
                print_info "Windows build completed"
            else
                print_warn "Skipping Windows build (not on Windows)"
            fi
            ;;
        android)
            flutter build apk --$BUILD_MODE
            print_info "Android build completed"
            ;;
        ios)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                flutter build ios --$BUILD_MODE --no-codesign
                print_info "iOS build completed (unsigned)"
            else
                print_warn "Skipping iOS build (not on macOS)"
            fi
            ;;
        *)
            print_error "Unknown platform: $PLATFORM"
            ;;
    esac
done

print_info "Build process completed!"

