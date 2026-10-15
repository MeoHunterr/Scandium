#!/usr/bin/env bash
# build_ipa.sh — Automated Linux build + ldid pseudo-sign + .ipa packaging for xtool
# Project: Scandium | Author: MeoHunter | License: GPL-3.0
#
# Usage:
#   chmod +x scripts/build_ipa.sh
#   ./scripts/build_ipa.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_NAME="Scandium"
IPA_OUTPUT="${PROJECT_ROOT}/${APP_NAME}.ipa"
ENTITLEMENTS_FILE="${PROJECT_ROOT}/entitlements.plist"
STAGING_DIR="${PROJECT_ROOT}/.build_staging"

echo "============================================"
echo "  Scandium IPA Builder (xtool / TrollStore)"
echo "  Author: MeoHunter"
echo "============================================"
echo ""

# -------------------------------------------------------------------
# Step 1: Build with xtool
# -------------------------------------------------------------------
echo "[1/4] Building ${APP_NAME} with xtool dev build (-c release)..."
cd "${PROJECT_ROOT}"
xtool dev build -c release

echo "       Build completed."
echo ""

# -------------------------------------------------------------------
# Step 2: Locate output .app bundle
# -------------------------------------------------------------------
echo "[2/4] Locating ${APP_NAME}.app bundle..."

APP_BUNDLE=""
CANDIDATE_PATHS=(
    "${PROJECT_ROOT}/xtool/${APP_NAME}.app"
    "${PROJECT_ROOT}/xtool/${APP_NAME}-App.app"
    "${PROJECT_ROOT}/.build/release-iphoneos/${APP_NAME}.app"
    "${PROJECT_ROOT}/.build/release-iphoneos/${APP_NAME}-App.app"
)

for candidate in "${CANDIDATE_PATHS[@]}"; do
    if [ -d "${candidate}" ]; then
        APP_BUNDLE="${candidate}"
        break
    fi
done

if [ -z "${APP_BUNDLE}" ]; then
    echo "       Searching in ${PROJECT_ROOT}/xtool and .build..."
    APP_BUNDLE="$(find "${PROJECT_ROOT}/xtool" "${PROJECT_ROOT}/.build" -maxdepth 3 -name "*.app" -type d 2>/dev/null | head -n 1)"
fi

if [ -z "${APP_BUNDLE}" ] || [ ! -d "${APP_BUNDLE}" ]; then
    echo "ERROR: Could not locate built .app bundle."
    echo "       Expected at: ${PROJECT_ROOT}/xtool/${APP_NAME}.app"
    exit 1
fi

echo "       Found: ${APP_BUNDLE}"
echo ""

# -------------------------------------------------------------------
# Step 3: Patch Mach-O headers (weak-link SwiftUICore & iOS 18+ libs)
# -------------------------------------------------------------------
echo "[3/5] Patching Mach-O headers for iOS backward compatibility..."
PATCH_SCRIPT="${PROJECT_ROOT}/scripts/patch_macho_weak.py"
MAIN_BINARY="${APP_BUNDLE}/${APP_NAME}"

if [ -f "${PATCH_SCRIPT}" ] && [ -f "${MAIN_BINARY}" ]; then
    python3 "${PATCH_SCRIPT}" "${MAIN_BINARY}"
    echo "       Mach-O weak-linking completed successfully."
else
    echo "WARNING: Patch script or main binary not found at ${MAIN_BINARY}. Skipping patch."
fi
echo ""

# -------------------------------------------------------------------
# Step 4: Pseudo-sign with ldid
# -------------------------------------------------------------------
echo "[4/5] Pseudo-signing ${APP_BUNDLE} with ldid..."

# Use the project-root entitlements.plist (contains correct TrollStore entitlements)
if [ ! -f "${ENTITLEMENTS_FILE}" ]; then
    echo "ERROR: ${ENTITLEMENTS_FILE} not found. Run from project root."
    exit 1
fi

if command -v ldid > /dev/null 2>&1; then
    ldid -S"${ENTITLEMENTS_FILE}" "${APP_BUNDLE}"
    echo "       Signed ${APP_BUNDLE} with ldid."

    # Sign any embedded frameworks/dylibs
    if [ -d "${APP_BUNDLE}/Frameworks" ]; then
        for fw in "${APP_BUNDLE}/Frameworks/"*.dylib "${APP_BUNDLE}/Frameworks/"*.framework; do
            if [ -e "${fw}" ]; then
                ldid -S"${ENTITLEMENTS_FILE}" "${fw}" 2>/dev/null || true
                echo "       Signed framework: $(basename "${fw}")"
            fi
        done
    fi
else
    echo "WARNING: ldid not found in PATH. Skipping pseudo-signing step."
fi

echo ""

# -------------------------------------------------------------------
# Step 5: Package into .ipa
# -------------------------------------------------------------------
echo "[5/5] Packaging ${APP_NAME}.ipa..."

rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}/Payload"

# Copy into Payload/Scandium.app
cp -a "${APP_BUNDLE}" "${STAGING_DIR}/Payload/${APP_NAME}.app"

rm -f "${IPA_OUTPUT}"
cd "${STAGING_DIR}"
zip -r9 "${IPA_OUTPUT}" Payload

# Cleanup
cd "${PROJECT_ROOT}"
rm -rf "${STAGING_DIR}"

echo ""
echo "============================================"
echo "  SUCCESS!"
echo "  Output: ${IPA_OUTPUT}"
if [ -f "${IPA_OUTPUT}" ]; then
    FILE_SIZE=$(du -h "${IPA_OUTPUT}" | cut -f1)
    echo "  Size:   ${FILE_SIZE}"
fi
echo "============================================"
echo ""
echo "  Install via TrollStore or sideload tool."
echo ""
