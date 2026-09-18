# scrub5.py — final scrub (fixes UTF-16 host regex bug in scrub4)
# 
# Key fix: scrub4's HOST_RE_U16 pattern was `(?:[A-Za-z0-9]\x00)(?:[A-Za-z0-9\-\x00_\x00]*...)+`
# which allowed stray nulls (\x00) within labels, causing it to swallow non-host characters
# (e.g. "api.pinyin.sogou.comhttp" as a single token, then host_is_public returns False
# because the token contains "http"). This left UTF-16 URL hosts unscrubbed.
#
# scrub5 uses a strict label+dot pattern: each label is a strict sequence of
# label-chars followed by \x00. Multiple labels separated by \x2e\x00.

import os, re, struct

CORE_RELPATHS = {
    'ime_system32/SogouPY.ime','ime_system32/SogouTSF.ime',
    'ime_syswow64/SogouPY.ime','ime_syswow64/SogouTSF.ime',
    'ime_broker/SogouImeBroker.exe','ime_broker/SogouWin10Setup.exe',
}
CORE_RELPATHS_BS = {p.replace('/','\\') for p in CORE_RELPATHS}
CORE_RELPATHS = CORE_RELPATHS | CORE_RELPATHS_BS
SKIP_HOST = {'127.0.0.1','localhost','0.0.0.0','ime.local','pc.store.ime.local',
             'android.cloud_device_model.ime.local','pc.rare.ime.local','trpc.apipc.pinyinimeconfig.http'}
SKIP_SUFFIX = ('.local','.internal','.lan','.localhost','.http','.ime.local')

PATCH_SUFFIXES = [
    'sogou.com','sogoucdn.com','sginput.qq.com','sginput.com','qq.com',
    'woa.com','tencent.com','sohu.com','soso.com','sogou.cn',
    'zhiyin.sogou.com','speech.sogou.com','shouji.sogou.com','get.sogou.com',
    'pinyin.sogou.com','account.sogou.com','api.pinyin.sogou.com',
    'config.pinyin.sogou.com','download.pinyin.sogou.com',
    'ping.pinyin.sogou.com','encrypt.pinyin.sogou.com','sugg.sogou.com',
    'cloud.pinyin.sogou.com','longca.pinyin.sogou.com',
    'qqcenter.pinyin.sogou.com','torrent.ie.sogou.com',
    'rdelivery.qq.com','qqdata.ab.qq.com','tqqdata.ab.qq.com',
    'trace.inlong.qq.com','galileotelemetry.tencent.com',
    'oth.eve.mdt.qq.com','snowflake.qq.com','ts.qq.com','6ts.qq.com',
    'eve.mdt.qq.com','mdt.qq.com','ocean.qq.com',
    'digicert.com','globalsign.com','usertrust.com','comodoca.com',
    'verisign.com','catcert.net',
    'config.zhushou.sogou.com','p3p.sogou.com','ping.acc.sogou.com',
    'security.ie.sogou.com','tb.sogou.com','www.sogou.com',
    'ime.sogou.com','info.pinyin.sogou.com','p4p.so.sohu.com',
    'minisite2009.qq.com','auto.qq.com','auto.sohu.com',
    'qq.sohu.com','weixin.sohu.com','h5api.shouji.sogou.com',
    'sogoupinyin.com','sogoupinyin.compc','page.sogou',
    's.sogou.com','mbox.sogou.com','cbbs.sohu.com',
    'nei.chinaren.com','sina.com.cn',
    'sina.cn','163.com','126.com','vip.qq.com','vip.sohu.com',
    'input.shouji.sogou.com','GetLevelDataFromMobileService',
]
NO_DIAL = {
    'www.w3.org','ns.adobe.com','purl.org','schemas.xmlsoap.org',
    'schemas.microsoft.com','docs.microsoft.com','support.microsoft.com',
    'privacy.microsoft.com','msdl.microsoft.com','microsoft.com',
    'www.openssl.org','www.winimage.com','gitlab.gnome.org','mozilla.org',
    'github.com','hanyi.com.cn','www.hanyi.com.cn','symmetricom.com',
    'curl.se','www.catcert.net','aliyun.com','aliyuncs.com',
    'aipic','stats','beacon',
}

def host_no_dial(h):
    h2=h.lower()
    for s in NO_DIAL: 
        if s in h2: return True
    return False

def host_is_public(h):
    h=(h or '').strip('.').lower()
    if not h: return False
    if h in SKIP_HOST: return False
    if h.endswith(SKIP_SUFFIX): return False
    if re.match(r'^\d{1,3}(\.\d{1,3}){3}$', h): return False
    if host_no_dial(h): return False
    for s in PATCH_SUFFIXES:
        if h==s or h.endswith('.'+s): return True
    return False

def pe_sections(d):
    if d[:2]!=b'MZ' or len(d)<0x40: return None
    el=struct.unpack('<I',d[0x3c:0x40])[0]
    if el+24>len(d) or d[el:el+4]!=b'PE\x00\x00': return None
    magic=struct.unpack('<H',d[el+24:el+26])[0]
    if magic not in (0x10b,0x20b): return None
    nsec=struct.unpack('<H',d[el+6:el+8])[0]
    optsz=struct.unpack('<H',d[el+20:el+22])[0]
    so=el+24+optsz; secs=[]
    for i in range(nsec):
        r=so+i*40
        if r+40>len(d): break
        name=d[r:r+8].split(b'\x00')[0].decode('latin1','replace')
        vsize=struct.unpack('<I',d[r+8:r+12])[0]
        va=struct.unpack('<I',d[r+12:r+16])[0]
        rsize=struct.unpack('<I',d[r+16:r+20])[0]
        roff=struct.unpack('<I',d[r+20:r+24])[0]
        chars=struct.unpack('<I',d[r+36:r+40])[0]
        secs.append((name,roff,min(rsize,vsize) if vsize else rsize,chars))
    return secs

def is_upx(d):
    secs=pe_sections(d)
    if not secs: return False
    names=[s[0] for s in secs]
    return ('UPX0' in names or 'UPX!' in names)

def data_sections(d):
    secs=pe_sections(d)
    if not secs: return []
    out=[]
    for name,roff,rsize,chars in secs:
        if rsize==0 or roff==0: continue
        if chars & 0x20000000: continue
        if chars & 0x00000020: continue
        out.append((roff,rsize))
    return out

# STRICT UTF-16 host regex (no stray nulls within labels)
URL_RE_A = re.compile(rb'(?:https?|wss?|ftps?|tls)://(?:[A-Za-z0-9._\-]+@)?[A-Za-z0-9.\-_]+(?::[0-9]+)?(?:/[^ \t\x00\x0a\x0d\x22<>\\]*)?')
URL_RE_U16 = re.compile(rb'(?:h\x00t\x00t\x00p\x00s\x00?|w\x00s\x00s\x00?\x00|f\x00t\x00t\x00p\x00s\x00?)\x3a\x00\x2f\x00\x2f\x00(?:[A-Za-z0-9._\-\x00]+\x00)?(?:[A-Za-z0-9\-_]\x00)+(?:\x2e\x00(?:[A-Za-z0-9\-_]\x00)+)+(?:\x3a\x00[0-9]\x00\x00\x00)?(?:[\x20-\x7e]\x00)*')
HOST_RE_A = re.compile(rb'[A-Za-z0-9](?:[A-Za-z0-9\-_]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9\-_]*[A-Za-z0-9])?)+')
# FIXED: each label = (label_char + null)+, no stray nulls
HOST_RE_U16 = re.compile(rb'(?:[A-Za-z0-9\-_]\x00)+(?:\x2e\x00(?:[A-Za-z0-9\-_]\x00)+)+')

def scan_section(d, off, size):
    blob=d[off:off+size]
    urls, bare = set(), set()
    for m in URL_RE_A.finditer(blob):
        mm=re.match(rb'(?:https?|wss?|ftps?|tls)://([^/?#]+)', m.group(0))
        if not mm: continue
        h=mm.group(1).decode('latin1','replace').split('@')[-1].lower()
        if host_is_public(h): urls.add(h)
    for m in URL_RE_U16.finditer(blob):
        try: s=m.group(0).decode('utf-16-le','replace')
        except: continue
        mm=re.match(r'(?:https?|wss?|ftps?|tls)://([^/?#]+)', s)
        if not mm: continue
        h=mm.group(1).split('@')[-1].lower()
        if host_is_public(h): urls.add(h)
    for m in HOST_RE_A.finditer(blob):
        t=m.group(0).decode('latin1','replace').lower()
        if host_is_public(t): bare.add(t)
    for m in HOST_RE_U16.finditer(blob):
        try: t=m.group(0).replace(b'\x00',b'').decode('latin1','replace').lower()
        except: continue
        if host_is_public(t): bare.add(t)
    return sorted(urls), sorted(bare)

def scan_file(d):
    urls, bare = set(), set()
    for off,size in data_sections(d):
        u,b = scan_section(d, off, size)
        urls.update(u); bare.update(b)
    return sorted(urls), sorted(bare)

def do_replace(buf, start, old_len, new_bytes):
    nl=len(new_bytes)
    assert nl<=old_len
    buf[start:start+nl]=new_bytes
    for k in range(nl,old_len): buf[start+k]=0

def patch_section(buf, off, size):
    end=off+size; hits=0
    seg=bytes(buf[off:end])
    for m in list(URL_RE_A.finditer(seg)):
        mm=re.match(rb'(?:https?|wss?|ftps?|tls)://([^/?#]+)', m.group(0))
        if not mm: continue
        auth=mm.group(1)
        h=auth.decode('latin1','replace').split('@')[-1].lower()
        if not host_is_public(h): continue
        new=b'127.0.0.1'
        if b':' in auth and auth.count(b':')==1 and auth.rsplit(b':',1)[1].isdigit():
            new=b'127.0.0.1:'+auth.rsplit(b':',1)[1]
        if len(new)>len(auth): continue
        start=off+m.start()+len(mm.group(0))-len(auth)
        if bytes(buf[start:start+len(new)])==new: continue
        do_replace(buf, start, len(auth), new); hits+=1
    for m in list(URL_RE_U16.finditer(seg)):
        try: s=m.group(0).decode('utf-16-le','replace')
        except: continue
        mm=re.match(r'(?:https?|wss?|ftps?|tls)://([^/?#]+)', s)
        if not mm: continue
        auth=mm.group(1)
        h=auth.split('@')[-1].lower()
        if not host_is_public(h): continue
        new='127.0.0.1'
        if ':' in auth and auth.count(':')==1 and auth.rsplit(':',1)[1].isdigit():
            new='127.0.0.1:'+auth.rsplit(':',1)[1]
        nb=new.encode('utf-16-le'); ab=auth.encode('utf-16-le')
        if len(nb)>len(ab): continue
        hdr=len(mm.group(0).encode('utf-16-le'))-len(ab)
        start=off+m.start()+hdr
        if bytes(buf[start:start+len(nb)])==nb: continue
        do_replace(buf, start, len(ab), nb); hits+=1
    for m in list(HOST_RE_A.finditer(seg)):
        tok=m.group(0)
        t=tok.decode('latin1','replace').lower()
        if not host_is_public(t) or len(tok)<7: continue
        new=b'127.0.0.1' if len(tok)>=9 else b'0.0.0.0'
        if len(new)>len(tok): continue
        start=off+m.start()
        if bytes(buf[start:start+len(new)])==new: continue
        do_replace(buf, start, len(tok), new); hits+=1
    for m in list(HOST_RE_U16.finditer(seg)):
        raw=m.group(0)
        try: t=raw.replace(b'\x00',b'').decode('latin1','replace').lower()
        except: continue
        if not host_is_public(t) or len(t)<7: continue
        new_t='127.0.0.1' if len(t)>=9 else '0.0.0.0'
        new_b=new_t.encode('utf-16-le')
        if len(new_b)>len(raw): continue
        start=off+m.start()
        if bytes(buf[start:start+len(new_b)])==new_b: continue
        do_replace(buf, start, len(raw), new_b); hits+=1
    return hits

def patch_file(path):
    d=bytearray(open(path,'rb').read())
    total=0
    for off,size in data_sections(bytes(d)):
        total += patch_section(d, off, size)
    if total==0: return 0
    open(path,'wb').write(bytes(d))
    return total

def walk(root):
    for dp,dn,fn in os.walk(root):
        for n in fn:
            p=os.path.join(dp,n); yield p, os.path.relpath(p,root).replace('\\','/')

if __name__=='__main__':
    import sys
    argv=sys.argv[1:]
    cmd=argv[0]; root=argv[1]
    files=[(p,r) for p,r in walk(root) if r not in CORE_RELPATHS and os.path.splitext(r)[1].lower() in ('.exe','.dll')]
    if cmd=='scan':
        rep={}
        for p,r in files:
            d=open(p,'rb').read()
            if not pe_sections(d): continue
            if is_upx(d):
                rep[r]={'urls':[],'bare':['<<UPX>>']}; continue
            u,b=scan_file(d)
            if u or b: rep[r]={'urls':u,'bare':b}
        print(f'scan: {len(rep)} files with hits')
        for r in sorted(rep):
            print(r, rep[r])
    elif cmd=='patch':
        n=0
        for p,r in files:
            t=patch_file(p)
            if t: print(f'PATCH {r} {t}'); n+=1
        print(f'done {n}')
    elif cmd=='verify':
        rep={}
        for p,r in files:
            d=open(p,'rb').read()
            if not pe_sections(d): continue
            if is_upx(d):
                rep[r]={'urls':[],'bare':['<<UPX>>']}; continue
            u,b=scan_file(d)
            if u or b: rep[r]={'urls':u,'bare':b}
        print(f'verify: {len(rep)} residual')
        for r in sorted(rep): print(r, rep[r])
