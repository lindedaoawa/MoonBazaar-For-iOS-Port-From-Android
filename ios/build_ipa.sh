#!/usr/bin/env bash
# ============================================================================
# MoonBazaar iOS 一键打包脚本
#
#   ./build_ipa.sh                     # Release 未签名 IPA（默认）
#   ./build_ipa.sh --simulator         # 仅编译模拟器版本（快速校验）
#   ./build_ipa.sh --signed --team ABCDE12345
#                                      # 已签名 IPA（需本机已装证书 / 描述文件）
#   ./build_ipa.sh -c Debug            # 指定构建配置
#
# 产物：ios/dist/MoonBazaar-v<版本>-<构建号>[-unsigned].ipa
# ============================================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

PROJECT="MoonBazaar.xcodeproj"
SCHEME="MoonBazaar"
PRODUCT="MoonBazaar.app"
CONFIG="Release"
MODE="unsigned"          # unsigned | signed | simulator
TEAM_ID="${DEVELOPMENT_TEAM:-}"
METHOD="${EXPORT_METHOD:-development}"
OUT_DIR="$PROJECT_DIR/dist"
DD_UNSIGNED="build"
DD_SIGNED="build-archive"
DD_SIM="build-sim"

usage() {
  cat <<'EOF'
用法: ./build_ipa.sh [选项]

  -c, --config <Debug|Release>   构建配置（默认 Release）
      --simulator                只编译模拟器版本，产物在 build-sim/
      --signed                   产出已签名 IPA（archive + export）
      --team <TEAM_ID>           签名用 Apple Team ID（也可用环境变量 DEVELOPMENT_TEAM）
      --method <method>          导出方式：development | ad-hoc | app-store
                                 （默认 development，也可用 EXPORT_METHOD）
      --clean                    构建前清理 DerivedData
  -h, --help                     显示帮助
EOF
}

CLEAN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config) CONFIG="$2"; shift 2 ;;
    --simulator) MODE="simulator"; shift ;;
    --signed)    MODE="signed"; shift ;;
    --team)      TEAM_ID="$2"; shift 2 ;;
    --method)    METHOD="$2"; shift 2 ;;
    --clean)     CLEAN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "错误：iOS 打包需要 macOS + Xcode。非 macOS 环境请使用 GitHub Actions 工作流：" >&2
  echo "        .github/workflows/ios-build.yml" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "错误：未找到 xcodebuild，请安装 Xcode 并执行 sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi

echo "==> Xcode: $(xcodebuild -version | head -n1)"
echo "==> 配置: $CONFIG   模式: $MODE"

build_common=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIG"
)

# ---------------------------------------------------------------------------
# 模拟器：仅做编译校验
# ---------------------------------------------------------------------------
if [[ "$MODE" == "simulator" ]]; then
  [[ "$CLEAN" == "1" ]] && rm -rf "$DD_SIM"
  xcodebuild "${build_common[@]}" \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DD_SIM" \
    CODE_SIGNING_ALLOWED=NO \
    build
  echo "==> 模拟器编译完成：$DD_SIM/Build/Products/${CONFIG}-iphonesimulator/$PRODUCT"
  exit 0
fi

# ---------------------------------------------------------------------------
# 已签名：archive + exportArchive
# ---------------------------------------------------------------------------
if [[ "$MODE" == "signed" ]]; then
  if [[ -z "$TEAM_ID" ]]; then
    echo "错误：--signed 需要 --team <TEAM_ID>（或环境变量 DEVELOPMENT_TEAM）" >&2
    exit 1
  fi
  [[ "$CLEAN" == "1" ]] && rm -rf "$DD_SIGNED"
  ARCHIVE="$DD_SIGNED/$SCHEME.xcarchive"

  echo "==> 归档中（Team: $TEAM_ID）…"
  xcodebuild "${build_common[@]}" \
    -sdk iphoneos \
    -derivedDataPath "$DD_SIGNED" \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    archive

  EXPORT_DIR="$DD_SIGNED/export"
  rm -rf "$EXPORT_DIR"; mkdir -p "$EXPORT_DIR" "$OUT_DIR"
  cat > "$DD_SIGNED/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>${METHOD}</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>compileBitcode</key>
	<false/>
</dict>
</plist>
PLIST

  echo "==> 导出 IPA…"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$DD_SIGNED/ExportOptions.plist" \
    -allowProvisioningUpdates

  VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ARCHIVE/Info.plist")
  BUILDNO=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$ARCHIVE/Info.plist")
  IPA="$OUT_DIR/MoonBazaar-v${VERSION}-${BUILDNO}.ipa"
  mv "$EXPORT_DIR/$SCHEME.ipa" "$IPA"
  echo "==> 打包完成：$IPA"
  exit 0
fi

# ---------------------------------------------------------------------------
# 未签名：直接 build 后手工组装 Payload/*.ipa
# ---------------------------------------------------------------------------
[[ "$CLEAN" == "1" ]] && rm -rf "$DD_UNSIGNED"

echo "==> 构建中（未签名）…"
xcodebuild "${build_common[@]}" \
  -sdk iphoneos \
  -derivedDataPath "$DD_UNSIGNED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  ONLY_ACTIVE_ARCH=NO \
  build

APP="$DD_UNSIGNED/Build/Products/${CONFIG}-iphoneos/$PRODUCT"
if [[ ! -d "$APP" ]]; then
  echo "错误：未找到构建产物 $APP" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Info.plist")
BUILDNO=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Info.plist")
IPA_NAME="MoonBazaar-v${VERSION}-${BUILDNO}-unsigned.ipa"

echo "==> 组装 IPA…"
rm -rf "$OUT_DIR/Payload"
find "$OUT_DIR" -maxdepth 1 -name '*.ipa' -delete 2>/dev/null || true
mkdir -p "$OUT_DIR/Payload"
cp -R "$APP" "$OUT_DIR/Payload/"
xattr -cr "$OUT_DIR/Payload" 2>/dev/null || true
( cd "$OUT_DIR" && zip -qry "$IPA_NAME" Payload && rm -rf Payload )

echo "==> 打包完成：$OUT_DIR/$IPA_NAME"
echo "    未签名 IPA 需经 TrollStore / AltStore / Sideloadly 等工具重签后安装。"