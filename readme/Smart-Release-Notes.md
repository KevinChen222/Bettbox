# Bettbox Smart 1.19.4 · 2026-10-04

本版本为 KevinChen222 的个人自用分支，公开仓库和产物用于源码透明与版本留存；不提供面向其他试用者的支持、稳定性或适用性保证。其他人自行试用造成的问题与本 fork 维护者及 Bettbox、Mihomo、Smart 上游作者无关。原开源许可证保留。

## 来源

- Bettbox：`45d6fd3781a20bc7639cb7788b542e0cba1ec3af`，App 1.19.4。
- Smart：vernesong/mihomo `Alpha`，`baef5ee5ac6b4ab84349f9a5251df0fb264c999a`。
- 初始官方 Mihomo 基线：`88dcbf7f1614a67c3b36b848ee3592dfa92ada36`。
- LightGBM：上游 `LightGBM-Model/Model.bin` 发布，运行时可更新。

## 本次变化

- 本日第 2 次发布新增 `Bettbox-smart-android-arm64-v8a.apk`，只包含 arm64-v8a 运行库，以减少支持该架构设备的下载体积；保留通用 APK 和 Windows 包。来源提交保持如上，两种安卓 APK 沿用同一持久自用签名；维护手册同步加入单架构构建、验证和发布步骤。
- Windows 与 Android 集成 Smart 统计选路与纯 Go LightGBM 推理。
- 客户端识别 Smart 策略组，支持固定节点及恢复自动选择。
- 资源页面增加 LightGBM 同步按钮；校验后保存至内核 `HomeDir/Model.bin` 并即时重新加载，失败时保留旧文件。
- 保留 Bettbox 安卓 VPN/TUN、流量统计和低内存补丁，防止内存清理卸载 Smart 正在使用的 GeoIP/ASN 数据。
- 更新检查指向个人 fork，并兼容 `smart-v…` 发布标签；同一 App 版本内的内核更新由维护流程检查。
- Smart 以内核补丁独立维护，原始 Bettbox 内核保持不变，构建时三方合并。新增 Smart 上游增量更新器、来源记录，以及给后续 AI 助手的独立更新/构建/发布操作手册。
- 构建使用 Flutter 3.44.9；Windows 提供 x64 兼容指令集便携包，Android 提供 arm64-v8a、armeabi-v7a、x86_64 通用 APK。

## 验证与限制

Smart 客户端模型、Go 桥接、内核策略组、TCP 统计、TUN 补丁及模型更新回归测试已验证；安卓三 ABI 共享内核编译及 64 位 16 KB 页对齐已检查。完整 App 构建结果以本 Release 的 `build-info.json` 和关联 Actions 运行记录为准。

没有在真实 Windows TUN 或安卓 VPN/后台环境进行设备测试。Windows 包不使用上游 SignPath 证书；安卓使用本 fork 自用签名，不能覆盖官方签名版本。LightGBM 首次下载/更新需要访问上游模型地址。现有配置不会被自动改写为 Smart，使用方法见 `readme/Smart.md`。
