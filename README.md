# singbox-lite 小内存精简版

这个仓库提供适合小内存 NAT 机器的 sing-box + Xray 管理脚本，重点减少空闲 CPU、重复校验和首次安装开销。新建节点菜单保留：

| 核心 | 支持新建 |
| --- | --- |
| sing-box | VLESS + TCP + Reality + Vision、AnyTLS、TUIC v5 |
| Xray | VLESS + TCP + Reality + Vision、VLESS + XHTTP + TLS（H2 回源） |

原有节点查看、删除、端口修改、Argo、中转、端口转发和 Xray 管理仍保留。

## 一键安装

复制这一行到服务器执行。它会下载安装器、安装四个脚本、创建与原项目相同的 `/usr/local/bin/sb` 命令，并直接打开管理菜单：

```bash
(curl -LfsS https://raw.githubusercontent.com/bobvhfhh/singbox-lite-smallmem/main/install.sh -o /tmp/sb-lite-install || wget -q https://raw.githubusercontent.com/bobvhfhh/singbox-lite-smallmem/main/install.sh -O /tmp/sb-lite-install) && bash /tmp/sb-lite-install
```

使用 root 账号可直接执行，无需安装 `sudo`。普通用户执行时会自动调用 `sudo`；如果机器没有 `sudo`，先运行 `su -` 切换到 root，再执行上面的命令。需要 `bash` 和 `curl` / `wget` 中的任意一个下载工具。

安装器会检查脚本语法，把运行脚本放在 `/usr/local/lib/singbox-lite-smallmem`。再次执行同一命令即可更新。现有配置保留在 `/usr/local/etc/sing-box/` 与 `/usr/local/etc/xray/`。更新后，在菜单中重启正在使用的核心，使运行参数生效。

### 首次创建节点

1. 使用 sing-box：主菜单选 `[15]` 安装核心，再选 `[1]` 添加节点。
2. 使用 Xray：主菜单选 `[16]` 安装核心，再选 `[19]` → `[6]` 添加节点。
3. 输入运营商分配给这台 NAT 机器的**内部监听端口**，创建完成后复制分享链接。
4. 如果公网端口与内部端口不同，在客户端把地址改为运营商提供的公网地址、端口改为对应公网端口。

128MB 机器优先只运行一个核心、创建实际需要的 1–3 个节点；使用 sing-box 的三种协议时，无需再安装 Xray。

## 运行与更新

安装器每次运行都会打开管理菜单。安装后，root 账号直接运行：

```bash
sb
```

普通用户使用 `sudo sb`；未安装 `sudo` 时，先用 `su -` 切换 root 再运行 `sb`。

重新运行上面的一键安装命令即可更新。也可以更新本地克隆版：

```bash
cd singbox-lite-smallmem
git pull --ff-only
bash install.sh --source "$PWD"
```

精简版主菜单的 `[13]` 在线脚本更新已停用，避免上游整组更新恢复完整节点菜单；请用以上安装命令更新配套文件。

## CPU、内存与节点创建

sing-box 与 Xray 使用以下资源设置：

- 系统可见内存及 cgroup 限额取较小值。128MiB 环境的 `GOMEMLIMIT` 为 40MiB；256MiB 及更大环境默认 64MiB。
- `GOGC=100`，避免强制更频繁的垃圾回收；`GOMAXPROCS=1`，每个核心使用一个 Go 并行执行槽。
- 节点向导在输入关闭时立即退出并回滚，避免端口提示循环空转。退出 `sb` 后，管理菜单不常驻。
- 创建节点先完成输入与配置生成，再停止对应核心并等待退出；整份配置只启动一次核心检查，通过后启动服务。失败时恢复快照和此前服务状态。
- 删除节点、修改端口也复用一次核心校验；只改名称或客户端地址时更新分享配置，避免无用的核心检查与重启。
- 首次安装逐包补齐必要依赖，不自动安装或启动 cron，也不预装端口转发等功能的可选依赖；重复打开菜单复用依赖检查结果。
- 新建 sing-box 配置默认只记录 warning/error，减少日志写入和 CPU 开销。
- 没有 IPv6 或系统禁用 IPv6 时，新建节点监听 `0.0.0.0`；其余环境使用 `::`。

`GOMEMLIMIT` 是 Go 运行时软预算，进程 RSS 还包含二进制映射、TLS 与网络缓冲；`GOMAXPROCS=1` 也不是 CPU 百分比限速。实际占用随并发、连接数和吞吐变化。

### 已完成的资源测试

2026-11-19，在 Ubuntu 24.04 Docker NAT 容器中，分别验证 **128MiB / 256MiB、仅 IPv4 / 双栈** 四种组合，全部限制为 **0.5 CPU、禁用 swap**。使用 sing-box **1.13.21** 和 Xray **26.11.9**，两个服务核心同时运行。

| 场景 | 进程 RSS | CPU 占单核比例 |
| --- | ---: | ---: |
| sing-box 空闲，3 个节点，连续 60 秒 | 42.9–43.2MiB | 0.0% |
| Xray 空闲，2 个节点，连续 60 秒 | 32.8–33.0MiB | 0.0% |
| sing-box AnyTLS，1MiB/s，连续 30 秒 | 44.9–45.3MiB | 0.27–0.37% |
| sing-box TUIC v5，同上 | 46.8–47.3MiB | 0.53–0.77% |
| sing-box VLESS Reality，同上 | 47.5–48.4MiB | 0.63–0.90% |
| Xray VLESS Reality，同上 | 36.3–36.7MiB | 0.67–0.87% |
| Xray XHTTP TLS H2，同上 | 37.5–37.8MiB | 0.53–0.77% |

每个协议每组传输 30MiB，逐次核对响应内容。1MiB/s 约为 8.39Mbit/s，测试每秒建立 4 次下载请求；CPU 只统计服务核心进程，100% 代表一个逻辑 CPU。测试客户端、TLS 伪装目标与 HTTP 目标位于同一容器，夹具关闭公网 NTP 探测。该结果对应以上固定负载；更高吞吐和并发会增加 CPU 占用。

四组均通过五种节点创建、每次创建仅一次核心校验、无效配置与中断回滚、输入关闭退出及真实客户端转发；删除和改端口也通过单次校验与恢复测试，Xray 全删保留中转入口及其元数据。`oom` 和 `oom_kill` 全部为 **0**。[完整运行记录和原始数据](https://github.com/bobvhfhh/singbox-lite-smallmem/actions/runs/44551276623)。

另外在 **Ubuntu 24.04 / Alpine 3.22 × sing-box / Xray** 四组干净的 128MiB、0.5 CPU、无 swap NAT 容器中，从实际安装器和交互菜单安装依赖、下载核心、创建节点并再次启动 `sb`，全部通过，OOM 为 **0**。首次安装会短时占用 CPU，实测安装依赖和打开首个菜单消耗 1.16–6.41 CPU 秒；创建一个节点消耗 0.27–0.77 CPU 秒，完成后没有安装进程继续轮询。安装阶段容器内存峰值约 **97–128MiB**，应预留系统空间并优先只运行一个核心。[全新安装记录](https://github.com/bobvhfhh/singbox-lite-smallmem/actions/runs/44551276640)。

这次审查修复了旧版首次安装批量依赖导致的 OOM、yq 下载查询失败、未运行的 OpenRC 被误判、Xray 创建中断未恢复及服务启动后立即退出仍报告成功的问题。可复现脚本和测量口径见 `tests/`。

## NAT 使用要点

- VLESS Reality、AnyTLS、XHTTP 使用 **TCP** 端口映射；TUIC v5 使用 **UDP** 端口映射。
- 公网地址填运营商分配的出口地址，监听端口填分配的内部端口；内外端口不同时，客户端使用公网端口。
- XHTTP 经 Cloudflare 回源时，域名、回源端口及运营商映射必须对应；SSL 模式按节点提示配置。

端口映射由 NAT 运营商提供，服务器及面板防火墙需要允许对应 TCP/UDP 端口。

## 文件与路径

`install.sh` 安装这四个运行脚本：`singbox.sh`、`xray_manager.sh`、`advanced_relay.sh`、`parser.sh`。已安装路径为 `/usr/local/lib/singbox-lite-smallmem/`，启动命令为 `/usr/local/bin/sb`。现有服务器配置继续使用项目原有路径 `/usr/local/etc/sing-box/` 和 `/usr/local/etc/xray/`。

本地克隆用户可用 `--branch NAME`、`--install-dir DIR` 和 `--bin PATH` 调整分支和安装路径；`install.sh --help` 会显示选项。
