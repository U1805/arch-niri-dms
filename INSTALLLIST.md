# Arch Niri DMS 安装清单

> 本清单以 `README.md`、安装脚本和 `common-applist.txt` 为依据。
> 本清单记录脚本的当前行为，不记录计划中的设计。
>
> `官方` 表示 Arch 官方仓库。`archlinuxcn` 表示 ArchLinuxCN 仓库。
> `AUR` 表示 paru 构建的软件包。`Flathub` 表示 Flatpak 应用。
> `外部` 表示脚本从 GitHub、CNB、npm 或 PyPI 获取的资源。

## 0. 安装前提

运行 `strap.sh` 前，请完成以下操作。安装脚本不会创建或修复磁盘分区。

- [ ] 使用 UEFI 启动 Linux x86_64 系统。
- [ ] 创建约 300 MiB 的 FAT32 ESP，并挂载到 `/efi`。
- [ ] 为 ESP 设置 `boot/esp` 标志。
- [ ] 使用 Btrfs 系统盘，并创建 `@` 和 `@home` 子卷。
- [ ] 将 `@` 挂载到 `/`，并将 `@home` 挂载到 `/home`。
- [ ] 按 README 安装 GRUB，并使用 removable 安装方式。
- [ ] 按 README 选择 `linux-lts` 和 `linux-zen`。本仓库不安装内核。
- [ ] 使用 NetworkManager 的默认后端连接网络。
- [ ] 将时区设置为 `Asia/Shanghai`。时区会影响软件源选择。
- [ ] 运行 `ln -s /efi/grub /boot/grub`，将 GRUB 目录链接到 ESP。

## 1. 总执行顺序

| 顺序 | 脚本/阶段 | 功能 | 
|---:|---|---|
| 0 | `strap.sh` 入口 | 检查平台和下载工具，下载仓库，以 root 启动安装程序，仅支持 Linux x86_64 |
| 1 | `install.sh` 安装准备 | 更新系统，安装基础工具 |
| 2 | `01-btrfs.sh` | 配置 Snapper 和 GRUB-Btrfs，仅当 `/home` 使用 Btrfs 时配置主目录快照 |
| 3 | `02-fonts.sh` | 配置 ArchLinuxCN、字体、TTY 和 AUR 助手 |
| 4 | `03-driver.sh` | 配置网络、音频、区域设置、输入法、硬件、GPU 和 Flatpak |
| 5 | `04-dualboot-fix.sh` | 根据检测结果配置双系统。始终配置用户 |
| 6 | `05a-dms-niri.sh` | 安装 Niri、DMS 核心包和 DMS Greeter |
| 7 | `05b-dms-tools.sh` | 安装桌面辅助工具和系统集成 |
| 8 | `06-config.sh` | 部署配置和壁纸，验证桌面状态 |
| 9 | `07a-grub-theme.sh` | 同步、选择并应用 GRUB 主题 |
| 10 | `07b-grub-config.sh` | 生成器配置 GRUB 菜单，并验证候选配置 |
| 11 | `99a-apps.sh` | 安装官方仓库、AUR/ArchLinuxCN 和 Flatpak 应用 |
| 12 | `99b-apps.sh` | 安装条件软件包和外部资源，应用安装后设置 |
| 13 | `install.sh` 清理 | 清理缓存并保存日志 |

## 2. 安装准备

| 顺序 | 包/资源 | 来源 | 作用 | 条件/备注 |
|---:|---|---|---|---|
| 安装入口 | 仓库 `${BRANCH:-main}.tar.gz` | 外部：GitHub | `strap.sh` 下载仓库 | 解压到 `/tmp/arch-niri-dms` |
| 0.0 | 全部已安装包 | 当前软件仓库 | 同步软件包数据库并更新系统 | 不单独运行 `pacman -Sy`，避免部分更新 |
| 0.1 | `bash`, `curl`, `wget`, `tar`, `unzip`, `git`, `jq`, `vim` | 官方 | 提供基础工具 | 将全局 `EDITOR` 设置为 `vim` |
| 0.2 | `nodejs`, `bun`, `uv`, `rust`, `go` | 官方 | 提供软件包工具和开发环境 | 使用 `pacman -S --needed` 安装 |
| 0.3 | 当前 Pacman 镜像列表 | README 基础安装配置 | 使用中国网络环境下已经配置的镜像 | 不再询问或运行 Reflector，避免重复测速和额外等待 |
| 0.4 | `archlinux-keyring` | 官方 | 更新 Arch 签名密钥 | 在系统更新后使用 `pacman -S --needed` 安装 |
| 0.5 | `[multilib]` | Arch 官方仓库配置 | 提供 32 位库 | 仅修改 `/etc/pacman.conf`。已启用时跳过 |
| 0.6 | 全部已安装包 | 当前软件仓库 | 运行 `pacman -Syu` | 更新所有已配置仓库中的软件包 |

## 3. 第一部分：系统基本配置

### 3.1 Btrfs

| 顺序 | 包/资源 | 来源 | 作用 | 条件/副作用 |
|---:|---|---|---|---|
| 1.1 | `snapper` | 官方 | root 与 home 快照管理 | home 仅在 `/home` 为 Btrfs 时配置 |
| 1.2 | `snap-pac` | 官方 | pacman 事务前后自动创建 root `pre/post` 快照 | 与 Snapper 一起安装 |
| 1.3 | `grub-btrfs`, `inotify-tools` | 官方 | 把 Snapper 快照加入 GRUB，并监听快照变化 | 仅 root 为 Btrfs 且 GRUB 可用时安装 |

### 3.2 字体

| 顺序 | 包/资源 | 来源 | 作用 | 条件/备注 |
|---:|---|---|---|---|
| 2.1 | `archlinuxcn-keyring` | archlinuxcn | ArchLinuxCN 签名密钥 | 先写入 USTC/TUNA/全局镜像配置 |
| 2.2 | `ttf-liberation`, `noto-fonts`, `noto-fonts-cjk`, `noto-fonts-emoji`, `otf-font-awesome`, `ttf-jetbrains-mono-nerd` | 官方 | 提供西文、CJK、Emoji 和图标字体 | JetBrains Nerd Font 供 Yazi 使用 |
| 2.3 | `ttf-maplemono-nf` | archlinuxcn | 提供带 Nerd Font 图标的等宽字体 | Kitty 和系统等宽字体使用 Maple Mono NF。不安装内嵌中文变体 |
| 2.4 | `terminus-font` | 官方 | 提供 TTY 字体 | 设置为 `ter-v28n` |
| 2.5 | `base-devel`, `paru` | `base-devel` 来自官方，`paru` 来自 archlinuxcn | 提供 AUR 构建工具 | 所有 AUR 操作均使用 paru |

### 3.3 硬件和 GPU 驱动

| 顺序 | 包/资源 | 来源 | 作用 | 条件/备注 |
|---:|---|---|---|---|
| 3.1 | `iwd`, `impala` | 官方 | 提供 Wi-Fi 后端和终端界面 | 仅当 NetworkManager 存在时安装。同时启用 iwd |
| 3.2 | `sof-firmware`, `alsa-ucm-conf`, `alsa-firmware` | 官方 | 声卡固件和 ALSA 配置 | 固定 |
| 3.3 | `pipewire`, `lib32-pipewire`, `wireplumber`, `pipewire-pulse`, `pipewire-alsa`, `pipewire-jack` | 官方 | 提供 PipeWire 音频组件和兼容层 | 为所有用户启用相关服务 |
| 3.4 | `en_US.UTF-8`, `zh_CN.UTF-8` | 本地系统配置 | 提供英文和简体中文区域设置 | 缺少设置时修改 `/etc/locale.gen`，然后运行 `locale-gen` |
| 3.5 | `fcitx5-im`, `fcitx5-rime` | 官方 | Fcitx5 输入法与 Rime |  |
| 3.6 | `usbutils`, `pciutils` | 官方 | USB/PCI 硬件检测 | 固定安装，用于蓝牙探测 |
| 3.7 | `bluez`, `bluetui` | 官方 | 提供蓝牙协议和终端界面 | 仅当脚本检测到蓝牙时安装。同时启用 `bluetooth` |
| 3.8 | `power-profiles-daemon` | 官方 | 电源模式管理及 DMS 电源控制后端 | 安装完成后立即启用并启动 |
| 3.9 | `clang`, `pciutils`, `lua`, `libusb`, chwd | chwd 来自外部仓库，依赖项来自官方；Rust crates 优先使用 RSProxy | 构建并临时运行 chwd | 浅克隆并在本机编译。不使用 AUR。运行后删除临时文件 |
| 3.10 | 显卡驱动包 | 由 `chwd -a` 决定 | 提供 Intel、AMD 或 NVIDIA 驱动 | 在 Flatpak 和桌面之前安装。失败时停止安装。pacman 负责后续更新 |
| 3.11 | `flatpak` | 官方 | 提供 Flatpak 运行环境 | 中国大陆环境使用 SJTU 镜像。其他环境使用 Flathub 官方源 |

### 3.4 双启动与用户

| 顺序 | 包/资源 | 来源 | 作用 | 条件/备注 |
|---:|---|---|---|---|
| 4.1 | `os-prober` | 官方 | 检测 Windows 和其他系统 | GRUB 存在时安装 |
| 4.2 | `exfat-utils` | 官方 | 访问 Windows exFAT 分区 | 仅检测到 Windows |
| 4.3 | `xdg-user-dirs` | 官方 | 生成 Documents/Pictures 等目录 | 固定 |
| 4.4 | 用户配置 | 本地配置 | 配置 wheel、sudo、I²C、密码策略和 PATH | 安装期间启用临时 `NOPASSWD`。主安装程序退出时删除此规则。系统继续使用 sudo 密码验证 |

## 4. 第二部分：个人桌面配置

### 4.1 Niri 和 DMS 核心组件

| 顺序 | 包/资源 | 来源 | 作用 | 条件/备注 |
|---:|---|---|---|---|
| 5.1 | `dms-shell-niri` | 官方 `extra` | Dank Material Shell + Niri 核心环境 | 自动依赖 `dms-shell`、`quickshell`、`dgop` 和 `niri` |
| 5.2 | `xdg-desktop-portal-gnome` | 官方 `extra` | Niri 的 PipeWire 屏幕共享/录制门户 | 脚本显式选择 GNOME 实现 |
| 5.3 | `xwayland-satellite` | 官方 `extra` | Niri 下运行 X11 应用 | 固定 |
| 5.4 | `libnotify`, `wl-clipboard`, `cliphist` | 官方 `extra` | 提供 DMS 通知和剪贴板功能 | DMS 使用这些软件包，但上游元数据未声明依赖关系 |
| 5.5 | `cava`, `cups-pk-helper`, `matugen`, `qt6-multimedia`, `qt6ct`, `wtype`, `swayosd` | 官方 `extra` | 提供音频显示、打印、主题、音效、Qt6 和按键提示 | 安装后启用并启动 `swayosd-libinput-backend.service` |
| 5.6 | `dsearch-bin` | AUR | 提供 DMS 文件索引搜索 | 官方仓库没有此软件包。paru 单独安装。配置启动 `dsearch serve` |
| 5.7 | `greetd-dms-greeter-bin` | AUR | 提供 `dms-greeter` 启动器和 Greeter QML 文件 | 其依赖来自官方 `extra`。随后运行 `dms greeter enable`、`sync`、`status` |

当前 Portal 与文件管理器的依赖链如下：

```text
dms-shell-niri
└── niri
    └── xdg-desktop-portal-impl（虚拟依赖）
        └── xdg-desktop-portal-gnome（脚本选择的实现，提供屏幕录制）
            └── nautilus（Arch 软件包的必需依赖项）
```

`xdg-desktop-portal-gtk` 提供常规文件选择功能。
GNOME Portal 为 Niri 提供屏幕共享功能。
脚本不为 Nautilus 配置快捷键或启动入口，并隐藏其桌面条目。

### 4.2 桌面预设工具

以下软件包属于 Shorin 桌面预设，不是 `dms-shell-niri` 的依赖项。
pacman 安装这些软件包。

| 顺序 | 包组 | 包 | 来源 | 作用 |
|---:|---|---|---|---|
| 5.8 | 文件管理 | `imv`, `mpv`, `thunar`, `tumbler`, `thunar-archive-plugin`, `thunar-volman`, `ffmpegthumbnailer`, `icoextract`, `python-pillow`, `poppler-glib`, `webp-pixbuf-loader`, `libgsf`, `kimageformats`, `gvfs-smb`, `file-roller`, `gnome-keyring`, `xdg-desktop-portal-gtk`, `gst-plugins-base`, `gst-plugins-good`, `gst-libav` | 官方 `extra` | 提供文件管理、预览、网络共享、归档、凭据、桌面门户和媒体解码。`Mod+E` 启动 Thunar |
| 5.9 | 终端/CLI | `kitty`, `bat`, `fuzzel`, `fzf`, `eza`, `zoxide`, `starship`, `fish`, `imagemagick` | 官方 `extra` | 终端、启动器、Shell、提示符、图像工具和独立工具共用的模糊搜索后端 |
| 5.10 | 主题 | `adw-gtk-theme`, `nwg-look`, `breeze-cursors` | 官方 `extra` | GTK 主题管理和光标 |
| 5.11 | Wayland 授权 | `xorg-xhost` | 官方 `extra` | 允许 GParted 等特权程序访问显示环境。脚本始终安装 |

### 4.3 用户配置

| 顺序 | 包/资源 | 来源 | 作用 | 条件/备注 |
|---:|---|---|---|---|
| 6.1 | 仓库 `dotfiles/` | 本仓库 | 部署桌面配置和用户工具 | 部署到目标用户目录。将 `~/.local/bin` 加入 PATH |
| 6.2 | 仓库 `etc/` | 本仓库 | 部署系统配置 | 将仓库中的文件逐个部署到 `/etc` |
| 6.3 | 壁纸列表 | 外部：`wallpapers.txt` 直链 | 用户壁纸 | 下载失败仅记录警告 |
| 6.4 | 核心软件包清单 | pacman 本地数据库 | 使用 `pacman -T` 验证 5.1 至 5.7 |  |
| 6.5 | `~/.config/niri/dms` | 用户配置 | 验证 Niri 配置 | 这是脚本明确检查的配置路径 |

### 4.4 GRUB 个性化

| 顺序 | 包/资源 | 来源 | 作用 | 条件/备注 |
|---:|---|---|---|---|
| 7.1 | 仓库内 `bsol`、`wuthering`、`senren-banka` 主题；`ttf-gentium-book`, `python-fonttools` | 主题来自本仓库，两个条件生成依赖来自官方 `extra` | 提供 GRUB 主题 | 两个依赖仅在选择千恋万花时安装 |
| 7.2 | Minegrub | 外部：`Lxtharia/double-minegrub-menu` | 可选 Minecraft 风格 GRUB 主题 | 浅克隆，并直接执行上游 `install.sh` |
| 7.3 | GRUB 菜单 | Arch 的 GRUB 生成器 | 设置 `GRUB_DEFAULT=saved` 和 `GRUB_SAVEDEFAULT=true` 以记住上次启动项；不调整原生菜单内容和排序，不使用自定义 UKI、Advanced 或 UEFI 生成器 |
| 7.4 | GRUB 配置验证 | 本地事务逻辑 | 先生成候选配置，验证传统内核、initramfs、Advanced、外置 `grub-btrfs.cfg` 和 Snapshot 引用后再替换活动配置 | 保留 grub-btrfs 原生菜单位置和内容；仅针对 `/boot/grub` 链接到 ESP 的布局，按 ESP UUID 定位外置 `grub-btrfs.cfg` |

## 5. 固定应用与安装后工具

`99a-apps.sh` 在主安装阶段处理 `common-applist.txt` 的全部条目：官方仓库包使用 Pacman，
AUR/ArchLinuxCN 条目由目标用户通过 Paru 批量安装，Flatpak 应用安装到系统级 Flathub。
`99b-apps.sh` 随后处理条件依赖项、外部资源和用户设置。

### 5.1 Pacman

| 顺序 | 包 | 来源 | 作用 | 后续动作 |
|---:|---|---|---|---|
| 8.1 | `baobab` | 官方 | 以图形界面分析磁盘占用 | 无 |
| 8.2 | `mission-center` | 官方 `extra` | 以图形界面监控系统 | 无 |
| 8.3 | `gparted` | 官方 | 管理磁盘分区 | 需要特权。5.11 安装 `xorg-xhost` 以授权显示访问 |
| 8.4 | `gnome-font-viewer` | 官方 | 字体查看 | 无 |
| 8.5 | `gnome-calendar`, `gnome-clocks` | 官方 | 日历和时钟 | 无 |
| 8.6 | `fastfetch`, `gdu`, `btop`, `yazi` | 官方 | 系统摘要、磁盘空间分析、资源监控和终端文件管理 | 固定安装 |
| 8.7 | `wine` | 官方和 multilib | 提供 Windows 应用兼容层 | 99b 配置 Gecko、Mono、Wine 前缀和字体 |
| 8.8 | `virt-manager` | 官方 | 提供 KVM/QEMU 图形界面 | 99b 在物理机上配置虚拟化组件和服务 |
| 8.9 | `zed` | 官方 `extra` | 代码编辑器 | 无 |
| 8.10 | `keyd` | 官方 | 系统级按键重映射 | 服务启动与配置重载在 8.37 执行 |
| 8.11 | `watchexec` | 官方 | 文件变化命令执行器 | 无 |
| 8.12 | `btrfs-assistant` | 官方 `extra` | 以图形界面管理 Btrfs 子卷和 Snapper 快照 | 软件包提供默认配置和 Polkit 策略 |
| 8.13 | `bazaar` | 官方 `extra` | 以 Flathub 为重点的 Flatpak 图形应用商店 | 固定安装 |

### 5.2 通过 Paru 路由的应用

| 顺序 | 包 | 来源 | 作用 |
|---:|---|---|---|
| 8.14 | `mark-shot` | archlinuxcn | 提供截图、标注、录制和 Niri 窗口识别。 |
| 8.15 | `sparkle-bin` | AUR | Sparkle Clash 图形界面 |
| 8.16 | `zen-browser` | archlinuxcn | Zen Browser。 |

### 5.3 Flatpak 应用

| 顺序 | 应用 ID | 来源 | 作用 |
|---:|---|---|---|
| 8.17 | `com.rustdesk.RustDesk` | Flathub | 远程桌面 |
| 8.18 | `it.mijorus.gearlever` | Flathub | AppImage 管理 |
| 8.19 | `com.google.Chrome` | Flathub | Chrome 浏览器 |
| 8.20 | `org.keepassxc.KeePassXC` | Flathub | 密码管理 |
| 8.21 | `com.qq.QQ` | Flathub | QQ |
| 8.22 | `com.spotify.Client` | Flathub | Spotify |
| 8.23 | `com.tencent.WeChat` | Flathub | 微信 |
| 8.24 | `com.tencent.wemeet` | Flathub | 腾讯会议 |
| 8.25 | `com.wps.Office` | Flathub | WPS Office |
| 8.26 | `md.obsidian.Obsidian` | Flathub | Obsidian |
| 8.27 | `org.telegram.desktop` | Flathub | Telegram |

### 5.4 条件追加包和外部资源

| 顺序 | 包/资源 | 来源 | 作用 | 触发条件 |
|---:|---|---|---|---|
| 8.28 | `qemu-full`, `swtpm`, `dnsmasq`, `virt-viewer`（以及 `virt-manager`） | 官方 | 提供 KVM、TPM、NAT 和虚拟机查看器 | 仅在物理机上配置。启用 libvirtd。将用户加入相关组 |
| 8.29 | `wine-gecko`, `wine-mono`, 临时 `xorg-server-xvfb` | 官方/multilib | Wine 浏览器、.NET 兼容及无桌面环境下的虚拟 X11 显示 | Wine Prefix 未初始化时，在 Xvfb 中运行 `wineboot`；只卸载本次事务新增的 Xvfb 及依赖，失败或中断同样清理 |
| 8.30 | `simfang.ttf`, `simhei.ttf`, `simkai.ttf`, `simsun.ttc` | 外部：SHORiN-KiWATA GitHub | 提供 Wine 中文字体 | 安装 Wine 后逐个下载获取，失败时清理 `.part` 文件 |
| 8.31 | U1805/rime 仓库 | 外部：GitHub | 提供 Rime 方案、词典、Lua 和 OpenCC 配置 | 完整部署成功后写入标记 |
| 8.32 | `wanxiang-lts-zh-hans.gram` | 外部：万象官方 CNB 加速下载 | U1805/rime 所需万象语法模型 | 不打包进仓库，安装时单独下载 |
| 8.33 | `rapidocr`, `onnxruntime` | 外部：PyPI，经清华 PyPI 镜像和 `uv pip` | 提供 mark-shot OCR | 先验证已有虚拟环境，缺失时在临时环境安装并验证，成功后替换，失败时保留旧环境 |
| 8.34 | `@earendil-works/pi-coding-agent` | 外部：npm，经 npmmirror 和 Bun | 提供 AI 编程助手 | 仅当 bun 存在时安装 |
| 8.35 | EasyTier 最新稳定版 x86_64 ZIP | 外部：GitHub Release | 提供 P2P VPN | 两个命令已存在时跳过；仅验证 ZIP，不验证签名或哈希 |
| 8.36 | GTK、终端、Flatpak 和应用菜单设置 | 本地操作 | 配置深色主题、默认终端、Flatpak 权限和应用菜单 | 安装应用后执行。隐藏辅助程序入口。保留 Fcitx 和 Thunar 主入口 |
| 8.37 | `keyd.service` 和 keyd 配置 | 本地操作 | 启用 keyd 并重新加载按键映射 | 仅当 keyd 已安装时执行；启动后短暂重试 reload，避免服务套接字初始化竞态；失败时写入报告 |

## 6. 无法预先列出的安装项

以下内容取决于当前系统或上游项目，本清单不逐项列出：

1. pacman 和 paru 解析的传递依赖项。
2. `pacman -Syu` 更新或替换的现有系统包。
3. `chwd -a` 根据 GPU/PCI 硬件选择的驱动、内核模块和库。
4. Flatpak 应用下载的运行环境。
5. AUR PKGBUILD 后续版本新增的依赖项或构建步骤。
