cmake_minimum_required(VERSION 3.10)
project(echo_peer CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ----------------------------------------------------------------------------
# Builds the toxee-local echo peer binary.
#
# Linking strategy: against the pre-built `libtim2tox_ffi.dylib` produced by
# `third_party/tim2tox/build_ffi.sh`. That single shared library bundles both
# the static tim2tox core (V2TIMManager*, ToxManager, ToxAVManager) AND the
# FFI shim symbols (`tim2tox_ffi_*`, `Dart*`, `tim2tox_virtual_time_cb`,
# `GetOrCreateFriendshipListenerForInstance`, …) that the static `tim2tox`
# core depends on.
#
# WHY NOT add_subdirectory of tim2tox/source + toxcore directly?
#   `libtim2tox.a` references symbols that live in `tim2tox/ffi/` (the FFI
#   shim). The shim ISN'T compiled into the static lib — `tim2tox` only
#   builds the V2TIM*Impl + ToxManager .cpp files. So a plain static link
#   leaves undefined references to `tim2tox_ffi_save_friend_nickname`,
#   `GetOrCreateFriendshipListenerForInstance`, etc. The upstream
#   third_party/tim2tox/example/echo_bot_server target has the same problem
#   and isn't actually being built in CI today.
#
# TODO: tim2tox CMake target export — if tim2tox grows a public `tim2tox_ffi`
# CMake target (already exists in tim2tox/ffi/CMakeLists.txt but isn't
# add_subdirectory'd here because that path would force-build the WHOLE FFI
# library with toxav + bootstrap + sqlite from scratch every cmake configure),
# we can switch to add_subdirectory + target_link_libraries(echo_peer
# tim2tox_ffi). For now, link to the pre-built dylib that
# `third_party/tim2tox/build_ffi.sh` already produces.
# ----------------------------------------------------------------------------

# Resolve tim2tox source tree (repo root / third_party / tim2tox).
get_filename_component(TIM2TOX_ROOT
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/tim2tox"
    ABSOLUTE)

if(NOT EXISTS "${TIM2TOX_ROOT}/CMakeLists.txt")
    message(FATAL_ERROR
        "tim2tox source tree not found at ${TIM2TOX_ROOT}; "
        "did you `git submodule update --init --recursive` "
        "(or `dart run tool/bootstrap_deps.dart`)?")
endif()

message(STATUS "echo_peer: tim2tox root = ${TIM2TOX_ROOT}")

# ---- Locate the pre-built libtim2tox_ffi dylib ------------------------------
# Standard build output of `third_party/tim2tox/build_ffi.sh`. Honor
# TIM2TOX_FFI_LIB override for CI / unusual layouts.
if(DEFINED ENV{TIM2TOX_FFI_LIB})
    set(TIM2TOX_FFI_LIB "$ENV{TIM2TOX_FFI_LIB}")
elseif(DEFINED TIM2TOX_FFI_LIB)
    # already set via -DTIM2TOX_FFI_LIB=...
else()
    if(APPLE)
        set(TIM2TOX_FFI_LIB "${TIM2TOX_ROOT}/build/ffi/libtim2tox_ffi.dylib")
    elseif(WIN32)
        set(TIM2TOX_FFI_LIB "${TIM2TOX_ROOT}/build/ffi/tim2tox_ffi.dll")
    else()
        set(TIM2TOX_FFI_LIB "${TIM2TOX_ROOT}/build/ffi/libtim2tox_ffi.so")
    endif()
endif()

if(NOT EXISTS "${TIM2TOX_FFI_LIB}")
    message(FATAL_ERROR
        "Pre-built tim2tox FFI library not found at:\n"
        "  ${TIM2TOX_FFI_LIB}\n"
        "Build it first:\n"
        "  (cd ${TIM2TOX_ROOT} && ./build_ffi.sh)\n"
        "Or pass an alternate path via -DTIM2TOX_FFI_LIB=/abs/path/libtim2tox_ffi.dylib")
endif()

message(STATUS "echo_peer: linking against ${TIM2TOX_FFI_LIB}")

# IMPORTED SHARED target so dependents see proper transitive properties.
add_library(tim2tox_ffi SHARED IMPORTED)
set_target_properties(tim2tox_ffi PROPERTIES
    IMPORTED_LOCATION "${TIM2TOX_FFI_LIB}"
    INTERFACE_INCLUDE_DIRECTORIES "${TIM2TOX_ROOT}/include")

# ---- Echo peer executable --------------------------------------------------
add_executable(echo_peer echo_peer.cpp)

target_include_directories(echo_peer
    PRIVATE
        ${TIM2TOX_ROOT}/include)

target_link_libraries(echo_peer
    PRIVATE
        tim2tox_ffi)

if(APPLE)
    # The dylib was linked at its build path; on this machine that path is
    # absolute and valid, so no rpath gymnastics are needed. But document it.
    set_target_properties(echo_peer PROPERTIES
        INSTALL_RPATH "${TIM2TOX_ROOT}/build/ffi"
        BUILD_WITH_INSTALL_RPATH TRUE)
endif()
