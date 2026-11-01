# Mika Console — TestFlight 分发链日志（2026-11-01）

结论：**构建已上 TestFlight，内部测试组可用。** App：Mika Console（Apple ID 6829457620，Bundle ID com.jigaoyi.mikaconsole，团队 6566672L5G）。

## 步骤与证据

1. **证书仓与密钥** ✅
   - 私有仓 `yijigao/mikaconsole-certs` 已建（PRIVATE）。
   - 专用 SSH deploy key 已生成（私钥 `~/workspace/mika-ios-client/.secrets/certs_deploy_key`，0600），公钥登记为该仓 deploy key id **168379441**、可写（read_only=false）。
   - match 密码存 `~/workspace/mika-ios-client/.secrets/match_password.txt`（0600）。密钥/密码值未出现在任何日志。

2. **fastlane + 工作流** ✅
   - 仓内新增 `Gemfile`、`fastlane/{Appfile,Fastfile,Matchfile}`、`.github/workflows/{prepare,release}.yml`，照 LongShot 参考实现改名单 App（提交 2b96123）。`.gitignore` 已补 `.secrets/`。
   - GitHub Secrets 已注入（仅名字）：ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_P8_B64、MATCH_PASSWORD、MATCH_DEPLOY_KEY、APNS_TEAM_ID。

3. **prepare（match 生成签名材料）** ✅
   - Run **41318241282**，conclusion=success。
   - 证书仓已存入分发证书（B48Z8JJ458.cer/.p12，Apple Distribution: Joey Yi）与描述文件 `AppStore_com.jigaoyi.mikaconsole.mobileprovision`（profile 名 `match AppStore com.jigaoyi.mikaconsole`）。

4. **release（归档＋上传）** ⚠️ 一败一成
   - Run 41318368795 **失败**：归档成功，上传被 altool 拒收。根因原文：`Missing required icon file. The bundle does not contain an app icon for iPad of exactly '152x152' pixels, in .png format for iOS versions >= 10.0. (90023)`——工程 TARGETED_DEVICE_FAMILY=1,2 支持 iPad 但无任何图标资产。
   - 修复：新增 `MikaConsole/Assets.xcassets/AppIcon.appiconset`（全尺寸 PNG，含 iPad 76@2x=152 与 83.5@2x=167、1024 营销图；占位图：深蓝渐变＋白色 M＋绿点），pbxproj 挂入 Resources 并设 ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon；`scripts/validate_project.py` 做最小修正以接受 assetcatalog 目录（提交 735e5d4，静态校验 PASS）。
   - Run **41318601741**，conclusion=success，日志原文：`Successfully uploaded the new binary to App Store Connect`。

5. **ASC 构建状态** ✅
   - 构建号 **202611011456**，build id `9a760d59-5aa6-4fd2-9eb7-4a172a31123b`，版本 0.1.0，上传 2026-11-01 06:58:29 -08:00，`processingState` 由 PROCESSING → **VALID**，expired=false。
   - 挂组前补答出口合规：PATCH builds 将 `usesNonExemptEncryption=false`（否则挂组报 422 `Build is not in an internally testable state`）。

6. **内部测试组与测试员** ✅
   - betaGroup「Internal」id `c32643b2-8b3d-41c0-acf7-7581a1922389`，isInternalGroup=true；构建挂组成功（HTTP 204），组内 builds 回读为 VALID 的 202611011456。
   - 账号持有人 Joey（/v1/users 中 ACCOUNT_HOLDER 账号）已加入：注意其名下原有两条同邮箱 betaTester 旧记录加入时均报 409 `Tester(s) cannot be assigned`，改走「新建 betaTester 并在创建时带 betaGroups 关系」成功（HTTP 201，新 tester id `a8cd5e5f-d703-493a-880c-fe7db43fe660`），组内回读确认在册。

## 红线遵守
未提交审核、未建 appStoreVersion 提交、未接受任何协议、未动 Mika Console 以外任何 App。

## Joey 需要做的动作（最少步骤）
1. iPhone 打开 **TestFlight** App → 应能看到 **Mika Console**（构建 0.1.0 / 202611011456）→ 点「安装」。
2. 若 TestFlight 里没出现：确认登录的 Apple ID 是账号持有人那个，再下拉刷新一次；仍无则回报。
3. 图标目前是占位图（深蓝底白 M），正式图标待后续替换，不影响本次验证安装。
