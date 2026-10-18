#!/bin/bash
set -e

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGING_DIR="/tmp/Pomme_DMG_Staging"
ENTITLEMENTS="$WORKSPACE_DIR/Config/Pomme-DMG-Distribution.entitlements"
DMG_OUTPUT="$WORKSPACE_DIR/Pomme.dmg"

echo "==> 1. Compiling Release build for macOS..."
xcodebuild -scheme Pomme -destination 'platform=macOS' -configuration Release build

RELEASE_APP="/Users/david/Library/Developer/Xcode/DerivedData/Pomme-euogaiexgynengfjpzcxlrlufapg/Build/Products/Release/Pomme.app"
if [ ! -d "$RELEASE_APP" ]; then
    echo "Error: Release Pomme.app not found at $RELEASE_APP"
    exit 1
fi

echo "==> 2. Preparing staging directory..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$RELEASE_APP" "$STAGING_DIR/Pomme.app"

echo "==> 3. Stripping AR/VR 3D models for distribution version..."
find "$STAGING_DIR/Pomme.app" -name "*.usdz" -delete
find "$STAGING_DIR/Pomme.app" -name "*.reality" -delete

echo "==> 4. Stripping personal collection data (ensuring clean public sample data)..."
find "$STAGING_DIR/Pomme.app" -name "MyMuseum-PersonalCollection.json" -delete

echo "==> 5. Removing UDID-restricted development provisioning profiles..."
rm -f "$STAGING_DIR/Pomme.app/Contents/embedded.provisionprofile"

echo "==> 6. Ad-hoc signing with public sandbox distribution entitlements..."
codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$STAGING_DIR/Pomme.app"
codesign -vvv --deep --strict "$STAGING_DIR/Pomme.app"

echo "==> 7. Creating Applications drag-and-drop shortcut..."
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> 8. Packaging Pomme.dmg..."
rm -f "$DMG_OUTPUT"
hdiutil create -volname "Pomme" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_OUTPUT"

echo "==> 9. Done! DMG Package created successfully:"
ls -lh "$DMG_OUTPUT"
