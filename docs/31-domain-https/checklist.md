# App 域名切换清单

- [x] 需求已列明；无 UI 变动。
- [x] 修改默认地址，移除 HTTP 放行，同步端点安全测试；准备 0.5.14（35）。
- [x] 设置 GitHub 构建变量 MOVELIQ_SERVICE_URL=https://moveliq.work/api，云端验收并行推进。
- [x] 本地 Swift 6.0.3 可移植鉴权 9/9 通过；Info.plist 已无 ATS 例外，两个构建默认值一致，git diff --check 通过。
- [x] App 功能提交 5fdaa83e9509181724ce9f779a7d64207bfd4110 已推送当前分支；Apple CI 的编译、iOS 487 项单测和 28 项 Apple 音频检查通过（0 失败）。[CI / IPA](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/37917041170)，完整工作流已成功，IPA 归档完成。
- [x] 云端 API https://moveliq.work/api、WSS /api/v1/realtime、管理台 /admin/ 已上线；管理员 7/7、真实模型 SSE/WSS 150 秒 12/12 通过。Service 源码 3becdb6，部署文档 aee4928。新包需重新登录，旧 IP 本地记录不自动合并。

- [x] [0.5.14（35）IPA 下载](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/37917041170/artifacts/11610593869) 已下载并校验：ZIP 完整，App/Widget 版本正确，MoveliqServiceURL=https://moveliq.work/api，均无 ATS HTTP 例外，麦克风/摄像头/语音识别权限存在。verify_ipa.py 通过，MLX Metal 资源完整且无模型权重。大小 8,818,209 字节，SHA256 a90593e9b190e6eb34e96f3207a9743b942ef5b48ae406339a1f2875dd511493；需 AltStore/Sideloadly 重签安装。

设备与 IPv6-only 网络验证待装机，不由服务器合成音频验收替代。

日志：本地 /tmp/moveliq-domain-app-auth.log；Apple /tmp/moveliq-0.5.14-build-log/build.log 和 /tmp/moveliq-0.5.14-audio.log。后续本提交仅回填文档，不改变 CI 与 IPA 对应的功能源码 5fdaa83。
