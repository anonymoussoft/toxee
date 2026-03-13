#!/usr/bin/env bash
# 使用本地 tim2tox / chat-uikit-flutter 验证 bootstrap，无需从 GitHub 拉取。
# 在 tim2tox 改动尚未推送到 GitHub 时，用此脚本确认 bootstrap 流程符合预期。
# 从 toxee 仓库根目录执行: bash tool/verify_bootstrap_local.sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PARENT="$(cd "$ROOT/.." && pwd)"

echo "[verify] Using toxee root: $ROOT"
echo "[verify] Parent (workspace) dir: $PARENT"

# 1) 用本地目录填充 third_party，避免 git clone
mkdir -p third_party
if [ -d "$PARENT/tim2tox" ]; then
  rm -rf third_party/tim2tox
  ln -s "$PARENT/tim2tox" third_party/tim2tox
  echo "[verify] Linked third_party/tim2tox -> $PARENT/tim2tox"
else
  echo "[verify] ERROR: $PARENT/tim2tox not found. Run from a workspace that contains tim2tox (e.g. chat-uikit)." >&2
  exit 1
fi
if [ -d "$PARENT/chat-uikit-flutter" ]; then
  rm -rf third_party/chat-uikit-flutter
  ln -s "$PARENT/chat-uikit-flutter" third_party/chat-uikit-flutter
  echo "[verify] Linked third_party/chat-uikit-flutter -> $PARENT/chat-uikit-flutter"
else
  echo "[verify] WARN: $PARENT/chat-uikit-flutter not found. Bootstrap may try to clone it."
fi

# 2) 检查 tim2tox 内 lock 与 apply 脚本存在
LOCK="third_party/tim2tox/tool/tencent_cloud_chat_sdk.lock.json"
APPLY="third_party/tim2tox/tool/apply_sdk_patches.dart"
if [ ! -f "$LOCK" ]; then
  echo "[verify] ERROR: $LOCK not found." >&2
  exit 1
fi
if [ ! -f "$APPLY" ]; then
  echo "[verify] ERROR: $APPLY not found." >&2
  exit 1
fi
echo "[verify] Lock and apply script present."

# 3) 运行 bootstrap（会下载 SDK、应用 patch、生成 pubspec_overrides.yaml）
echo "[verify] Running bootstrap..."
dart run tool/bootstrap_deps.dart

# 4) 验证结果
echo "[verify] Checking bootstrap outputs..."
FAIL=0
if [ ! -f pubspec_overrides.yaml ]; then
  echo "[verify] FAIL: pubspec_overrides.yaml not generated." >&2
  FAIL=1
fi
if [ ! -d third_party/tencent_cloud_chat_sdk ]; then
  echo "[verify] FAIL: third_party/tencent_cloud_chat_sdk missing (SDK vendor failed?)." >&2
  FAIL=1
fi
if [ -f tool/vendor_state.json ]; then
  echo "[verify] vendor_state.json: $(cat tool/vendor_state.json)"
fi
if [ -f pubspec_overrides.yaml ]; then
  echo "[verify] pubspec_overrides.yaml (first 30 lines):"
  sed -n '1,30p' pubspec_overrides.yaml
fi
if [ $FAIL -eq 0 ]; then
  echo "[verify] Running flutter pub get..."
  flutter pub get
  echo "[verify] Bootstrap verification passed."
else
  echo "[verify] One or more checks failed." >&2
  exit 1
fi
