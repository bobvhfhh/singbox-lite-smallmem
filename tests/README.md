# 小内存 NAT 回归测试

在 Linux 上使用 Docker 执行：

```bash
docker build -f tests/Dockerfile -t smallmem-test .
docker run -d --name smallmem --memory=128m --memory-swap=128m --cpus=0.5 --sysctl net.ipv6.conf.all.disable_ipv6=1 -e IPV4_ONLY=1 -v "$PWD:/work:ro" smallmem-test
docker exec smallmem bash /work/tests/integration.sh
docker cp smallmem:/results ./test-results
```

工作流另外覆盖 256MiB 和启用 IPv6 的组合。`--memory-swap` 与 `--memory` 相同表示不允许使用 swap。测试容器使用 Docker 默认 bridge/NAT 网络。

测试调用仓库内真实的节点生成、配置事务、YAML/元数据写入和 direct 服务管理函数，校验及转发均由实际核心执行：

- 校验安装器在 root 且没有 sudo 的 Linux 容器中安装四个脚本。
- sing-box 创建 VLESS Reality Vision、AnyTLS、TUIC v5；Xray 创建 VLESS Reality Vision、VLESS XHTTP TLS（ALPN h2）。
- 记录核心校验次数，断言每次创建只执行一次；核心检查时同名运行核心不得仍在执行。
- 注入无效协议，检查配置哈希恢复、原服务重新运行。
- 两个服务核心同时运行，先采样 12 秒空闲 RSS/CPU，再逐协议持续转发约 5 秒。
- 使用真实客户端代理 HTTP 响应，逐次核对全部响应内容；测试最后检查 cgroup 的 `oom` / `oom_kill` 为零。

Docker 镜像预装依赖和核心，资源统计从安装管理脚本开始，覆盖节点创建、校验、启动、回滚与转发；不包含 apt 安装依赖的资源峰值。服务管理验证为 direct 模式。

Reality 的伪装 TLS 目标固定为容器内的 `openssl s_server`，避免公网网站影响结果。Xray 26.11.9 默认阻止入站代理访问私网地址，测试夹具仅允许 `127.0.0.1:28080` 这个响应目标。该规则仅存在于测试容器，不写入安装脚本或用户配置。

`resources.jsonl` 的 RSS 直接读取 `/proc/PID/status`；CPU 取采样区间的进程 CPU ticks 除以墙钟时间，100% 代表占满一个逻辑 CPU。两个核心的 RSS 含共享映射，不能相加当作容器实际内存；`memory.peak` 是整个容器的 cgroup 统计。

2026-11-19 的成功记录：[GitHub Actions 44542653777](https://github.com/bobvhfhh/singbox-lite-smallmem/actions/runs/44542653777)。摘要保存在 `results-2026-11-19.json`，完整原始数据在该运行的四个 artifact 中。

参数依据：[Go GC 指南](https://go.dev/doc/gc-guide)、[Go runtime 的 GOMAXPROCS 说明](https://pkg.go.dev/runtime#GOMAXPROCS)。`GOMEMLIMIT` 是软预算，不包含进程所有 RSS；`GOMAXPROCS=1` 限制 Go 并行执行槽，不等于设置 CPU 百分比。
