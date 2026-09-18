#!/usr/bin/env python3
# 【已否决方案，仅历史留存】SogouCloud.exe 入口点裸 ret 桩：把 PE 入口点改到 .text 末尾对齐填充区的
# 3 字节 stub `xor eax,eax; ret` (31 C0 C3)，使进程启动即退出。
#
# 注意：必须使用【未改动的官方 pristine】SogouCloud.exe 作为输入，
#       （该方案已被否决，产物不在安装包内；此处仅为历史记录）SHA256：
#       351a01b81b1f93d97bcfc11cbaef24dbcf96e1011268aaf747566b97bee2b6e4
# 用法: python3 stub_cloud.py <pristine_SogouCloud.exe> <out.exe>
import struct
import sys

GAP = 32  # 从 .text 节 raw 末尾回退 32 字节（PE 对齐填充区，安全，不覆盖真实代码）


def main(src, dst):
    d = bytearray(open(src, "rb").read())
    el = struct.unpack("<I", d[0x3c:0x40])[0]          # e_lfanew
    assert d[el:el + 4] == b"PE\x00\x00", "not PE"
    nsec = struct.unpack("<H", d[el + 6:el + 8])[0]
    optsz = struct.unpack("<H", d[el + 20:el + 22])[0]
    opt = el + 24
    magic = struct.unpack("<H", d[opt:opt + 2])[0]
    entry = struct.unpack("<I", d[opt + 16:opt + 20])[0]
    print(f"PE{'32+' if magic == 0x20B else '32'} nsec={nsec} EP=0x{entry:x}")
    so = opt + optsz
    for i in range(nsec):
        r = so + i * 40
        name = d[r:r + 8].split(b"\x00")[0].decode("latin1")
        vsz, va, rsz, ro = struct.unpack("<IIII", d[r + 8:r + 24])
        if name == ".text":
            off = ro + rsz - GAP
            rva = va + (rsz - GAP)
            print(f".text VA=0x{va:x} RawPtr=0x{ro:x} RawSize=0x{rsz:x}")
            print(f"stub 31 C0 C3 @ file 0x{off:x} (RVA 0x{rva:x}), 新 EP=0x{rva:x}")
            d[off:off + 3] = b"\x31\xc0\xc3"
            struct.pack_into("<I", d, opt + 16, rva)
            break
    else:
        raise SystemExit("未找到 .text 节")
    open(dst, "wb").write(bytes(d))
    print("写出", dst, len(d), "字节")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
