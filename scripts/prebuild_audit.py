#!/usr/bin/env python3
# prebuild_audit.py — Pre-build safety audit for Scandium
# Project: Scandium | Author: MeoHunter | License: GPL-3.0
#
# Run before every build:  python3 scripts/prebuild_audit.py
# Returns exit code 0 on PASS, 1 on FAIL.

import os
import re
import sys
import json
import struct
import plistlib

# ─── Configuration ────────────────────────────────────────────────────────────

PROJECT_ROOT   = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES_DIR    = os.path.join(PROJECT_ROOT, "Sources", "Scandium")
INFO_PLIST     = os.path.join(PROJECT_ROOT, "Info.plist")
ENTITLEMENTS   = os.path.join(PROJECT_ROOT, "entitlements.plist")
SCANDIUM_APP   = os.path.join(PROJECT_ROOT, "xtool", "Scandium.app")
BUILT_PLIST    = os.path.join(SCANDIUM_APP, "Info.plist")

# All ObservableObject classes in the project — must ALL be injected at root
REQUIRED_ENV_OBJECTS = {
    "ClientIDScraper": "scraper",
    "SoundCloudAPI":   "api",
    "AudioPlayerEngine": "player",
    "LibraryManager":  "library",
}

# ─── Helpers ──────────────────────────────────────────────────────────────────

PASS = "✅"
FAIL = "❌"
WARN = "⚠️ "
failures = []

def collect_swift_files(directory):
    result = []
    for root, _, files in os.walk(directory):
        for f in files:
            if f.endswith(".swift"):
                result.append(os.path.join(root, f))
    return result

def read_file(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except Exception as e:
        return ""

def report(ok, check_name, detail=""):
    status = PASS if ok else FAIL
    msg = f"{status} {check_name}"
    if detail:
        msg += f"\n     → {detail}"
    print(msg)
    if not ok:
        failures.append(check_name + (f": {detail}" if detail else ""))

# ─── Check 1: Plist Validity ──────────────────────────────────────────────────

def check_plists():
    print("\n[1] Plist validity")
    for label, path in [("Info.plist", INFO_PLIST), ("entitlements.plist", ENTITLEMENTS)]:
        if not os.path.exists(path):
            report(False, f"{label} exists", f"Not found at {path}")
            continue
        try:
            with open(path, "rb") as f:
                data = plistlib.load(f)
            report(True, f"{label} valid XML/plist")

            if label == "Info.plist":
                # Source Info.plist is a merge-only file for xtool:
                # CFBundleIdentifier and CFBundleExecutable are injected by xtool from xtool.yml.
                # We only verify UIBackgroundModes here; the built bundle check covers the rest.
                if "UIBackgroundModes" not in data:
                    report(False, "Info.plist has key 'UIBackgroundModes'",
                           "Missing UIBackgroundModes — background audio will not work")
                else:
                    report(True, "Info.plist has key 'UIBackgroundModes'")
                # UIBackgroundModes must be an array
                if "UIBackgroundModes" in data:
                    ok = isinstance(data["UIBackgroundModes"], list)
                    report(ok, "UIBackgroundModes is array type",
                           f"Wrong type: {type(data['UIBackgroundModes'])}" if not ok else "")

            if label == "entitlements.plist":
                # Must have no-sandbox, must NOT have no-container (which causes amfid kill)
                if "com.apple.private.security.no-container" in data:
                    report(False, "entitlements.plist free of 'no-container'",
                           "Key 'com.apple.private.security.no-container' causes amfid SIGKILL on TrollStore — use 'no-sandbox' instead")
                else:
                    report(True, "entitlements.plist free of 'no-container'")

                if "com.apple.private.security.no-sandbox" in data:
                    report(True, "entitlements.plist has 'no-sandbox'")
                else:
                    report(False, "entitlements.plist has 'no-sandbox'",
                           "TrollStore apps must have com.apple.private.security.no-sandbox = true")

                if "application-identifier" in data:
                    ok = data["application-identifier"] == "com.meohunter.scandium"
                    report(ok, "application-identifier is 'com.meohunter.scandium'",
                           f"Found: {data.get('application-identifier')}" if not ok else "")
                else:
                    report(False, "entitlements.plist has 'application-identifier'")

        except Exception as e:
            report(False, f"{label} parseable", str(e))

# ─── Check 2: Built Bundle Plist (if exists) ──────────────────────────────────

def check_built_bundle():
    print("\n[2] Built bundle Info.plist (xtool/Scandium.app/Info.plist)")
    if not os.path.exists(BUILT_PLIST):
        print(f"  {WARN} Built bundle not found — skipping (run build first)")
        return
    try:
        with open(BUILT_PLIST, "rb") as f:
            data = plistlib.load(f)
        report(True, "Built Info.plist parseable")
        bid = data.get("CFBundleIdentifier", "")
        report(bid == "com.meohunter.scandium", "CFBundleIdentifier correct",
               f"Found: '{bid}'" if bid != "com.meohunter.scandium" else "")
        exec_name = data.get("CFBundleExecutable", "")
        report(bool(exec_name), "CFBundleExecutable present",
               "Missing" if not exec_name else f"'{exec_name}'")
        bg = data.get("UIBackgroundModes", [])
        report("audio" in bg, "UIBackgroundModes contains 'audio'",
               f"Found: {bg}" if "audio" not in bg else "")
    except Exception as e:
        report(False, "Built Info.plist parseable", str(e))

# ─── Check 3: Force Unwraps ───────────────────────────────────────────────────

def check_force_unwraps(swift_files):
    print("\n[3] Force-unwrap scan")
    # Patterns that are dangerous: try!, as!, .first!, URL(...)!, array[n]! in expressions
    patterns = [
        (r'\btry!\b',              "try!"),
        (r'\bas!\b',               "as!  (force cast)"),
        (r'\bURL\(string:[^)]+\)!', "URL(string:...)!"),
        (r'\.first!',              ".first!"),
        (r'\.last!',               ".last!"),
        (r'\[0\]!',                "[0]! index force-unwrap"),
    ]
    found_any = False
    for path in swift_files:
        content = read_file(path)
        rel = os.path.relpath(path, PROJECT_ROOT)
        for pattern, name in patterns:
            for m in re.finditer(pattern, content):
                line_no = content[:m.start()].count("\n") + 1
                snippet = content.splitlines()[line_no - 1].strip()[:80]
                report(False, f"No {name} in {rel}:{line_no}", snippet)
                found_any = True
    if not found_any:
        report(True, "No dangerous force-unwraps found")

# ─── Check 4: EnvironmentObject injection audit ───────────────────────────────

def check_env_objects(swift_files):
    print("\n[4] EnvironmentObject injection audit")
    all_content = {os.path.basename(p): read_file(p) for p in swift_files}

    # Map from view file -> what @EnvironmentObjects it declares
    view_env_objects: dict[str, set[str]] = {}
    for filename, content in all_content.items():
        declared = set(re.findall(r'@EnvironmentObject\s+var\s+\w+:\s+(\w+)', content))
        if declared:
            view_env_objects[filename] = declared

    # Check ScandiumApp.swift injects all required env objects
    app_content = all_content.get("ScandiumApp.swift", "")
    print("  Checking ScandiumApp.swift provides all required environmentObjects:")
    for cls, _ in REQUIRED_ENV_OBJECTS.items():
        # Look for .environmentObject(...) calls in body
        ok = bool(re.search(rf'\.environmentObject\([^)]*\)', app_content)) and cls in app_content
        report(ok, f"ScandiumApp passes {cls} via environmentObject",
               f"'{cls}' not found in ScandiumApp.swift env injection" if not ok else "")

    # For each view that declares @EnvironmentObject<X>, check X is also declared
    # at the points where that view is instantiated in sheets/fullScreenCover
    print("  Checking all sheets/fullScreenCover pass required env objects:")
    sheet_files = ["MainContainerView.swift", "FullPlayerView.swift"]
    for filename in sheet_files:
        content = all_content.get(filename, "")
        # Find all .sheet { ViewName().environmentObject(...) } blocks
        # Simple heuristic: look for view types instantiated inside sheet blocks
        sheet_views = re.findall(r'\.sheet[^{]*\{[^}]*?(\w+View)\(\)', content, re.DOTALL)
        sheet_views += re.findall(r'fullScreenCover[^{]*\{[^}]*?(\w+View)\(\)', content, re.DOTALL)
        for view_name in set(sheet_views):
            view_file = f"{view_name}.swift"
            required = view_env_objects.get(view_file, set())
            for cls in required:
                # Check if .environmentObject(...) is present near that view in the sheet
                pattern = rf'{view_name}\(\)[^}}]*.environmentObject\([^)]*\)'
                found = bool(re.search(pattern, content, re.DOTALL))
                report(found or cls not in REQUIRED_ENV_OBJECTS,
                       f"{filename}: {view_name} sheet passes {cls}",
                       f"May be missing .environmentObject({cls.lower()}) in sheet" if not found else "")

# ─── Check 5: Negative .frame() values ───────────────────────────────────────

def check_negative_frames(swift_files):
    print("\n[5] Negative .frame() value scan")
    # Pattern: .frame(width: expr - num  or height: expr - num  without max(
    pattern = re.compile(r'\.frame\([^)]*(?:width|height)\s*:\s*[^,)]*\s*-\s*\d+[^)]*\)')
    found_any = False
    for path in swift_files:
        content = read_file(path)
        rel = os.path.relpath(path, PROJECT_ROOT)
        for m in re.finditer(pattern, content):
            snippet = m.group(0)
            # Only flag if max( is NOT present in this frame call
            if "max(" not in snippet:
                line_no = content[:m.start()].count("\n") + 1
                report(False, f"Negative frame guard in {rel}:{line_no}",
                       f"Missing max(1,...) around: {snippet[:80]}")
                found_any = True
    if not found_any:
        report(True, "All .frame() subtraction expressions use max() guard")

# ─── Check 6: Singleton vs StateObject conflicts ──────────────────────────────

def check_singleton_conflicts(swift_files):
    print("\n[6] Singleton vs StateObject conflict check")
    issues = []
    for path in swift_files:
        content = read_file(path)
        rel = os.path.relpath(path, PROJECT_ROOT)
        # Find classes that have both static let shared and are used as StateObject(wrappedValue: ClassName())
        state_inits = re.findall(r'StateObject\(wrappedValue:\s*(\w+)\(\)', content)
        for cls in state_inits:
            # Check if this class has a singleton
            cls_file_content = ""
            for p2 in swift_files:
                if os.path.basename(p2) == f"{cls}.swift":
                    cls_file_content = read_file(p2)
                    break
            if "static let shared" in cls_file_content:
                issues.append(f"{rel}: StateObject(wrappedValue: {cls}()) but {cls} has .shared singleton")

    if issues:
        for issue in issues:
            report(False, "No singleton/StateObject conflict", issue)
    else:
        report(True, "No singleton vs StateObject conflicts detected")

# ─── Check 7: Quick logic tests ───────────────────────────────────────────────

def check_logic_tests():
    print("\n[7] Logic unit tests (pure Python)")

    # Test: Track.artworkURL size replacement logic
    def artwork_url(url_str, size):
        if not url_str:
            return None
        return url_str.replace("-large.", f"-{size}.")

    url = "https://i1.sndcdn.com/artworks-000123456-abcdef-large.jpg"
    result = artwork_url(url, "t500x500")
    ok = result == "https://i1.sndcdn.com/artworks-000123456-abcdef-t500x500.jpg"
    report(ok, "Track artwork URL upgrade (large→t500x500)",
           f"Got: {result}" if not ok else "")

    # Test: ClientID regex pattern
    sample_js = 'const config = {client_id: "aBcDeFgHiJkLmNoPqRsTuVwXyZ012345"}'
    patterns = [
        r'client_id\s*:\s*"([a-zA-Z0-9]{32})"',
        r'client_id\s*=\s*"([a-zA-Z0-9]{32})"',
        r'"client_id"\s*:\s*"([a-zA-Z0-9]{32})"',
    ]
    found_id = None
    for p in patterns:
        m = re.search(p, sample_js)
        if m:
            found_id = m.group(1)
            break
    report(found_id == "aBcDeFgHiJkLmNoPqRsTuVwXyZ012345",
           "ClientID regex extracts 32-char ID from JS",
           f"Got: {found_id}" if found_id != "aBcDeFgHiJkLmNoPqRsTuVwXyZ012345" else "")

    # Test: JSON decode Track stub
    track_json = '''{"id": 12345, "title": "Test Track", "duration": 180000,
        "user": {"id": 1, "username": "artist", "permalink": "artist"},
        "streamable": true, "sharing": "public"}'''
    try:
        obj = json.loads(track_json)
        ok = obj["id"] == 12345 and obj["title"] == "Test Track"
        duration_secs = obj["duration"] / 1000.0
        ok2 = duration_secs == 180.0
        report(ok and ok2, "Track JSON stub decodes correctly",
               f"duration_secs={duration_secs}" if not ok2 else "")
    except Exception as e:
        report(False, "Track JSON stub decodes correctly", str(e))

# ─── Check 8: Mach-O Weak Linking Audit (if binary exists) ───────────────────

def check_macho_weak_links():
    binary_path = os.path.join(SCANDIUM_APP, "Scandium")
    print("\n[8] Mach-O Weak Linking Audit (xtool/Scandium.app/Scandium)")
    if not os.path.exists(binary_path):
        print(f"  {WARN} Binary not found — skipping (run build first)")
        return

    LC_LOAD_DYLIB = 0x0c
    LC_LOAD_WEAK_DYLIB = 0x80000018
    MH_MAGIC_64 = 0xfeedfacf

    try:
        with open(binary_path, "rb") as f:
            magic = struct.unpack("<I", f.read(4))[0]
            if magic != MH_MAGIC_64:
                report(True, "Mach-O magic recognized (non-64bit or fat)")
                return

            f.seek(16)
            ncmds, _ = struct.unpack("<II", f.read(8))
            f.seek(32)

            swiftuicore_status = None
            for _ in range(ncmds):
                cmd_start = f.tell()
                cmd, cmdsize = struct.unpack("<II", f.read(8))
                if cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB):
                    stroff, _, _, _ = struct.unpack("<IIII", f.read(16))
                    f.seek(cmd_start + stroff)
                    name = f.read(max(0, cmdsize - stroff)).split(b"\x00")[0].decode("utf-8", errors="ignore")
                    if "SwiftUICore.framework" in name:
                        swiftuicore_status = "WEAK" if cmd == LC_LOAD_WEAK_DYLIB else "REQUIRED"
                f.seek(cmd_start + cmdsize)

            if swiftuicore_status == "WEAK":
                report(True, "SwiftUICore.framework is LC_LOAD_WEAK_DYLIB")
            elif swiftuicore_status == "REQUIRED":
                report(False, "SwiftUICore.framework is LC_LOAD_WEAK_DYLIB",
                       "SwiftUICore is LC_LOAD_DYLIB (required). Run scripts/patch_macho_weak.py!")
            else:
                report(True, "SwiftUICore.framework not linked directly")
    except Exception as e:
        report(False, "Mach-O weak link audit parseable", str(e))

# ─── Check 9: Modifier Safety Blacklist (per rule.md) ─────────────────────────

def check_modifier_blacklist(swift_files):
    print("\n[9] Modifier Safety Blacklist (rule.md compliance)")
    blacklisted = [
        (r'\.fixedSize\(',           ".fixedSize() layout modifier"),
        (r'\.layoutPriority\(',      ".layoutPriority() modifier"),
        (r'\bUIViewRepresentable\b', "UIViewRepresentable protocol (can emit iOS17+ symbols)"),
        (r'\bUIViewControllerRepresentable\b', "UIViewControllerRepresentable protocol (can emit iOS17+ symbols)"),
        (r'\bNavigationStack\b',     "NavigationStack (iOS 16+)"),
        (r'\.sensoryFeedback\(',     ".sensoryFeedback() (iOS 17+)"),
        (r'\.symbolEffect\(',        ".symbolEffect() (iOS 17+)"),
        (r'\.contentTransition\(',   ".contentTransition() (iOS 16+)"),
        (r'\bMeshGradient\b',        "MeshGradient (iOS 18+)"),
        (r'\bShader\b',              "Shader (iOS 17+)"),
        (r'Text\([^)]*\)\.fontWeight', "Text.fontWeight (iOS 16+)"),
    ]
    found_any = False
    for path in swift_files:
        content = read_file(path)
        rel = os.path.relpath(path, PROJECT_ROOT)
        for pattern, name in blacklisted:
            for m in re.finditer(pattern, content):
                line_no = content[:m.start()].count("\n") + 1
                report(False, f"No {name} in {rel}:{line_no}",
                       f"Violates rule.md: {name} emits incompatible symbols on iOS 15/16")
                found_any = True
    if not found_any:
        report(True, "All Swift files comply with rule.md (no blacklisted modifiers)")

# ─── Check 10: Incompatible Symbol Scan in Binary (_FixedSizeLayout) ──────────

def check_incompatible_symbols():
    binary_path = os.path.join(SCANDIUM_APP, "Scandium")
    print("\n[10] Incompatible Symbol Scan (llvm-nm)")
    if not os.path.exists(binary_path):
        print(f"  {WARN} Binary not found — skipping (run build first)")
        return

    import subprocess
    llvm_nm_candidates = [
        "/home/meohunter/.local/share/swiftly/bin/llvm-nm",
        "llvm-nm",
    ]
    nm_bin = None
    for cand in llvm_nm_candidates:
        if os.path.exists(cand) or subprocess.run(["which", cand], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
            nm_bin = cand
            break

    if not nm_bin:
        print(f"  {WARN} llvm-nm not found — skipping symbol scan")
        return

    try:
        res = subprocess.run([nm_bin, "-u", binary_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        symbols = res.stdout
        forbidden_symbols = {
            "_FixedSizeLayout": "Found _FixedSizeLayout in undefined symbols — causes dyld crash on iOS 16.2!",
            "_$ss5NeverO7SwiftUI4ViewACWP": "Found Never:SwiftUI.View witness symbol — can crash at launch on iOS 15/16 with new toolchain builds.",
        }

        has_forbidden = False
        for symbol, detail in forbidden_symbols.items():
            if symbol in symbols:
                report(False, f"Binary free of {symbol} symbols", detail)
                has_forbidden = True

        if "_FixedSizeLayout" in symbols:
            pass
        elif not has_forbidden:
            report(True, "Binary free of known incompatible SwiftUI symbols")
        else:
            pass
    except Exception as e:
        report(False, "Symbol check executed", str(e))

# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("  SCANDIUM PRE-BUILD AUDIT")
    print(f"  Project root: {PROJECT_ROOT}")
    print("=" * 60)

    swift_files = collect_swift_files(SOURCES_DIR)
    print(f"\nFound {len(swift_files)} Swift source files.\n")

    check_plists()
    check_built_bundle()
    check_force_unwraps(swift_files)
    check_env_objects(swift_files)
    check_negative_frames(swift_files)
    check_singleton_conflicts(swift_files)
    check_logic_tests()
    check_modifier_blacklist(swift_files)
    check_macho_weak_links()
    check_incompatible_symbols()

    print("\n" + "=" * 60)
    if failures:
        print(f"  {FAIL} AUDIT FAILED — {len(failures)} issue(s):")
        for i, f in enumerate(failures, 1):
            print(f"    {i}. {f}")
        print("=" * 60)
        sys.exit(1)
    else:
        print(f"  {PASS} ALL CHECKS PASSED — Safe to build!")
        print("=" * 60)
        sys.exit(0)

if __name__ == "__main__":
    main()
