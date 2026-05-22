#!/bin/bash
set -e

VERSION="$1"
CHANGELOG="$2"
REPO="Pakzartl/obd2-flutter"
API_BASE="https://adv350.pakzartl.xyz"
COMPONENT="flutter-app"

if [ -z "$VERSION" ] || [ -z "$CHANGELOG" ]; then
  echo "Usage: ./release.sh <version> <changelog>"
  echo "Example: ./release.sh 0.3.3 \"fix BLE reconnect + add trip filter\""
  exit 1
fi

# Get current build number and increment
CURRENT_BUILD=$(grep "version:" pubspec.yaml | head -1 | sed 's/.*+//')
NEW_BUILD=$((CURRENT_BUILD + 1))

echo "=== Release v${VERSION}+${NEW_BUILD} ==="
echo "Changelog: $CHANGELOG"
echo ""

# 1. Bump version
sed -i '' "s/version: .*/version: ${VERSION}+${NEW_BUILD}/" pubspec.yaml
echo "[1/6] Version bumped to ${VERSION}+${NEW_BUILD}"

# 2. Commit + tag
git add -A
git commit -m "release: v${VERSION} — ${CHANGELOG}"
git tag "v${VERSION}"
git push origin main --tags
echo "[2/6] Committed + tagged + pushed"

# 3. Build APK
echo "[3/6] Building APK..."
flutter build apk --release 2>&1 | tail -1

APK="build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK" ]; then
  echo "ERROR: APK not found"
  exit 1
fi

# 4. GitHub release
gh release create "v${VERSION}" "$APK" \
  --repo "$REPO" \
  --title "v${VERSION} — ${CHANGELOG}" \
  --notes "$CHANGELOG"
echo "[4/6] GitHub release created"

# 5. Register in D1
APK_SIZE=$(stat -f%z "$APK")
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/app-release.apk"
bunx wrangler d1 execute adv350-telemetry --remote \
  --command "INSERT INTO firmware (component, version, changelog, download_url, size) VALUES ('${COMPONENT}', '${VERSION}', '${CHANGELOG}', '${DOWNLOAD_URL}', ${APK_SIZE})" \
  2>&1 | grep -q '"success": true' && echo "[5/6] D1 registered" || echo "[5/6] D1 registration failed!"

# 6. Done
echo "[6/6] Done!"
echo ""
echo "=== v${VERSION} released ==="
echo "GitHub: https://github.com/${REPO}/releases/tag/v${VERSION}"
echo "APK: ${APK_SIZE} bytes"
