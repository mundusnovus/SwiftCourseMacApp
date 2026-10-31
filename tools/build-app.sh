#!/bin/bash
# Builds "Swift Zero to Hero.app" and a disk image in build/.
#
#   tools/build-app.sh                 build, sign and make the DMG
#   NOTARY_PROFILE=asteria tools/build-app.sh
#                                      also notarize and staple (see README: Signing and notarizing)
#   STORE=1 tools/build-app.sh           the Mac App Store build instead: sandboxed, signed with Apple Distribution,
#                                      as build/appstore/Swift-Zero-to-Hero-<version>.pkg (see README: Mac App Store)
#
# Signing: uses SIGN_IDENTITY if set, else the first "Developer ID Application" certificate in the keychain, else an
# ad-hoc signature (fine on this Mac, but other Macs will warn). The app runs with the hardened runtime.
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME="Swift Zero to Hero"
BUNDLE_ID="technology.asteria.zerotohero"
VERSION="${VERSION:-$(cat VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
OUT=build
[ -n "${STORE:-}" ] && OUT=build/appstore
TEAM_ID="${TEAM_ID:-KZFR2T5L2A}"
SIGNING="$HOME/Library/Application Support/Asteria Signing"
PROFILE="${PROFILE:-$SIGNING/zerotohero-macappstore.provisionprofile}"
APP="$OUT/$APP_NAME.app"

# Without full Xcode, SwiftUI's macros are missing from the macOS 27 SDK, so build against 26.5 (the app needs 26 anyway)
if ! xcodebuild -version >/dev/null 2>&1; then
  for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk; do
    [ -d "$sdk" ] && export SDKROOT="$sdk" && break
  done
  ARCHS=(--arch arm64)
else
  ARCHS=(--arch arm64 --arch x86_64)
fi

echo "Building $APP_NAME $VERSION ($BUILD_NUMBER)…"
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/ZeroToHero"

rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ZeroToHero"
cp Resources/course.json Resources/AsteriaPixel-Regular.ttf Resources/AppIcon.icns "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>ZeroToHero</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Asteria Technology. Open source under the Asteria License.</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><true/>
  <key>ITSAppUsesNonExemptEncryption</key><false/>
</dict>
</plist>
PLIST

if [ -n "${STORE:-}" ]; then
  # The App Store wants the sandbox. Exercises still run: the app uses the compiler's interpreter there (see Runner.swift)
  [ -f "$PROFILE" ] || { echo "Missing the Mac App Store provisioning profile at $PROFILE"; exit 1; }
  cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
  ENT="$OUT/entitlements.plist"
  cat > "$ENT" <<ENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.application-identifier</key><string>$TEAM_ID.$BUNDLE_ID</string>
  <key>com.apple.developer.team-identifier</key><string>$TEAM_ID</string>
</dict>
</plist>
ENTS
  APP_ID="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 -E '"(Apple Distribution|3rd Party Mac Developer Application)' | sed -E 's/.*"(.*)"/\1/')}"
  PKG_ID="$(security find-identity -v | grep -m1 -E '"(3rd Party Mac Developer Installer|Mac Installer Distribution)' | sed -E 's/.*"(.*)"/\1/')"
  echo "Signing with $APP_ID"
  codesign --force --options runtime --timestamp --entitlements "$ENT" --sign "$APP_ID" "$APP"
  codesign --verify --deep --strict --verbose=1 "$APP"
  PKG="$OUT/Swift-Zero-to-Hero-$VERSION.pkg"
  productbuild --component "$APP" /Applications --sign "$PKG_ID" --timestamp "$PKG"
  echo "Built $PKG (upload it with: xcrun altool --upload-package, or the Transporter app)"
  exit 0
fi

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Developer ID Application' | sed -E 's/.*"(.*)"/\1/' || true)}"
if [ -n "$IDENTITY" ]; then
  echo "Signing with $IDENTITY"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/MacOS/ZeroToHero"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  echo "No Developer ID certificate found: signing ad hoc (other Macs will warn)"
  codesign --force --options runtime --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=1 "$APP"

DMG="$OUT/Swift-Zero-to-Hero-$VERSION.dmg"
STAGE="$OUT/dmg"
rm -rf "$STAGE" "$DMG" && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
[ -n "$IDENTITY" ] && codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "Notarizing (this takes a few minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler staple "$APP"
  spctl --assess --type open --context context:primary-signature -v "$DMG" || true
fi
echo "Built $APP and $DMG"
