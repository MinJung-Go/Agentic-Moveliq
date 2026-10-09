# App 域名切换清单

- [x] 需求已列明；无 UI 变动。
- [x] 修改默认地址，移除 HTTP 放行，同步端点安全测试；准备 0.5.14（35）。
- [x] 设置 GitHub 构建变量 MOVELIQ_SERVICE_URL=https://moveliq.work/api，云端验收并行推进。
- [x] 本地 Swift 6.0.3 可移植鉴权 9/9 通过；Info.plist 已无 ATS 例外，两个构建默认值一致，git diff --check 通过。
- [ ] 提交推送当前分支并执行 Apple CI；记录提交号及测试数量。
- [ ] 回填云端入口和安装注意事项。

设备与 IPv6-only 网络验证待装机，不由服务器合成音频验收替代。
