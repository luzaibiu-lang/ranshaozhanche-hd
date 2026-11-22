# 自行部署 Go 服务

以下示例部署自己的实例。公开仓库默认连接本机，账号和进度由各部署独立保存。

## 最小运行

在仓库根目录执行：

~~~sh
cd 源码/server
go build -trimpath -o ../../.tools/hdserver .
../../.tools/hdserver --listen 127.0.0.1:18180 --assets ../client/assets --data ../../.tools/dev-server
~~~

将仓库中的地图资源一并提供给服务端。Go 程序在启动时读取 19 张地图的碰撞数据，日常运行不需要 Python、Godot 编辑器或旧游戏客户端。

健康接口为 `/health`，GM 页面为 `/gm`。使用 `--admin-password-file` 指定至少 8 字节的独立密码文件后启用 GM；公开版本的管理员用户名为 `admin`。密码文件由部署者在源码目录之外创建，不附带默认密码。

## Linux 常驻

将 Go 可执行文件放到 `/opt/burningchariot-hd/hdserver`，资源放到 `/opt/burningchariot-hd/assets`。使用独立的非特权用户 `bchd`，数据目录为 `/var/lib/burningchariot-hd`，配置与密码位于 `/etc/burningchariot-hd`。这些路径仅为示例。

仓库提供 [systemd 示例](../deploy/burningchariot-hd.service)。安装服务前先确认本机用户、文件权限、资源路径和端口，再以系统管理员身份安装并启动。公网入口建议由反向代理终止可信 HTTPS，应用只监听本机；也可使用程序的 `--cert` 和 `--key` 参数直接提供 TLS。

使用自己的域名和端口，Windows 客户端通过 `connection.json` 的 `endpoint` 指向该 HTTPS origin。登录器允许受信任的 HTTPS 或回环 HTTP，默认拒绝明文远程 HTTP。

## 发布自己的 Windows 更新

1. 按[构建指南](BUILDING.md)生成完整客户端，并使用 `build_client.py --endpoint https://game.example.org` 指定自己的服务。
2. 将客户端的 `manifest.json` 发布到更新目录根部；对清单中每个文件，按 `blobs/<sha256>` 保存对应完整文件。
3. 用服务端 `--updates /path/to/publication` 将该目录映射到 `/updates/`。
4. 先上传不可变 blob，确认文件哈希后最后原子替换清单。不要发布尚未上传完整的清单。
5. 初次分发完整客户端；后续启动器只下载发生变化的受管理文件。

“增量”指按文件更新，不是二进制差分。SHA-256 负责完整性，HTTPS 和发布目录访问控制负责发布来源的可信性。不要把数据库、GM 密码、凭据或 TLS 私钥放到更新目录。

未提供更新目录时，可使用 Godot 编辑器直接连接游戏 API 开发；发行登录器需要可访问的更新清单。

## 数据与升级

SQLite 位于 `--data` 目录，包含账号、背包、进度、会话和管理操作记录。备份应使用 SQLite 一致性备份方式，或停止自己的服务后备份数据库及必要的 WAL 文件。不要仅复制一个仍在写入的数据库主文件。

升级前保留程序、资源、配置与数据库备份，并在没有活跃对局时切换。此示例不操作任何既有运营实例，也不共用其他项目的数据目录。
