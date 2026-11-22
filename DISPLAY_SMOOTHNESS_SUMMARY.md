# 显示流畅度与网络改动记录

日期：2026-11-21
设备：Xiaomi Pad 5（Nabu，SM8150）

## 显示卡顿排查

- 面板当前 DRM 模式为 1600×2560、约 120 Hz；Lipstick 使用 EGLFS/KMS，显示输出绑定到 `msm_dpu`。
- 通过 DRM/EGL 直接探测时，渲染器是 `freedreno / FD640`，说明 Adreno 640 可被硬件渲染路径使用。
- 通过设备当前 Wayland socket 建立 EGL 上下文时，渲染器变成 `llvmpipe (LLVM 20.1.2, 128 bits)`。同时出现 Mesa 无法从 Wayland 获取 DRM 设备、Zink 找不到 `libvulkan.so.1` 的日志。
- Wayland registry 暴露 `wl_shm`，但没有 `wl_drm` 或 `zwp_linux_dmabuf_v1`。Lipstick 启动日志持续报告缺少 `EGL_WL_bind_wayland_display`；QtWayland 的 EGL 客户端缓冲集成在缺少该扩展时会退出初始化，见 `source/reference/qtwayland/src/hardwareintegration/compositor/wayland-egl/waylandeglclientbufferintegration.cpp`。
- 目前最有力的解释是：Wayland 应用客户端没有走 Adreno 共享缓冲路径，渲染回退到 CPU 软件渲染；这与应用内滚动和画面卡顿相符。显示输出本身有 120 Hz 时序，不能据此认为应用也在 120 FPS 渲染。
- 一次短时进程/GPU 频率采样没有取得有效帧率数据，采样时 GPU 频率处于 257 MHz；尚未完成滚动过程的 FPS/帧时采集。
- 后续平板地址更新为 `192.168.3.46`；重新连接确认 ConnMan 在线、Lipstick 正常运行，当前 systemd-resolved 仍未运行。重连后复测结果一致：DRM EGL 为 `freedreno / FD640`，Wayland EGL 为 `llvmpipe`。
- DRM EGL 提供 `EGL_EXT_image_dma_buf_import`，但没有 `EGL_WL_bind_wayland_display`、`eglBindWaylandDisplayWL`、`eglQueryWaylandBufferWL`。因此 `QT_WAYLAND_IGNORE_BIND_DISPLAY` 只能跳过早期检查，仍无法建立当前 QtWayland 5.6 所需的 Wayland buffer 查询/导入路径。
- 当前 QtWayland 5.6 compositor 源码只有基于 `EGL_WL_bind_wayland_display` 的旧集成，没有 `linux-dmabuf` compositor 协议实现；继续方向是为 Qt 5.6 添加 dmabuf buffer 导入集成并在设备上验证，或评估兼容 Sailfish/Lipstick 的替代 compositor。

## 网络提交

- 将提交 [a9784198e3ff4ea13152a24d1ab2ae7f279d5fd4](https://github.com/sailfish-on-ginkgo/droid-config-ginkgo/commit/a9784198e3ff4ea13152a24d1ab2ae7f279d5fd4) 的 drop-in 加入 `overlay/native/usr/lib/systemd/system/systemd-resolved.service.d/resolved_inet_group.conf`，内容为 `[Service]` 与 `SupplementaryGroups=inet`。
- 重建了 `dist/sfos-nabu-native-5.3.0.15-1.aarch64.rpm`，并确认 RPM 文件清单含该 drop-in。构建脚本会从 `overlay/native` 复制配置并自动纳入 RPM。
- 平板上 `inet` 组存在，但当前 `systemd-resolved` 未运行、ConnMan 正在管理网络。因此 drop-in 会随下次安装进入系统，但不能直接解释或修复此前的息屏 Wi-Fi 断线。新 RPM 尚未安装到平板。

## 2026-11-21 网络、传感器和音量键复查

- 新地址 `192.168.3.46` 上 ConnMan 显示 online，`wlan0` 获得 `192.168.3.46/24`，默认网关为 `192.168.3.1`。最初 `/etc/resolv.conf` 指向不存在的 `/run/connman/resolv.conf`，`systemd-resolved.service` 被 `/etc/systemd/system` 中的 `/dev/null` mask；ConnMan 有尝试通过 D-Bus 请求 resolve1。
- 在平板安装上述 `inet` 组 drop-in，解除 resolved 的 mask、启动并 enable `systemd-resolved`，再将 `/etc/resolv.conf` 改为 `/run/systemd/resolve/stub-resolv.conf`。`getent` 现在能解析 `example.com` 与 `www.baidu.com`，HTTPS 请求两站均返回 HTTP 200。
- 为使重建镜像也保留修复，已更新 `scripts/configure-native.sh`：不再 mask/disable `systemd-resolved`，而是 unmask/enable，并将 resolv.conf 链接到 resolved stub。相应 Nabu rootfs/镜像构建正在运行，完成状态需再核实。
- 方向传感器：平板只枚举到 PMIC 温度 IIO 设备，没有加速度计/陀螺仪 IIO 设备。`hw-settings.ini` 将 `GSensor` 与 `Gyro` 设为 0；sensorfwd 的配置依赖 IIO adaptor，因此目前没有可供自动旋转使用的数据源。sensorfw 插件文件虽安装，但启动日志报告 orientation sensor 不可用；SLPI/hexagonrpcd 运行中仍报告不支持的 handle。仅打开设置开关不足以修复，需要先让内核/SLPI 数据进入 Linux 可用的传感器接口。
- 音量键事件设备为 `/dev/input/event1`（键码 114，音量减）和 `/dev/input/event2`（键码 115，音量加）。已监听两节点 15 秒但没有捕获按键；仍需用户按键时再采样，以区分物理事件未上报与 MCE/PulseAudio 映射问题。PulseAudio 的 MainVolume2、Nemo stream-restore 和 D-Bus 模块已运行。

## 后续

优先研究 QtWayland compositor 对 `EGL_WL_bind_wayland_display` / DMA-BUF 的支持，或评估能向客户端提供 GPU 可导入缓冲区的 compositor 路径；不要先用提高 GPU governor 频率作为修复。修复候选需在设备上重新检查 Wayland globals，并确认应用 EGL renderer 不再是 llvmpipe，再测滚动帧时间。网络方面应继续单独追踪息屏/深度休眠期间 ConnMan 与 Wi-Fi 的断连。
