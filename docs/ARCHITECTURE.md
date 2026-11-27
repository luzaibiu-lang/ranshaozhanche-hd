# 架构

燃烧战车 HD 将一局对战分成两部分。Go 服务端计算行动顺序、碰撞、伤害和胜负，Godot 客户端根据服务端状态绘制战场、播放动画并接收玩家输入。两位玩家看到的落点、地形变化和扣血结果来自同一次服务端计算。

| 模块 | 代码入口 | 负责内容 |
| --- | --- | --- |
| Windows 启动入口 | [Launcher.cs](../源码/launcher/Launcher.cs) | 校验增量更新、替换已验证文件、启动游戏 |
| 平台适配 | [game_platform.gd](../源码/client/game_platform.gd)、[Vault.cs](../源码/launcher/Vault.cs) | Windows 用当前用户的 DPAPI 保护记住的密码，网页版只在当前站点存储会话令牌 |
| 游戏客户端 | [main.gd](../源码/client/main.gd)、[net.gd](../源码/client/net.gd) | 大厅、房间、商城、战斗输入和状态同步 |
| 战场表现 | [world_view.gd](../源码/client/world_view.gd)、[battle_hud.gd](../源码/client/battle_hud.gd) | 摄像机、地形绘制、炮弹和战车动画、音画反馈 |
| 网络与存储 | [main.go](../源码/server/main.go)、[store.go](../源码/server/store.go) | HTTP 接口、会话、账号与背包的 SQLite 持久化 |
| 房间与战斗 | [world.go](../源码/server/world.go)、[battle.go](../源码/server/battle.go)、[ai_turn.go](../源码/server/ai_turn.go) | 席位、回合、AI 决策、结算和碰撞后的世界状态 |

## 一次开火

玩家松开空格时，客户端发送当前武器、角度和力度。服务端检查是否轮到这位玩家、能量是否足够，再模拟弹道、命中、地形变化和掉落。客户端取得新的战斗状态后按事件顺序播放表现。修改伤害或命中规则时从服务端入手，调整烟雾颜色、浮字位置或摄像机时从客户端入手。

## 资源与更新

服务端从每张地图的 `collision.bin` 读取可破坏区域，客户端用同一地图编号选择背景和渲染资源。Windows 导出将代码和地图、战车、音频等资源拆成多个包。启动器读取 `/updates/manifest.json`，按文件长度和 SHA-256 校验本地文件，下载发生变化的内容，再替换已验证的文件。

网页导出将游戏资源放入浏览器加载的 PCK，Godot 引擎以单线程 WebAssembly 在玩家设备运行。浏览器向当前站点的 `/hd-api/api/` 请求状态，反向代理转发到与 Windows 相同的 Go API。网页入口每次重新验证，带内容哈希的构建目录使用长期缓存。首次加载引擎和资源约需传输 131 MiB（gzip）。当前端采用新的构建目录时，浏览器会请求该版本资源。

Android 和 iOS 可继续复用游戏场景和网络协议。原生移动发行还需要适配触控、软键盘、安全存储、应用生命周期和商店发布。

游戏自建所需的环境、资源目录和本地启动方式见[构建指南](BUILDING.md)。
