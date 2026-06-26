#!/usr/bin/env bash
# ビルド成果物を .app バンドルにまとめる。
# 使い方: bash Scripts/bundle.sh [debug|release]   (既定: release)
#
# ローカル検証用ビルド: LOCAL=1 bash Scripts/bundle.sh debug
#   本番アプリ(com.mtkg.clipkun)と TCC 権限が衝突しないよう、バンドルID と表示名を分けた
#   「Clipkun (Local)」を生成する。メニューバーには「ローカル」と併記され本番と区別できる。
#
# 署名:
#   既定では Developer ID Application（team id 指定）で署名する。安定した署名にすると、
#   再ビルドや更新で .app を入れ替えても権限が保持される。環境変数で上書きできる:
#     SIGN_IDENTITY  ... codesign の署名アイデンティティ（既定: Developer ID Application）
#     TEAM_ID        ... Developer Team ID（既定: G72M73C546）
#     AD_HOC=1       ... アドホック署名に切り替える（証明書が無い環境向け）
#     LOCAL=1        ... ローカル検証ビルド（バンドルID/表示名を分離）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
LOCAL="${LOCAL:-0}"

# ローカル検証ビルドはバンドルID/表示名を分けて本番と権限を分離する。
if [[ "$LOCAL" == "1" ]]; then
  APP_NAME="Clipkun (Local)"
  BUNDLE_ID="com.mtkg.clipkun.local"
else
  APP_NAME="Clipkun"
  BUNDLE_ID="com.mtkg.clipkun"
fi
APP="$ROOT/$APP_NAME.app"

# 既定の署名設定（Developer Team ID）。
TEAM_ID="${TEAM_ID:-G72M73C546}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Masaki TAKAGI (${TEAM_ID})}"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

echo "==> Bundling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN_DIR/Clipkun" "$APP/Contents/MacOS/Clipkun"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# ローカル検証ビルドはバンドルID/表示名を差し替える（CFBundleExecutable は Clipkun のまま）。
if [[ "$LOCAL" == "1" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist"
fi

# SwiftPM が生成するリソースバンドル（ローカライズ文字列 en/ja を含む）。
# Localization.swift の `L` が Contents/Resources から解決するため、ここに配置する。
RES_BUNDLE="$BIN_DIR/Clipkun_Clipkun.bundle"
if [[ ! -d "$RES_BUNDLE" ]]; then
  echo "error: リソースバンドルが見つかりません: $RES_BUNDLE" >&2
  exit 1
fi
cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"

# メニューバー用テンプレート画像（実行時に Bundle.main から読み込む）。
if [[ -f "$ROOT/Resources/MenuBarIcon.png" ]]; then
  cp "$ROOT/Resources/MenuBarIcon.png" "$APP/Contents/Resources/MenuBarIcon.png"
fi

# アプリアイコン: Resources/AppIcon.png があれば .icns を生成する。
ICON_SRC="$ROOT/Resources/AppIcon.png"
if [[ -f "$ICON_SRC" ]]; then
  echo "==> Generating app icon"
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

# コード署名。
if [[ "${AD_HOC:-0}" == "1" ]]; then
  echo "==> Codesign (ad-hoc)"
  codesign --force --deep --sign - "$APP"
else
  if ! security find-identity -v -p codesigning | grep -q "$TEAM_ID"; then
    echo "error: 署名アイデンティティが見つかりません (team id: $TEAM_ID)" >&2
    echo "       AD_HOC=1 でアドホック署名に切り替えられます。" >&2
    exit 1
  fi
  echo "==> Codesign ($SIGN_IDENTITY)"
  codesign --force --deep --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP"
fi

echo "==> Verify"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature|Authority" || true

echo "==> Done: $APP"
echo "起動: open \"$APP\""
