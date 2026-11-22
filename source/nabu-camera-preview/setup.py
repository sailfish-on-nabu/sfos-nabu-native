#!/usr/bin/python3
import subprocess
import time
from nabu_camera import MediaGraph

for module in ('qcom_camss', 'i2c_qcom_cci', 'ov13b10', 'ov8856', 'cn3927'):
    subprocess.run(['/sbin/modprobe', module], check=True)
deadline = time.monotonic() + 25
last_error = None
while time.monotonic() < deadline:
    graph = None
    try:
        graph = MediaGraph()
        graph.configure('rear')
        graph.configure('front')
        break
    except (OSError, StopIteration, TypeError) as exc:
        last_error = exc
        time.sleep(0.25)
    finally:
        if graph:
            graph.close()
else:
    raise SystemExit(f'Camera initialization failed: {last_error}')
