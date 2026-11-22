import sys, contextlib, io, struct, os
from pathlib import Path
with contextlib.redirect_stdout(io.StringIO()):
    import importlib.util
    s=importlib.util.spec_from_file_location('probe',str(Path(__file__).with_name('camera-probe.py')))
    p=importlib.util.module_from_spec(s);s.loader.exec_module(p)
if len(sys.argv)!=2 or sys.argv[1] not in ('front','rear'):
    raise SystemExit('usage: camera-configure.py front|rear')
camera=sys.argv[1]
rear=camera=='rear'
pipe=0 if rear else 1
sensor=next(e for e in p.entities.values() if e['name'].startswith('ov13b10 ' if rear else 'ov8856 '))
names=[sensor['name'],'msm_csiphy0' if rear else 'msm_csiphy1',f'msm_csid{pipe}',f'msm_vfe{pipe}_rdi0',f'msm_vfe{pipe}_video0']
chosen={(names[1],1,names[2],0),(names[2],1,names[3],0)}
for l in sorted(p.alllinks.values(),key=lambda l: (l['source'],l['source_pad'],l['sink'],l['sink_pad']) in chosen):
    if l['flags']&2:continue
    if not (l['source']==names[1] or l['sink']==names[2] or l['source']==names[2] or l['sink']==names[3]):continue
    flags=1 if (l['source'],l['source_pad'],l['sink'],l['sink_pad']) in chosen else 0
    if flags == (l['flags']&1):continue
    print('link',l['source'],l['source_pad'],l['sink'],l['sink_pad'],'set',flags,flush=True)
    raw=bytearray(52)
    struct.pack_into('IH2xI2I',raw,0,l['source_id'],l['source_pad'],2,0,0)
    struct.pack_into('IH2xI2I',raw,20,l['sink_id'],l['sink_pad'],1,0,0)
    struct.pack_into('I',raw,40,flags)
    p.ioctl_rw(p.fd,'|',3,raw)
width,height=(1364,768) if rear else (1640,1232)
code=0x300a if rear else 0x3007
for name in names[:-1]:
    e=next(e for e in p.entities.values() if e['name']==name)
    pads=[0] if e is sensor else [0,1]
    f=os.open(e['node'],os.O_RDWR)
    for pad in pads:
        raw=bytearray(88)
        struct.pack_into('6I',raw,0,1,pad,width,height,code,1)
        p.ioctl_rw(f,'V',5,raw)
        w,h,c=struct.unpack_from('3I',raw,8)
        print(name,pad,w,h,hex(c))
        if (w,h,c)!=(width,height,code):raise RuntimeError('format mismatch')
    os.close(f)
