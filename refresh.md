简化流程见 `antissh/refresh_antissh.sh:1`。

它会做这些事：

- 清理残留进程：`language_server` / `gg` / `graftcp-local`，见 `antissh/refresh_antissh.sh:26`
- 清理残留 FIFO / 临时标记，见 `antissh/refresh_antissh.sh:87`
- 显示当前最新远端 server 版本目录，见 `antissh/refresh_antissh.sh:96`
- 默认最后重新执行 `antissh.sh`，见 `antissh/refresh_antissh.sh:120`

推荐在每次 Antigravity 升级后的固定流程：

1. 先断开 Remote-SSH 会话
2. 先清理一次旧进程和旧状态：
   `bash ~/antissh/refresh_antissh.sh --cleanup-only`
3. 重新连接 Remote-SSH，让 IDE 下载最新远端 server 版本；完成后再次断开
4. 重新套代理：
   `bash ~/antissh/refresh_antissh.sh`
   或显式指定后端：
   `bash ~/antissh/refresh_antissh.sh --backend graftcp`
5. 再重新连接 Remote-SSH
6. 若仍异常，优先查看：
   `tail -n 120 ~/.graftcp-antigravity/wrapper.log`

补充说明：

- 默认后端是 `gg`，因此重跑 `antissh.sh` 时通常不会再询问 `graftcp-local` 端口
- 只有显式使用 `ANTISSH_PROXY_BACKEND=graftcp` 时，才会进入 `graftcp-local` 端口和 DNS 策略那套交互
- 现在也可以直接用 `--backend gg|graftcp` 显式指定，无需只依赖环境变量
