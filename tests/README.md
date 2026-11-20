# 小内存 NAT 回归测试

在 Linux 上使用 Docker 执行：

```bash
docker build -f tests/Dockerfile -t smallmem-test .
docker run -d --name smallmem --memory=128m --memory-swap=128m --cpus=0.5 --sysctl net.ipv6.conf.all.disable_ipv6=1 -e IPV4_ONLY=1 -v "$PWD:/work:ro" smallmem-test
docker exec smallmem bash /work/tests/integration.sh
docker exec smallmem bash /work/tests/service-failure.sh
docker exec smallmem bash /work/tests/maintenance.sh
docker cp smallmem:/results ./test-results
```

工作流另外覆盖 256MiB 和启用 IPv6 的组合。`--memory-swap` 与 `--memory` 相同表示不允许使用 swap。测试容器使用 Docker 默认 bridge/NAT 网络。

测试调用仓库内真实的节点生成、配置事务、YAML/元数据写入和 direct 服务管理函数，校验及转发均由实际核心执行：

- 校验安装器在 root 且没有 sudo 的 Linux 容器中安装四个脚本。
- sing-box 创建 VLESS Reality Vision、AnyTLS、TUIC v5；Xray 创建 VLESS Reality Vision、VLESS XHTTP TLS（ALPN h2）。
- 记录核心校验次数，断言每次创建只执行一次；核心检查时同名运行核心不得仍在执行。
- 注入无效协议，检查配置哈希恢复、原服务重新运行。
- 两个服务核心同时运行，先采样 60 秒空闲 RSS/CPU，单核心空闲 CPU 超过 1% 则失败。
- 每个协议按 1MiB/s 持续 30 秒；每次响应 256KiB、每秒 4 次请求，实际速率必须在 0.9–1.05MiB/s，服务核心 CPU 超过 20% 则失败。
- 在每个 sing-box 节点输入点关闭标准输入，验证及时退出、配置恢复及原服务继续运行；Xray 另测创建中断和停服校验中断。
- 实际修改端口、删除单个及全部节点，断言每步只检查一次核心；名称修改不重启，失败的认证修改恢复服务，Xray 全删保留中转入口与对应元数据。
- 使用真实客户端代理 HTTP 响应，逐次核对全部响应内容；测试最后检查 cgroup 的 `oom` / `oom_kill` 为零。

`tests/Dockerfile` 预装依赖和核心，覆盖创建、校验、启动、回滚与转发；服务管理实测为 direct 模式。`service-failure.sh` 另外模拟 systemd/OpenRC 启动返回成功而状态已停止，确认脚本报告失败。

`fresh.yml` 另用干净的 Ubuntu 24.04 和 Alpine 3.22，分别安装 sing-box 和 Xray。容器只有 bash、curl、证书（Alpine 还有未运行的 OpenRC），不预装核心、jq 或 yq。`fresh-menu.py` 通过 PTY 操作真实安装器和菜单，在 128MiB、0.5 CPU、禁 swap 的 NAT 容器里完成安装及节点创建，并检查 OOM。`*-phases.jsonl` 记录首次菜单、核心安装、创建节点及再次进入菜单的容器 CPU 时间；其百分比包含包管理器等全部进程，不能与单个服务核心 CPU 混用。

Reality 的伪装 TLS 目标固定为容器内的 `openssl s_server`，并关闭 sing-box 的 NTP，避免公网探测影响结果。Xray 26.11.9 默认阻止入站代理访问私网地址，测试夹具仅允许 `127.0.0.1:28080` 这个响应目标。该规则仅存在于测试容器。

`resources.jsonl` 的 RSS 直接读取 `/proc/PID/status`；CPU 取采样区间的进程 CPU ticks 除以墙钟时间，100% 代表占满一个逻辑 CPU。两个核心的 RSS 含共享映射，不能相加当作容器实际内存；`memory.peak` 是整个容器的 cgroup 统计。

2026-11-19 的成功记录：[持续资源与维护回归测试](https://github.com/bobvhfhh/singbox-lite-smallmem/actions/runs/44551276623)、[全新安装测试](https://github.com/bobvhfhh/singbox-lite-smallmem/actions/runs/44551276640)。摘要保存在 `results-2026-11-19.json`；原始数据位于对应工作流的四个 artifact 中。

参数依据：[Go GC 指南](https://go.dev/doc/gc-guide)、[Go runtime 的 GOMAXPROCS 说明](https://pkg.go.dev/runtime#GOMAXPROCS)。`GOMEMLIMIT` 是软预算，不包含进程所有 RSS；`GOMAXPROCS=1` 限制 Go 并行执行槽，不等于设置 CPU 百分比。
