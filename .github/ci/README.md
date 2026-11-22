# CI 模板

同目录的 go-checks.yml 包含 Go 1.26 测试、go vet 和 Python 文档链接检查，配置只申请 contents: read。

当前发布凭据不含 GitHub 的 workflow 权限，因此以模板形式提供，仓库暂未自动启用 Actions。具备该权限的维护者可将 go-checks.yml 移到 .github/workflows/ci.yml 并推送；随后 main 分支推送和 Pull Request 会触发检查。

启用前可以直接在本机运行：

    cd 源码/server
    go test ./...
    go vet ./...

从仓库根目录运行 python scripts/check_docs.py 检查文档与 Python 语法。
