import os, glob, struct, fcntl, ctypes, json
def ioctl_rw(fd, typ, nr, data):
    return fcntl.ioctl(fd, (3<<30)|(len(data)<<16)|(ord(typ)<<8)|nr, data, True)
nodes = {}
for path in glob.glob('/dev/video*')+glob.glob('/dev/v4l-subdev*'):
    st=os.stat(path)
    nodes[(os.major(st.st_rdev), os.minor(st.st_rdev))]=path
fd=os.open('/dev/media0', os.O_RDWR)
entities={}
idx=0
while True:
    raw=bytearray(256)
    struct.pack_into('I',raw,0,idx|0x80000000)
    try: ioctl_rw(fd,'|',1,raw)
    except OSError as e:
        if e.errno==22: break
        raise
    idx=struct.unpack_from('I',raw,0)[0]
    name=bytes(raw[4:36]).split(b'\0')[0].decode()
    pads,links=struct.unpack_from('HH',raw,52)
    major,minor=struct.unpack_from('II',raw,72)
    entities[idx]={'id':idx,'name':name,'pads':pads,'links':links,'node':nodes.get((major,minor))}
alllinks={}
for e in entities.values():
    pads=ctypes.create_string_buffer(e['pads']*20)
    links=ctypes.create_string_buffer(e['links']*52)
    raw=bytearray(struct.pack('I4xQQ4I',e['id'],ctypes.addressof(pads),ctypes.addressof(links),0,0,0,0))
    ioctl_rw(fd,'|',2,raw)
    e['pad_info']=[]
    for i in range(e['pads']):
        entity,index,flags=struct.unpack_from('IH2xI',pads.raw,i*20)
        fmt=None
        if e['node'] and 'subdev' in e['node']:
            sf=os.open(e['node'],os.O_RDWR)
            data=bytearray(88);struct.pack_into('II',data,0,1,index)
            try:
                ioctl_rw(sf,'V',4,data)
                w,h,code,field=struct.unpack_from('4I',data,8)
                fmt={'width':w,'height':h,'code':hex(code),'field':field}
            except OSError as err: fmt={'error':str(err)}
            os.close(sf)
        e['pad_info'].append({'pad':index,'flags':flags,'format':fmt})
    for i in range(e['links']):
        s,sp=struct.unpack_from('IH',links.raw,i*52)
        t,tp=struct.unpack_from('IH',links.raw,i*52+20)
        flags=struct.unpack_from('I',links.raw,i*52+40)[0]
        alllinks[(s,sp,t,tp)]={'source':entities[s]['name'],'source_id':s,'source_pad':sp,'sink':entities[t]['name'],'sink_id':t,'sink_pad':tp,'flags':flags}
print(json.dumps({'entities':list(entities.values()),'links':list(alllinks.values())},indent=2))
