#!/usr/bin/env python3
"""
inject.py -- offline-hook injection entry (5 modules).

Usage:
    python3 inject.py <payload_root>

    <payload_root>  e.g. ../../work16/payload
                    The script looks under
                    <payload_root>/progfiles/SogouInput/16.8.0.4914/ and injects
                    the .nblk offline hook into exactly these 5 modules:
                        SGTool.exe  SGDownload.exe  SGCurlHelper.dll
                        networkbase.dll  shiply.dll

Notes:
    - Imports inject_block.py from the same directory (no sys.path hack).
    - Idempotent: skips a file that already has a .nblk section.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inject_block as ib  # noqa: E402

INJECT = ["SGTool.exe", "SGDownload.exe", "SGCurlHelper.dll",
          "networkbase.dll", "shiply.dll"]


def main(payload_root):
    ver_dir = os.path.join(payload_root, "progfiles", "SogouInput", "16.8.0.4914")
    if not os.path.isdir(ver_dir):
        print("ERROR: version dir not found:", ver_dir)
        return 2
    for fn in INJECT:
        fp = os.path.join(ver_dir, fn)
        if not os.path.exists(fp):
            print("MISSING", fn)
            continue
        try:
            r = ib.inject(fp)
            print(("OK  " if r else "SKIP"), fn)
        except Exception as e:  # noqa: BLE001
            print("ERR ", fn, e)
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1]))
