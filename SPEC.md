# Mika iOS 控制端（C 路线）验证规格 v1

**立项依据**：Joey 2026-11-01 22:33 批准 C 验证（≤1 人周）。评估案卷：`~/workspace/mika-ios-eval/REPORT.md`。
**目标**：证明「iPhone 下令 → 安卓手机上的 Mika 执行 → 进度/结果回传 iPhone」这条链在真机上成立。本阶段是验证，不是可送审 MVP，不上架、不公开发布。

## 上游协议（已源码/文档核实，Mika APK ≥ v0.1.23）

手机端远程任务服务，HTTP + Bearer 令牌，基址 `http://<手机IP>:8765`，路径前缀 `/api/v1`：

| 方法与路径 | 说明 |
|---|---|
| GET `/api/v1/` | 版本、能力、输入上限 |
| GET `/api/v1/device` | 设备状态（未提供时 503） |
| POST `/api/v1/tasks` | body `{goal, conversation?}`，201 返回任务状态与 ID |
| GET `/api/v1/tasks?limit=10` | 最近远程任务（1–50） |
| GET `/api/v1/tasks/{id}` | 任务当前状态 |
| POST `/api/v1/tasks/{id}/wait` | body `{timeout_s: 1–50}`，状态变化或结束返回 |
| POST `/api/v1/tasks/{id}/answer` | body `{text}`，回答当前追问 |
| POST `/api/v1/tasks/{id}/steer` | body `{text}`，仅 running 任务，202 |
| POST `/api/v1/tasks/{id}/cancel` | body `{}` |

- 错误为结构化 JSON（code/message）+ HTTP 状态：400 校验、404 任务不存在、409 状态不允许、503 服务拒绝。
- 连接前提（手机端，Joey 操作）：Mika 设置 › 连接电脑 › 打开「网络访问」；服务端只接受局域网/私有 VPN 来源地址；明文 HTTP，只在可信网络使用。付款与需同意的操作只能在手机端处理，远程任务不会替用户确认——此边界在客户端 UI 上要明示。
- 令牌只存 iOS Keychain，绝不写入日志、源码或仓库。

## 客户端范围（SwiftUI，iOS 17+）

1. **连接页**：输入基址（IP:端口）与令牌（Keychain 存储）；「检测连接」调 GET / 与 GET /device，显示版本/能力/设备状态或结构化错误。
2. **任务列表**：GET /tasks 拉最近任务（ID、目标摘要、状态、时间）；下拉刷新。
3. **新建任务**：输入 goal（支持多行），POST /tasks，成功后跳详情。
4. **任务详情**：轮询 GET /tasks/{id}（结合 wait 长轮询优先，失败降级 5 秒轮询）；展示状态流与结果文本；任务处于 waiting/追问态时可 answer；running 时可 steer（追加要求）与 cancel；终态显示最终结果与耗时。
5. **断线恢复**：App 被杀/切后台/网络中断后重开，能从本地保存的任务 ID 列表重新拉取状态并对齐，不重复提交。
6. **工程要求**：Info.plist 含 NSLocalNetworkUsageDescription 与 ATS 局域网例外（NSAllowsLocalNetworking），不放宽全局 ATS；无第三方依赖、无统计 SDK；界面简体中文；深色模式可读即可，不做视觉打磨。
7. **开源预备**：仓库含 LICENSE（Apache-2.0）、NOTICE（注明衍生自 wangzan101/Mika 的协议设计、非官方项目）、README（用途、协议来源、构建方法、安全边界）。

## 构建与交付

- 工程目录：`~/workspace/mika-ios-client/`（本目录，git 管理）。
- bundle id：`com.jigaoyi.mikaconsole`；显示名「Mika 控制台」。
- codemagic.yaml 提供 `ios-simulator-build` 工作流（无签名、simulator 构建）用于编译验证；TestFlight 工作流本阶段不做（待 ASC 应用记录建立后另行接入）。
- 交付物：可编译的完整工程 + codemagic 模拟器构建通过的证据 + `VALIDATION.md`（按下节标准逐项记录实测结果，未测项写明原因）。

## 验证通过标准（真机，Joey 的 iPhone + 安卓机）

1. 连接检测通过（版本/能力/设备状态可见）。
2. 三项真实任务端到端完成并回传结果：①网页类（如查天气/资讯并汇总）；②App 操作类（如打开某 App 查一条信息）；③运行中追加要求（steer）或回答追问（answer）至少一项生效。
3. cancel 一次生效（以查询到 cancelled 为准，不以 accepted 为准）。
4. 断线恢复：任务执行中杀掉 iOS App 再重开，状态能对齐、无重复提交。
5. 全程无令牌出现在日志/截图/仓库中；付款类步骤在手机端拦截（若任务触发，记录其行为）。

任一项失败：记录原始错误与复现条件，区分是协议、网络、iOS 限制还是上游问题，再决定修或停。

## 明确不做

- 不做 App Store 提审、不建 ASC 记录（验证通过后另行立项决定）。
- 不做 B 路线能力（自家浏览器 web agent、Shortcuts 集成）。
- 不动安卓端 Mika 源码；不给上游提 PR（本阶段）。
- 不处理付款/同意类步骤（协议层本来就禁止远程确认）。
