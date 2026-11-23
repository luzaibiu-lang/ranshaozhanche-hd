# 架构

燃烧战车 HD 将一局对战分成两部分。Go 服务端计算行动顺序、碰撞、伤害和胜负，Godot 客户端根据服务端状态绘制战场、播放动画并接收玩家输入。两位玩家看到的落点、地形变化和扣血结果来自同一次服务端计算。

| 模块 | 代码入口 | 负责内容 |
| --- | --- | --- |
| Windows 登录器 | [Launcher.cs](../源码/launcher/Launcher.cs)、[LauncherWindow.cs](../源码/launcher/LauncherWindow.cs) | 注册、登录、增量更新、启动游戏 |
| 凭据工具 | [LauncherWindow.cs](../源码/launcher/LauncherWindow.cs)、[Vault.cs](../源码/launcher/Vault.cs) | 使用 CurrentUser DPAPI 加密密码与会话，分别写入 `%LOCALAPPDATA%\BurningChariotHD` 下的 `account.dat` 和 `session.dat`，并交接一次性启动令牌 |
| 游戏客户端 | [main.gd](../源码/client/main.gd)、[net.gd](../源码/client/net.gd) | 大厅、房间、商城、战斗输入和状态同步 |
| 战场表现 | [world_view.gd](../源码/client/world_view.gd)、[battle_hud.gd](../源码/client/battle_hud.gd) | 摄像机、地形绘制、炮弹和战车动画、音画反馈 |
| 网络与存储 | [main.go](../源码/server/main.go)、[store.go](../源码/server/store.go) | HTTP 接口、会话、账号与背包的 SQLite 持久化 |
| 房间与战斗 | [world.go](../源码/server/world.go)、[battle.go](../源码/server/battle.go)、[ai_turn.go](../源码/server/ai_turn.go) | 席位、回合、AI 决策、结算和碰撞后的世界状态 |

## 一次开火

玩家松开空格时，客户端发送当前武器、角度和力度。服务端检查是否轮到这位玩家、能量是否足够，再模拟弹道、命中、地形变化和掉落。客户端取得新的战斗状态后按事件顺序播放表现。修改伤害或命中规则时从服务端入手，调整烟雾颜色、浮字位置或摄像机时从客户端入手。

## 资源与更新

服务端从每张地图的 `collision.bin` 读取可破坏区域，客户端用同一地图编号选择背景和渲染资源。Windows 导出将代码和地图、战车、音频等资源拆成多个包。启动器读取 `/updates/manifest.json`，按文件长度和 SHA-256 校验本地文件，下载发生变化的内容，再替换已验证的文件。

游戏自建所需的环境、资源目录和本地启动方式见[构建指南](BUILDING.md)。
