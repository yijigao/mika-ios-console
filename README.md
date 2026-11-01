# Mika 控制台

非官方 iOS 验证客户端：在 iPhone 下令，由安卓手机上的 Mika 执行，并将进度、追问和结果回传。仅用于 SPEC.md 的 C 路线验证，不是可送审 MVP，不上架、不提供 TestFlight 工作流、不创建 ASC 记录。

SwiftUI，iOS 17+，无第三方依赖、无统计 SDK。Bundle ID 为 `com.jigaoyi.mikaconsole`，显示名为「Mika 控制台」。

## 协议来源

以本仓库 [SPEC.md](SPEC.md) 为验收依据，对接 [wangzan101/Mika](https://github.com/wangzan101/Mika) 的 `/api/v1` HTTP 远程任务 API（APK ≥ v0.1.23），不是 MCP JSON-RPC 客户端。上游资料：[CLI / HTTP 契约](https://github.com/wangzan101/Mika/blob/main/docs/cli.md)、[远程连接与安全边界](https://github.com/wangzan101/Mika/blob/main/docs/mcp.md)。上游协议设计归属见 [NOTICE](NOTICE)，许可全文见 [LICENSE](LICENSE)。本项目不修改安卓源码，也不代表上游。

本次能访问上游文档，但未取得可逐字段核对的 Kotlin 实现或真实响应。解析器接受直接任务对象及 `task` 包装、`task_id`/`id`、`status`/`state`；未知字段保留在详情。缺少 ID/状态视为协议不兼容，不捏造状态。时间、追问、结果字段的实际兼容性须真机确认；原始 JSON 可用于对照修正。

## 构建

1. 在安装 iOS SDK 的 Mac 上，用 Xcode 15+ 打开 `MikaConsole.xcodeproj`；推荐当前稳定版 Xcode。
2. 选择共享 Scheme `MikaConsole` 与 iOS 17+ 模拟器，运行。无需安装依赖或执行工程生成步骤。
3. 真机运行时，在 Signing & Capabilities 选择自己的开发团队；工程不内置团队、证书或描述文件。

无签名模拟器构建：

```sh
xcodebuild build \
  -project MikaConsole.xcodeproj \
  -scheme MikaConsole \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

`codemagic.yaml` 包含 `ios-simulator-build`，在 Codemagic 连接仓库后选择此工作流。其保存日志、xcresult 和模拟器 .app。构建步骤启用 pipefail，`tee` 不会吞掉 xcodebuild 失败。模拟器产物不能直接安装到 iPhone。

本机无 Xcode/Swift 工具链，本次未执行上述构建，也未运行 Codemagic，**没有编译通过证据**。请把首次成功构建的 URL、提交 SHA 和产物记录到 VALIDATION.md。可先运行 `python3 scripts/validate_project.py` 验证工程静态结构；它不是 Swift 编译器。

## 使用

1. 安卓 Mika「设置 › 连接电脑」开启网络访问；两台手机处于可信局域网或同一私有 VPN。不要使用 USB 专用令牌。
2. 在连接页输入 `http://手机IP:8765` 或 `IP:端口` 与令牌，点击「保存并检测连接」。基址只接受根地址，不接受 `/mcp`、`/api/v1`、内嵌凭据、查询参数或片段。留空令牌会复用同一基址的 Keychain 项。
3. 检测分别请求 `GET /api/v1/` 和 `/device`，显示完整版本、能力、输入上限及设备响应；设备返回 503 会明确显示，不能视为设备就绪。
4. 任务页下拉刷新最近十条及本地记录；新建多行目标，可选传入远程 conversation ID。提交成功跳转详情。
5. 详情先 GET 当前状态，随后优先 `POST /wait`（30 秒，客户端预算 65/70 秒）；wait 或初始读取失败后，本轮观察降级为每 5 秒 GET。追问或手机接管时 wait 可能立即返回，因此也保留 5 秒间隔。重新对齐、回前台或重开详情会再次优先尝试 wait。
6. `waiting_for_answer` / `waiting` 可以 answer；`running` 可以 steer；非终态可以请求 cancel。操作后重新 GET。接收回执和追加要求 message_id 可在详情查看，`steers` 的实际去向保留在完整任务状态中。
7. 切后台会取消详情读取，不申请后台保活。前台、重开、网络恢复时仅查询，绝不重新提交任务。持久化 ID 按规范化基址隔离；上游重启若丢失内存索引，404 会保留本地 ID 并提示，不擅自重建任务。

列表与恢复只有读取请求会重试；创建、answer、steer、cancel 均不会自动重发。提交结果不明时，先刷新最近任务并核对目标/时间，再决定如何操作。取消必须查询到 `cancelled` 才算成功；追加被接受也不代表要求已执行。

## 安全与限制

- HTTP 是明文，令牌和任务内容可能被同网人员看到；只在可信网络使用，勿做公网端口转发。私有 VPN 的连通性、ATS 和实际 IP 地址必须实机验证。
- ATS 仅设 `NSAllowsLocalNetworking`，没有 `NSAllowsArbitraryLoads`、禁用 TLS 校验或证书绕过；若地址被系统拦截，记录具体网络/iOS 条件，不以全局放宽 ATS 解决。
- 令牌仅持久化至 Keychain，按基址隔离，`WhenUnlockedThisDeviceOnly`，不写入 UserDefaults、源码、日志或仓库。运行时需短暂存在内存和 Authorization 请求头。连接页使用 SecureField；无主动请求日志，响应/错误展示会遮盖与当前令牌完全相同的文本。
- URLSession 使用 ephemeral 配置，无磁盘缓存、Cookie 存储，拒绝 HTTP 重定向，避免带令牌跳至别处。基址只保存在本机偏好设置。
- 后台遮罩用于降低 App 切换器暴露，不保证阻止用户主动截图。分享截图前检查任务内容与个人信息，不截图手机端令牌。
- 付款、同意、审批与手机接管只在安卓手机处理。客户端 UI 明示边界，不提供远程确认/解锁接口；answer 不能绕过上游限制。
- 本地仅持久化基址与任务 ID，不缓存目标、回答、结果或历史状态流；状态流是本次进程中观察到的快照，不是完整服务端事件日志。完整响应可能含敏感任务内容，请谨慎分享。
- 本阶段没有提交幂等键、推送通知、离线创建、后台持续执行或安卓端持久化保证。换手机、安卓服务重启或已清理的任务可能无法恢复。移除连接删除当前基址的令牌；本地 ID 保留，重新配置相同基址可继续对齐。

验收操作与证据位置见 [VALIDATION.md](VALIDATION.md)，实现清单与未验证事项见 [BUILD-NOTES.md](BUILD-NOTES.md)。
