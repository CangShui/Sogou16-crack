# -*- coding: utf-8 -*-
"""
inject_block.py — 纯内嵌断网补丁注入器（零系统环境依赖）
============================================================
原理:
  在目标 32 位 PE(搜狗组件) 末尾追加一个新节 .nblk:
    [patcher]  进程入口钩子: 运行时算出模块基址, 把自己的 IAT 网络函数槽
               全部改写为指向本文件内嵌的 stub(返回失败)
    [table]    {iat_rva, stub_rva} 补丁表 (生成器根据导入表精确算出)
    [stubs]    每个网络函数的失败实现:  B8 imm32  C2 NN NN  (mov eax,v; ret N)
  并把 AddressOfEntryPoint 改为 patcher; patcher 完成补丁后跳回原入口。
  代码位置无关(call/pop 自定位), 兼容 ASLR。
  不修改任何系统文件/hosts/防火墙; 断网逻辑完全在组件自身 PE 内。
用法: python inject_block.py <exe/dll>
"""
import sys, struct, os
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

# ---------- 需要拦截的网络函数: dll -> {name: (ret_bytes, retval)} ----------
# retval: 返回的 eax 值 (SOCKET_ERROR=-1 / INVALID_SOCKET=0xFFFFFFFF / NULL=0 / 错误码)
BLOCK = {
    'WS2_32.dll': {
        # name: (stack bytes to ret, return value)
        'WSAStartup': (8, 0),                 # 成功, 避免 app 直接退出
        'WSACleanup': (0, 0),
        'socket': (12, 0xFFFFFFFF),
        'bind': (12, 0xFFFFFFFF),
        'connect': (12, 0xFFFFFFFF),
        'listen': (8, 0xFFFFFFFF),
        'accept': (12, 0xFFFFFFFF),
        'send': (16, 0xFFFFFFFF),
        'sendto': (24, 0xFFFFFFFF),
        'recv': (16, 0xFFFFFFFF),
        'recvfrom': (24, 0xFFFFFFFF),
        'shutdown': (8, 0xFFFFFFFF),
        'closesocket': (4, 0xFFFFFFFF),
        'ioctlsocket': (12, 0xFFFFFFFF),
        'setsockopt': (20, 0xFFFFFFFF),
        'select': (20, 0xFFFFFFFF),
        'getpeername': (12, 0xFFFFFFFF),
        'getsockname': (12, 0xFFFFFFFF),
        'getsockopt': (20, 0xFFFFFFFF),
        'getaddrinfo': (16, 0x00002AF9),      # WSAHOST_NOT_FOUND
        'freeaddrinfo': (4, 0),
        'gethostbyname': (4, 0),
        'gethostbyaddr': (12, 0),
        'gethostname': (8, 0xFFFFFFFF),
        'inet_addr': (4, 0xFFFFFFFF),
        'inet_ntoa': (4, 0),
        'WSASocketA': (24, 0xFFFFFFFF),
        'WSASocketW': (24, 0xFFFFFFFF),
        'WSAConnect': (28, 0xFFFFFFFF),
        'WSASend': (28, 0xFFFFFFFF),
        'WSARecv': (28, 0xFFFFFFFF),
        'WSASendTo': (36, 0xFFFFFFFF),
        'WSARecvFrom': (36, 0xFFFFFFFF),
        'WSAGetLastError': (0, 0),
        'WSASetLastError': (4, 0),
        'WSACreateEvent': (0, 0),
        'WSACloseEvent': (4, 0),
        'WSAResetEvent': (4, 0),
        'WSAEventSelect': (12, 0xFFFFFFFF),
        'WSAEnumNetworkEvents': (12, 0xFFFFFFFF),
        'WSAWaitForMultipleEvents': (20, 0xFFFFFFFF),
        'WSAIoctl': (36, 0xFFFFFFFF),
        'WSASetServiceA': (12, 0xFFFFFFFF),
        'WSADuplicateSocketA': (12, 0xFFFFFFFF),
        'WSADuplicateSocketW': (12, 0xFFFFFFFF),
        'GetAddrInfoW': (16, 0x00002AF9),
        'FreeAddrInfoW': (4, 0),
        'getnameinfo': (28, 0x00002AF9),
        'inet_ntop': (16, 0),
        'inet_pton': (12, 0),
        'InetNtopW': (16, 0),
        'InetPtonW': (12, 0),
        'WSAAddressToStringW': (20, 0xFFFFFFFF),
        'WSAStringToAddressW': (20, 0xFFFFFFFF),
        'WSAGetOverlappedResult': (20, 0),
        'WSASetEvent': (4, 0),
        '__WSAFDIsSet': (8, 0),
    },
    'WININET.dll': {
        'InternetOpenA': (20, 1),              # 伪句柄: DllMain 初始化不崩
        'InternetOpenW': (20, 1),
        'InternetConnectA': (32, 1),
        'InternetConnectW': (32, 1),
        'InternetOpenUrlA': (24, 0),           # 真实拨号失败
        'InternetOpenUrlW': (24, 0),
        'HttpOpenRequestA': (32, 1),           # 伪句柄: DllMain 初始化不崩
        'HttpOpenRequestW': (32, 1),
        'HttpSendRequestA': (20, 0),
        'HttpSendRequestW': (20, 0),
        'HttpSendRequestExW': (20, 0),
        'HttpEndRequestA': (16, 0),
        'HttpEndRequestW': (16, 0),
        'InternetReadFile': (16, 0),
        'InternetWriteFile': (16, 0),
        'InternetSetOptionA': (16, 0),
        'InternetSetOptionW': (16, 0),
        'InternetQueryOptionA': (16, 0),
        'InternetQueryOptionW': (16, 0),
        'InternetQueryDataAvailable': (16, 0),
        'InternetCheckConnectionW': (12, 0),
        'HttpQueryInfoA': (20, 0),
        'HttpQueryInfoW': (20, 0),
        'InternetCanonicalizeUrlW': (16, 0),
        'InternetCrackUrlA': (16, 0),
        'InternetCrackUrlW': (16, 0),
        'InternetErrorDlg': (20, 0),
        'InternetGetConnectedState': (8, 0),
        'InternetSetCookieW': (12, 0),
        'InternetCloseHandle': (4, 0),
        'HttpAddRequestHeadersA': (16, 0),
        'HttpAddRequestHeadersW': (16, 0),
    },
    'WINHTTP.dll': {
        'WinHttpOpen': (20, 1),                # 伪句柄: DllMain 初始化不崩
        'WinHttpConnect': (16, 1),
        'WinHttpOpenRequest': (28, 1),
        'WinHttpSendRequest': (28, 0),         # 真实拨号失败
        'WinHttpReceiveResponse': (8, 0),
        'WinHttpReadData': (16, 0),
        'WinHttpWriteData': (16, 0),
        'WinHttpQueryDataAvailable': (8, 0),
        'WinHttpQueryHeaders': (24, 0),
        'WinHttpQueryOption': (16, 0),
        'WinHttpSetOption': (16, 0),
        'WinHttpSetTimeouts': (20, 0),
        'WinHttpCloseHandle': (4, 0),
        'WinHttpCrackUrl': (16, 0),
        'WinHttpGetIEProxyConfigForCurrentUser': (4, 0),
        'WinHttpGetProxyForUrl': (16, 0),
        'WinHttpAddRequestHeaders': (16, 0),
    },
}

# 真实 32 位 ws2_32 的 ordinal -> 函数名 (从 SysWOW64 ws2_32.dll 提取, base=1)
ORD_NAME = {
    1:'accept',2:'bind',3:'closesocket',4:'connect',5:'getpeername',6:'getsockname',
    7:'getsockopt',8:'htonl',9:'htons',10:'ioctlsocket',11:'inet_addr',12:'inet_ntoa',
    13:'listen',14:'ntohl',15:'ntohs',16:'recv',17:'recvfrom',18:'select',19:'send',
    20:'sendto',21:'setsockopt',22:'shutdown',23:'socket',
    26:'FreeAddrInfoW',31:'GetAddrInfoW',43:'WSAAddressToStringW',45:'WSACloseEvent',
    46:'WSAConnect',50:'WSACreateEvent',51:'gethostbyaddr',52:'gethostbyname',
    53:'getprotobyname',55:'getservbyname',56:'getservbyport',57:'gethostname',
    58:'WSADuplicateSocketA',59:'WSADuplicateSocketW',64:'WSAEnumNetworkEvents',
    67:'WSAEventSelect',68:'WSAGetOverlappedResult',78:'WSAIoctl',91:'WSARecv',
    93:'WSARecvFrom',95:'WSAResetEvent',96:'WSASend',99:'WSASendTo',100:'WSASetEvent',
    111:'WSAGetLastError',112:'WSASetLastError',115:'WSAStartup',116:'WSACleanup',
    117:'WSASetServiceA',119:'WSASocketA',120:'WSASocketW',122:'WSAStringToAddressW',
    124:'WSAWaitForMultipleEvents',151:'__WSAFDIsSet',176:'freeaddrinfo',
    177:'getaddrinfo',178:'getnameinfo',179:'inet_ntop',180:'inet_pton',
}

def parse_pe(d):
    if d[:2] != b'MZ': raise ValueError('not MZ')
    el = struct.unpack('<I', d[0x3c:0x40])[0]
    if d[el:el+4] != b'PE\x00\x00': raise ValueError('no PE sig')
    nsec = struct.unpack('<H', d[el+6:el+8])[0]
    optsz = struct.unpack('<H', d[el+20:el+22])[0]
    opt = el + 24
    magic = struct.unpack('<H', d[opt:opt+2])[0]
    if magic != 0x10b: raise ValueError('not PE32')
    entry = struct.unpack('<I', d[opt+16:opt+20])[0]
    imgbase = struct.unpack('<I', d[opt+28:opt+32])[0]
    sec_align = struct.unpack('<I', d[opt+32:opt+36])[0]
    file_align = struct.unpack('<I', d[opt+36:opt+40])[0]
    soi = struct.unpack('<I', d[opt+56:opt+60])[0]
    import_rva, import_sz = struct.unpack('<II', d[opt+96+8:opt+96+16])   # data dir[1] = import
    so = opt + optsz
    secs = []
    for i in range(nsec):
        r = so + i*40
        name = d[r:r+8].split(b'\x00')[0].decode('latin1','replace')
        vsz, va, rsz, ro = struct.unpack('<IIII', d[r+8:r+24])
        chars = struct.unpack('<I', d[r+36:r+40])[0]
        secs.append(dict(name=name,vsz=vsz,va=va,rsz=rsz,ro=ro,chars=chars))
    return dict(el=el,opt=opt,nsec=nsec,optsz=optsz,entry=entry,imgbase=imgbase,
                sec_align=sec_align,file_align=file_align,soi=soi,import_rva=import_rva,
                import_sz=import_sz,so=so,secs=secs)

def rva2off(pe, rva):
    for s in pe['secs']:
        if s['va'] <= rva < s['va'] + max(s['vsz'], s['rsz']):
            return s['ro'] + (rva - s['va'])
    return None

def collect_patch_slots(d, pe):
    """返回 [(iat_rva, stub_key)] 其中 stub_key=(retbytes, retval)"""
    slots = []
    io = rva2off(pe, pe['import_rva'])
    while io:
        nameRVA = struct.unpack('<I', d[io+12:io+16])[0]
        if nameRVA == 0: break
        no = rva2off(pe, nameRVA)
        dll = d[no:no+64].split(b'\x00')[0].decode('latin1','replace') if no else '?'
        if dll in BLOCK:
            othRVA = struct.unpack('<I', d[io+0:io+4])[0]
            if othRVA == 0: othRVA = struct.unpack('<I', d[io+16:io+20])[0]
            ftRVA  = struct.unpack('<I', d[io+16:io+20])[0]
            ot = rva2off(pe, othRVA)
            ft = rva2off(pe, ftRVA)
            tbl = BLOCK[dll]
            idx = 0
            while ot and ft:
                val = struct.unpack('<I', d[ot:ot+4])[0]
                if val == 0: break
                if val & 0x80000000:
                    fn = ORD_NAME.get(val & 0xFFFF)
                else:
                    hno = rva2off(pe, val & 0x7FFFFFFF)
                    if hno is None or hno+2 > len(d):
                        fn = None
                    else:
                        fn = d[hno+2:hno+66].split(b'\x00')[0].decode('latin1','replace') if hno else None
                if fn and fn in tbl:
                    # IAT slot rva = FirstThunk[i]
                    slots.append((ftRVA + idx*4, tbl[fn]))
                ot += 4; ft += 4; idx += 1
        io += 20
    return slots

def build_patcher(pe, slots):
    """生成 .nblk 节数据: patcher + table + stubs, 返回 (data, new_va, new_entry_rva)"""
    # stubs 去重
    uniq = {}
    for _, key in slots:
        uniq.setdefault(key, None)
    stub_list = list(uniq.keys())          # [(retbytes, retval)]
    stub_index = {k:i for i,k in enumerate(stub_list)}

    # 布局(相对新节): patcher + table(8*(n+1)) + stubs(8*len)
    patcher_len = 47
    table_off = patcher_len
    table_count = len(slots)
    table_bytes = table_off + table_count*8
    stubs_off = table_bytes + 8
    # 节内偏移
    def sec_off_to_rva(off): return new_va + off

    # 计算 new_va
    last = pe['secs'][-1]
    new_va = ((last['va'] + max(last['vsz'], last['rsz']) + pe['sec_align'] - 1) // pe['sec_align']) * pe['sec_align']
    # patcher 机器码 (位置无关)
    # 我们需要 base 常量: patcher 内 'next' 指令的节内偏移 = 5
    base_imm = new_va + 5                    # ebx - base_imm = imagebase
    tbl_rva = new_va + table_off
    orig_entry_rva = pe['entry']
    code = bytearray()
    code += b'\xE8\x00\x00\x00\x00'          # call +5
    code += b'\x5B'                          # pop ebx
    code += b'\x81\xEB' + struct.pack('<I', base_imm)   # sub ebx, base_imm -> ebx=imagebase
    code += b'\x8D\xB3' + struct.pack('<I', tbl_rva)    # lea esi,[ebx+tbl_rva]
    # loop:
    code += b'\x8B\x06'                      # mov eax,[esi]        (iat_rva)
    code += b'\x85\xC0'                      # test eax,eax
    code += b'\x74\x0E'                      # jz done (+14)
    code += b'\x8B\x56\x04'                  # mov edx,[esi+4]      (stub_rva)
    code += b'\x03\xC3'                      # add eax,ebx
    code += b'\x03\xD3'                      # add edx,ebx
    code += b'\x89\x10'                      # mov [eax],edx        (patch IAT)
    code += b'\x83\xC6\x08'                  # add esi,8
    code += b'\xEB\xEC'                      # jmp loop (-20)
    # done:
    code += b'\x8B\xC3'                      # mov eax,ebx
    code += b'\x05' + struct.pack('<I', orig_entry_rva)  # add eax, orig_entry_rva
    code += b'\xFF\xE0'                      # jmp eax
    assert len(code) == 47, len(code)

    # table
    for iat_rva, key in slots:
        code += struct.pack('<II', iat_rva, new_va + stubs_off + stub_index[key]*8)
    code += struct.pack('<II', 0, 0)

    # stubs
    for retbytes, retval in stub_list:
        code += b'\xB8' + struct.pack('<I', retval & 0xFFFFFFFF) + b'\xC2' + struct.pack('<H', retbytes)

    new_entry_rva = new_va
    return bytes(code), new_va, new_entry_rva

def inject(fp, outfp=None):
    d = bytearray(open(fp,'rb').read())
    pe = parse_pe(bytes(d))
    # 已注入则跳过（防重复）
    for s in pe['secs']:
        if s['name'].startswith('.nblk'):
            print(f'{fp}: already injected (skip)')
            return False
    slots = collect_patch_slots(bytes(d), pe)
    if not slots:
        print(f'{fp}: no network imports to block (skipped)')
        return False
    blob, new_va, new_entry_rva = build_patcher(pe, slots)
    blob_align = (len(blob) + pe['file_align'] - 1) // pe['file_align'] * pe['file_align']
    raw_off = (len(d) + pe['file_align'] - 1) // pe['file_align'] * pe['file_align']
    # 扩展文件
    d.extend(b'\x00' * (raw_off - len(d)))
    d.extend(blob)
    d.extend(b'\x00' * (blob_align - len(blob)))
    # 更新头
    el = pe['el']; opt = pe['opt']
    # IAT 槽所在节必须可写：patcher 运行时写 IAT 槽，若节只读则 AV(0xc0000005)
    writable_secs = set()
    for iat_rva, _ in slots:
        for i, s in enumerate(pe['secs']):
            if s['va'] <= iat_rva < s['va'] + max(s['vsz'], s['rsz']):
                writable_secs.add(i)
                break
    for i in writable_secs:
        sec_off = pe['so'] + i*40
        chars = struct.unpack('<I', d[sec_off+36:sec_off+40])[0]
        if not (chars & 0x80000000):
            struct.pack_into('<I', d, sec_off+36, chars | 0x80000000)  # +MEM_WRITE
    # 增加节表项
    struct.pack_into('<H', d, el+6, pe['nsec']+1)
    so = pe['so'] + pe['nsec']*40
    name = b'.nblk'
    struct.pack_into('<8s', d, so, name)
    vsz = blob_align
    struct.pack_into('<IIIIIIHHI', d, so+8, vsz, new_va, blob_align, raw_off, 0,0,0,0,
                     0xE0000060)  # code|idata|read|write|execute
    # SizeOfImage
    new_img = ((new_va + blob_align + pe['sec_align'] - 1) // pe['sec_align']) * pe['sec_align']
    struct.pack_into('<I', d, opt+56, new_img)
    # entry
    struct.pack_into('<I', d, opt+16, new_entry_rva)
    out = outfp or fp
    open(out,'wb').write(d)
    print(f'{fp}: injected .nblk ({len(blob)} bytes, {len(slots)} IAT slots) -> {out}')
    return True

if __name__ == '__main__':
    import traceback
    for f in sys.argv[1:]:
        try:
            inject(f)
        except Exception:
            print(f'{f}: ERROR')
            traceback.print_exc()
