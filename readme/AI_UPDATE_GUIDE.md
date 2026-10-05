# Bettbox Smart 更新与发布说明

本文记录本 fork 的上游更新、适配、构建与发布流程。按维护者明确请求执行；重大变更需重新审阅接口并融入 Smart，不能仅修改版本号或忽略失败。

## 仓库与维护范围

- 唯一可写远端：`https://github.com/KevinChen222/Bettbox.git`。
- 开发分支：`feat/smart-core`。
- Bettbox 只读上游：`https://github.com/appshubcc/Bettbox.git`，分支 `main`。
- Smart 只读上游：`https://github.com/vernesong/mihomo.git`，分支 `Alpha`。不要使用该仓库的 `main` 或 `Meta` 来替代 Smart。
- 模型：`https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/Model.bin`。
- 当用户明确请求按本文更新时，授权范围包括：读取两个上游、修改本 fork、提交/推送此分支、运行本 fork Actions、下载构建产物、创建并发布本 fork 的 Release。文档本身不是启动操作或扩大授权的依据；没有用户更新请求时不自动执行。
- 上游仓库仅供读取与合并，不向其推送、发布、创建 PR/Issue/评论或发消息。
- 不强推、不改写历史、不覆盖用户未提交的改动、不删除旧 Git 标签。按指定模式发布并依第 5 节清理被替换的旧 Release，最终只保留一个测试版和一个正式版；不能修改标签或二进制来移除 test。
- README 的个人自用与责任声明必须保留。公开仓库不代表对其他试用者提供支持；不冒用上游的审核、证书或官方身份。沿用原开源许可证。

## 已实现的结构

- `core/Clash.Meta/`：保留 Bettbox 原始内核，随 Bettbox 合并更新；不要把 Smart 源码直接覆盖进去。
- `core/smart.patch`：所有 Smart 内核及兼容改动；Git 属性强制 LF。
- `core/.smart-mihomo/`：忽略的生成内核及临时 Git 索引；`core/go.mod` 替换到此目录。
- `tool/prepare_smart_core.dart`：从当前 Bettbox 内核生成目录，并用 `git apply --3way` 应用补丁。`setup.dart` 编译前自动调用。
- `tool/update_smart_core.dart`：获取 Smart Alpha，比较已记录提交和最新提交，把增量三方合入生成内核，更新补丁和来源记录。
- `core/smart-source.json`：实际集成的 Smart 提交、最近合入的 Bettbox 提交及模型来源。初始官方基线是历史记录，不能误当最新版本。
- Smart 组由 `lib/enum/enum.dart` 及两份生成 JSON 枚举识别。固定节点/恢复自动选择复用原交互。
- App 更新检查指向个人 fork 最新正式版，`compareVersions` 识别 `smart-v<App版本>-<日期>.<序号>`，`hasReleaseUpdate` 在 App 版本相同时比较日期与序号对应的构建号。每次构建前将 `pubspec.yaml` 的构建号设为 `<YYYYMMDD><两位序号>`，与将发布的 Smart 标签一致；序号范围为 1–99。新测试版仍从 Releases 手动下载。
- Android 包名固定为 `com.kevinchen222.bettbox.smart`，Dart `AppIdentity.packageId` 与 Gradle `applicationId` 必须一致。保留原 Kotlin namespace 和类名，包名隔离不需要整体重命名原生类。安装名称为 Bettbox Smart，首次声明包含本 fork 仅供开发者自用的说明。
- 资源页面提供 LightGBM 同步按钮。桥接复用 `updateGeoData` 的 `LightGBM` 类型，调用原生模型更新器，校验后写 `HomeDir/Model.bin` 并重新加载。默认来源如上；配置的 `lgbm-url` 可覆盖。
- `core/common.go` 保留 Smart 使用的 GeoIP/ASN 数据，不能让原内存清理卸载它们。
- `core/smart_test.go` 验证组、选择、Geo 数据、模型更新和单次 Smart 延迟请求；`test/smart_group_test.dart` 验证客户端模型及虚拟节点解析，`test/views/proxies/smart_delay_test.dart` 验证整组测速、嵌套卡片单次测速和失败状态清理。保留 Smart 组自身测速全部成员并恢复自动选路、其他组中 Smart 卡片单次测速且不清除固定选择的区别。
- `.github/workflows/smart.yaml`：分支推送后在 GitHub 构建 Windows x64 便携包和 Android arm64-v8a 单架构 APK。工作流显示名 `Build Smart`。完整历史用于三方合并。Android 只编译和发布 arm64-v8a，不生成通用包、armeabi-v7a 或 x86_64 包。内核使用 `dart setup.dart android --arch arm64 --out core`，APK 使用 `--split-per-abi --target-platform android-arm64`；Rust 只安装 Android 的 `aarch64-linux-android` target。`android/core` 与 `plugins/flutter_qjs/android` 的 `ndk.abiFilters` 也只保留 arm64-v8a，避免 Gradle 额外编译其他 ABI。不能先编译全部架构再改名或删除已签名 APK 中的文件。
- `.test/` 与生成目录都不能提交；密钥与密码不能进入 Git、文档、日志、构建 Artifact 或 Release。

### 独立客户端扩展：代理链路

本 fork 现已增加 Avalon 的链路创建能力，完整使用、结构、接入点、来源和后续适配说明见 [代理链路维护说明](Proxy-Chains.md)。新增模块集中在 `lib/features/chains/`，没有修改原始内核或 Smart 补丁。Avalon 只作为编译器的只读参考，不整体合并其分支，也不自动开启第三套上游更新/发布流程。

合并 Bettbox 更新时保留三处接入：`lib/views/tools.dart` 的独立入口及搜索项；`lib/state.dart` 在脚本/过滤之后、加载内核之前应用链路；`lib/controller.dart` 的链路库备份、恢复及清空处理。UI 改版时移动入口即可，不能用旧 Avalon UI 覆盖 Bettbox 的新 UI。订阅原文件、Profile/Config 生成模型保持原结构。`proxy-chains.json` 跟随应用数据目录与备份，更新应用时不能删除。

移植来源记录在 `lib/features/chains/avalon-source.json`；保留编译器的 Avalon 版权头、模块内 AGPL 许可及根目录 `NOTICE`，原项目 GPL 许可和个人自用声明仍须保留。链路默认不改变原规则/选中节点。多跳链路第一跳直接引用原节点或策略组，前置组跟随实时选择（含 Smart 自动选路），不能再展开前置成员或重命名前置。后续节点生成副本，出口组按实际落地节点展开；两跳链路的选项数只取决于落地节点数。创建本地配置/导出 YAML 保留原规则，切换本地配置前继承源配置已有的 HTTP provider/规则集缓存，不能因新配置 ID 强制重新下载。

`Build Smart` 会把模块许可和根目录 `NOTICE` 打包进 Flutter 的 `assets/data/avalon-chain-LICENSE.txt` 与 `avalon-chain-NOTICE.txt`。发布检查时核实 Windows ZIP 和 arm64-v8a APK 都包含这两项，不能在已签名 APK 上直接补文件。

## 1. 检查账号、工作区和远端

先读取当前项目的 `AGENTS.md`（如有）、本文、`readme/Smart.md`、来源 JSON、工作流和相关构建文件，再运行：

```sh
git status --short
git branch --show-current
git remote -v
gh auth status
gh api user --jq .login
```

若工作区有用户改动，先识别并保留；必要时使用隔离工作树，不擅自 stash/reset/clean。确认当前账号具备本 fork 的写入权限；账号或仓库不符时先处理歧义，再推送或发布。

认证过期时请用户执行 `gh auth login -h github.com`。用户说已登录后重新检查，继续当前流程，无需重新解释项目。不能读取、打印或从其他应用提取 token。

核实 `origin` 的 fetch/push URL 均指向个人 fork。`upstream` 只指向 Bettbox 上游，并禁止推送：

```sh
git remote set-url --push upstream DISABLED
git switch feat/smart-core
git fetch origin
git merge --ff-only origin/feat/smart-core
```

远端缺失时按上面的确定地址添加；若存在但指向其他仓库，先处理歧义。完整克隆通常包含全部对象；浅克隆先 `git fetch --unshallow origin`。若 Git 提示 dubious ownership，核实当前工作区后只对其绝对路径设置 `safe.directory`，不要设置通配信任。

## 2. 同时检查两个上游

读取 `core/smart-source.json`。分别获取最新 Bettbox `main` 和 Smart `Alpha`，比较实际 SHA，不依赖 Release 标题或日期。记录旧/新 SHA 和相关 changelog。

```sh
git fetch upstream main
git log --oneline HEAD..upstream/main
git diff --stat HEAD...upstream/main
git merge upstream/main
```

先解决普通客户端/构建冲突，保留本 fork 的来源、更新地址、Smart 枚举、模型按钮和责任声明。再运行：

```sh
flutter pub get
dart tool/update_smart_core.dart
```

该脚本读取来源 JSON、从只读 Smart 远端获取 Alpha，生成「旧 Smart → 新 Smart」完整 Go 增量（包括 Smart 同步的官方 Mihomo 改动），三方合并到当前 Bettbox+Smart 内核，成功后保存 `core/smart.patch` 和新的 Smart SHA。如果 Smart 未更新，仍须运行 `dart tool/prepare_smart_core.dart` 来适配已变化的 Bettbox。

将来源 JSON 的 `bettboxRevision` 更新为本次实际合入的 `upstream/main` SHA。不要把最新查询 SHA 写成已集成 SHA，除非代码确实合入并将通过验证。

### 冲突、接口变化或重大升级

生成器报冲突时，保留失败生成目录，查看文件的三方冲突。比较 Bettbox 平台补丁、旧 Smart 和新 Smart 的实现，按实际接口修复；不要一律选 ours/theirs。

```sh
# 在 core/.smart-mihomo 中修改并消除冲突标记后
dart tool/prepare_smart_core.dart --refresh-patch
```

若冲突来自 Smart 更新器，还要审阅并把 `.test/smart-candidate.json` 的来源信息保存为 `core/smart-source.json`。这是本次候选 Smart 提交，不要混用旧的候选文件。之后重新运行生成器和测试。**保存补丁前不要再运行生成器、更新器或 setup.dart，它们会覆盖生成目录。** 生成器不应与 Go 构建同时运行。

如果无法自动合并、依赖/API 改动较大或构建失败，重新审阅并修复：Go 桥接、安卓 VPN/JNI、Bettbox TUN/低内存/流量统计补丁、Smart 统计/缓存/退出探测、LightGBM 校验及热加载。必要时参考两个上游的合并基线，重建独立补丁。验证充分前不发布。

生成补丁始终用 UTF-8 和 LF；不要使用 Windows 的默认系统编码来捕获 Git diff。脚本已显式指定 UTF-8。不要在 `core/Clash.Meta` 中留下试验性修改。

## 3. 依赖、生成代码和本地验证

按需升级不符合项目要求的工具/依赖，不做无关全面升级。基线需要 Flutter 3.44.9（Dart 3.12.2）、Go 1.25+、Rust；Android JDK 17、NDK 28.2.13676358、CMake 3.22.1；Windows 需要 Visual Studio C++。以后以合入后的 SDK/Gradle/pubspec/Go 要求为准，同时更新 workflow 和说明。

运行前确认实际使用的工具版本与 PATH，不假设本机 SDK 满足要求。PowerShell 使用安全的参数数组和 `pwsh`；调用 `.bat` 时保持正常参数边界。

```sh
flutter pub get
dart run build_runner build -d
dart tool/prepare_smart_core.dart
flutter test test/smart_group_test.dart test/views/proxies/smart_delay_test.dart test/views/proxies/delay_test_coordinator_test.dart test/controller_loading_test.dart
flutter test test/features/chains
dart analyze lib/features/chains test/features/chains lib/state.dart lib/views/tools.dart lib/controller.dart
dart analyze tool/prepare_smart_core.dart tool/update_smart_core.dart lib/views/resources.dart lib/clash/interface.dart
# 在 core 中：Windows 关闭 CGO，与实际 exe 构建一致
go test -tags=with_gvisor ./...
# 包含 TestProxyChainConnectDirection：实际验证两跳 HTTP CONNECT 链路
# 在 core/.smart-mihomo 中：
go test -tags=with_gvisor ./common/callback ./adapter/outboundgroup ./component/smart/... ./tunnel/statistic ./listener/sing_tun
```

代码生成可能带来许多无关格式差异。只保留所需模型变更，确保 JSON 枚举有 `GroupType.Smart: 'Smart'`；不要漏掉生成模型，也不要把整个项目顺便重排。

不能因本机缺少 VS/Rust 而声称已验证完整 App；可用 GitHub 完整构建做验证。Android arm64-v8a 要检查 `.so` 的 ELF LOAD 页对齐至少 16 KB（`0x4000`）。构建通过仍不等于真机 TUN/VPN/后台表现已验证，最终回复须准确说明验证范围。

## 4. 提交、构建与失败处理

先更新 `readme/Smart-Release-Notes.md`，仅说明本次主要更新内容，包括实际功能、修复、模型、工具链或打包变化。不列测试通过、测试清单或验证过程，也不把内核基线沿用、发布轮换过程写入更新日志；这些记录放 Actions、构建来源 JSON 或维护文档，来源 SHA 保存在来源 JSON 和构建来源 JSON。无新代码时不要造空提交或新 Release；若仅模型更新，它由 App 按钮/自动更新获取，通常无需重新发布 App。

```sh
git diff --check
git status --short
git add <逐项核实的文件>
git commit -m "Update Bettbox and Smart core"
git push origin feat/smart-core
git rev-parse HEAD
gh run list --repo KevinChen222/Bettbox --branch feat/smart-core --workflow smart.yaml --limit 5 --json databaseId,headSha,status,conclusion,url
```

选择 `headSha` 等于本次提交的运行，记下运行 ID。`Build Smart` 的 Windows、Android 两个任务都必须成功。用 `gh run view <ID> --repo KevinChen222/Bettbox --json status,conclusion,jobs` 检查进度，有失败则读取该运行失败日志修复后再提交。不要以旧提交的绿色构建替代当前提交结果，不带着失败发布，也不要连续高频轮询。

Fork 的工作流只在功能分支，手动 workflow_dispatch 的可用性取决于 GitHub 默认分支注册情况。日常依靠分支推送触发；已完成的同一提交可以 rerun。不要为触发工作流推送上游或创建空提交。

### 安卓持久签名

工作流使用本 fork Secrets：`KEYSTORE`（JKS 文件 base64）、`KEY_ALIAS`、`STORE_PASSWORD`、`KEY_PASSWORD`。检查名字是否存在，不打印值。没有时只能得到临时 debug 签名，应先配置持久签名再正式发布；不要每次生成新 key，也不能覆盖原有 Secrets/签名而不核实。签名资料单独备份，不提交到仓库或附到 Release。

同一 key 签名的后续 APK 可以覆盖更新。不能用此 key 覆盖官方 App；不要使用上游 SignPath 的秘密或宣称上游签名。Windows 本 fork 包为未签名便携包。

## 5. 在个人 fork 发布

完整构建成功后，从准确的运行下载两个 Artifact 到 `dist/smart/<运行ID>`：

```sh
gh run download <ID> --repo KevinChen222/Bettbox --dir dist/smart/<ID>
```

应有 `Bettbox-smart-windows-x64.zip` 和 `Bettbox-smart-android-arm64-v8a.apk`。核实 Windows 内核/HelperService、APK 的 `lib/` 仅含 arm64-v8a 且含 `libmeta.so`；验证 APK 沿用上一版的持久自用签名，Smart 库保持 16 KB 页对齐。计算两个文件 SHA256，生成 `SHA256SUMS.txt`，并写 `build-info.json` 记录 App 提交、Bettbox SHA、Smart SHA、Actions URL、构建版本、产物架构和签名方式。新 Release 共四个资产：Windows ZIP、arm64-v8a APK、校验和与来源 JSON；上一版转正时保持其原有资产不变。不得把日志中的秘密、签名备份或源缓存打包。

### 测试版与正式版轮换规则

Release 最终只保留一个测试版和一个正式版。每一个新 Release 首先作为测试版发布：`prerelease=true`，标题末尾加 ` · test`，`latest=false`。每次依据用户明确指定的模式处理：

- **功能更新并转正上一测试版**：新测试版成功公开后，把上一测试版设为 `prerelease=false`，去掉标题末尾的 ` · test`，设为 `latest=true`，然后移除被替换的旧正式版 Release。
- **bug 修复替换测试版**：新测试版成功公开后，移除上一测试版 Release，现有正式版及 Latest 元数据保持不变；绝不自动把上一测试版转正。

用户未指定模式且上下文无法判断时，先准备可审阅的修复与构建，再询问模式，不擅自转正。仅清理本 fork 的 Smart Release，不删除 Git 标签、不移动标签、不改写历史。转正不代表新增了真机验证证明。

发布前用 `gh release list --repo KevinChen222/Bettbox --limit 20 --json tagName,name,isPrerelease,isDraft,publishedAt` 分别记录最新公开测试版和最新正式版的标签、原标题与资产。不能用 `/latest` 查找测试版，它排除预发布。只处理本 fork 的 `smart-v` 版本，跳过草稿。已有正式版本不反向改成 test。若有遗留版本，核对发布顺序后按本节只保留所需的一个测试版和一个正式版。

先成功发布并核实新 test，再执行转正或清理。构建失败、资产缺失、发布仍是草稿或新 Release 不可访问时，旧 Release 保持原状。转正或清理失败时保留新 test，重试同一操作，不创建重复发布。首次发布没有上一版时只发布 test。

标签格式仍为 `smart-v<App版本>-<台北日期YYYYMMDD>.<序号>`，例 `smart-v1.19.4-20261004.1`。**标签不加 test 后缀**，方便转正时只修改 Release 元数据。检查远端是否已存在；存在则核实并复用未完成的草稿，或选择下一个序号，不能移动已有标签。标签不要以裸 `v` 开头，避免触发上游原发布工作流。

```sh
gh release create <标签> <windows.zip> <android-arm64.apk> <SHA256SUMS.txt> <build-info.json> --repo KevinChen222/Bettbox --target <本次绿色构建的完整提交SHA> --title "Bettbox Smart <版本> · <台北日期.序号> · test" --notes-file readme/Smart-Release-Notes.md --draft --prerelease --latest=false
gh release view <标签> --repo KevinChen222/Bettbox --json tagName,targetCommitish,assets,isDraft,isPrerelease,url
```

检查草稿目标、文件数量、文件名和来源记录正确后：

```sh
gh release edit <标签> --repo KevinChen222/Bettbox --draft=false --prerelease=true --latest=false
gh release view <标签> --repo KevinChen222/Bettbox --json tagName,isDraft,isPrerelease,assets,url
# 仅在用户指定转正模式且新 test 已公开后执行：
gh release edit <上一版标签> --repo KevinChen222/Bettbox --prerelease=false --title "<上一版原标题，仅去掉末尾的 · test>" --latest=true
gh release view <上一版标签> --repo KevinChen222/Bettbox --json tagName,isDraft,isPrerelease,name,assets,url
```

bug 修复时跳过上面的转正命令。完成所需元数据操作后，使用 `gh release delete <被替换或更早的Smart标签> --repo KevinChen222/Bettbox --yes` 清理多余 Release，**不要添加 `--cleanup-tag`**。清理前再次确认保留的新测试版及正式版均公开且资产齐全；最后核对 Release 列表恰有这两个版本。

转正只改 GitHub Release 的预发布标记、标题和 Latest 元数据，不重新构建、不替换资产、不移动/重命名标签、不修改安装包内的 APP_ENV、签名或版本号。App 默认的正式版更新渠道仍按 GitHub 最新正式版处理；新 test 从 Releases 页面手动下载，不把它冒充正式版自动推送。

只发布到个人 fork。若失败就保留草稿，修复资产或说明后继续；不制造重复发布。发布后再次核实新版本为 test、正式版已按指定模式保留或转正、列表只有这两个 Release。`build-info.json` 记录发布时为 test、发布模式、上一测试版与所保留的正式版标签，作为历史记录；不能因日后转正而重写旧资产。最终回复提供 test Release、正式版保留或转正结果、Actions 与维护说明，准确说明上游更新范围及真机验证限制。

## 成功标准

两个上游都已核查（单独发布客户端修复时如实说明沿用原内核基线，不冒称已更新上游）；代码与来源 JSON 一致；Bettbox 原内核目录未混入 Smart；个人自用声明保留；工作区无临时试验；本次提交的 Windows/Android 构建都成功；新 Release 为 test，含正确二进制、校验和及来源信息；正式版按用户指定模式保留或转正；Release 仅保留这两个版本。账号失效或构建确实受阻时明确说明已完成内容和阻塞原因，保留可继续的状态，不能假称发布成功。
