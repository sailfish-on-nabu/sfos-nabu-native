# Sailfish OS 5.3.0.21 for Xiaomi Pad 5

面向 nabu 的原生持久化安装镜像。Android bootloader 装载 SM8150 主线内核，initramfs 将带有 `SFOS_ROOT` 标签的 ext4 根文件系统挂载为可写，随后直接启动 Sailfish 的 systemd。`/home` 和系统文件保存在同一个根文件系统中。

图形配置参考 Sailfish on Don't Be Evil 的 PineTab2 适配。Lipstick 使用 Qt EGLFS/KMS，应用通过 Lipstick 的 Wayland 服务显示，应用端 Qt 平台使用 `wayland`。Mesa 库采用已验证可解析依赖的 Ubuntu arm64 构建，随原生 RPM 安装在 `/usr/lib/sailfish-native`。

## 镜像文件

`dist/` 成品已于 2026-11-22 按当前源码重建，版本号保持 `5.3.0.21`。
本次包含原生相机及拍照、SSC 加速度/方向桥接、扬声器高通滤波、
铃音试听控制，以及匹配的新内核、模块和 initramfs。
双击唤醒实验代码及配置也已打包，但最新真机测试仍未实现唤醒。

SHA256、ext4、sparse/raw 一致性、启动镜像内容及 107 个适配文件的
比对已通过，结果见 `dist/validation.json`。新镜像尚未进行真机启动
或 QEMU 开机验证。后文调试记录中的“镜像尚未重建”描述记录当时的状态；
当前成品内容以本节及最新验证记录为准。

- `dist/sailfish-5.3.0.21-nabu-rootfs.sparse.img` 用于 fastboot 写入 userdata。
- `dist/sailfish-5.3.0.21-nabu-rootfs.img` 是同一文件系统的 raw ext4 镜像，用于检查或直接块设备写入。初始容量为 4 GiB，首次启动扩展到所在分区的容量。
- `dist/sailfish-5.3.0.21-nabu-boot.img` 使用 Android header v0，包含内核、追加的 nabu DTB 和安装版 initramfs。
- `dist/sailfish-5.3.0.21-nabu-boot-v3.img` 与 `dist/sailfish-5.3.0.21-nabu-vendor_boot-v3.img` 配套，其中 DTB 位于 vendor_boot。
- `dist/package-audit.json` 核对参考包版本、排除包和新增原生组件。
- `dist/validation.json` 记录本次成品的验证结果及限制。
- `dist/SHA256SUMS` 包含本次成品的校验值。

此前的 Live 镜像文件保存在 `dist/legacy-live/`。

## 安装

需要已解锁的 nabu。写入 userdata 会覆盖其中的数据，应先备份需要保留的内容。安装版 rootfs 需要配套使用本次生成的 boot，启动查找标签为 `SFOS_ROOT`。

```bash
cd /home/bird/data/sfos_aarch64/dist
sha256sum -c SHA256SUMS
fastboot flash userdata sailfish-5.3.0.21-nabu-rootfs.sparse.img
```

继续使用你已经在真机上验证能启动的同一种 boot 格式。v0 方案的命令如下。

```bash
fastboot flash boot sailfish-5.3.0.21-nabu-boot.img
fastboot reboot
```

v3 方案使用配套的两个文件。

```bash
fastboot flash vendor_boot sailfish-5.3.0.21-nabu-vendor_boot-v3.img
fastboot flash boot sailfish-5.3.0.21-nabu-boot-v3.img
fastboot reboot
```

本次安装沿用已成功启动时的 dtbo 配置。启动参数与内核来源保存在 `inputs/`，构建流程保持 Android bootloader。

## 登录和诊断

用户为 `defaultuser`，初始密码为 `live`。管理员通过 `devel-su` 提权，初始 root 密码为 `live`。安装后可运行 `passwd`，再通过 `devel-su passwd` 修改管理员密码。SSH 开放给默认用户。

```bash
ssh defaultuser@DEVICE_IP
devel-su
findmnt /
df -h /
systemctl status nabu-grow-root connman mce
journalctl -b -u nabu-display-config
journalctl -b _COMM=lipstick
ls -l /dev/dri
```

Wi-Fi 由 Sailfish ConnMan 直接管理，可在系统设置中连接，也可以在管理员终端运行以下命令。

```bash
connmanctl enable wifi
connmanctl scan wifi
connmanctl services
connmanctl
```

进入交互界面后启用 `agent on`，再使用 `connect` 和扫描到的服务标识连接。

USB 使用 configfs 和 usb-moded，预置 ECM 网络与 MTP 功能。USB 模式、Wi-Fi、音频、传感器、触摸、休眠和图形输出需要这版系统的 nabu 真机验证。

## 构建

源码仓库为 `sailfish-on-nabu/sfos-nabu-native`，内核位于
`sailfish-on-nabu/linux-nabu-native` 的 `native` 分支。内核和上游参考源码
通过 Git 子模块固定到提交；首次下载应包含子模块：

```bash
git clone --recurse-submodules https://github.com/sailfish-on-nabu/sfos-nabu-native.git
cd sfos-nabu-native
```

已有检出可运行 `git submodule update --init --recursive`。源码提交包含
原生适配、相机、音频、传感器、双击唤醒实验和构建输入配置；生成的
`dist/` 镜像、编译产物、设备备份与 `work/` 调试日志保留在本地。
`config/patches/` 保存构建时应用的上游补丁。

构建仍依赖 `inputs/sailfish-rootfs.json` 指定的本地 Sailfish 基础归档，
基础软件归档和下载认证没有包含在源码仓库中。下文的本机路径描述当前
构建环境；在其他机器上构建时需要准备相同输入并调整相应路径。

```bash
./build.sh
```

镜像版本由 `config/image-version` 指定，当前为 `5.3.0.21`；系统版本信息、登录提示、原生 RPM 和成品名称使用此值。基础 Sailfish 软件包沿用已验证的 `5.3.0.15` 归档，SSU 软件源保持该基础版本；`/etc/sailfish-native-image-release` 记录镜像版本和基础版本。

默认临时目录为 `/home/bird/data/tmp/sfos-aarch64`。下载、RPM 构建、根文件系统、内核编译和测试磁盘均放在这里。成品位于本项目 `dist/`。Ubuntu 工具根目录仅用于准备 Mesa 和早期启动工具。

内核基于 `Kumar-Jy/linux` 的 `sm8150/7.3.y` 分支，当前修改保存在 `sailfish-on-nabu/linux-nabu-native` 的 `native` 分支。基础配置采用 `sm8150_defconfig`，`config/kernel-nabu.config` 内包含面板内建、Sailfish 所需 memory cgroup v1、配额通知及 QEMU 测试设备支持。更改该配置会触发内核重建。

Sailfish 初始文件来自本机 5.3.0.15 nabu 归档。775 个参考组件中排除 46 个 Android 适配包，保留 729 个原版本组件，新增 Mesa 通用运行库 RPM、nabu 原生适配 RPM 和与发行版 Qt 匹配的 EGLFS 插件，共 732 个组件。安装及构建执行 RPM 依赖检查。

原生适配 RPM 包含内核模块、nabu 固件、ALSA UCM、EGLFS 配置、USB 配置、设备标识和首次扩容服务。独立发布新的内核时，还需要更新匹配的 boot 镜像。当前适配包由本地构建提供。

## 参考实现

参考仓库保存在 `source/reference/`，具体提交记录在 `inputs/native-reference-repositories.json`。

- https://github.com/sailfish-on-dontbeevil/droid-config-pinetab2
- https://github.com/piggz/droid-hal-configs 的 native 分支
- https://github.com/sailfish-on-dontbeevil/pinephonepro-image-maker

使用了原生 EGLFS/KMS、通用系统配置和首次扩容的实现思路。nabu 的内核、固件、显示参数和 Android 启动格式使用本机目标配置。

## 验证范围

```bash
bash scripts/test-installed-qemu.sh
```

本次 5.3.0.21 构建检查原生 RPM 版本及依赖、ext4 文件系统、SHA256、sparse/raw 一致性和镜像内配置。按用户要求，本次不进行 QEMU 验证。此前的 QEMU 开机与持久性记录保存在旧版验证资料中；可选测试脚本使用独立 qcow2 写入层和 127.0.0.1:2227 SSH 转发。新镜像的首次设置与完整应用流程仍需真机验证。

当前产物处于原生适配阶段。此前 Live 版的真机开机结果不能代替这一版的图形、外设和稳定性验证。

## 无线、背光与传感器适配

nabu 使用 WCN3990 Wi-Fi，驱动为 `ath10k_snoc`。镜像补入独立的 `ath10k/WCN3990` 和 `qca` 固件，解压成自包含文件，包含 WCN3991 蓝牙所需的 QCA 文件。模块加载配置包含 Qualcomm remoteproc、QRTR、PD mapper、FastRPC、ath10k_snoc 和 HCI UART。`tqftpserv` 提供 DSP 固件传输。

`/usr/share/csd/settings.d/hw-settings.ini` 声明背光、显示、Wi-Fi、蓝牙等设备能力，供系统设置查询。背光能力标记用于显示息屏时间选项。实际亮度和息屏行为需要真机核验。

传感器位于 SLPI/SSC。`nabu-hexagonrpcd.service` 为传感器 DSP 提供配置与可写 registry。新的 `nabu-accelerometer.service` 通过 QRTR/SSC 读取真实加速度并发布 evdev 设备，SensorFW 使用该设备计算方向，Qt 的 Sensors.conf 声明对应后端。该桥接已安装到调试设备，Qt 客户端已成功读取方向；相机按钮随设备转动已由用户确认。陀螺仪和光线传感器尚未接入。当前发布镜像尚未包含这一更新。

若 Wi-Fi、蓝牙或传感器仍异常，可在管理员终端执行以下命令，将日志复制回电脑。

```bash
collect-nabu-hardware > /home/defaultuser/nabu-hardware.log 2>&1
```

## 2026-11-21 真机调试补充

SSH 真机调试确认 Wi-Fi 需要 RMTFS 服务与 modem 子系统启动。加入 `nabu-rmtfs.service`，使用 `rmtfs -r -P -s` 以只读底层分区、内存写入影子的方式提供 EFS。运行后出现 wlan0，ConnMan 扫描列出周边网络，并报告连接到 Jane2020。网络密码由用户现有配置处理。

蓝牙解除软件阻塞后，BlueZ 扫描发现 12 个附近设备，配对和音频链路尚未验证。

“关于设备”通过 SSU 识别厂商和型号。补入 `/etc/hw-release` 的 `MER_HA_DEVICE=nabu` 后，真机 SSU 能识别 Xiaomi Pad 5。`nabu-bluetooth-address.service` 从 BlueZ 读取内建控制器当前地址，写入设置应用使用的 `/var/lib/bluetooth/board-address`；已确认默认用户可读此文件，配对数据目录仍为 `0700`。这两项已应用于真机并同步到构建源码。

MCE 需要明确配置 `/sys/class/backlight/ktz8866-backlight`，已实测亮度调整及息屏为 0、亮屏恢复。

SLPI 固件会写入传感器 registry，原 HexagonRPC 只读实现使初始化失败。构建应用上游 PR 27 的文件写入支持补丁，并让传感器文件服务在成功退出后也自动重启。真机观察期内未再复现此前的 SLPI 周期性崩溃。SSC 到 SensorFW 的实际传感器数据接口尚未完成。

本节硬件修正已应用到调试中的平板并同步到构建源码。随后已重新构建发布镜像，当前 rootfs 包含本节修正及音量控制配置；真机硬件结果保存在 `dist/physical-debug-2026-11-21.json`。

扬声器无声的问题已在真机修复。适配包先前仅包含 nabu 专用 UCM，缺少 ALSA 的顶层 ucm2/ucm.conf 和 ucm2/lib/generic.conf，导致 PulseAudio 无法创建声卡配置并回退到伪输出。补入与系统 ALSA 1.2.13 对应的公共配置后，已出现 HiFi Speaker 输出和 Mic 输入。两秒低音量测试期间 PCM 为 RUNNING，用户确认听到声音。公共配置及许可证已加入构建输入，麦克风录音和蓝牙音频尚未测试。

随后用户报告 USB 插入时扬声器出现很大噪音。SSH 检查发现原生 PulseAudio 未加载 `module-dbus-protocol`，ngfd 和 Lipstick 持续无法访问音量控制 D-Bus 接口。已在真机加载模块并增加 `/etc/pulse/default.pa.d/90-nabu-dbus.pa`，对应配置已同步到 overlay；ngfd 的周期性连接报错停止。输出音量暂从 30% 降至 15%。本次未播放测试音或重现插线噪音，不能据此认定爆音原因或已经修复。

音量键和声音设置滑块还需要 `module-meego-mainvolume` 的 MainVolume2 接口、Nemo stream-restore 及参数服务。增加 `95-nabu-volume.pa`、固定 speaker 参数模式、`route-entry.table` 和 `stream-restore.table`，初始化可用的媒体及通话音量代理。仅加载主音量模块而不初始化代理会在修改档位时触发 PulseAudio 的 channels 断言，因此这些配置必须配套部署。真机重启音频服务后，通过虚拟输出上的静音 PCM 流验证档位 2→3→2 对应流音量约 11%→16%→11%，未使用实体扬声器。关闭继承配置中的 flat-volumes，防止播放流自动抬高总音量；测试期间实体扬声器总音量保持 15%。设置滑块及有声播放仍需用户确认，音量接口修复不能代替爆音验证；音量键的后续真机结果见下文。
设备树把音量加键放在 `gpio-keys`，音量减键则由独立的 `pm8941_resin` 输入设备上报；MCE 已配置两者为 `VOLUME_KEYS`。用户实测仅补充该分类后，按键仍未触发界面响应。

继续检查发现原生运行包缺少 `/etc/dbus-1/system.d/ohm-policy.conf`，真机 OHM 日志报告资源协议 D-Bus 初始化失败，`org.maemo.resource.manager` 未注册。Lipstick 只有取得 `ScaleButton` 资源后才处理音量键。已将配置加入 runtime overlay 和 RPM 清单，并直接安装到 `192.168.3.46`：重载 D-Bus 配置、重启 OHM 与 Lipstick 后，资源管理器已注册，桌面及音频服务正常。配置备份位于设备的 `/var/tmp/nabu-volume-fix.aaB5pR`，本次记录在 `/home/bird/data/tmp/sfos-aarch64/logs/volume-policy-20261121/`，用户随后确认音量按键恢复，记录同时捕获了音量加、音量减的按下和释放事件。该 OHM 配置已纳入 5.3.0.21 发布镜像。

按用户要求，源码中的 `[FeatureHybris] LightSensor` 已设为 `true`；真机配置原本已是 `true`。该开关允许 MCE 使用 Hybris 光线接口，SSC 到 SensorFW 的数据接口仍需独立完成，不能据此认定自动亮度已经工作。

Wi-Fi 日志记录到多次 `PM: suspend entry (deep)` 紧接本地主动断开（reason 3），ConnMan 同时报 WoWLAN 设置失败（-22）。当前普通亮屏超时为 3600 秒，但锁屏息屏超时另为 10 秒。为隔离休眠问题，真机暂设 `mcetool --set-suspend-policy=disabled`；45 秒实际息屏测试期间 SSH 保持连接，没有新增深度休眠或 Wi-Fi 断开记录，WoWLAN 错误仍存在。该临时策略增加待机耗电，未写入镜像默认配置；恢复命令为管理员执行 `mcetool --set-suspend-policy=enabled`。本次日志在 `/home/bird/data/tmp/sfos-aarch64/logs/usb-wifi-audio-20261121/`。旧镜像此前通过文件系统、SHA256 和 QEMU 启动检查；音量键在后续真机补装 OHM 配置后已恢复；设置滑块和 USB 插入噪音仍待平板上核验，OHM 配置与 LightSensor 开关已纳入 5.3.0.21 镜像。

## Wi-Fi MAC 持久化修正

WCN3990 固件没有提供有效的硬件 MAC，驱动日志报告 `invalid MAC address; choosing random`，每次启动生成的新地址会改变 ConnMan 网络标识。`nabu-wifi-mac.service` 在 udev 初始化前准备固定地址：首次安装从 SoC 序列号生成本地管理单播地址，并保存至 `/var/lib/nabu/wifi-mac-address`；已有系统可以通过 `nabu-wifi-mac --seed-current` 保存当前地址，以继续匹配现有网络配置。每次启动生成 `/run/systemd/network/10-nabu-wifi.link`，在接口启用时指定该地址。

ConnMan 还需要等待 `sys-subsystem-net-devices-wlan0.device`，以免在 udev 设置固定地址前缓存驱动随机地址。该排序由 `connman.service.d/95-nabu-wifi-mac.conf` 提供。真机再次重启后已确认 MAC 保持不变，ConnMan 使用固定地址作为服务标识，并自动恢复此前保存的 Wi-Fi 连接。相关证据保存在 `/home/bird/data/tmp/sfos-aarch64/logs/wifi-mac-20261121/`，本次修正均已纳入 5.3.0.21 镜像。

## 下拉菜单音效与低音量噪声

真机下拉菜单无声时，general 情景的 `touchscreen.sound.level` 为 0；设为低档 1 后，用户确认音效恢复，但伴有明显沙沙声。ngfd 增加 PulseAudio 启动依赖，避免在音频服务尚未就绪时连接 libcanberra。

FFmemless 配置采用用户提供的[菜单反馈修正](https://github.com/sailfish-on-nabu/droid-config-nabu/commit/230f4afa317c9c7b9662b8a3e9a2386014773755)，补上分开的 drag_boundary、drag_end 效果，并使用 rumble 效果参数。此前的 [droid vibrator 插件](https://github.com/mer-hybris/ngfd-plugin-droid-vibrator) 面向 Android HAL 或原生 sysfs 震动控制，不能直接替代当前系统的声音播放链路。

静音 PCM 保持声卡运行的对照测试未改善杂音。已捕获的 PCM 对应部分与原音效一致，没有削波；24 位输出测试无声，已恢复 16 位格式。将原来的低音量软件衰减部分移入四个 CS35L41 的硬件数字音量后，用户确认杂音明显减少。UCM 设置四路 Digital PCM Volume 为 529（−36 dB），`nabu-audio-volume.service` 首次初始化 Speaker 软件音量为 39134，综合增益约 −49.44 dB。后续用户音量调整仍由 PulseAudio 保存。设备重启音频服务后，硬件与软件配套值仍正确；记录不声明杂音完全消除。

这组修正已部署到调试设备并同步到源码，当前发布镜像尚未重打包。诊断、捕获音频和服务重启证据位于 `/home/bird/data/tmp/sfos-aarch64/logs/menu-feedback-20261121/`。

## 原生相机调试

旧内核未启用 OV13B10 后摄、OV8856 前摄和 CN3927 对焦器驱动。与设备当前内核匹配的三个模块已安装到调试设备；加载后出现完整 CAMSS 媒体图。前后摄均成功连续取得 5 帧 packed RAW10，所需选项已补入 `config/kernel-nabu.config`。

Jolla 相机原先通过自动视频源尝试打开编解码器节点 `/dev/video0`，失败后显示 GStreamer 测试色条。实验性的 RAW10 → RGB 源已让相机读取真实传感器，前后摄 RGB 管线测试也已通过。初版用户看到黑灰界面，进一步发现图像偏暗和 Qt 显示层启动超时。

预览源将 caps 协商移到启动返回之后，补入亮度曲线、模拟增益反馈和白平衡。用户已确认前摄画面恢复。当前 0.6 版进一步提高曝光亮度，改用较亮的中性区域估算白平衡，并对颜色较淡的区域增强色度。用户确认 0.5 版明显改善后，最后的小幅增艳已按请求应用；0.6 版连续 60 帧测试通过。

反复启动相机时的 CCI 首次传输超时也已在内核模块中加入恢复处理，OV8856 每次启动重新检查通信。两个模块已安装到设备；使用正常的自动运行时休眠，三次关闭、等待两秒、重新捕获均通过。当前临时打开的是前摄预览。

源码和说明位于 `source/nabu-camera-preview/`，调试证据位于 `work/logs/camera-20261121/`。0.11 版插件和 Qt 相机枚举桥接库已安装到设备，用户已确认镜头切换和拍照按钮恢复。前后摄均通过 Qt 后端实际拍摄和 JPEG 保存测试；后摄白平衡根据实测数据修正了初始绿色偏色。首帧通知拍摄就绪，拍摄帧发送曝光事件，让原有界面触发快门声和拍后动画；拍后动画已由用户确认恢复，普通模式的系统声音级别已从 0 恢复到默认值 1。原生预览仅校正安装角度并裁剪填充；后摄使用保留完整视野的 2104×1560 合并模式，输出 1052×780，并接入 CN3927 中心对比度对焦。完整尺寸模式因用户报告延迟已改为合并模式，积压时丢弃旧帧。用户已确认画面与旋转正常。快门提示音改为 160 毫秒短双音，清除旧声音缓存。模拟增益重配试验因声音设置播放回归已撤回，设备与源码恢复数字音量 529、模拟音量 6。声音恢复情况和新快门音听感待确认。

开机媒体图初始化服务已启用。普通相机图标使用单实例 Qt 启动路径，Sailjail 保持启用。系统加速度与方向桥接也已接入源码及设备，Qt 客户端已能读取方向。原生 RPM 构建包含相机插件、Qt 桥接库、SSC 桥接及其配置和服务。安装证据位于 `work/logs/camera-install-20261121/` 和 `work/logs/camera-sensors-20261121/`。当前发布镜像尚未重建，未进行整机重启验证，也没有使用 QEMU。

## 扬声器备用配置（2026-11-21）

设备 192.168.3.241 出现 auto_null：HiFi 播放端可打开，但 Mic 的 DSP SLIMBUS_0_TX 在 prepare 时返回 -114，导致整套 HiFi 被 PulseAudio 丢弃。增加独立 Speaker UCM 备用用例，保留原 HiFi 和麦克风配置；已部署真机，音频服务重复启动后真实扬声器输出保持可用。四路数字音量 529、模拟音量 6，软件音量 39134；初始化脚本兼容备用输出名称。麦克风 DSP 故障仍未解决，实际声音和杂音程度待用户核验。镜像尚未重建。

后续 Jolla 铃声试听：用户报告 39134 软件电平时音乐大多为噪音，降至 9830 后主体正常但重低音仍有杂音。PulseAudio monitor 捕获为连续 PCM（48 kHz、16 位，无削波），不能据此证明 DSP/功放输出正确。关闭 mmap 改 RW 未解决，已恢复原传输方式。模拟增益 6→0、数字增益 529→577 的等增益对照无明显改善，已恢复 6/529。初始化脚本默认软件电平改为 9830，保留既有音量保存机制。低频失真仍在定位，尚不能宣称完全修复。

Jolla 铃声 15–35 秒 A/B：用户确认 200 Hz 二阶高通版本的杂音明显改善。新增原生 LADSPA 高通及 nabu-speaker-filter 用户服务，已部署真机并验证重启音频服务后默认输出为 nabu_speaker，实际硬件与滤波输出共享音量均为 9830。该措施削弱低音，是规避而非根因修复；完整铃声和系统音效仍待用户复测。源文件未改，蓝牙输出不经过该滤波。实现、响应测试和撤回方式见 source/nabu-audio/README.md。原生 RPM 构建脚本已包含插件，发布镜像未重建。

铃声试听音量修正：声音选择页 PreviewPlayer.qml 的 Audio 原先固定满音量，播放流未标注铃声角色，不会跟随 ringing.alert.volume。为该试听组件绑定 ProfileControl 的铃音音量（采用 PulseAudio 三次方幅度曲线）和静音情景，不改变滤波器或全局扬声器上限。已部署并在真机 Qt QML 实例验证 0/50/100% 的 volume 为 0/0.13/1，0% 和 silent 均 muted；实际 x-ringtone-volume 接口对应 0/32768/65536。测试后恢复 general、40%，降噪默认输出和 15% 主音量保留。用户需关闭并重新打开设置加载 QML。证据位于 work/logs/audio-music-20261121/preview-volume/，发布镜像未重建。

用户确认低频滤波与铃音滑块修正可用，但响度不足；后续把滤波/硬件共享主音量由 9830（15%）提高至 19661（30%），保留四路数字音量 529、模拟音量 6。初始化默认值及滤波启动上限同步调整，已部署并读回确认，铃音滑块和静音绑定不变。新档位的响度及低音杂音仍待听感反馈。

30% 最大铃音仍被报告破音，已将启动默认及上限回退到 15%。继续检查确认 TDM 总线 32 位时隙与 CS35L41 ASP_WIDTH_RX=24 不一致；增加仅针对 nabu QUATERNARY_TDM_RX_0 的 prepare 修正，将 ASP_WIDTH_RX 置 32，保留 ASP_RX_WL=24。测试模块已临时加载，四路寄存器验证为 0x20180200 / WL 0x18，正在以 30% 对照原有 Jolla 片段。尚未获得听感结论，不能声明该实验修复根因。设备磁盘上的原内核模块未覆盖，源代码候选备份和实验模块保存在 work/logs/audio-music-20261121/；镜像未重建。

时隙宽度实验被用户确认无声，已撤回源代码改动、恢复本地模块构建产物，并在设备重新加载磁盘上的原模块；寄存器恢复 0x18180200 / WL 0x18。用户确认恢复有声。32 位接收时隙假设未通过试听，不能作为可用修复。当前启动上限仍为 15%。继续以离线 200 Hz 高通 + -18.06 dBFS 限峰片段，在 30% 共享主音量下做短暂对照，播放结束恢复 15%；该限峰方案尚未应用于系统。

用户未听到离线限峰对照，因恢复到 15% 后感觉设置试听更小；限峰方案没有得到听感验证，也未安装进实时链路。检查时铃音情景为 general、铃音滑块 60%，共享主音量 15%。当前将共享主音量改为中间档 13107（20%），初始化及启动上限同步；不再自动播放或在试听后回退。原驱动、200 Hz 高通和铃音/静音绑定保留。20% 下最大铃音的失真与响度尚待用户在设置中确认。

用户确认共享主音量 20%、铃音滑块当前档干净，读回铃音为 80%。据此将共享主音量校准为 10400（显示约 16%），铃音改为 100%；考虑 Qt 试听音量舍入，新最大档比此前干净档约低 0.18 dB。初始化及滤波启动上限同步更新并部署，已读回物理/滤波输出均 10400、general 情景铃音 100%。不自动播放，待用户在设置中复测最大档。保留原驱动、200 Hz 高通及铃音/静音绑定；限峰方案未安装，仍不能宣称根因修复。

## 原生双击唤醒适配（待真机验证）

已按本地 nabu 原厂驱动协议实现 NT36523 双击手势解码、0x13 低功耗手势入口、显示/触控同步及 TDDI 保电、系统休眠 IRQ 唤醒配对和 MCE 锁屏唤醒事件。完整测试内核、匹配触屏模块及临时启动镜像已构建；解析器 sanitizer 测试、boot 重打包一致性检查和 MCE 合成手势锁屏唤醒测试通过。原 boot_a 已完整备份，未刷写分区，发布镜像未改。设备已安装条件启动服务，旧内核缺少接口时自动跳过。需 USB 转接虚拟机后以 fastboot 临时启动，实体双击、功耗和深度休眠唤醒均未验证；仍保留此前禁用自动休眠的策略。实现、构建和撤回说明见 source/nabu-doubletap/README.md，证据在 work/logs/doubletap-20261121/。

双击唤醒后续：已通过 USB fastboot 临时启动测试内核，正常触控由用户确认可用，boot 分区仍未刷写。初次实体测试用户反馈无可见唤醒，曾捕获一次原生 gesture 4 和短暂 MCE ON，尚不能认定成功。按用户提供的 ginkgo 提交补齐 MCE [DoubleTap] ControlPath、默认模式和 udev 链接；已在真机验证 MCE never/always 实际把驱动开关置 0/1。运行中的 v4 触屏模块修正了重复启用及息屏 GPIO/PDC 唤醒配对，测试镜像同步更新；配置补齐后的实体唤醒仍待反馈，未更换触屏固件。
