#!/bin/zsh
# Build a native or universal signed app, ZIP and drag-to-install DMG.
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"
architecture="${1:-$(uname -m)}"
case "$architecture" in
  arm64|x86_64) architectures=("$architecture") ;;
  universal) architectures=(arm64 x86_64) ;;
  *) echo "Usage: $0 [arm64|x86_64|universal]" >&2; exit 2 ;;
esac
sdk_root="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
[[ -d "$sdk_root" ]] || { echo "macOS SDK not found: $sdk_root" >&2; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
export MACOSX_DEPLOYMENT_TARGET=14.0
export CLANG_MODULE_CACHE_PATH="$project_root/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.cache/swiftpm"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" "$project_root/dist"
# Build each slice separately: SwiftPM multi-arch mode requires full Xcode.
# Separate native builds plus lipo also work with Command Line Tools.
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
binary_paths=()
for slice in "${architectures[@]}"; do
  build_options=(--disable-sandbox -c release --sdk "$sdk_root" --scratch-path "$project_root/.build-$slice" --arch "$slice")
  swift build "${build_options[@]}"
  binary_dir=$(swift build "${build_options[@]}" --show-bin-path)
  binary_paths+=("$binary_dir/LaunchpadOS")
done
app_dir="$stage/LaunchpadOS.app"
contents="$app_dir/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
if [[ "$architecture" == "universal" ]]; then
  lipo -create "${binary_paths[@]}" -output "$contents/MacOS/LaunchpadOS"
else
  cp "${binary_paths[1]}" "$contents/MacOS/LaunchpadOS"
fi
cp Resources/Info.plist "$contents/Info.plist"
cp Resources/LaunchpadOS.icns Resources/AppIcon.png "$contents/Resources/"
chmod +x "$contents/MacOS/LaunchpadOS"

binary_archs=$(lipo -archs "$contents/MacOS/LaunchpadOS")
if [[ "$architecture" == "universal" ]]; then
  [[ "$binary_archs" == *arm64* && "$binary_archs" == *x86_64* ]] || { echo "Invalid universal binary: $binary_archs" >&2; exit 1; }
else
  [[ "$binary_archs" == "$architecture" ]] || { echo "Wrong architecture: $binary_archs" >&2; exit 1; }
fi
codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
plutil -lint "$contents/Info.plist"

name="LaunchpadOS_${version}_${architecture}"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$stage/$name.app.zip"
mkdir "$stage/dmg"
ditto "$app_dir" "$stage/dmg/LaunchpadOS.app"
ln -s /Applications "$stage/dmg/Applications"
hdiutil create -volname LaunchpadOS -srcfolder "$stage/dmg" -format UDZO -ov "$stage/$name.dmg" >/dev/null
hdiutil verify "$stage/$name.dmg" >/dev/null
# Preserve the familiar local app path; architecture-specific installers can coexist.
if [[ -d "$project_root/dist/LaunchpadOS.app" ]]; then
  backup="$project_root/dist/.previous-LaunchpadOS.app"
  [[ ! -e "$backup" ]] || { echo "Remove the previous local backup before rebuilding: $backup" >&2; exit 1; }
  mv "$project_root/dist/LaunchpadOS.app" "$backup"
  ditto "$app_dir" "$project_root/dist/LaunchpadOS.app"
  rm -rf "$backup"
else
  ditto "$app_dir" "$project_root/dist/LaunchpadOS.app"
fi
mv "$stage/$name.dmg" "$stage/$name.app.zip" "$project_root/dist/"
(cd "$project_root/dist" && shasum -a 256 "$name.dmg" "$name.app.zip" > "$name.sha256")
echo "Created: dist/$name.dmg, dist/$name.app.zip"
