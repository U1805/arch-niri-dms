# AGENTS.md

本文件约束本仓库后续的优化、重构和审查工作。目标是维护一套面向 Arch Linux
x86_64、Niri + DMS 桌面的可审查安装流程。

## 1. 项目入口与环境前提

- 唯一面向用户的完整入口是 `strap.sh`；`install.sh` 和 `scripts/*.sh` 是其后续阶段。
- 修改安装顺序时，同时检查 `strap.sh`、`install.sh` 的 `MODULES`、README 和
  `INSTALLLIST.md`，不能只按脚本文件名推断顺序。
- 目标平台固定为 Linux x86_64，使用 UEFI、GRUB 和 Btrfs。
- 用户应在执行 `strap.sh` 前完成 [Arch 基础安装、联网和以下磁盘布局](README.md)：
  - ESP 为 FAT32，约 300 MiB，挂载到 `/efi`，具有 `boot/esp` 标志；
  - Btrfs 至少具有 `@` → `/` 和 `@home` → `/home`；
  - GRUB 按 README 安装，`/boot/grub` 指向 `/efi/grub`；
  - 内核由 Arch 安装阶段选择，本仓库当前不负责安装内核。
- 不要在未同步修改 README 和 Btrfs/GRUB 检测逻辑时，擅自改变 `/efi`、子卷或
  GRUB 布局约定。

## 2. 安装设计主旨

### 2.1 软件来源优先级

新增或迁移软件时按以下顺序选择来源：

1. Arch 官方仓库：系统组件、驱动、库、服务、CLI 依赖和开发工具优先使用 Pacman。
2. Flatpak/Flathub：浏览器、QQ、微信、WPS 等日常个人 GUI 软件优先使用 Flatpak。
3. ArchLinuxCN：只在官方仓库没有合适包且项目确实需要时使用；必须在审计清单标明。
4. AUR：最后选择，尽可能避免；确需使用时必须明确包名、用途和构建边界。
5. 外部源码或二进制：仅在以上来源无法满足需求时采用，并记录上游、版本、校验和清理策略。

- 不要把“可由 paru 解析”当成来源说明。必须先确认包最终来自官方仓库、
  ArchLinuxCN 还是 AUR。
- 官方仓库包优先用 `pacman`，AUR 才使用 `paru`。不要重新引入 yay；本项目只保留 paru。
- `paru` 当前来自 ArchLinuxCN，这是一项已接受的例外，不要擅自改为 AUR 自举。
- 安装包使用 `--needed`，避免无意义重装；不要引入 Arch partial upgrade。

### 2.2 网络与仓库体积

- 以中国大陆安装网络可用性为重要约束，减少直接访问 GitHub 和重复下载。
- 必须下载 GitHub 内容时，使用项目现有的 `https://gh-proxy.org/` 加速前缀。
- Git 仓库尽量使用浅克隆；需要确定分支或提交时显式 checkout，并验证失败状态。
- 大型模型、压缩包、运行时资源不得提交进本仓库，应在安装阶段下载，以保持 clone 轻量。
- 临时源码、构建产物和下载缓存放到 `/tmp` 或独立临时目录，成功或失败后都应清理。
- 外部预编译二进制应固定版本，并尽可能增加 SHA256 或签名校验；缺少校验必须写入审计清单。

## 3. 修改工作流与验证

开始修改前：

1. 阅读 `README.md`、相关脚本和 `INSTALLLIST.md`。
2. 使用 `pacman -Si/-Ss/-Sl` 核对包是否存在于官方仓库；不要凭包名猜测来源。
