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
(curl -LfsS https://raw.githubusercontent.com/bobvhfhh/singbox-lite-smallmem/main/install.sh -o /tmp/sb-lite-install || wget -q https://raw.githubusercontent.com/bobvhfhh/singbox-lite-smallmem/main/install.sh -O /tmp/sb-lite-install) && sudo bash /tmp/sb-lite-install
```

安装器会检查脚本语法，把运行脚本放在 `/usr/local/lib/singbox-lite-smallmem`。再次执行同一命令即可更新。需要 `bash`、`curl` 或 `wget` 和 `sudo`。现有配置保留在 `/usr/local/etc/sing-box/` 与 `/usr/local/etc/xray/`。

## 运行与更新

安装器每次运行都会打开管理菜单。安装后也可随时使用原项目同名命令启动：

```bash
sudo sb
```

重新运行上面的一键安装命令即可更新。也可以更新本地克隆版：

```bash
cd singbox-lite-smallmem
git pull --ff-only
sudo bash install.sh --source "$PWD"
```

精简版主菜单的 `[13]` 在线脚本更新已停用，避免上游整组更新恢复完整节点菜单；请用以上安装命令更新配套文件。

## 内存与节点创建

sing-box 与 Xray 使用按系统可见内存和 cgroup 限额计算的 `GOMEMLIMIT`，并设置 `GOGC=50`。创建节点时先完成交互输入，再暂时停止原本运行的对应核心，执行一次核心配置检查，随后重新启动。创建失败时恢复配置快照及此前的服务运行状态。

此脚本创建本机监听节点，不会替 VPS 提供公网 IP、NAT 端口映射或安全组放行。连接地址和端口可达性仍需符合服务器网络环境。

## 文件与路径

`install.sh` 安装这四个运行脚本：`singbox.sh`、`xray_manager.sh`、`advanced_relay.sh`、`parser.sh`。已安装路径为 `/usr/local/lib/singbox-lite-smallmem/`，启动命令为 `/usr/local/bin/sb`。现有服务器配置继续使用项目原有路径 `/usr/local/etc/sing-box/` 和 `/usr/local/etc/xray/`。

本地克隆用户可用 `--branch NAME`、`--install-dir DIR` 和 `--bin PATH` 调整分支和安装路径；`install.sh --help` 会显示选项。
