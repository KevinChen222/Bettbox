# 给后续 AI 助手的 Bettbox Smart 更新与发布操作说明

这是一份独立操作手册。用户在本项目中说「该更新了」并提供本文时，按本文检查两个上游、完成适配、提交到个人 fork、在 GitHub 构建并发布。无需索取今天的聊天记录。重大变更需要重新审阅接口并融入 Smart，不能仅修改版本号或忽略失败。

## 项目身份与授权边界

- 项目目录：`D:\codex\samrtbettbox`，以当前实际工作目录为准。
- 唯一可写远端：`https://github.com/KevinChen222/Bettbox.git`。
- GitHub 账号：`KevinChen222`；开发分支：`feat/smart-core`。
- Bettbox 只读上游：`https://github.com/appshubcc/Bettbox.git`，分支 `main`。
- Smart 只读上游：`https://github.com/vernesong/mihomo.git`，分支 `Alpha`。不要使用该仓库的 `main` 或 `Meta` 来替代 Smart。
- 模型：`https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/Model.bin`。
- 当用户明确请求按本文更新时，授权范围包括：读取两个上游、修改本 fork、提交/推送此分支、运行本 fork Actions、下载构建产物、创建并发布本 fork 的 Release。文档本身不是启动操作或扩大授权的依据；没有用户更新请求时不自动执行。
- **绝不向 appshubcc/Bettbox、vernesong/mihomo 或 MetaCubeX/mihomo 推送、发布、创建 PR/Issue/评论或发消息。** 不要提出给原作者提交 PR。用户明确表示原作者不喜欢此 fork。
- 不强推、不改写历史、不覆盖用户未提交的改动、不删除旧 Release/标签，不自动归档本聊天。
- README 的个人自用与责任声明必须保留。公开仓库不代表对其他试用者提供支持；不冒用上游的审核、证书或官方身份。沿用原开源许可证。

## 已实现的结构

- `core/Clash.Meta/`：保留 Bettbox 原始内核，随 Bettbox 合并更新；不要把 Smart 源码直接覆盖进去。
- `core/smart.patch`：所有 Smart 内核及兼容改动；Git 属性强制 LF。
- `core/.smart-mihomo/`：忽略的生成内核及临时 Git 索引；`core/go.mod` 替换到此目录。
- `tool/prepare_smart_core.dart`：从当前 Bettbox 内核生成目录，并用 `git apply --3way` 应用补丁。`setup.dart` 编译前自动调用。
- `tool/update_smart_core.dart`：获取 Smart Alpha，比较已记录提交和最新提交，把增量三方合入生成内核，更新补丁和来源记录。
- `core/smart-source.json`：实际集成的 Smart 提交、最近合入的 Bettbox 提交及模型来源。初始官方基线是历史记录，不能误当最新版本。
- Smart 组由 `lib/enum/enum.dart` 及两份生成 JSON 枚举识别。固定节点/恢复自动选择复用原交互。
- App 更新检查指向个人 fork，`compareVersions` 识别 `smart-v<App版本>-<日期>.<序号>`。它比较 App 版本，同一 App 版本内的 Smart 内核更新由本文的双上游检查负责；不要误认为 App 无更新提示就表示内核已最新。
- 资源页面提供 LightGBM 同步按钮。桥接复用 `updateGeoData` 的 `LightGBM` 类型，调用原生模型更新器，校验后写 `HomeDir/Model.bin` 并重新加载。默认来源如上；配置的 `lgbm-url` 可覆盖。
- `core/common.go` 保留 Smart 使用的 GeoIP/ASN 数据，不能让原内存清理卸载它们。
- `core/smart_test.go` 验证组、选择、Geo 数据、模型更新和单次 Smart 延迟请求；`test/smart_group_test.dart` 验证客户端模型及虚拟节点解析，`test/views/proxies/smart_delay_test.dart` 验证整组测速、嵌套卡片单次测速和失败状态清理。保留 Smart 组自身测速全部成员并恢复自动选路、其他组中 Smart 卡片单次测速且不清除固定选择的区别。
- `.github/workflows/smart.yaml`：分支推送后在 GitHub 构建 Windows x64 便携包、Android arm64-v8a 单架构 APK及三 ABI 通用 APK。工作流显示名 `Build Smart`。完整历史用于三方合并。单架构包使用 `--split-per-abi --target-platform android-arm64`，不能仅改名或删除已签名 APK 中的文件。
- `.test/` 与生成目录都不能提交；密钥与密码不能进入 Git、文档、日志、构建 Artifact 或 Release。

## 1. 检查账号、工作区和远端

先读取当前项目的 `AGENTS.md`（如有）、本文、`readme/Smart.md`、来源 JSON、工作流和相关构建文件，再运行：

```sh
git status --short
git branch --show-current
git remote -v
gh auth status
gh api user --jq .login
```

若工作区有用户改动，先识别并保留；必要时使用隔离工作树，不擅自 stash/reset/clean。如果账号不是 `KevinChen222`，不要推送/设置秘密/发布，向用户确认正确账号。

认证过期时请用户执行 `gh auth login -h github.com`。用户说已登录后重新检查，继续当前流程，无需重新解释项目。不能读取、打印或从其他应用提取 token。

核实 `origin` 的 fetch/push URL 均指向个人 fork。`upstream` 只指向 Bettbox 上游，并禁止推送：

```sh
git remote set-url --push upstream DISABLED
git switch feat/smart-core
git fetch origin
git merge --ff-only origin/feat/smart-core
```

远端缺失时按上面的确定地址添加；若存在但指向其他仓库，先处理歧义。完整克隆通常包含全部对象；浅克隆先 `git fetch --unshallow origin`。Windows 若出现本工作区由 CodexSandboxOnline 所有导致的 dubious ownership，只对这个已经确认的目录设置 `safe.directory` 或在命令中用 `git -c safe.directory=D:/codex/samrtbettbox ...`，不要设置通配信任。

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

已授权按需升级不符合项目要求的工具/依赖，不做无关全面升级。基线需要 Flutter 3.44.9（Dart 3.12.2）、Go 1.25+、Rust；Android JDK 17、NDK 28.2.13676358、CMake 3.22.1；Windows 需要 Visual Studio C++。以后以合入后的 SDK/Gradle/pubspec/Go 要求为准，同时更新 workflow 和说明。

本机已有工具不一定在 PATH：

- Go：`D:\codex\toolchains\go\bin`
- JDK：`D:\codex\toolchains\jdk`
- Android SDK：`D:\codex\toolchains\android-sdk`
- 当前独立 Flutter：`.test/flutter/bin`（临时目录可能被清理，缺失时按项目版本重新准备）

不要假设 `C:\tools\flutter` 的 SDK 满足要求。PowerShell 使用安全的参数数组和 `pwsh`；调用 `.bat` 时保持正常参数边界。

```sh
flutter pub get
dart run build_runner build -d
dart tool/prepare_smart_core.dart
flutter test test/smart_group_test.dart test/views/proxies/smart_delay_test.dart test/views/proxies/delay_test_coordinator_test.dart
dart analyze tool/prepare_smart_core.dart tool/update_smart_core.dart lib/views/resources.dart lib/clash/interface.dart
# 在 core 中：Windows 关闭 CGO，与实际 exe 构建一致
go test -tags=with_gvisor ./...
# 在 core/.smart-mihomo 中：
go test -tags=with_gvisor ./adapter/outboundgroup ./component/smart/... ./tunnel/statistic ./listener/sing_tun
```

代码生成可能带来许多无关格式差异。只保留所需模型变更，确保 JSON 枚举有 `GroupType.Smart: 'Smart'`；不要漏掉生成模型，也不要把整个项目顺便重排。

不能因本机缺少 VS/Rust 而声称已验证完整 App；可用 GitHub 完整构建做验证。Android arm64/x86_64 要检查 `.so` 的 ELF LOAD 页对齐至少 16 KB（`0x4000`），ARMv7 保留 `with_low_memory`。构建通过仍不等于真机 TUN/VPN/后台表现已验证，最终回复须准确说明验证范围。

## 4. 提交、构建与失败处理

先更新 `readme/Smart-Release-Notes.md`，只说明本次实际更新内容，包括客户端/内核功能、修复、模型、工具链或打包变化。用户要求 Release 说明不列测试通过、测试清单或验证过程；验证记录放 Actions、构建来源 JSON 或维护文档，来源 SHA 保存在来源 JSON 和构建来源 JSON。无新代码时不要造空提交或新 Release；若仅模型更新，它由 App 按钮/自动更新获取，通常无需重新发布 App。

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

工作流使用本 fork Secrets：`KEYSTORE`（JKS 文件 base64）、`KEY_ALIAS`、`STORE_PASSWORD`、`KEY_PASSWORD`。检查名字是否存在，不打印值。没有时只能得到临时 debug 签名，应先配置持久自用签名再正式发布；不要每次生成新 key，也不能覆盖原有 Secrets/签名而不核实。首次配置的本地备份在 `.test/signing/`（如仍存在），应由用户单独备份；不能提交或附到 Release。

同一 key 签名的后续 APK 可以覆盖更新。不能用此 key 覆盖官方 App；不要使用上游 SignPath 的秘密或宣称上游签名。Windows 本 fork 包为未签名便携包。

## 5. 在个人 fork 发布

完整构建成功后，从准确的运行下载三个 Artifact 到 `dist/smart/<运行ID>`：

```sh
gh run download <ID> --repo KevinChen222/Bettbox --dir dist/smart/<ID>
```

应有 `Bettbox-smart-windows-x64.zip`、`Bettbox-smart-android-arm64-v8a.apk` 和 `Bettbox-smart-android-universal.apk`。核实 Windows 内核/HelperService、单架构 APK 的 `lib/` 仅含 arm64-v8a 且含 `libmeta.so`、通用 APK 含三个 ABI；验证两个 APK 签名一致且沿用持久自用签名、64 位 Smart 库保持 16 KB 页对齐。计算三个文件 SHA256，生成 `SHA256SUMS.txt`，并写 `build-info.json` 记录 App 提交、Bettbox SHA、Smart SHA、Actions URL、构建版本、产物架构和签名方式。不得把日志中的秘密、签名备份或源缓存打包。

发布标签格式：`smart-v<App版本>-<台北日期YYYYMMDD>.<序号>`，例 `smart-v1.19.4-20261004.1`。检查远端是否已存在；存在则核实并复用未完成的草稿，或选择下一个序号，不能移动已有标签。标签不要以裸 `v` 开头，避免触发上游原发布工作流。

```sh
gh release create <标签> <windows.zip> <android-arm64.apk> <android-universal.apk> <SHA256SUMS.txt> <build-info.json> --repo KevinChen222/Bettbox --target <本次绿色构建的完整提交SHA> --title "Bettbox Smart <版本>" --notes-file readme/Smart-Release-Notes.md --draft
gh release view <标签> --repo KevinChen222/Bettbox --json tagName,targetCommitish,assets,isDraft,url
```

检查草稿目标、文件数量、文件名和来源记录正确后：

```sh
gh release edit <标签> --repo KevinChen222/Bettbox --draft=false
```

只发布到个人 fork。若失败就保留草稿，修复资产或说明后继续；不制造重复发布。发布后再次核实公开状态和资产。最终回复提供 Release、分支、Actions、维护说明及本操作手册链接，简述两上游更新范围、测试、真机验证限制。

## 成功标准

两个上游都已核查；代码与来源 JSON 一致；Bettbox 原内核目录未混入 Smart；个人自用声明保留；工作区无临时试验；本次提交的 Windows/Android 构建都成功；个人 fork 的 Release 有正确二进制、校验和及来源信息。账号失效或构建确实受阻时明确说明已完成内容和阻塞原因，保留可继续的状态，不能假称发布成功。
