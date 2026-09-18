# -*- coding: utf-8 -*-
"""
analyze_net.py — 把 sysnet_capture.ps1 抓取的 raw.csv 分析并导出为 Excel
======================================================================
用法:
  python analyze_net.py <raw.csv> [--out out.xlsx]

功能（导出到 xlsx 多个工作表）:
  1. 总览   : 每次采样的连接数 + 时间线
  2. 进程汇总: 每个进程 -> 连接次数 -> 目标列表（可排序筛选）
  3. 目标汇总: 每个远程服务器 -> 连接次数 -> 涉及的进程
  4. 可疑标记: 搜狗/腾讯系 IP 段自动标红 + 独立"搜狗连接"页
  5. 明细    : 全部原始记录（带时间）

不写 hosts、不碰防火墙；纯离线分析。
依赖: pandas, openpyxl (pip install pandas openpyxl)
"""
import sys, re, argparse
from collections import defaultdict
import pandas as pd

SOGOU_RANGES = [
    ('116.130.0.0/16', '搜狗/搜狐自有CDN'),
    ('123.125.0.0/16', '搜狗/百度CDN段'),
    ('123.6.0.0/16',  '搜狗下载节点(联通)'),
    ('220.194.0.0/16','搜狗/百度CDN段'),
    ('111.206.0.0/16','搜狗/百度CDN段'),
    ('218.61.0.0/16', '搜狗节点(东北联通)'),
]

def ip_in_cidr(ip, cidr):
    net, bits = cidr.split('/')
    bits = int(bits)
    def to_int(s):
        return sum(int(o) << (8 * (3 - i)) for i, o in enumerate(s.split('.')))
    m = (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF
    return (to_int(ip) & m) == (to_int(net) & m)

def classify(ip):
    for cidr, label in SOGOU_RANGES:
        if ip_in_cidr(ip, cidr):
            return ('SOGOU', label)
    # 常见非搜狗分类（粗）
    if ip.startswith(('4.145','4.150','4.152','20.','40.','52.','13.','51.','111.221','134.33')):
        return ('MS', 'Microsoft')
    if ip.startswith(('23.','72.153','104.110','150.171','74.226','23.46','23.49','23.55','23.194')):
        return ('CDN', 'Akamai/微软CDN')
    return ('OTHER', '其他/待确认')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('raw')
    ap.add_argument('--out', default='')
    args = ap.parse_args()

    df = pd.read_csv(args.raw, dtype=str)
    df['remote_addr'] = df['remote_addr'].fillna('')
    # 拆 ip:port
    rp = df['remote_addr'].str.rsplit(':', n=1, expand=True)
    df['remote_ip'] = rp[0]
    df['remote_port'] = rp[1]
    df['cls'] = df['remote_ip'].apply(lambda x: classify(x)[0])
    df['cls_label'] = df['remote_ip'].apply(lambda x: classify(x)[1])

    out = args.out or args.raw.replace('.raw.csv', '_analysis.xlsx')
    writer = pd.ExcelWriter(out, engine='openpyxl')

    # 1) 总览
    ov = df.groupby('sample_time').size().reset_index(name='conn_count')
    ov.to_excel(writer, sheet_name='总览-时间线', index=False)

    # 2) 进程汇总: 进程 -> 总次数, 独立目标数
    proc = df.groupby(['process_name','remote_ip','remote_port','state']).size().reset_index(name='count')
    proc_pivot = proc.groupby(['process_name','remote_ip','remote_port'])['count'].sum().reset_index()
    proc_sum = proc_pivot.groupby('process_name').agg(total=('count','sum'), targets=('remote_ip','nunique')).reset_index()
    proc_sum = proc_sum.sort_values('total', ascending=False)
    proc_sum.to_excel(writer, sheet_name='进程汇总', index=False)

    # 3) 目标汇总
    tgt = proc_pivot.groupby(['remote_ip','remote_port']).agg(total=('count','sum'), procs=('process_name', lambda s: ','.join(sorted(set(s))))).reset_index()
    tgt['cls'] = tgt['remote_ip'].apply(lambda x: classify(x)[0])
    tgt['cls_label'] = tgt['remote_ip'].apply(lambda x: classify(x)[1])
    tgt = tgt.sort_values('total', ascending=False)
    tgt.to_excel(writer, sheet_name='目标汇总', index=False)

    # 4) 可疑标记: 搜狗连接
    sog = df[df['cls'] == 'SOGOU']
    if len(sog):
        sog.to_excel(writer, sheet_name='搜狗连接(可疑)', index=False)
    else:
        empty = pd.DataFrame({'note': ['0 条搜狗/腾讯系连接']})
        empty.to_excel(writer, sheet_name='搜狗连接(可疑)', index=False)

    # 5) 明细
    df[['sample_time','local_addr','remote_addr','state','pid','process_name','remote_ip','remote_port','cls','cls_label']].to_excel(
        writer, sheet_name='明细', index=False)

    writer.close()
    print(f'OK -> {out}')
    print(f'  总记录 {len(df)}, 独立进程 {df["process_name"].nunique()}, 独立目标 {df["remote_ip"].nunique()}')
    print(f'  搜狗/腾讯系连接: {len(sog)} 条')
    if len(sog):
        for _, r in sog[['sample_time','process_name','remote_addr','state']].drop_duplicates().head(20).iterrows():
            print(f'    {r["sample_time"]} {r["process_name"]} -> {r["remote_addr"]} {r["state"]}')

if __name__ == '__main__':
    main()
