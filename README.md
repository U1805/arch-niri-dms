本配置方案基于 [ShorinWiki](https://github.com/SHORiN-KiWATA/Shorin-ArchLinux-Guide/wiki/%E4%B8%80%E9%94%AE%E9%85%8D%E7%BD%AE%E6%A1%8C%E9%9D%A2%E7%8E%AF%E5%A2%83) 修改

===

# shorin-dms-niri

基于Niri+DMS的桌面预设，开箱即用。


##  Usage 使用方法

- install安装

    ```
    yay -S shorin-dms-niri-git
    ```

    ```
    shorindms init 
    ```

    启动niri：
    
    ```
    niri-session
    ```

    如果你使用显示管理器的话在登录界面切换为niri

- update更新

    ```
    shorindms update
    ```
    以防万一，你的配置文件会被备份到`.cache`。

- uninstall卸载

    ```
    shorindms remove 
    ```

    ```
    yay -Rns shorin-dms-niri-git
    ```
