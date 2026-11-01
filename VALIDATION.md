# 验证记录

记录日期：2026-11-01。判定依据：SPEC.md。当前结论：**尚未通过构建与真机验收**。此环境没有 Xcode、iOS SDK、Swift 工具链、iPhone/安卓设备及可执行的 Codemagic 连接；不能把静态检查或已实现代码计作端到端通过。

## 已执行的静态检查

`python3 scripts/validate_project.py`：通过。解析 OpenStep 工程、检查对象引用、7 个 Swift 源文件恰好各一次进入 Sources、Debug/Release 设置、共享 Scheme、Info.plist、局域网 ATS、CI 命令与 Apache 许可关键段。该脚本不检验 Swift 类型或运行时行为。

`git diff --check --no-index /dev/null <新增文本文件>` 等价的逐文件空白检查：结果见 BUILD-NOTES.md。没有使用真实令牌或真实任务数据。

## 编译证据（待填写）

| 项目 | 状态 | 原因 / 待记录证据 |
|---|---|---|
| Codemagic `ios-simulator-build` | 未执行 | 需连接仓库并运行工作流；记录构建 URL、提交 SHA、Xcode/SDK 版本、结束时间、xcodebuild.log 与 xcresult |
| Xcode 模拟器启动 | 未执行 | 本机无 Xcode；记录 iOS 版本、启动截图及基本导航 |
| iPhone 签名安装 | 未执行 | 需本人的开发团队与 iPhone；记录设备与 iOS 版本，不记录凭据 |

## SPEC 真机通过标准

| 标准 | 状态 | 操作与通过判据 | 待填证据 |
|---|---|---|---|
| 1. 连接检测 | 待实测：无设备 | 开启安卓网络访问，iPhone 输入基址和令牌；GET 根与 device 成功，能看到版本、能力、设备状态。503 不算设备通过 | 安卓 APK 版本、iOS、网络类型、脱敏响应与截图 |
| 2① 网页任务 | 待实测：无设备/模型 | 创建天气/资讯汇总任务；手机执行，iPhone 查到终态 done，结果可见 | 目标、任务 ID、起止时间、最终结果及脱敏截图 |
| 2② App 操作任务 | 待实测：无设备 | 创建打开指定 App 查信息任务；手机真实执行并回传结果 | App、任务 ID、执行观察与结果 |
| 2③ steer 或 answer 至少一次 | 待实测：无设备 | 另建任务；running 时追加要求，或 waiting_for_answer 时回答；继续查询至结束，人工确认要求/回答实际影响结果。accepted / joined 本身不等于业务成功 | 任务 ID、message_id（如有）、状态变化、最终结果 |
| 3. cancel 生效 | 待实测：无设备 | 运行中点击取消，继续查询到 cancelled；只收到 accepted 不通过 | 请求回执及后续 cancelled 查询证据 |
| 4. 杀进程恢复 | 待实测：无设备 | 任务执行中杀掉 iOS App，再打开；同一 ID 从本地恢复、状态与安卓对齐；核对没有第二次 POST /tasks | 原任务 ID、重开前后截图、安卓任务数 / 请求计数 |
| 5. 令牌与付款边界 | 待实测：无设备 | 检查日志、截图、仓库均无真实令牌；若触发付款/同意，确认留在安卓手机，远程 answer 不能代替批准；未触发则记“未触发”，不能编造通过 | 脱敏审查记录、手机提示与动作观察 |

通过条件：上述所有必测项通过，且构建证据齐全。任何失败记录原始错误与复现条件，区分协议、网络、iOS 限制或上游问题，再决定修复或停止。

## 补充回归清单

- [ ] Keychain：保存后重开可连接；更换令牌更新；移除后不能继续请求；锁屏/Keychain 不可用时错误清晰。任务 ID 和基址以外不进入 UserDefaults。
- [ ] 网络：局域网权限允许/拒绝、不同 Wi-Fi、访客隔离、VPN、数字 IPv4 / IPv6、.local 名称、安卓断网恢复；不放宽全局 ATS。
- [ ] 错误：400 / 401 / 403 / 404 / 409 / 429 / 503、非法 JSON 与 HTML、服务端重定向均安全可见；错误 code/message 不泄露令牌。
- [ ] wait 正常阻塞后状态改变；wait 路由不支持/超时/返回格式不匹配时，每次 GET 之间至少等 5 秒；网络恢复后能对齐；终态停止观察。
- [ ] starting / running / paused / waiting_for_answer / waiting_on_phone / done / failed / cancelled 的 UI；手机接管态无 answer/steer；终态无写操作。
- [ ] 追问和接管状态 wait 立即返回时无高频请求；后台取消读取，回前台恢复；导航返回、换连接后不会将旧连接任务写入新连接。
- [ ] 创建/answer/steer/cancel 响应丢失不自动重发；创建不明时能通过最近列表找到任务；创建返回 ID 后即使详情解析不兼容仍保留 ID。
- [ ] 最近任务之外的本机 ID 也被查询；安卓重启造成 404 时 ID 仍保留且不新建；连接 A/B 的 ID 与令牌互不混用。
- [ ] 用真实响应核对任务 JSON 包装、目标、创建时间单位、追问/结果结构、最终耗时字段；原始任务状态仍可查看。
- [ ] 多行中文、空白输入、服务端输入长度上限、动态字体、深色模式、横屏、iPad、空列表及较长结果。

## 单次实测记录模板

- 日期 / 操作人 / 构建提交 / 构建 URL：
- iPhone 型号 / iOS / 安卓型号 / APK 版本：
- 网络类型（勿公开完整配置） / 本地网络权限：
- 标准编号 / 前置条件 / 步骤：
- 任务 ID / 请求路径 / HTTP 状态 / code / 脱敏 message：
- 预期 / 实际 / 通过或失败：
- 原始证据位置（先移除令牌和个人信息）：
- 归因：协议 / 网络 / iOS 限制 / 上游 / 待确认：
- 后续：修复 / 复测 / 停止及原因：

## 构建证据（2026-11-01 追加）

- GitHub Actions CI run 41317717147（repo: yijigao/mika-ios-console，job 124881208703）：macos-26 runner，xcodebuild build（generic iOS Simulator，CODE_SIGNING_ALLOWED=NO）**BUILD SUCCEEDED**，47 秒。链接：https://github.com/yijigao/mika-ios-console/actions/runs/41317717147
- 含义：Swift 源码与工程结构在真实 Xcode 下编译通过。仍未做：签名构建、TestFlight 分发、真机安装与五项真机标准实测。
