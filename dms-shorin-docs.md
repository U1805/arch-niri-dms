【可以查阅的文档】
ArchWiki: https://wiki.archlinux.org/title/Main_page
DMSWiki: https://danklinux.com/
NiriWiki: https://github.com/niri-wm/niri/wiki
ShorinArch: https://shorin.xyz/wiki

如果出现了两个任务栏可以运行以下命令关掉：
systemctl --user disable --now  dms

如果出现网络问题可以进行以下操作更换wifi后端：
sudo rm /etc/NetworkManager/conf.d/iwd.conf
sudo systemctl restart NetworkManager

【重要按键】
super+shift+/ 打开按键教程
super+T 打开终端
super+E 打开文档管理器
super+Z 开始菜单
super+Q 关闭窗口
super+R 按预设切换 宽度
super+F 最大化
super+alt+F 全屏
super+G/O 切换overview
super+alt+A 截图（或者用printscreen键）
super+V 开关剪贴板
super+C 切换浮动窗口
super+N 切换浮动窗口聚焦

super+H/L 左右切换聚焦
super+U/i 上下切换工作区
super+右键 调整窗口大小
super+左键 移动窗口
super+滚轮 左右切换聚焦
super+Shift+滚轮 上下切换工作区
super+A/D 左右移动窗口（合并列）
super+shift+F10 下载随机动漫壁纸
【详细按键教程】
所有的键位都可以在.config/niri/dms/binds.kdl里找到

【实用命令】
pac 安装软件
pacr 卸载软件
clean 系统清理

【有趣实用的TUI软件】
gdu：磁盘空间管理
nmtui：网络配置工具
impala：wifi连接工具，tab键切换，上下左右选择，回车确认（仅支持iwd后端）
btop：终端任务管理器
gtop：dms做的终端任务管理器
yazi：文档管理器
fastfetch：系统信息显示工具

【关于系统维护】
1. 系统更新
系统使用 snap-pac 在每次 pacman 事务前后自动创建 root 的 Snapper pre/post 快照。更新前请关注 Arch Linux 重要新闻；出现问题时可从 GRUB 的快照菜单启动对应快照，再按 Snapper 文档手动处理恢复。

2. 系统清理
clean命令可以清理软件包缓存、回收站、截图、录屏、超数量上限的快照、btrfs备份子卷等内容。clean all命令可以更进一步，清理所有软件包缓存和所有快照。home目录下的.cache文件内的文件也都是可以安全删除的缓存，不过一股脑删除可能会少用户登录什么的，可以使用gdu寻找大文件删除。
