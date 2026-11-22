import fcntl, os, struct, subprocess, time
mcetool='/usr/sbin/mcetool'
def status():
    text=subprocess.check_output([mcetool],text=True)
    return [line.strip() for line in text.splitlines() if line.startswith(('Display state:', 'Touchscreen/Keypad lock:'))]
fd=os.open('/dev/uinput',os.O_WRONLY|os.O_NONBLOCK)
created=False
try:
    fcntl.ioctl(fd,0x40045564,4) # UI_SET_EVBIT(EV_MSC)
    fcntl.ioctl(fd,0x40045568,2) # UI_SET_MSCBIT(MSC_GESTURE)
    setup=struct.pack('80sHHHHI',b'Nabu double-tap MCE self-test',0x19,1,1,1,0)+bytes(1024)
    os.write(fd,setup)
    fcntl.ioctl(fd,0x5501);created=True
    time.sleep(2)
    subprocess.run([mcetool,'--set-doubletap-mode=show-unlock-screen','--set-doubletap-wakeup=always','--set-tklock-mode=locked','--blank-screen'],check=True)
    time.sleep(3)
    before=status();print('BEFORE',before,flush=True)
    now=time.time(); sec=int(now); usec=int((now-sec)*1e6)
    os.write(fd,struct.pack('llHHi',sec,usec,4,2,4)+struct.pack('llHHi',sec,usec,0,0,0))
    time.sleep(3)
    after=status();print('AFTER',after,flush=True)
    assert any(line.split(':',1)[1].strip()=='off' for line in before if line.startswith('Display state:')),before
    assert any(line.split(':',1)[1].strip()=='on' for line in after if line.startswith('Display state:')),after
    assert any(line.split(':',1)[1].strip()=='locked' for line in after if line.startswith('Touchscreen/Keypad lock:')),after
    print('PASS: MSC_GESTURE=4 wakes to locked screen',flush=True)
finally:
    if created:fcntl.ioctl(fd,0x5502)
    os.close(fd)
    subprocess.run([mcetool,'--blank-screen'])
