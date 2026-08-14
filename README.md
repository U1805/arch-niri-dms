本配置方案基于 [ShorinWiki](https://github.com/SHORiN-KiWATA/Shorin-ArchLinux-Guide/wiki/%E4%B8%80%E9%94%AE%E9%85%8D%E7%BD%AE%E6%A1%8C%E9%9D%A2%E7%8E%AF%E5%A2%83) 修改

---

## 0. 从启动盘开始

下载 Arch Linux 的 ISO，放进 Ventoy。

开机时按 `F12` 进入启动项，选择 U 盘，然后：

```bash
boot in normal mode
```

进入 archlive 环境。

> `ls /sys/firmware/efi/efivars` 确认 UEFI Firmware。

------

## 1. 联网。

```bash
iwctl
device list
station wlan0 scan
station wlan0 get-networks
station wlan0 connect XXX
exit
```

测试一下：

```bash
ping -c 3 bilibili.com
```

能 ping 通，继续。

这里的 `wlan0` 不是绝对的。
如果机器上的网卡名字不一样，要以 `device list` 显示的为准。

------

## 2. 时间

检查时间同步：

```bash
timedatectl
```

重点看：

```text
NTP service: active
```

它会影响密钥、软件源、证书、同步。

------

## 3. 换镜像源

安装前先更新镜像列表：

```bash
reflector -a 12 -c cn -f 10 --sort rate --v --save /etc/pacman.d/mirrorlist
pacman -Syy
```

这里的策略是：
中国区，最近 12 小时，取前 10 个，按速度排序。

---

## 4. 清空分区

```
cfdisk /dev/nvme0n1
# 删除旧的分区
```

## 5. 安装 arch

```
archinstall
```

- Mirros and repositories: China, multilib
- Disk configuration > Manual Partitioning
  - 300MB, fat32, /efi, bootable, esp
  - ALL, btrfs, compressed, subvolume
    - @, /
    - @home, /home
  - Snapper
- Bootloader: Grub, removable
- Kernel: linux-lts, linux-zen
- Authentication: 添加用户
- Network: Use Network Manager default backend
- Timezone: Asia/Shanghai

选择 `chroot into installation`, 
在 /boot/grub 创建链接
```
ln -s /efi/grub /boot/grub
```

------

## 6. 第一次重启

```bash
reboot
```

现在可以拔 U 盘。

进入系统后，启用 NetworkManager：

```bash
systemctl enable --now NetworkManager
nmtui
```

在 `nmtui` 里：

```text
Activate a connection
```

再测试：

```bash
ping -c 3 bilibili.com
```

运行：

```bash
curl -fsSL https://raw.githubusercontent.com/U1805/arch-niri-dms/refs/heads/main/strap.sh | bash
```

## 虚拟机的 3D 加速

使用 VMware、Virt Manager/QEMU 等虚拟机测试时，必须启用虚拟显卡的 3D 加速。
Niri 是 Wayland 合成器，需要虚拟 GPU 提供可用的 DRM 和 OpenGL 渲染能力。

- VMware：在虚拟机显示设置中启用 **Accelerate 3D graphics**。
- Virt Manager/QEMU：使用支持 3D 的 Virtio 显卡并启用 3D acceleration（virgl）。

如果安装后 `greetd` 和 Niri 进程均在运行，但屏幕仍然全黑，并在日志中看到
`no allocator available for device`、`DeviceMissing`，或者虚拟 GPU 显示 `-virgl`，应先检查宿主侧的 3D 加速。
