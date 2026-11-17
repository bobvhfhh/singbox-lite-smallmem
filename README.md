# singbox-lite 小内存精简版

这个仓库提供 sing-box + Xray 服务器管理脚本的低内存精简版本。新建节点菜单保留：

| 核心 | 支持新建 |
| --- | --- |
| sing-box | VLESS + TCP + Reality + Vision、AnyTLS、TUIC v5 |
| Xray | VLESS + TCP + Reality + Vision、VLESS + XHTTP + TLS（H2 回源） |

原有节点查看、删除、端口修改、Argo、中转、端口转发和 Xray 管理仍保留。

## 一键安装

安装器需要 `bash`、`gh`、`base64` 和 `sudo`。服务器上的 GitHub CLI 账号需能读取此私有仓库，令牌至少带有 `repo` 读取权限。安装器先下载并检查 Bash 语法，再调用 `sudo` 安装到 `/usr/local/lib/singbox-lite-smallmem`，并创建 `/usr/local/bin/sb-lite` 启动命令。脚本首次运行时会按原项目流程安装系统依赖；需要创建节点时，再从菜单安装对应核心。安装器只替换脚本，不改动 `/usr/local/etc/sing-box/` 或 `/usr/local/etc/xray/` 中的现有配置。

目前仓库为私有。服务器需要安装 GitHub CLI (`gh`)，并先登录：

```bash
gh auth login -h github.com
```

登录后用这一条命令安装；安装器会用已登录的 `gh` 下载私有文件，并在写入系统目录时调用 `sudo`：

```bash
gh api 'repos/bobvhfhh/singbox-lite-smallmem/contents/install.sh?ref=main' --jq .content | tr -d '\n' | base64 -d | bash
```

匿名 `curl | sudo bash` 无法读取私有仓库。仓库公开后，可以直接一行安装：

```bash
curl -fsSL https://raw.githubusercontent.com/bobvhfhh/singbox-lite-smallmem/main/install.sh | sudo bash
```

也可以用 `gh` 克隆后从本地安装：

```bash
gh repo clone bobvhfhh/singbox-lite-smallmem
cd singbox-lite-smallmem
sudo bash install.sh --source "$PWD"
```

## 运行与更新

安装完成后启动管理菜单：

```bash
sudo sb-lite
```

重新运行一键安装命令会更新已安装的四个配套脚本。更新本地克隆版：

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

`install.sh` 安装这四个运行脚本：`singbox.sh`、`xray_manager.sh`、`advanced_relay.sh`、`parser.sh`。已安装路径为 `/usr/local/lib/singbox-lite-smallmem/`，启动命令为 `/usr/local/bin/sb-lite`。现有服务器配置继续使用项目原有路径 `/usr/local/etc/sing-box/` 和 `/usr/local/etc/xray/`。

本地克隆用户可用 `--branch NAME`、`--install-dir DIR` 和 `--bin PATH` 调整分支和安装路径；`install.sh --help` 会显示选项。
