# singbox-lite 小内存精简版

这个仓库提供 sing-box + Xray 服务器管理脚本的低内存精简版本。新建节点菜单保留：

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

安装器会检查脚本语法，把运行脚本放在 `/usr/local/lib/singbox-lite-smallmem`。再次执行同一命令即可更新。现有配置保留在 `/usr/local/etc/sing-box/` 与 `/usr/local/etc/xray/`。

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

## 内存与节点创建

sing-box 与 Xray 使用以下资源设置：

- 系统可见内存及 cgroup 限额取较小值。128MiB 环境的 `GOMEMLIMIT` 为 40MiB；256MiB 及更大环境默认 64MiB。
- `GOGC=100`，避免强制更频繁的垃圾回收；`GOMAXPROCS=1`，每个核心使用一个 Go 并行执行槽。
- 创建节点先完成输入与配置生成，再停止对应核心并等待退出；整份配置只启动一次核心检查，通过后启动服务。失败时恢复快照和此前服务状态。
- 新建 sing-box 配置默认只记录 warning/error，减少日志写入和 CPU 开销。
- 没有 IPv6 或系统禁用 IPv6 时，新建节点监听 `0.0.0.0`；其余环境使用 `::`。

`GOMEMLIMIT` 是 Go 运行时软预算，进程 RSS 还包含二进制映射、TLS 与网络缓冲；`GOMAXPROCS=1` 也不是 CPU 百分比限速。实际占用随并发、连接数和吞吐变化。

### 已完成的资源测试

2026-11-19，在 Ubuntu 24.04 Docker NAT 容器中，分别验证 **128MiB / 256MiB、仅 IPv4 / 双栈** 四种组合，全部限制为 **0.5 CPU、禁用 swap**。使用 sing-box **1.13.21** 和 Xray **26.11.9**，两个服务核心同时运行。

| 场景 | 进程 RSS | CPU 占单核比例 |
| --- | ---: | ---: |
| sing-box 空闲，3 个节点 | 41.1–42.1MiB | 12 秒采样为 0.0% |
| Xray 空闲，2 个节点 | 32.6–32.9MiB | 12 秒采样为 0.0% |
| sing-box 三种协议分别转发 | 43.4–48.0MiB | 0.8–8.6% |
| Xray 两种协议分别转发 | 38.3–41.8MiB | 3.4–8.2% |

四组均通过一键安装器、五种节点创建、每次创建仅一次核心校验、无效配置回滚、真实客户端转发与内容校验；`oom` 和 `oom_kill` 全部为 **0**。每种协议持续转发约 5 秒，单组传输 11–59MiB。测试目标位于容器内，CPU 数据包含该测试负载，不能换算为公网满速能力。测试使用预装核心与依赖，包管理器安装阶段不计入这些资源数据。

可复现脚本在 `tests/`，运行记录见 [资源验证工作流](https://github.com/bobvhfhh/singbox-lite-smallmem/actions/workflows/smallmem.yml)。

## NAT 使用要点

- VLESS Reality、AnyTLS、XHTTP 使用 **TCP** 端口映射；TUIC v5 使用 **UDP** 端口映射。
- 公网地址填运营商分配的出口地址，监听端口填分配的内部端口；内外端口不同时，客户端使用公网端口。
- XHTTP 经 Cloudflare 回源时，域名、回源端口及运营商映射必须对应；SSL 模式按节点提示配置。

端口映射由 NAT 运营商提供，服务器及面板防火墙需要允许对应 TCP/UDP 端口。

## 文件与路径

`install.sh` 安装这四个运行脚本：`singbox.sh`、`xray_manager.sh`、`advanced_relay.sh`、`parser.sh`。已安装路径为 `/usr/local/lib/singbox-lite-smallmem/`，启动命令为 `/usr/local/bin/sb`。现有服务器配置继续使用项目原有路径 `/usr/local/etc/sing-box/` 和 `/usr/local/etc/xray/`。

本地克隆用户可用 `--branch NAME`、`--install-dir DIR` 和 `--bin PATH` 调整分支和安装路径；`install.sh --help` 会显示选项。
