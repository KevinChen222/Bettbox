# Bettbox Smart 1.19.9

- 合入 Bettbox 1.19.9。配置页加入节点库，可导入单个节点、为落地节点指定前置代理，并绑定当前配置或托管分流的策略组。
- 新增「订阅合并」，将多个普通配置生成一个可选用的聚合订阅，支持成员节点前缀、重复节点合并和随成员更新重新生成。
- 旧链路的迁移需在升级前导出 YAML，在新版导入为本地配置。也可以在新版节点页手动重建前置和落地绑定。[旧版迁移步骤](https://github.com/KevinChen222/Bettbox/blob/feat/smart-core/readme/Fork-Features.md#从旧版升级)
- 更新内置托管分流脚本与共享规则，加入 Android 主屏幕小组件，调整首页导航和工具箱。
- 上游将 Android Gradle 最低要求降到 API 24（Android 7.0）。个人分支仍提供 arm64-v8a APK，Android 7.x 兼容性以该 Smart 产物的实际验证为准。
- 同步 Mihomo Smart Alpha，降低启动时 Geo 数据的内存占用，加入 Snell v6 支持并修正部分 HTTP CONNECT 与 ShadowTLS 连接问题。Smart 策略组继续支持自动选路和手动固定节点。资源页可同步 LightGBM 模型，模型通过校验后立即生效，校验失败时继续使用原模型。
