# singbox-lite 小内存精简版

本目录基于本地保存的上游快照 `2164f9baf8eabf8faf1a3dccfb4b085ac74e9685`，只精简直连节点创建菜单，并为 sing-box 与 Xray 的 Go 核心配置低内存运行参数和创建时校验流程。已有节点仍可查看、删除和修改；主菜单的 Argo、Xray 管理、中转与端口转发功能也继续保留。

## 保留的直连节点

| 核心 | 新建菜单选项 |
| --- | --- |
| sing-box | VLESS + TCP + Reality + Vision |
| sing-box | AnyTLS |
| sing-box | TUIC v5 |
| Xray | VLESS + TCP + Reality + Vision |
| Xray | VLESS + XHTTP + TLS（H2 回源） |

其他已存在协议的管理逻辑仍在脚本中，精简的是新建菜单入口。

## 内存与创建校验

sing-box 和 Xray 服务及配置检查进程会使用按物理内存与 cgroup 限额计算的 `GOMEMLIMIT`，并设置 `GOGC=50`。创建节点时先完成交互和配置写入，再短暂停止原本正在运行的对应核心，执行一次完整核心配置校验，随后启动服务。失败时恢复配置快照，并恢复创建前的服务运行状态。

单独手动启动或重启服务仍执行配置预检。小内存机器上，配置检查结束后再启动服务可避免运行核心与检查核心的内存峰值重叠。

## 文件部署

将以下四个脚本放在同一目录，再运行 `singbox.sh`：

- `singbox.sh`
- `xray_manager.sh`
- `advanced_relay.sh`
- `parser.sh`

主脚本会从自身目录查找 Xray 和中转管理脚本。中转导入解析器也会优先从该目录查找 `parser.sh`。首次启动所需的系统工具仍按上游流程安装，Xray 管理所需的 `yq` 依赖也予以保留。

## 更新

主菜单 `[13] 更新脚本` 在此精简版中停用，以免上游更新恢复完整协议菜单。更新时从同一个上游提交重新取回四个配套脚本，再将本地精简改动应用到 `singbox.sh` 与 `xray_manager.sh`。不要只替换主脚本，否则会恢复上游的完整节点新建菜单。
