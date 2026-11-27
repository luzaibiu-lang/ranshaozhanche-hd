# 第三方依赖与资源

## 引擎与程序依赖

| 组件 | 用途 | 许可证／出处 |
| --- | --- | --- |
| Godot Engine 4.5.1 | 游戏客户端与导出模板 | [MIT 及其第三方说明](https://godotengine.org/license/) |
| Go | 联机服务构建工具链 | [BSD-style](https://go.dev/LICENSE) |
| github.com/coder/websocket 1.8.14 | Go WebSocket 长连接 | [ISC](https://github.com/coder/websocket/blob/v1.8.14/LICENSE.txt) |
| golang.org/x/text | Unicode 与文本处理 | [BSD-3-Clause](https://pkg.go.dev/golang.org/x/text) |
| modernc.org/sqlite | Go SQLite 驱动 | [BSD-3-Clause；SQLite 本体为 public domain](https://pkg.go.dev/modernc.org/sqlite) |
| .NET Framework | Windows 登录器与 DPAPI | [Microsoft 发行许可](https://dotnet.microsoft.com/en-us/download/dotnet-framework) |

Go 的完整直接与间接依赖版本由 `源码/server/go.mod`、`go.sum` 固定。构建与测试工具的 Python 依赖列在 `源码/tools/requirements.txt`；它们不参与服务器日常运行。重新分发第三方组件时应保留其许可证和归属说明。

Windows 构建工具通过 Godot 的许可证 API 生成 `LICENSES.txt`，随客户端一起分发。Godot 导出模板和 .NET Framework 不以本项目原创代码的名义再许可。

## 历史游戏资源

`源码/client/assets/` 包含从历史游戏资料整理的兼容资源，涵盖战车、界面、地图、特效、音效与音乐。它们的文件格式转换不改变原有版权。原始权利人或完整再分发授权尚未统一核实的内容，不适用本仓库 MIT 授权。

规则表和资源索引位于 `源码/docs/`。这些资料用于追踪重建依据，不构成原游戏官方背书。关于使用和替换的边界见 [NOTICE](../NOTICE.md)。
