# nabu SSC 加速度桥接

ssc-accelerometer.py 使用标准 Python 库和 Linux QRTR、uinput 接口读取真实传感器数据。它动态查找 QRTR 服务 400，查询默认 accel 的 SUID，以 10 Hz 订阅连续报告，将 m/s² 转成 SensorFW evdev 适配器所需的 milli-g，并发布 /dev/input/nabu-accelerometer。

nabu-accelerometer.service 在真实数据和 udev 设备准备完成后通知 systemd，再启动 SensorFW。SensorFW 的 accelerometeradaptor 读取这一设备，orientationchain 计算方向；QtProject/Sensors.conf 为 Qt 加速度和方向接口选择 SensorFW 后端。配置中仅声明已接入的加速度和方向能力。

QRTR 服务发现、SUID 查询、加速度样本、uinput 设备、SensorFW 方向接口及 Qt 方向读取均已在设备上验证。用户已确认相机按钮随设备转动。整机重启及休眠续接尚未验证。日志位于 work/logs/camera-sensors-20261121/。

协议参考来自 [libssc](https://codeberg.org/DylanVanAssche/libssc)、[python-ssc 的协议描述](https://github.com/1337Misom/python-ssc/tree/main/python_ssc/protobufs/src) 和 [qsnsd 的 QMI 描述](https://github.com/kcxt/qsnsd/blob/master/qmi_sns.qmi)。SensorFW 配置依据其 [evdev 加速度适配器](https://github.com/sailfishos/sensorfw/tree/master/adaptors/accelerometeradaptor)。桥接自行编码和解析协议，不依赖 GI、libqmi 或 protobuf 运行库。
