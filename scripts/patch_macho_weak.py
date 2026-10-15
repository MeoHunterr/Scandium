#!/usr/bin/env python3
# patch_macho_weak.py — Patch Mach-O load commands to weak-link iOS 18+ frameworks (SwiftUICore, etc.)
# Project: Scandium | Author: MeoHunter | License: GPL-3.0
#
# Changes LC_LOAD_DYLIB (0x0c) -> LC_LOAD_WEAK_DYLIB (0x80000018) for frameworks
# that do not exist on iOS < 18 (e.g., SwiftUICore), preventing DYLD crash on iOS 15-17.

import sys
import os
import struct

# Load command constants
LC_LOAD_DYLIB = 0x0c
LC_LOAD_WEAK_DYLIB = 0x80000018  # 0x18 | 0x80000000 (LC_REQ_DYLD)

# Mach-O Magics
MH_MAGIC_64 = 0xfeedfacf       # Little-endian 64-bit
MH_CIGAM_64 = 0xcffaedfe       # Big-endian 64-bit
FAT_MAGIC = 0xcafebabe
FAT_CIGAM = 0xbebafeca
FAT_MAGIC_64 = 0xcafebabf
FAT_CIGAM_64 = 0xbfbafeca

# Target frameworks that must be weak-linked for backward compatibility (iOS 15-17)
WEAK_TARGET_PATTERNS = [
    "SwiftUICore.framework",
    "SwiftData.framework",
    "Observation.framework",
]

def patch_mach_header(f, header_offset, is_64, endian):
    """Scan and patch load commands in a single Mach-O architecture slice."""
    f.seek(header_offset)
    magic_bytes = f.read(4)
    if len(magic_bytes) < 4:
        return 0, 0

    # Header size: 32 bytes for 64-bit, 28 bytes for 32-bit
    header_size = 32 if is_64 else 28
    f.seek(header_offset + 16)
    ncmds, sizeofcmds = struct.unpack(f"{endian}II", f.read(8))

    load_commands_offset = header_offset + header_size
    patched_count = 0
    already_weak_count = 0

    current_offset = load_commands_offset
    for cmd_idx in range(ncmds):
        f.seek(current_offset)
        cmd_data = f.read(8)
        if len(cmd_data) < 8:
            break
        cmd, cmdsize = struct.unpack(f"{endian}II", cmd_data)

        if cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB):
            # Read dylib path string
            f.seek(current_offset + 8)
            stroff, timestamp, current_version, comp_version = struct.unpack(f"{endian}IIII", f.read(16))
            str_abs_offset = current_offset + stroff
            f.seek(str_abs_offset)
            raw_name = f.read(max(0, cmdsize - stroff))
            dylib_name = raw_name.split(b"\x00")[0].decode("utf-8", errors="ignore")

            for pattern in WEAK_TARGET_PATTERNS:
                if pattern in dylib_name:
                    if cmd == LC_LOAD_DYLIB:
                        print(f"  [PATCH] Found {dylib_name}")
                        print(f"          Offset: 0x{current_offset:X} | Changing LC_LOAD_DYLIB (0x{cmd:08X}) -> LC_LOAD_WEAK_DYLIB (0x{LC_LOAD_WEAK_DYLIB:08X})")
                        f.seek(current_offset)
                        f.write(struct.pack(f"{endian}I", LC_LOAD_WEAK_DYLIB))
                        patched_count += 1
                    elif cmd == LC_LOAD_WEAK_DYLIB:
                        print(f"  [OK] Already weak-linked: {dylib_name}")
                        already_weak_count += 1
                    break

        current_offset += cmdsize

    return patched_count, already_weak_count

def patch_binary(binary_path):
    if not os.path.isfile(binary_path):
        print(f"ERROR: Binary not found at: {binary_path}", file=sys.stderr)
        return False

    print(f"==================================================")
    print(f" Mach-O Weak-Link Patcher for iOS Backward Compat")
    print(f" Target: {binary_path}")
    print(f"==================================================")

    total_patched = 0
    total_already_weak = 0

    with open(binary_path, "r+b") as f:
        magic_bytes = f.read(4)
        if len(magic_bytes) < 4:
            print("ERROR: File too small to be Mach-O binary", file=sys.stderr)
            return False

        magic_le = struct.unpack("<I", magic_bytes)[0]
        magic_be = struct.unpack(">I", magic_bytes)[0]

        if magic_le == MH_MAGIC_64:
            # 64-bit Little Endian (arm64 iOS standard)
            patched, already_weak = patch_mach_header(f, 0, is_64=True, endian="<")
            total_patched += patched
            total_already_weak += already_weak

        elif magic_be == MH_MAGIC_64:
            # 64-bit Big Endian
            patched, already_weak = patch_mach_header(f, 0, is_64=True, endian=">")
            total_patched += patched
            total_already_weak += already_weak

        elif magic_le in (FAT_MAGIC, FAT_CIGAM, FAT_MAGIC_64, FAT_CIGAM_64):
            # Universal / Fat Binary
            is_cigam = magic_le in (FAT_CIGAM, FAT_CIGAM_64)
            is_fat64 = magic_le in (FAT_MAGIC_64, FAT_CIGAM_64)
            endian = ">" if is_cigam else "<"
            f.seek(4)
            nfat_arch = struct.unpack(f"{endian}I", f.read(4))[0]
            print(f"Detected Fat binary with {nfat_arch} architectures")

            for i in range(nfat_arch):
                if is_fat64:
                    f.seek(8 + i * 32)
                    cputype, cpusubtype, offset, size, align = struct.unpack(f"{endian}QQQQQ", f.read(32))
                else:
                    f.seek(8 + i * 20)
                    cputype, cpusubtype, offset, size, align = struct.unpack(f"{endian}IIIII", f.read(20))

                # Check slice magic
                f.seek(offset)
                slice_magic = struct.unpack("<I", f.read(4))[0]
                is_64 = slice_magic == MH_MAGIC_64
                slice_endian = "<" if is_64 else ">"
                patched, already_weak = patch_mach_header(f, offset, is_64=is_64, endian=slice_endian)
                total_patched += patched
                total_already_weak += already_weak
        else:
            print(f"ERROR: Unrecognized binary format (magic: 0x{magic_le:08X})", file=sys.stderr)
            return False

        f.flush()

    print("--------------------------------------------------")
    print(f"Result: {total_patched} dylib(s) patched to LC_LOAD_WEAK_DYLIB")
    print(f"        {total_already_weak} dylib(s) were already weak-linked")
    print("==================================================")
    return True

def verify_binary(binary_path):
    """Print all dylibs and their link type (LC_LOAD_DYLIB vs LC_LOAD_WEAK_DYLIB)."""
    print(f"\n--- Verification of {os.path.basename(binary_path)} ---")
    has_unweakened_swiftuicore = False

    with open(binary_path, "rb") as f:
        magic_bytes = f.read(4)
        magic_le = struct.unpack("<I", magic_bytes)[0]
        if magic_le != MH_MAGIC_64:
            print("Verification only displays thin 64-bit slices.")
            return True

        f.seek(16)
        ncmds, sizeofcmds = struct.unpack("<II", f.read(8))
        f.seek(32)

        for _ in range(ncmds):
            cmd_start = f.tell()
            cmd, cmdsize = struct.unpack("<II", f.read(8))
            if cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB):
                stroff, _, _, _ = struct.unpack("<IIII", f.read(16))
                f.seek(cmd_start + stroff)
                name = f.read(max(0, cmdsize - stroff)).split(b"\x00")[0].decode("utf-8", errors="ignore")
                cmd_type = "LC_LOAD_DYLIB     " if cmd == LC_LOAD_DYLIB else "LC_LOAD_WEAK_DYLIB"
                status = ""
                for pat in WEAK_TARGET_PATTERNS:
                    if pat in name:
                        if cmd == LC_LOAD_WEAK_DYLIB:
                            status = " [WEAK-LINKED OK]"
                        else:
                            status = " [ERROR: STILL REQUIRED DYLIB!]"
                            has_unweakened_swiftuicore = True
                print(f"  {cmd_type} | {name}{status}")
            f.seek(cmd_start + cmdsize)

    if has_unweakened_swiftuicore:
        print("\nFATAL: One or more iOS 18+ frameworks are still LC_LOAD_DYLIB!", file=sys.stderr)
        return False
    print("\nVerification PASSED: All iOS 18+ frameworks are safely weak-linked.")
    return True

if __name__ == "__main__":
    default_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "xtool", "Scandium.app", "Scandium")
    target = sys.argv[1] if len(sys.argv) > 1 else default_path

    if not patch_binary(target):
        sys.exit(1)

    if not verify_binary(target):
        sys.exit(1)

    sys.exit(0)
