# 本地开发与 Windows 构建

以下命令在仓库根目录的 PowerShell 中执行。服务端使用 Go 1.26.0，客户端使用 Godot 4.5.1 Standard。Windows x64 导出还需要 Python 3.11、Godot 同版本导出模板和带有 64 位 `csc.exe` 的 .NET Framework 4.x。

## 编译服务端

```powershell
Push-Location '源码/server'
go mod download
go build ./...
go vet ./...
Pop-Location
```

公开仓库已包含运行所需的资源和全部 19 张地图碰撞文件；资源的许可范围见 [NOTICE](../NOTICE.md)。服务端按 `源码/client/assets/maps/<编号>/collision.bin` 加载编号 1 至 19。战车、地图、界面、音效、音乐与动画索引位于 `源码/client/assets/` 下，替换资源时需保持相对路径与格式兼容。缺少任意地图时，服务端会打印第一个失败的地图编号并退出。

## 启动本地对局

```powershell
Push-Location '源码/server'
go run . --listen 127.0.0.1:18180 --assets ../client/assets --data ../../.tools/dev-server
```

保留这个终端，在新的 PowerShell 中检查服务状态。

```powershell
Invoke-RestMethod 'http://127.0.0.1:18180/health'
```

账号数据库在 `.tools/dev-server/hd.sqlite3`。使用 Ctrl+C 关闭开发服务。若要执行包含地图碰撞用例的回归测试，进入 `源码/server` 运行 `go test ./...`。

## 启动 Godot 客户端

用 Godot 4.5.1 导入 `源码/client/project.godot`。使用本地服务时可以从命令行显式指定地址。以下写法适用于已将 Godot 可执行文件加入 PATH 并命名为 `godot` 的环境。

```powershell
godot --path '源码/client' -- --qa-endpoint=http://127.0.0.1:18180
```

最后一个参数仅选择连接地址。进入登录界面后可注册一个本地账号，创建房间并添加 AI 陪练。开发运行使用 Godot 自带的登录界面，Windows 发行包另有独立登录器。

## 导出 Windows x64 客户端

在仓库根目录运行构建脚本。Godot 和导出模板会保存在本仓库的 `.tools` 下。首次安装需要网络。

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r 源码/tools/requirements.txt
.\.venv\Scripts\python.exe 源码/tools/bootstrap.py
.\.venv\Scripts\python.exe 源码/tools/bootstrap_templates.py
.\.venv\Scripts\python.exe 源码/tools/check_client.py
.\.venv\Scripts\python.exe 源码/tools/build_client.py --output .tools/windows-client
```

公开版本构建器默认连接本地服务；可增加参数 --endpoint https://game.example.org 配置自己的 HTTPS 服务。脚本将游戏、资源包、C# 登录器和增量更新清单写入 `.tools/windows-client`。通过 `燃烧战车.exe` 启动发行客户端时，登录器还会检查更新服务。自建更新目录应提供 `manifest.json` 和清单中每个 `blobs/<sha256>` 文件，使用服务端的 `--updates <目录>` 将其挂到 `/updates/`。运行编辑器客户端则可以直接连接本机游戏服务。

对外提供服务时可通过 `--cert` 与 `--key` 配置自己的 TLS 证书和私钥。管理接口由 `--admin-password-file` 启用，密码文件、SQLite 数据库和 TLS 私钥应放在仓库之外。启动参数见[服务端入口](../源码/server/main.go)。
