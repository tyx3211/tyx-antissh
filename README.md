# 反重力代理配置工具

> 当前 Antigravity 远端 server 的实现会在二进制中硬编码访问 `localhost:9222/json/list`。在多人共享服务器上，一旦别的用户先占住 `9222`，远端 server 可能卡在 waiting for language server start，导致 agent pane 一直加载不出来。
>
> 这个 fork 额外做了一个等长二进制替换兜底，用来避开这个问题。

> 当前 fork 默认使用 `gg` 作为代理后端，并默认按纯 Go 路径编译（`CGO_ENABLED=0`）。这样更适合 `no-sudo`、`conda`、共享开发机等环境，也避免了 `cgo` 在部分 Conda 工具链下注入编译标志后引发的转义/解析问题。

## 当前设计

- 默认后端是 `gg`
- `gg` 使用 `ptrace` 接管目标进程网络调用，适合 Linux 用户态、无 sudo 场景
- `socks5` 是默认推荐路径；`http/https` 也支持，但 `gg` 会自动附加 `--noudp`
- `graftcp` 仍然保留，作为兼容后端；它更像传统的本地转发方案，需要 `graftcp-local`
- 本仓库中的 `refresh_antissh.sh` 用于处理 IDE 升级后版本目录变化、残留进程和重新套壳

## 系统支持

| 系统        | 支持情况 | 说明 |
| ----------- | -------- | ---- |
| **Linux**   | 支持     | 默认使用 `gg`；可切换到 `graftcp` |
| **macOS**   | 不支持   | `gg/graftcp` 都依赖 Linux 的 `ptrace`，推荐使用 Proxifier 或 TUN |
| **Windows** | 不支持   | 推荐使用 Proxifier 或 TUN；WSL 可按 Linux 方式使用 |

## 快速开始

### 1. 下载脚本

```bash
curl -O https://raw.githubusercontent.com/ccpopy/antissh/main/antissh.sh
chmod +x antissh.sh
```

### 2. 运行脚本

默认走 `gg`：

```bash
bash ./antissh.sh
bash ./antissh.sh --backend gg
```

如需切换到 `graftcp`：

```bash
bash ./antissh.sh --backend graftcp
ANTISSH_PROXY_BACKEND=graftcp bash ./antissh.sh
```

### 3. 代理地址格式

默认推荐：

```text
socks5://127.0.0.1:10808
```

也支持：

```text
http://127.0.0.1:10809
https://127.0.0.1:10810
```

说明：

- `gg + socks5`：保留 UDP/DNS 接管能力，行为最完整
- `gg + http/https`：脚本会自动加 `--noudp`，此时 gg 不接管 UDP/DNS，域名解析回退到本机 resolver
- `graftcp`：主要支持 `socks5/http`；若输入 `https://`，脚本会按 `http://` 处理

## 后端对比

| 维度 | `gg`（默认） | `graftcp`（兼容） |
| ---- | ------------ | ----------------- |
| 运行方式 | `ptrace` 接管目标进程 | `graftcp + graftcp-local` |
| 是否需要本地监听端口 | 否 | 是 |
| 默认编译方式 | 纯 Go（`CGO_ENABLED=0`） | 仍可能涉及 `gcc/make/cgo` 兼容问题 |
| DNS/UDP 处理 | `socks5` 下可接管；`http/https` 下自动 `--noudp` | 不负责完整 UDP 接管 |
| 推荐程度 | 默认优先 | 仅保留兼容场景 |

## 脚本当前流程

### `gg` 路径

1. 询问代理地址
2. 说明 `gg` 的 DNS / UDP 行为
3. 做一次轻量级代理探测
   - 该探测只用于决定后续 `git/curl` 下载阶段是否临时导出代理环境变量
   - 这一步不等于最终 `language_server` 的真实运行路径
4. 检查依赖：`git / go / curl`
5. 编译或复用 `gg`
6. 查找最新版本的 `language_server_*`
7. 备份原始二进制，写入 wrapper
8. 测试 `gg` 代理链路

### `graftcp` 路径

1. 询问代理地址
2. 配置 `graftcp-local` 监听端口
3. 选择 `graftcp` 的 DNS 策略（是否强制 `netdns=cgo`）
4. 做一次轻量级代理探测
5. 检查依赖：`git / make / gcc / go / curl`
6. 编译或复用 `graftcp`
7. 查找最新版本的 `language_server_*`
8. 备份原始二进制，写入 wrapper
9. 启动 `graftcp-local` 并测试代理链路

## IDE 升级后的推荐流程

Antigravity 升级后，远端通常会新增一个新的版本目录；这时旧 wrapper 不会自动迁移到新目录。

推荐直接使用 `refresh_antissh.sh`：

```bash
# 1) 断开 Remote-SSH 后，先清理残留
bash ~/antissh/refresh_antissh.sh --cleanup-only

# 2) 重新连接一次，让 IDE 下载新的远端 server
# 3) 再断开 Remote-SSH，重新套代理
bash ~/antissh/refresh_antissh.sh
bash ~/antissh/refresh_antissh.sh --backend graftcp
```

这个脚本会：

- 清理残留 `language_server / gg / graftcp-local` 进程
- 清理残留 FIFO / 临时标记
- 显示当前最新远端 server 版本目录
- 默认最后重新执行 `antissh.sh`

## 常见问题

### 1. `.bak` 文件是不是异常？

不是。`.bak` 是原始 `language_server_*` 二进制；当前同名文件会被替换成 wrapper，这是预期行为。

### 2. 为什么脚本前半段探测成功，但实际远端还是不通？

因为前半段的“轻量级代理探测”只决定后续 `git/curl` 下载阶段要不要临时导出代理环境变量。它不是完整的 Antigravity 会话验证。

真正相关的是脚本后半段的“代理链路测试”和远端运行日志：

```bash
tail -n 120 ~/.graftcp-antigravity/wrapper.log
```

### 3. 为什么 `gg + http/https` 下 DNS 表现和 `gg + socks5` 不一样？

因为 `http/https` 节点不提供完整 UDP 转发能力，脚本会自动给 `gg` 附加 `--noudp`。此时 gg 不接管 UDP/DNS，域名解析回退到本机 resolver。

如果希望尽量保留 gg 的 DNS/UDP 能力，优先使用 `socks5`。

### 4. 为什么 `graftcp` 还要问系统 DNS？

那是 `graftcp` 分支自己的历史兼容逻辑，不是 `gg` 的行为。当前脚本已经把这条提示限制在 `graftcp` 路径里。

### 5. IDE 升级后代理失效怎么办？

优先使用：

```bash
bash ~/antissh/refresh_antissh.sh --cleanup-only
bash ~/antissh/refresh_antissh.sh
```

### 6. agent pane 还是一直 loading，应该先看什么？

先看这几项：

```bash
# 当前 wrapper 日志
tail -n 120 ~/.graftcp-antigravity/wrapper.log

# 当前最新 Antigravity 版本目录
ls -1 ~/.antigravity-server/bin | sort -V | tail -n 5

# 相关进程
pgrep -a language_server || true
pgrep -a gg || true
pgrep -a graftcp-local || true
```

## WSL 说明

如果在 WSL 中使用本脚本，建议开启 **Mirrored 网络模式**，这样 WSL 可以直接访问宿主机的 `127.0.0.1` 代理。

`.wslconfig` 示例：

```ini
[wsl2]
networkingMode=mirrored
```

然后执行：

```powershell
wsl --shutdown
```

重新进入 WSL 后，即可直接使用：

```text
socks5://127.0.0.1:10808
http://127.0.0.1:10809
```

## macOS / Windows 替代方案

由于 `gg/graftcp` 都依赖 Linux 的 `ptrace`，macOS / Windows 上推荐：

1. **Proxifier**：对 IDE 进程做用户态代理
2. **TUN 模式**：使用 Clash、Surge 等工具做透明代理

## Antigravity Server 手动安装脚本

远端如果因为网络受限而无法自动下载 `.antigravity-server`，可使用 `installAntigravity.sh` 手动安装。

### 下载脚本

```bash
curl -O https://raw.githubusercontent.com/ccpopy/antissh/main/installAntigravity.sh
chmod +x installAntigravity.sh
```

### 使用方法

1. 运行脚本：`bash ./installAntigravity.sh`
2. 按提示从 Antigravity 客户端获取版本信息：
   - 打开 Antigravity 客户端
   - 点击 **Help → About**
   - 点击 **Copy** 按钮
3. 将复制的版本信息粘贴到终端，连续按两次回车
4. 脚本会自动下载并安装对应版本

> 此脚本会将组件安装到 `~/.antigravity-server/bin/<commit-id>/` 目录，与 IDE 自动下载的路径一致。

## 依赖要求

### 默认 `gg` 后端

- Go >= 1.18
- Git
- curl

### `graftcp` 后端

- Go >= 1.13
- Git
- Make
- GCC
- curl

## 鸣谢

- [gg](https://github.com/mzz2017/gg)
- [graftcp](https://github.com/hmgle/graftcp)
- [思路来源](https://www.v2ex.com/t/1174113)

### 特别感谢

<a href="https://github.com/ccpopy/antissh/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=ccpopy/antissh" />
</a>

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=ccpopy/antissh&type=date&legend=top-left)](https://www.star-history.com/#ccpopy/antissh&type=date&legend=top-left)
