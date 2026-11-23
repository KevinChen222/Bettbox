# Bettbox Smart 维护参考

本文保存详细操作与维护约束，供执行到相应阶段时按节读取；日常开聊只需引用 [AI 更新入口](AI_UPDATE_GUIDE.md)，不用粘贴本文或旧更新记录。按维护者明确请求执行；重大变更需重新审阅接口并融入 Smart，不能仅修改版本号或忽略失败。

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
- App 更新检查指向个人 fork 的公开 Releases（包含正式版与测试版，排除草稿），优先读取 `releases.atom` 并在失败时回退 GitHub Releases API；`compareVersions` 识别 `smart-v<App版本>-<日期>.<序号>`，`hasReleaseUpdate` 与 `selectLatestReleaseTag` 在 App 版本相同时比较日期与序号对应的构建号。每次构建前将 `pubspec.yaml` 的构建号设为 `<YYYYMMDD><两位序号>`，与将发布的 Smart 标签一致；序号范围为 1–99。
- Android 包名固定为 `com.kevinchen222.bettbox.smart`，Dart `AppIdentity.packageId` 与 Gradle `applicationId` 必须一致。保留原 Kotlin namespace 和类名，包名隔离不需要整体重命名原生类。安装名称为 Bettbox Smart，首次声明包含本 fork 仅供开发者自用的说明。
- 资源页面提供 LightGBM 同步按钮。桥接复用 `updateGeoData` 的 `LightGBM` 类型，调用原生模型更新器，校验后写 `HomeDir/Model.bin` 并重新加载。默认来源如上；配置的 `lgbm-url` 可覆盖。
- `core/common.go` 保留 Smart 使用的 GeoIP/ASN 数据，不能让原内存清理卸载它们。
- `core/smart_test.go` 验证组、选择、Geo 数据、模型更新和单次 Smart 延迟请求；`test/smart_group_test.dart` 验证客户端模型及虚拟节点解析，`test/views/proxies/smart_delay_test.dart` 验证整组测速、嵌套卡片单次测速和失败状态清理。保留 Smart 组自身测速全部成员并恢复自动选路、其他组中 Smart 卡片单次测速且不清除固定选择的区别。
- `.github/workflows/smart.yaml`：分支推送后在 GitHub 构建 Windows x64 便携包与 Android arm64-v8a 单架构 APK。Ubuntu 24.04 Linux x64 DEB 由本机 `tool/build-linux-local.sh` 构建并检查；Rust target 为 x86_64-unknown-linux-gnu，内核为 AMD64 v3，只使用 flutter_distributor 的 deb 目标。工作流显示名 `Build Smart`。完整历史用于三方合并。Android 只编译和发布 arm64-v8a，不生成通用包、armeabi-v7a 或 x86_64 包。内核使用 `dart setup.dart android --arch arm64 --out core --standard`，APK 使用 `--split-per-abi --target-platform android-arm64`；Rust 只安装 Android 的 `aarch64-linux-android` target。`android/core` 的 `ndk.abiFilters` 也只保留 arm64-v8a，避免 Gradle 额外编译其他 ABI。1.19.5 已移除 `flutter_qjs`，脚本引擎由 `code_forge` 的 Rust 模块提供。不能先编译全部架构再改名或删除已签名 APK 中的文件。
- `.test/` 与生成目录都不能提交；密钥与密码不能进入 Git、文档、日志、构建 Artifact 或 Release。

### 本 fork 维护范围与上游原生功能边界

当前合并基线 `upstream/main` 为 `fdf5cd34`（Bettbox 1.19.10）。随着 Bettbox 上游原生加入了节点库、落地代理（链式代理创建）与订阅合并（`7f4293ce`、`389cd5fd` 及 1.19.10 的多节点导入），本 fork 不再单独维护自定义链路系统，核心维护聚焦于：

- **Smart 策略组内核与客户端适配**：`core/smart.patch`、`core/smart-source.json`、`lib/enum/enum.dart`、Smart 组测速与固定节点交互，以及 LightGBM 模型同步。
- **连接关闭高 CPU / 内存与资源泄漏维护**：保留 `core/smart.patch` 中 `tcpTracker` CAS 关闭权保护（见 [连接关闭高 CPU 修复记录](Smart-CPU-Fix.md)）、`core/common.go` 对 Smart GeoIP/ASN 数据的保留，以及持续关注 Smart 后台任务与连接生命周期清理。
- **Android 端自定义应用名称与展示图标（应用伪装）**：仅在 Android 端提供（Windows / Linux 不开放入口）。通过 `lib/common/app_disguise.dart`、`lib/views/app_disguise.dart`、`AppDisguiseStore.kt`、`DisguiseIconWidgetProvider.kt` 及 `AndroidManifest.xml` 的 `MainActivityDefault` / 中立伪装 `<activity-alias>` 实现；支持自定义名称、相册上传裁切图标、1×1 无角标桌面小组件、固定快捷方式、应用抽屉预设切换，以及最近任务/通知栏/快捷磁贴名称同步。`MainActivity` 始终保持启用，确保切换抽屉别名时已添加的小组件与快捷方式不失效。
- **个人构建与更新渠道**：独立 Android 包名/持久签名、Ubuntu 24.04 Linux x64 DEB 打包，以及覆盖本 fork 测试版与正式版的应用内更新检查。

以下上游原生能力在合并时需关注兼容性与回归，直接沿用上游实现，不另起炉灶：

- 节点页与配置绑定见 `lib/views/profiles/nodes.dart`、`edit_node.dart`、`lib/models/node.dart`（支持一次导入多个节点并优先排在选择策略组前部）。`core/nodes.go` 在运行配置中处理节点、`dialer-proxy` 和组成员，检查前置失效及循环时的行为。Avalon 的来源和许可作为历史贡献保存在根目录 `NOTICE`，旧版迁移见 [使用与升级](Fork-Features.md)。
- 聚合入口在 `lib/views/profiles/merge_profile.dart`。客户端先应用托管脚本，内核通过 `core/provider_expand.go` 和 `core/profile_merge.go` 处理 Provider 与合并结果。检查成员更新、Provider 缓存、规则、节点去重及名称重写。兼容备份恢复实现位于 `lib/common/profile_recovery.dart`，覆盖同 URL 配置的 ID 保留和合并。
- 上游 Android 应用和核心声明 `minSdk = 24`。发布前另查 Smart APK 的实际最低版本、arm64-v8a 原生库和 Android 7.x 启动及 VPN 表现，再确认可用范围。

## 1. 检查账号、工作区和远端

先读取当前项目的 `AGENTS.md`（如有）、`readme/AI_UPDATE_GUIDE.md` 和 `core/smart-source.json`，再检查工作区与账号。本文只读当前阶段需要的小节；`readme/Smart.md`、工作流和构建文件在涉及对应功能或构建时读取，不在开聊时全部加载。

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

合并开始前可按以下命令获取和审阅变更。若已有 `MERGE_HEAD`，从当前合并继续处理冲突。

```sh
git fetch upstream main
git log --oneline HEAD..upstream/main
git diff --stat HEAD...upstream/main
git merge upstream/main
```

读取 `core/smart-source.json`，分别比较 Bettbox `main` 与 Smart `Alpha` 的实际 SHA。记录旧、新 SHA 和相关 changelog。先解决普通客户端/构建冲突，保留本 fork 的来源、更新地址、Smart 枚举、模型按钮和责任声明。

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

按需升级工具和依赖。Bettbox 1.19.9 的 `pubspec.yaml` 要求 Dart 3.14+，上游 CI 使用 Flutter 3.50.1。Smart 本机构建和 Actions 均需使用满足依赖的 SDK。另需 Go 1.25+、Rust、Android JDK 21、Gradle 9.5.0（AGP 9.3.1）、NDK 28.2.13676358 和 CMake 3.22.1。Windows 需要 Visual Studio C++。检查当前 Gradle wrapper 与 `android/settings.gradle.kts`，用与项目 AGP 兼容的版本。

运行前确认实际使用的工具版本与 PATH，不假设本机 SDK 满足要求。PowerShell 使用安全的参数数组和 `pwsh`；调用 `.bat` 时保持正常参数边界。

### Linux 日常开发

默认在本机 Ubuntu 24.04 x86_64 的 `/home/kevin-chen/project/bettbox_smart` 维护客户端和 Smart 内核。日常本机测试只构建 Linux x64 客户端/DEB 与 Android arm64-v8a APK，先跑变更相关的定向测试，再交付维护者实测。Android 日常构建固定使用 `bash tool/build-android-local.sh --require-signing`，不回退到 debug 签名。Windows x64 安装包由 `smart.yaml` 的 Windows runner 构建，不要求本机构建 Windows 客户端；Windows 原生界面和系统功能需在 Windows 上验证。

本机 SDK 放在 `~/development/bettbox-toolchains/`，Pub、Go 和 Gradle 下载缓存放在 `~/.cache/bettbox/`。终端启动时读取 `~/.config/bettbox/linux-env.sh`，也可运行 `source tool/linux-env.sh`。按上节要求更新 Flutter，并使用 Go 1.25.x、Rust stable、Linux JDK 17、Android JDK 21、Android API 36、Build Tools 36.0.0、NDK 28.2.13676358 和 Android CMake 3.22.1。`BETTBOX_TOOLCHAIN_DIR`、`BETTBOX_JAVA_HOME` 可覆盖 SDK/JDK 安装位置。

Ubuntu 系统依赖：`build-essential clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev libayatana-appindicator3-dev libkeybinder-3.0-dev libcurl4-openssl-dev liblzma-dev libsecret-1-dev libx11-dev libgl1-mesa-dev openjdk-17-jdk openjdk-21-jdk-headless unzip zip xz-utils git curl gh`。GitHub CLI 登录用 `gh auth login`，签名和凭据不写进环境脚本或版本控制。

从 Windows 迁移时重新运行 `flutter pub get`，不要复用 Windows 的 `.dart_tool`、插件路径、构建缓存和 Android `local.properties` 中的 SDK 路径。保留签名配置及用户修改。Linux 工作区使用 `core.autocrlf=false`，Shell 脚本和 Smart 补丁由 `.gitattributes` 固定 LF。NTFS 备份保留 `core.filemode=false`；本机已核实支持符号链接并启用 `core.symlinks=true`。**当前 `/mnt/shared` 的 NTFS 挂载配置使用 `fmask=0133` 且未启用逐文件权限，屏蔽执行位并忽略 `chmod`，因此当前配置不能直接完整构建/运行**；这是挂载配置限制，不是所有 NTFS 都无法构建。按维护者要求，唯一日常开发目录已迁移为 ext4 上的 `/home/kevin-chen/project/bettbox_smart`（`~/project/bettbox_smart`），共享盘原目录只保留备份，旧 `~/development/Bettbox` 开发副本已移走。不要在旧目录继续修改源码。复制到新路径后重新运行 `flutter pub get`，不复制 `.dart_tool`、`build`、`ephemeral`、`.cxx` 或 Rust `target` 缓存。

```sh
source tool/linux-env.sh
flutter doctor -v
flutter pub get
dart run build_runner build -d
# 只构建开发用内核，不运行需要 sudo 的 Linux 发行包打包步骤
dart setup.dart linux --arch amd64 --out core --dev --compatible
flutter run -d linux --dart-define=APP_DEV=true
```

### 本机 Linux 版本维护与 DEB 构建

已核实 Bettbox `main` 的 README、Linux runner 和上游构建工作流支持 Linux x64/arm64；Smart `Alpha` 的构建工作流也包含 Linux 内核。本 fork 复用现有 Linux 客户端和 Smart 补丁，不新增上游。参考：[Bettbox Linux 构建](https://github.com/appshubcc/Bettbox/blob/main/.github/workflows/build.yaml)、[Smart Alpha 构建](https://github.com/vernesong/mihomo/blob/Alpha/.github/workflows/build.yml)。

维护者本机为 Ubuntu 24.04.5 LTS（noble）、x86_64、AMD Ryzen 5 5600H。固定维护适用于 Ubuntu 24.04 的 **Linux x64 DEB**，内核使用默认 `GOAMD64=v3`（本机支持 AVX2/FMA/BMI 等要求）；不额外构建 Linux arm64、Compatible、RPM 或 AppImage。换机或升级系统后重新核实环境，不沿用本机记录作为新机器的兼容性证明。

沿用项目的 `flutter_distributor` DEB 打包器和 `linux/packaging/deb/make_config.yaml`。包名为 `bettbox-smart`，桌面显示 Bettbox Smart，运行时依赖采用 Ubuntu 24.04 的库包，不要求用户安装开发头文件。JNI 使用 `/usr/lib/jvm/java-17-openjdk-amd64/lib/server`，DEB 依赖 `openjdk-17-jre-headless`；CI 也使用 Ubuntu 的 OpenJDK 17，避免把 runner 私有的 Temurin 路径写进产物。可执行文件和安装目录仍沿用上游 `/usr/share/Bettbox/`，因此声明与上游 `bettbox` 包冲突，不承诺与原版共存；不要更改当前应用数据目录或在更新/卸载时删除配置。DEB 中 `BettboxCore` 保持 root 所有权、0755 执行权限，不预置 setuid；安装脚本通过 `libcap2-bin` 设置 `cap_net_admin,cap_net_bind_service,cap_net_raw=+ep`。包内 `90-bettbox.rules` 仅允许本地活动会话执行所需的四项 systemd-resolved DNS 操作，运行时支持 Linux 系统 DNS 设置及恢复。核实包内权限和安装脚本；安装后的 capabilities/TUN 授权需实机确认。App 更新链接保持进入 fork Release 页面（不设置上游格式的 `APP_ASSET_SUFFIX`，以免指向错误文件名）。

加载工具链并生成代码后，构建 Linux 内核并打包 DEB。

```sh
source tool/linux-env.sh
flutter pub get
dart run build_runner build -d
dart setup.dart linux --arch amd64 --out core --standard
dart pub global activate --source path plugins/flutter_distributor/packages/flutter_distributor
dart pub global run flutter_distributor:main package --skip-clean --platform linux --targets deb --description x64 --build-target-platform linux-x64 --build-dart-define=APP_ENV=pre --build-dart-define=APP_STANDARD=true
```

上述步骤及包检查封装在 `bash tool/build-linux-local.sh`。脚本将 DEB 和本机构建来源记录写入 `dist/smart-local/<提交SHA>/`，包名为 `Bettbox-smart-linux-x64.deb`。不要直接运行未指定 `--out core` 的 `dart setup.dart linux`，它会安装额外系统依赖并构建 DEB/RPM/AppImage。本地打包不提交、不推送、不安装、不发布、不修改版本号；需要试装时由维护者运行 `sudo apt install ./Bettbox-smart-linux-x64.deb`（或本地实际文件路径），由 apt 处理运行时依赖。

以后按 AI 更新入口更新时，Linux 与 Windows/Android 使用同一 App 提交、版本号、Bettbox SHA、Smart SHA 和发布轮换规则。发布前核实 DEB 的 `Package=bettbox-smart`、`Architecture=amd64`、版本含本次构建号，包含界面及 Smart 内核，所有 ELF 依赖均可解析。Linux 实机验证包括启动、托盘、系统代理、TUN 授权/连接、Smart 选路与模型同步；没有执行时如实注明，构建成功不能替代这些验证。旧测试版转正时保持旧资产，不给它补装新 Linux 包。

### 本机直接构建 Android APK

在 Linux 原生文件系统上的项目根目录运行：

```sh
cd ~/project/bettbox_smart
bash tool/build-android-local.sh
# 恢复原来的持久签名后，禁止回退到 debug 签名：
bash tool/build-android-local.sh --require-signing
```

脚本加载本机工具链，检查工作区执行权限，获取依赖、生成代码、编译 Smart 内核，再构建 **仅 arm64-v8a** 的 release-mode 测试 APK。不提交、不推送、不发布、不修改版本号。输出：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。生成代码后检查 Git 差异，不顺便提交无关 provider hash/格式变化。不要同时运行两个构建或 Smart 生成器与 Go 测试。

当前本机已从维护者的原始备份恢复 `android/app/keystore.jks`，在 `android/local.properties` 配置签名参数并保留 Linux SDK 路径；两份文件均为 `600` 权限且被 Git 忽略。日常构建建议使用 `--require-signing`，防止签名配置缺失时静默回退。换机时若没有恢复持久签名，默认脚本会明确警告，Gradle 回退到本机 debug key；这种 APK 不能覆盖此前由持久 key 签名的 App，且不适合正式发布。要支持覆盖更新，**恢复原来的同一份 keystore** 到上述忽略路径，在忽略的 `android/local.properties` 中本地配置 `keyAlias`、`storePassword`、`keyPassword`，同时保留 Linux 的 `sdk.dir` 与 `flutter.sdk`。不要新建替代 key，不把密码放进脚本、聊天、Git 或日志；本地配置权限建议 `chmod 600`。

Linux Flutter 无法直接构建完整 Windows 客户端。Go 内核可以交叉编译，但 Flutter Windows runner、MSVC 插件与 HelperService 仍需 Windows 工具链；完整便携包使用现有 `Build Smart` Windows runner，或 Windows 本机/虚拟机。本地 Android 构建不要求触发 Actions。

Linux 界面测试不替代 Windows 系统代理/托盘和 Android 真机 VPN/后台验证。发布同时维护 Windows x64、Android arm64-v8a 和 Ubuntu 24.04 Linux x64 DEB，安卓仍遵守持久签名要求。

```sh
flutter pub get
dart run build_runner build -d
dart tool/prepare_smart_core.dart
flutter test test/smart_group_test.dart test/views/proxies/smart_delay_test.dart test/views/proxies/delay_test_coordinator_test.dart
flutter test test/clash/bundle_sync_test.dart test/common/managed_script_test.dart test/common/profile_recovery_test.dart
dart analyze tool/prepare_smart_core.dart tool/update_smart_core.dart lib/views/resources.dart lib/clash/interface.dart
# 在 core 中：Windows 关闭 CGO，与实际 exe 构建一致
go test -tags=with_gvisor ./...
# nodes_test.go、profile_merge_test.go 等覆盖落地代理链路、订阅合并和 Provider 行为
# 在 core/.smart-mihomo 中：
go test -tags=with_gvisor ./common/callback ./adapter/outboundgroup ./component/smart/... ./tunnel/statistic ./listener/sing_tun
```

代码生成可能带来许多无关格式差异。只保留所需模型变更，确保 JSON 枚举有 `GroupType.Smart: 'Smart'`；不要漏掉生成模型，也不要把整个项目顺便重排。

不能因本机缺少 VS/Rust 而声称已验证完整 App；可用 GitHub 完整构建做验证。Android arm64-v8a 要检查 `.so` 的 ELF LOAD 页对齐至少 16 KB（`0x4000`）。构建通过仍不等于真机 TUN/VPN/后台表现已验证，最终回复须准确说明验证范围。

## 4. 提交、构建与失败处理

提交前先完成文档同步检查：核对 `README.md`、`readme/Smart.md`、`readme/Fork-Features.md`、`readme/AI_UPDATE_GUIDE.md`、`readme/Smart-Maintenance.md` 是否与本次上游变更及 fork 功能边界一致，再更新 `readme/Smart-Release-Notes.md`。更新日志仅说明本次主要更新内容，包括实际功能、修复、模型、工具链或打包变化。不列测试通过、测试清单或验证过程，也不把内核基线沿用、发布轮换过程写入更新日志；这些记录放 Actions、构建来源 JSON 或维护文档，来源 SHA 保存在来源 JSON 和构建来源 JSON。无新代码时不要造空提交或新 Release；若仅模型更新，它由 App 按钮/自动更新获取，通常无需重新发布 App。

```sh
git diff --check
git status --short
git add <逐项核实的文件>
git commit -m "Update Bettbox and Smart core"
git push origin feat/smart-core
git rev-parse HEAD
gh run list --repo KevinChen222/Bettbox --branch feat/smart-core --workflow smart.yaml --limit 5 --json databaseId,headSha,status,conclusion,url
```

选择 `headSha` 等于本次提交的运行，记下运行 ID。`Build Smart` 的 Windows、Android 两个任务和同一提交的本机 Linux DEB 构建检查都必须成功。用 `gh run view <ID> --repo KevinChen222/Bettbox --json status,conclusion,jobs` 检查进度，有失败则读取该运行失败日志修复后再提交。不要以旧提交的绿色构建替代当前提交结果，不带着失败发布，也不要连续高频轮询。

Fork 的工作流只在功能分支，手动 workflow_dispatch 的可用性取决于 GitHub 默认分支注册情况。日常依靠分支推送触发；已完成的同一提交可以 rerun。不要为触发工作流推送上游或创建空提交。

### 安卓持久签名

工作流使用本 fork Secrets：`KEYSTORE`（JKS 文件 base64）、`KEY_ALIAS`、`STORE_PASSWORD`、`KEY_PASSWORD`。检查名字是否存在，不打印值。没有时只能得到临时 debug 签名，应先配置持久签名再正式发布；不要每次生成新 key，也不能覆盖原有 Secrets/签名而不核实。签名资料单独备份，不提交到仓库或附到 Release。

同一 key 签名的后续 APK 可以覆盖更新。不能用此 key 覆盖官方 App；不要使用上游 SignPath 的秘密或宣称上游签名。Windows 本 fork 包为未签名便携包。

## 5. 在个人 fork 发布

完整构建成功后，从准确的运行下载 Windows/Android 两个 Artifact 到 `dist/smart/<运行ID>`：

```sh
gh run download <ID> --repo KevinChen222/Bettbox --dir dist/smart/<ID>
```

将 `tool/build-linux-local.sh` 生成且来源提交一致的 `Bettbox-smart-linux-x64.deb` 复制到同一产物目录，与下载的 `Bettbox-smart-windows-x64.zip`、`Bettbox-smart-android-arm64-v8a.apk` 一起发布。核实 Windows 内核/HelperService、APK 的 `lib/` 仅含 arm64-v8a 且含 `libmeta.so`；验证 APK 沿用上一版的持久自用签名，Smart 库保持 16 KB 页对齐。核实 Linux DEB 的 amd64 架构、版本和内核权限，并在 Ubuntu 24.04 检查动态库依赖。计算三个安装包 SHA256，生成 `SHA256SUMS.txt`，并写 `build-info.json` 记录 App 提交、Bettbox SHA、Smart SHA、Actions URL、本机 Linux 构建环境与来源、构建版本、产物架构和签名方式。新 Release 共五个资产：Windows ZIP、arm64-v8a APK、Linux x64 DEB、校验和与来源 JSON；上一版转正时保持其原有资产不变。不得把日志中的秘密、签名备份或源缓存打包。

### 测试版与正式版轮换规则

Release 最终只保留一个测试版和一个正式版。每一个新 Release 首先作为测试版发布：`prerelease=true`，标题末尾加 ` · test`，`latest=false`。每次依据用户明确指定的模式处理：

- **功能更新并转正上一测试版**：新测试版成功公开后，把上一测试版设为 `prerelease=false`，去掉标题末尾的 ` · test`，设为 `latest=true`，然后移除被替换的旧正式版 Release。
- **bug 修复替换测试版**：新测试版成功公开后，移除上一测试版 Release，现有正式版及 Latest 元数据保持不变；绝不自动把上一测试版转正。

用户未指定模式且上下文无法判断时，先准备可审阅的修复与构建，再询问模式，不擅自转正。仅清理本 fork 的 Smart Release，不删除 Git 标签、不移动标签、不改写历史。转正不代表新增了真机验证证明。

发布前用 `gh release list --repo KevinChen222/Bettbox --limit 20 --json tagName,name,isPrerelease,isDraft,publishedAt` 分别记录最新公开测试版和最新正式版的标签、原标题与资产。不能用 `/latest` 查找测试版，它排除预发布。只处理本 fork 的 `smart-v` 版本，跳过草稿。已有正式版本不反向改成 test。若有遗留版本，核对发布顺序后按本节只保留所需的一个测试版和一个正式版。

先成功发布并核实新 test，再执行转正或清理。构建失败、资产缺失、发布仍是草稿或新 Release 不可访问时，旧 Release 保持原状。转正或清理失败时保留新 test，重试同一操作，不创建重复发布。首次发布没有上一版时只发布 test。

标签格式仍为 `smart-v<App版本>-<台北日期YYYYMMDD>.<序号>`，例 `smart-v1.19.4-20261004.1`。**标签不加 test 后缀**，方便转正时只修改 Release 元数据。检查远端是否已存在；存在则核实并复用未完成的草稿，或选择下一个序号，不能移动已有标签。标签不要以裸 `v` 开头，避免触发上游原发布工作流。

```sh
gh release create <标签> <windows.zip> <android-arm64.apk> <linux-x64.deb> <SHA256SUMS.txt> <build-info.json> --repo KevinChen222/Bettbox --target <本次绿色构建的完整提交SHA> --title "Bettbox Smart <版本> · <台北日期.序号> · test" --notes-file readme/Smart-Release-Notes.md --draft --prerelease --latest=false
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

转正只改 GitHub Release 的预发布标记、标题和 Latest 元数据，不重新构建、不替换资产、不移动/重命名标签、不修改安装包内的 APP_ENV、签名或版本号。App 更新检查会检测本 fork 公开的正式版与测试版，并打开对应标签的 Release 页面供下载。

只发布到个人 fork。若失败就保留草稿，修复资产或说明后继续；不制造重复发布。发布后再次核实新版本为 test、正式版已按指定模式保留或转正、列表只有这两个 Release。`build-info.json` 记录发布时为 test、发布模式、上一测试版与所保留的正式版标签，作为历史记录；不能因日后转正而重写旧资产。最终回复提供 test Release、正式版保留或转正结果、Actions 与维护说明，准确说明上游更新范围及真机验证限制。

## 成功标准

两个上游都已核查（单独发布客户端修复时如实说明沿用原内核基线，不冒称已更新上游）；代码与来源 JSON 一致；Bettbox 原内核目录未混入 Smart；个人自用声明保留；相关功能与维护文档（含 `readme/AI_UPDATE_GUIDE.md`）已按本次变更同步检查更新；工作区无临时试验；本次提交的 Windows/Android Actions 构建与本机 Linux DEB 构建检查都成功；新 Release 为 test，含正确二进制、校验和及来源信息；正式版按用户指定模式保留或转正；Release 仅保留这两个版本。账号失效或构建确实受阻时明确说明已完成内容和阻塞原因，保留可继续的状态，不能假称发布成功。
