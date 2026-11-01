# 构建与实现说明

日期：2026-11-01。依据本目录 SPEC.md，从空白客户端工程构建。运行环境为 Linux，无 Xcode、iOS SDK 或 Swift 编译器。**尚无 Xcode/Codemagic 构建通过证据，不宣称已可编译或真机验收通过。**

## 文件清单

| 文件 | 用途 |
|---|---|
| SPEC.md | 用户提供的原始规格，未修改 |
| MikaConsole.xcodeproj/project.pbxproj | 手工标准 OpenStep 工程，单 App target，Debug/Release，iOS 17.0，Swift 5 语言模式，iPhone/iPad |
| MikaConsole.xcodeproj/xcshareddata/xcschemes/MikaConsole.xcscheme | 可共享 Scheme，构建、运行、分析、归档指向同一 target |
| MikaConsole/MikaConsoleApp.swift | App 入口、环境 Store、Tab、前台恢复、后台隐私遮罩与安全提示 |
| MikaConsole/Models.swift | 无第三方 JSON 保留、任务解析、状态/时间/结果、结构化错误 |
| MikaConsole/Keychain.swift | 按规范化基址隔离的 Keychain 增改查删 |
| MikaConsole/APIClient.swift | URL 校验、Bearer HTTP、禁止重定向、GET/list/wait、结构化错误及令牌遮盖 |
| MikaConsole/ConsoleStore.swift | 连接、任务 ID 持久化、恢复对齐、创建、状态流、长轮询降级、写操作后查询 |
| MikaConsole/ConnectionView.swift | 根地址与安全令牌输入、保存/检测/删除凭据、设备与 API 输出 |
| MikaConsole/TaskViews.swift | 任务列表、多行新建、详情、answer/steer/cancel 与回执 |
| MikaConsole/Info.plist | 显示名、版本、局域网用途、仅局域网 ATS 例外、启动屏与方向 |
| codemagic.yaml | ios-simulator-build 无签名工作流，保留日志、xcresult 和 .app |
| scripts/validate_project.py | 标准库静态验证，解析工程对象并检查引用、Scheme、配置、plist 和交付约束 |
| LICENSE | 系统标准 Apache License 2.0 全文，含附录 |
| NOTICE | 上游协议设计归属、非官方声明、独立实现说明 |
| README.md | 用途、协议链接、构建步骤、使用方式、数据处理与安全边界 |
| VALIDATION.md | SPEC 真机标准逐项待实测、构建证据空缺、补充回归与记录模板 |
| BUILD-NOTES.md | 本文件 |
| .gitignore | 排除构建目录、用户工程状态、日志及签名材料 |

环境已有的 `codex-build-1.log` 不是客户端源码或构建通过证据；未纳入工程，*.log 已忽略。未提交 git commit，也未改变 SPEC.md。

## 关键实现取舍

- 工程不依赖 XcodeGen、CocoaPods、SPM 或第三方库，不包含代码生成构建脚本。7 个 Swift 文件在 PBXFileReference、PBXBuildFile 和 PBXSourcesBuildPhase 中完整对应；Info.plist 由明确路径引用，不复制到 Resources。系统 SwiftUI/Foundation/Security/Combine 由 SDK 模块自动链接。
- 部署目标 iOS 17.0，使用 iOS 17 已提供的 SwiftUI NavigationStack、LabeledContent、顶栏 ToolbarItem、TextEditor、scenePhase 和结构化并发。Swift 5 语言模式与明确 MainActor UI/Store 用于避免把尚未验证的 Swift 6 严格并发迁移引入本阶段。
- 连接检测两个接口分别处理错误，API 成功但设备 503 时仍展示两者结果。版本、能力与输入上限保留为可检视的 JSON，服务端负责未知具体上限的权威校验。
- 所有 URL 根地址必须不含用户凭据/路径/查询/片段，缺省 scheme 为 HTTP；允许用户选择 HTTPS，TLS 使用系统默认验证。任务 ID 限制为单个路径组件。HTTP 重定向被拒绝，不跨主机发送令牌。
- 令牌按基址存 Keychain，使用 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`；运行时保留内存凭据。请求使用 ephemeral URLSession，禁用磁盘缓存与 Cookie 存储，没有请求日志。后台显示遮罩；不能保证阻止主动截图。
- 本地 UserDefaults 只存规范化基址和按基址区分的任务 ID；任务内容、状态历史与结果只在内存。移除连接删除当前 Keychain 项，保留 ID 以便同地址重连。协议未提供服务实例 ID，因此同一地址换设备/安卓重启须人工核对。
- 新建任务只发一次，收到 ID 立即记录；即使响应剩余字段不兼容，也可跳详情查询。响应完全丢失时没有 ID，提示用户核对最近列表，不自动重发。answer/steer/cancel 也不做自动重试。
- 详情先 GET，然后 wait(30 秒)，客户端请求/资源预算 65/70 秒。读取或 wait 失败降级为每次休息 5 秒再 GET；本轮不自动反复探测 wait。等待回答或手机接管时限速，避免服务端立即响应导致忙循环。404 停止观察并保留 ID；其他断线继续重试。重进详情、前台恢复或手动重新对齐会重新尝试 wait。
- 列表先读取最近十条，再按已存 ID 补查；退出后台/重开均只有读取行为，无后台模式或静默创建。观察任务通过 SwiftUI task 生命周期取消，连接代号阻止旧连接结果污染新连接。重叠读取不会把已知终态恢复成运行态。
- 取消与追加回执和最终生效分开呈现；操作后 GET 对齐状态，取消只以 cancelled 确认。steers 的 message_id/state 保留在完整状态里，不把 accepted/joined 当作业务要求成功。
- 状态流为本进程观察到的最多 200 条变化，不宣称完整事件历史。终态耗时优先使用服务端字段或创建/结束时间差，不用观察时长冒充执行耗时；字段缺失则明确提示。
- 上游文档可访问，直接源码和 API 树未能取得：shell 出站代理连接失败，web 工具多个源码路径不可用。没有绕过网络限制。本次只确认文档契约，不声称核对过具体 Kotlin 结构。模型为常见字段别名和未知字段保留做兼容，真实响应校准仍属于待测项。

## 已执行检查

- `python3 scripts/validate_project.py`：通过。自包含 OpenStep 子集解析器检查全部对象引用、7 个源文件各一次进入构建、单 target、Debug/Release、共享 Scheme、plist、ATS、CI 命令、许可关键段。
- Python 标准库解析 XML Scheme 与 Info.plist：通过（包含于上述脚本）。
- 逐一对新增交付文件执行 `git diff --no-index --check /dev/null <file>`：通过，无空白错误。
- LICENSE 与 `/usr/share/common-licenses/Apache-2.0` 的 SHA-256 一致；保留标准许可全文及附录。
- 没有输入真实令牌，无网络请求携带真实凭据；源代码未包含硬编码令牌值。

## 无法本地验证的点

- Swift 语法/类型检查、SDK 链接、SwiftUI 布局、Scheme 被 Xcode 识别、编译产物的 Info.plist 合并结果与安装启动。静态检查不能代替这些。
- Codemagic 工作流实际启动、所选 Xcode/SDK 的构建成功与可下载产物。本环境未配置可调用的 Codemagic 服务，不能生成通过证据；需运行后填写 VALIDATION.md。
- 局域网权限、数字 IP/.local/IPv6/私有 VPN 的 ATS 行为及 iPhone 网络路由。工程没有全局 ATS 例外；若失败，先记录实际地址与系统错误。
- Keychain 在真机安装、锁屏、重装时的行为；后台遮罩对切换器截图的时序。
- APK ≥ v0.1.23 的实际任务字段与所有错误格式、能力差异、追问/追加去向、结果与耗时字段；目前使用的容错别名尚未通过真实 fixture 校准。
- 网络中断、长轮询超时、写入响应丢失、后台/强杀恢复、取消生效及三项真实任务；没有设备与模型执行条件。具体操作与通过判据已列入 VALIDATION.md，全部待实测。
