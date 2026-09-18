#!/usr/bin/env python3
# 生成一个极小的合法 32 位 Windows EXE：入口即调用 ExitProcess(0)。
# 用于替换 SogouCloud.exe —— 被 IME 拉起时立刻正常退出，不崩溃、不占资源。
# 布局（单节 .text，RVA 0x1000 / file 0x200）：
#   0x000  code: push 0; call dword ptr [0x401100]; int3
#   0x020  Import descriptor + null
#   0x060  ILT
#   0x080  hint/name  "ExitProcess"
#   0x0A0  dll name   "KERNEL32.dll"
#   0x100  IAT (loader 填充)
import struct
import sys

IMAGEBASE = 0x400000
SEC_RVA = 0x1000
SEC_OFF = 0x200
SEC_SIZE = 0x200  # 文件/内存对齐后大小

CODE_OFF = 0x000
DESC_OFF = 0x020
ILT_OFF = 0x060
HN_OFF = 0x080
DLL_OFF = 0x0A0
IAT_OFF = 0x100


def rva(off):
    return SEC_RVA + off


def build():
    sec = bytearray(SEC_SIZE)

    # --- code ---
    code = b"\x6A\x00" + b"\xFF\x15" + struct.pack("<I", IMAGEBASE + rva(IAT_OFF)) + b"\xCC"
    sec[CODE_OFF:CODE_OFF + len(code)] = code

    # --- import descriptor ---
    desc = struct.pack("<IIIII", rva(ILT_OFF), 0, 0, rva(DLL_OFF), rva(IAT_OFF))
    sec[DESC_OFF:DESC_OFF + 20] = desc
    # null descriptor 已为 0

    # --- ILT ---
    sec[ILT_OFF:ILT_OFF + 4] = struct.pack("<I", rva(HN_OFF))

    # --- hint/name ---
    sec[HN_OFF:HN_OFF + 2] = struct.pack("<H", 0)
    sec[HN_OFF + 2:HN_OFF + 2 + 12] = b"ExitProcess\x00"

    # --- dll name ---
    sec[DLL_OFF:DLL_OFF + 13] = b"KERNEL32.dll\x00"

    # --- IAT (loader 会覆盖；文件里先填 ILT 同值) ---
    sec[IAT_OFF:IAT_OFF + 4] = struct.pack("<I", rva(HN_OFF))

    # ---------- headers ----------
    dos = bytearray(64)
    dos[0:2] = b"MZ"
    struct.pack_into("<I", dos, 0x3C, 0x40)

    pe = bytearray()
    pe += b"PE\x00\x00"
    # COFF: Machine, NSections, TimeDateStamp, PtrSymTab, NSyms, SizeOptHdr, Characteristics
    # 0x0103 = EXECUTABLE_IMAGE | 32BIT_MACHINE | RELOCS_STRIPPED (固定基址，无 ASLR)
    pe += struct.pack("<HHIIIHH", 0x014C, 1, 0, 0, 0, 0x00E0, 0x0103)

    opt = bytearray()
    opt += struct.pack("<H", 0x010B)            # Magic PE32
    opt += struct.pack("<BB", 8, 0)             # MajorLinkerVersion, Minor
    opt += struct.pack("<I", SEC_SIZE)          # SizeOfCode
    opt += struct.pack("<I", 0)                 # SizeOfInitializedData
    opt += struct.pack("<I", 0)                 # SizeOfUninitializedData
    opt += struct.pack("<I", rva(CODE_OFF))     # AddressOfEntryPoint
    opt += struct.pack("<I", rva(CODE_OFF))     # BaseOfCode
    opt += struct.pack("<I", 0)                 # BaseOfData
    opt += struct.pack("<I", IMAGEBASE)         # ImageBase
    opt += struct.pack("<I", 0x1000)            # SectionAlignment
    opt += struct.pack("<I", 0x200)             # FileAlignment
    opt += struct.pack("<HH", 6, 0)             # OS version
    opt += struct.pack("<HH", 0, 0)             # Image version
    opt += struct.pack("<HH", 6, 0)             # Subsystem version
    opt += struct.pack("<I", 0)                 # Win32VersionValue
    opt += struct.pack("<I", 0x2000)            # SizeOfImage
    opt += struct.pack("<I", 0x200)             # SizeOfHeaders
    opt += struct.pack("<I", 0)                 # CheckSum
    opt += struct.pack("<H", 2)                 # Subsystem = GUI
    opt += struct.pack("<H", 0)                 # DllCharacteristics (no ASLR)
    opt += struct.pack("<I", 0x100000)          # SizeOfStackReserve
    opt += struct.pack("<I", 0x1000)            # SizeOfStackCommit
    opt += struct.pack("<I", 0x100000)          # SizeOfHeapReserve
    opt += struct.pack("<I", 0x1000)            # SizeOfHeapCommit
    opt += struct.pack("<I", 0)                 # LoaderFlags
    opt += struct.pack("<I", 16)                # NumberOfRvaAndSizes
    dirs = [(0, 0)] * 16
    dirs[1] = (rva(DESC_OFF), 40)               # Import table
    for a, b in dirs:
        opt += struct.pack("<II", a, b)
    assert len(opt) == 0xE0, hex(len(opt))

    pe += opt
    # section header
    pe += b".text\x00\x00\x00"
    pe += struct.pack("<IIII", SEC_SIZE, SEC_RVA, SEC_SIZE, SEC_OFF)
    pe += struct.pack("<II", 0, 0)              # relocs, linenums
    pe += struct.pack("<HH", 0, 0)
    # Characteristics: CODE | EXECUTE | READ
    pe += struct.pack("<I", 0x60000020)

    out = bytearray()
    out += dos
    out += pe
    assert len(out) <= SEC_OFF, len(out)
    out += b"\x00" * (SEC_OFF - len(out))
    out += sec
    return bytes(out)


if __name__ == "__main__":
    data = build()
    dst = sys.argv[1] if len(sys.argv) > 1 else "SogouCloud.exe"
    open(dst, "wb").write(data)
    import hashlib
    print("wrote", dst, len(data), "bytes")
    print("sha256", hashlib.sha256(data).hexdigest())
