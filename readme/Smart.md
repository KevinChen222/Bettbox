# Bettbox Smart 内核分支

本分支为 Windows 和 Android 集成 [vernesong/mihomo 的 Smart 策略组](https://github.com/vernesong/mihomo/tree/Alpha)。合入 Smart `baef5ee5ac6b4ab84349f9a5251df0fb264c999a` 相对官方基线 `88dcbf7f1614a67c3b36b848ee3592dfa92ada36` 的 Go 代码差异，保留 Bettbox 的平台补丁。Smart 差异保存在 `core/smart.patch`，构建时生成 `core/.smart-mihomo`；原始 `core/Clash.Meta` 与 Bettbox 上游保持一致，不会在构建时自动切换到最新 Alpha。

## 使用

在配置编辑器中添加 Smart 策略组，或导入含 `type: smart` 的订阅配置。不会自动改变现有 select/url-test/fallback/load-balance 组。

```yaml
lgbm-auto-update: true
lgbm-update-interval: 72
proxy-groups:
  - name: Smart
    type: smart
    proxies: [节点 A, 节点 B] # 替换为配置中的实际节点，也可以使用 use 引用 provider
    url: https://www.gstatic.com/generate_204
    interval: 300
    lazy: true
    tolerance: 50
    uselightgbm: true
    collectdata: false
    prefer-asn: true
rules:
  - MATCH,Smart
```

Smart 按目标和连接表现选择节点。点击组内节点可固定选择，再点击已固定的节点可恢复自动选择。自动状态下没有唯一的全局选中节点。

Smart 组自己的测速按钮会测试全部可测速成员，解除手动固定并恢复自动选路；搜索筛选不影响测速范围。其他组中的 Smart 卡片只测速一次：固定模式测试固定节点，自动模式由 Smart 为测速地址选路，不触发整组测速或解除固定选择。

LightGBM 使用纯 Go 推理，不需要额外的原生 DLL/SO。启用 `uselightgbm` 后，内核会从上游模型发布下载 `Model.bin` 到应用内核数据目录；首次使用需能访问 GitHub。可以设置 `lgbm-url` 指定模型地址。设为 `uselightgbm: false` 时仍可使用 Smart 的统计选路。数据收集默认关闭。

资源页面提供 **LightGBM → 同步** 按钮，可首次下载或更新小模型，也参与「同步全部」。默认地址为 `https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/Model.bin`，内核保存路径为 `HomeDir/Model.bin`（Windows 为应用数据目录，安卓为应用私有数据目录），成功校验后替换文件并重新加载，无需重启。若配置指定了 `lgbm-url`，内核更新器遵守该覆盖地址。更新失败会提示错误并保留旧模型。

## 构建与下载

本 fork 还提供独立的 **工具 → 代理链路** 功能，可组合节点、策略组和 HTTP/SOCKS5 端点，预览多跳路径、绑定已有策略组，以及创建本地配置。使用方法与后续上游合并注意事项见 [代理链路说明](Proxy-Chains.md)。

`Build Smart` 工作流在 `feat/smart-core` 推送时运行，也支持 Actions 手动运行。产物在该次运行的 Artifacts 中：Windows x64 便携包（包含界面、内核和 HelperService）、Android arm64-v8a 单架构 APK，以及包含 arm64-v8a、armeabi-v7a、x86_64 内核的 Android 通用 APK。支持 arm64-v8a 的设备可下载体积更小的单架构包；两种 APK 使用相同版本和持久签名。Windows 内核使用兼容的 AMD64 v1 指令集；ARMv7 使用 `with_low_memory`。安卓 64 位库保留 16 KB 页对齐。

Fork 构建不使用上游 SignPath 证书。安卓通过 fork Secrets 中的持久自用 keystore 签名；缺少 Secrets 时退回构建环境 debug 签名。Android 包名为 `com.kevinchen222.bettbox.smart`，可与原版 Bettbox 共存；从旧包名迁移时通过备份导入数据。更新检查只读取 `KevinChen222/Bettbox` 最新正式版，同时比较应用版本与构建日期/序号。

Release 只保留一个 **test / Pre-release** 和一个正式版。每次由用户指定发布模式：功能更新在新测试版公开后把上一测试版转正；bug 修复替换测试版且保留现有正式版。本次为 bug 修复。转正只修改 Release 元数据，标签和安装包不变；删除被替换的旧 Release 时保留 Git 标签。测试版从 Releases 页面手动下载。

本机构建需要 Flutter 3.44.9、Go 1.25+、Rust；Windows 还需 Visual Studio C++ 工具链，Android 需 JDK 17 和 NDK 28.2.13676358。

后续 AI 助手独立更新两个上游、构建和发布的完整操作手册见 [AI 更新与发布说明](AI_UPDATE_GUIDE.md)，本次版本说明见 [更新日志](Smart-Release-Notes.md)。

```sh
flutter pub get
dart run build_runner build -d
flutter test test/smart_group_test.dart test/views/proxies/smart_delay_test.dart test/views/proxies/delay_test_coordinator_test.dart test/controller_loading_test.dart
dart tool/prepare_smart_core.dart
# cd core 后可运行 go test -tags=with_gvisor ./...
# Windows，包含 HelperService
dart setup.dart windows --arch amd64 --out core --compatible
# 将生成的内核/HelperService随 flutter build windows 产物一起打包
# Android，生成所有 ABI 的共享内核
dart setup.dart android --arch universal --out core
flutter build apk --release --target-platform android-arm,android-arm64,android-x64
# 复用已编译的内核，另生成仅含 arm64-v8a 的 APK
flutter build apk --release --split-per-abi --target-platform android-arm64
```

Go 桥接测试位于 `core/smart_test.go`，验证 Smart 配置、选择/恢复自动状态、客户端 JSON、GeoIP/ASN 数据保留，以及模型更新成功时即时加载、失败时保留旧文件。生成的内核保留 Smart 上游的策略组及 TCP 统计测试。SS2022 连接关闭的机制、修复和验证范围见 [连接关闭高 CPU 修复记录](Smart-CPU-Fix.md)。

## 合并后续 Bettbox 更新

克隆完整 Git 历史；三方补丁合并需要原始基线文件对象。`setup.dart` 每次构建都会从当前 Bettbox 内核重新生成 Smart 内核，忽略目录中旧的生成结果。

```sh
git remote add upstream https://github.com/appshubcc/Bettbox.git # 已存在则跳过
git fetch upstream
git switch feat/smart-core
git merge upstream/main
flutter pub get
dart run build_runner build -d
dart tool/prepare_smart_core.dart
flutter test test/smart_group_test.dart test/views/proxies/smart_delay_test.dart test/views/proxies/delay_test_coordinator_test.dart test/controller_loading_test.dart
# 在 core 目录运行 go test -tags=with_gvisor ./...
git push origin feat/smart-core
```

通常先按正常 Git 合并处理少量客户端/构建脚本改动，再执行构建即可。内核生成器使用 `git apply --3way` 合入独立补丁：不重叠的上游改动会自动保留。如果 Bettbox 修改了 Smart 涉及的同一段内核代码，构建会失败并打印冲突文件，不能保证所有更新零冲突。

此时打开 `core/.smart-mihomo` 中报告的文件，处理 `<<<<<<<` 等冲突标记并保留两侧需要的逻辑，然后运行：

```sh
dart tool/prepare_smart_core.dart --refresh-patch
dart tool/prepare_smart_core.dart
```

`--refresh-patch` 把已处理的结果保存到 `core/smart.patch`，拒绝保留冲突标记或生成空补丁。重新运行测试并提交此补丁。不要把生成目录提交，也不要在保存补丁前重新构建（生成目录会被覆盖）。

Smart 自身更新时运行 `dart tool/update_smart_core.dart`，它会将已记录 Smart 提交到最新 Alpha 的 Go 差异三方合入当前生成内核，同时保存新的补丁和 `core/smart-source.json`。若有冲突，先处理生成目录并保存补丁，再将 `.test/smart-candidate.json` 的候选来源记录保存到 `core/smart-source.json`；验证成功后再提交。两个上游都要检查，不应只更新 Bettbox。
