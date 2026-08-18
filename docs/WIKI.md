## 虚拟机的 3D 加速

使用 VMware、Virt Manager/QEMU 等虚拟机测试时，必须启用虚拟显卡的 3D 加速。
Niri 是 Wayland 合成器，需要虚拟 GPU 提供可用的 DRM 和 OpenGL 渲染能力。

- VMware：在虚拟机显示设置中启用 **Accelerate 3D graphics**。
- Virt Manager/QEMU：使用支持 3D 的 Virtio 显卡并启用 3D acceleration（virgl）。

如果安装后 `greetd` 和 Niri 进程均在运行，但屏幕仍然全黑，并在日志中看到
`no allocator available for device`、`DeviceMissing`，或者虚拟 GPU 显示 `-virgl`，应先检查宿主侧的 3D 加速。

## [live] PPPoE / 拨号联网

### 检查

1. ip addr, 找到有线网卡, eg. `enp2s0` LOWER_UP 状态
2. pppoe-discovery -I enp2s0, 输出类似
```
Access-Concentrator: ...
Service-Name: ...
AC-Name: ...
```

### 拨号

1. 编辑 `/etc/ppp/peers/campus`
```
plugin pppoe.so
nic-enp2s0

user "账号"

noauth
noipdefault
defaultroute
usepeerdns

mtu 1492
mru 1492
```
2. 编辑 `/etc/ppp/pap-secrets`
```
"账号" * "密码"
```
3. 编辑 `/etc/ppp/chap-secrets`
```
"账号" * "密码"
```
4. `chmod 600 /etc/ppp/pap-secrets /etc/ppp/chap-secrets`
5. `pppd call campus`
6. `ping -c 3 bilibili.com`

**在 archinstall 安装好后 chroot 时安装必要工具: pacman -S ppp vim**

## [reboot] PPPoE / 拨号联网

### nmcli

```
nmcli connection add type pppoe ifname enp2s0 con-name campus username '账号'
nmcli connection modify campus pppoe.password '密码'
nmcli connection up campus
ping -c 3 bilibili.com
```

### nmtui

```
Edit a connection 添加 PPPoE 或 DSL
campus, enp2s0, 账号, 密码. 
Service 留空
Activate
```

## 手动挂载

`lsblk -f` 检查

```
mount -o subvol=@ /dev/nvme0n1p4 /mnt

mkdir -p /mnt/home
mount -o subvol=@home /dev/nvme0n1p4 /mnt/home

mkdir -p /mnt/efi
mount /dev/nvme0n1p3 /mnt/efi
```

`ls -ld /mnt/boot/grub` 预期 `/mnt/boot/grub -> /efi/grub`