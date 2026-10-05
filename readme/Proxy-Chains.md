# Bettbox 代理链路

工具 → 设置 → **代理链路**。点击「创建链路」，选择已有配置，按「客户端 → 第一跳 → … → 最后一跳 → 目标」添加节点或代理端点。可以上移、下移、移除各跳，预览路径，设置最大路径数，再保存。

支持以下来源：

- 配置中的节点，按节点名引用，每次生成运行配置时读取最新内容。
- 配置中的策略组，包括嵌套组、Smart 组、`use`、`include-all`、`include-all-proxies`、`include-all-providers`。多跳链路的第一跳直接引用原组名，跟随该组实时选择和 Smart 自动选路；后续组展开为节点副本。DIRECT、REJECT 等内置动作不作为独立中转节点。
- 已有 Provider 缓存和 inline Provider 的节点。HTTP Provider 使用 Bettbox 自己的缓存路径；file Provider 的相对路径以内核数据目录为准。Provider 尚未下载时先在资源页面同步。节点按 Provider 名与节点名引用，不依赖订阅的排列顺序。
- 本地或远程 HTTP(S)/SOCKS5 端点，支持地址、端口和可选认证。Android 的 `127.0.0.1` 指设备自身。
- 在「添加一跳」窗口顶部点击「添加外部节点」，使用「手动添加」或「订阅链接」。添加后返回节点列表选择所需节点；外部节点随当前链路保存，仅加入链路生成的运行配置、本地配置或导出 YAML 的 `proxies`，不写回来源配置。复制、备份及链路库导入/导出会保留这些节点。

配置 → 某个配置的编辑页左下角也有「添加节点」按钮，与保存按钮采用相同样式。点击后两项带动画展开、背景变暗，点击空白或返回可收起。此入口将节点追加到当前配置的 `proxies` 末尾，点击右下角「保存」才写入文件；之后链路创建即可直接选择。若原配置开启订阅自动更新，后续更新可能覆盖手动修改，保存时沿用原编辑页的自动更新提示。

手动输入支持每行一条分享链接（包括 SS2022 的 `ss://`）、Mihomo YAML/JSON 节点对象、`- {...}` 列表、多行大括号对象、标准 YAML 列表，以及带 `proxies` 的完整配置。可混合分享链接与大括号对象。链接由当前打包内核的转换器识别，节点参数再由同一内核校验；任何无法识别或无效节点都使整批导入失败，避免悄悄丢节点。同名节点分配 `(2)` 等后缀，导入批次内部的 `dialer-proxy` 引用相应更新。

订阅链接接受 HTTP(S)，支持含 `proxies` 的 YAML/JSON、分享链接列表和 Base64 链接订阅。只读取节点，不导入规则、策略组或 Provider 定义，也不保存链接做自动更新。仅含远程 Provider 定义而没有实际节点的订阅需先转换为含节点的订阅。不改变已有规则或策略组成员。

保存后会生成与链路同名的 select 策略组；名称冲突时分配后缀，不改动原节点和原规则。可以勾选「加入已有策略组」，然后在代理页面选择链路。没有绑定入口组的链路仍可在全局模式选择，或在覆写规则里引用生成组名；名称冲突时以代理页面实际名称为准。不自动改变既有规则或自动选中链路。

链路组内的可选路径按「入口节点或策略组 → 中间跳板节点或策略组 → 实际出口节点」命名，保留中文及 emoji，重名追加 `(2)` 等后缀。前置节点/组不重命名、不生成每个入口对应的出口副本：例如香港组 → 德国组，只复制德国落地节点，各副本的 `dialer-proxy` 直接填写香港组名称。切换入口在原香港组中进行，Smart 前置组继续自动选路。自定义端点和单独选择的 Provider 前置节点以原名加入运行节点表一次；三跳及以上仍需复制中间节点。旧链路重新加载后使用新逻辑，可能需要重新选择出口；已导出的 YAML 和本地配置需重新生成。

链路管理支持编辑、复制、启停、删除，以及链路库 JSON 导入/导出。创建时也可以导出含链路的完整 YAML，或点击「从链路创建本地配置」。生成配置保留原规则和规则集定义，通过绑定的已有策略组选择链路；创建本地配置时同时保留原策略组选择。首次加载本地快照时，先将来源配置的已下载 HTTP Provider 和规则集缓存复制到新配置目录，再改写路径，已有新缓存不会被覆盖；同设备导出的 YAML 重新导入也可沿用尚存在的来源缓存，跨设备需正常同步资源。配置中的内置节点和链路副本是快照，不自动跟随来源订阅更新；HTTP Provider 保留自己的更新机制。全局脚本已应用，所以新配置默认关闭再次脚本覆写。绑定原订阅的链路则每次使用最新节点参数。JSON 引用原配置 ID，适合与 Bettbox 备份一起迁移；导入同 ID 链路会更新它。导出的配置、本地端点及备份可能含节点认证信息，按普通订阅凭据保存。

最大 16 跳，每条链路默认最多 64 条路径，可选择 16/64/256/1024，前置组成员数量不计入展开数。预览仅展示前 20 条。后续节点/出口组无法解析、落地 Provider 缓存缺失、组循环、路径数超限时会明确报错。前置组可直接引用尚未缓存的 Provider，由内核正常初始化。不能将链路加入其前置依赖的组；原 `include-all`/`include-all-proxies` 组会排除生成副本，避免自身链路循环。UDP 传输、Reality、ShadowTLS 或下游节点已有 `dialer-proxy` 时提供兼容提示；生成副本重新设置 `dialer-proxy`，原前置保持不变。

## 独立于上游的结构

不修改 Bettbox 原始 Go 内核、不改 Smart 补丁、不引入 Avalon 数据库、不改 Profile/Config 的生成模型。链路入口不覆写订阅原文件；配置编辑页的节点添加仅在用户保存时写回当前文件。`core/node_import.go` 作为独立 Go 桥接入口复用内核已有转换器和节点校验器。

| 文件 | 职责 |
| --- | --- |
| `lib/features/chains/compiler.dart` | 来自 Avalon 的独立 dialer-proxy 编译器 |
| `assembler.dart` | Bettbox 节点/组快照、过滤、名称分配与入口组绑定 |
| `integration.dart` | Provider 缓存解析与运行时接入 |
| `filter.dart` | 策略组与 Provider 共用的 `(?i)` 过滤兼容 |
| `model.dart` / `store.dart` | 版本化链路库与串行、原子写入 |
| `view.dart` | 独立管理与编辑界面 |
| `lib/features/node_import/` | 两个入口共用的动画菜单、手动编辑、订阅导入、名称分配和 YAML 追加 |
| `core/node_import.go` | 仅提取节点，复用 Mihomo 分享链接转换及参数校验 |
| `avalon-source.json` / `LICENSE` | 实际移植来源和 Avalon 编译器许可 |

数据保存在应用数据目录的 `proxy-chains.json`，Windows 便携模式同样跟随 portable 目录。Bettbox 本地/WebDAV 备份会包含它；恢复遵守原覆盖/合并策略；旧备份在覆盖恢复时清空链路库。清空应用数据也清空链路库。

链路运行和备份的三个主要接入点：

1. `lib/views/tools.dart`：导入 `view.dart`、加入 `ProxyChainsItem` 和搜索入口。上游改 UI 时可以将这个入口移到新工具页面，不需要移植 Avalon 界面或重做导航枚举。
2. `lib/state.dart`：`patchRawConfig` 在脚本、过滤和组开关等处理完成后、写入/加载运行配置前调用 `applyProxyChains(profileId, rawConfig)`。编辑器用 `includeProxyChains: false` 读取基础有效配置，避免旧链路影响编辑。若上游重构配置流水线，保持这一顺序；不能写回 `Profile` 的订阅文件。
3. `lib/controller.dart`：在备份中加入链路库；恢复时先校验版本，再按恢复策略合并/覆盖；清空数据时清空链路库。上游改备份格式时迁移这三个行为。

节点添加另接入 `lib/views/profiles/edit_profile.dart`，并通过 `ActionMethod.importNodes`、`lib/clash/core.dart` / `interface.dart`、`core/action.go` / `constant.go` 调用独立桥接文件。保持生成 JSON 枚举映射与方法名一致。UI 合并时保留配置页左下角入口和链路选节点窗口顶部入口。

这些接入点仍可能与上游同一区域的改动产生冲突，不能保证零冲突；主要功能留在独立目录，缩小冲突范围。上游新增链路功能或改变 `dialer-proxy` 语义时，先审阅再适配，不能直接选 ours/theirs。

## 后续维护与验证

日常仍合并 Bettbox `main`，更新 Smart `Alpha`；**不要把整个 Avalon 分支 merge 到本 fork**。Avalon 只作为链路编译器的只读参考。要更新它时，读取 `avalon-source.json` 中的实际基线，对比 Avalon 的 `lib/features/chains/chains.dart` 和相关测试，只移植所需编译器修正，保留本地适配与许可，通过验证后记录新的实际 SHA。

```sh
dart analyze lib/features/chains test/features/chains lib/state.dart lib/views/tools.dart lib/controller.dart
flutter test test/features/chains test/smart_group_test.dart test/views/proxies/smart_delay_test.dart test/views/proxies/delay_test_coordinator_test.dart test/controller_loading_test.dart
# 在 core 中，Windows 关闭 CGO，与便携包内核一致
go test -tags=with_gvisor -run TestProxyChainConnectDirection -count=1 .
go test -tags=with_gvisor -run TestImport -count=1 .
git diff --check
```

链路测试覆盖前置实时引用、出口展开/循环/数量限制、名称冲突、原规则不变、订阅节点变化、Provider 排序与新配置缓存继承、存储/恢复、手机宽度编辑交互。Go 测试通过两个本地 HTTP CONNECT 代理访问目标，分别验证原节点、select 和 Smart 策略组作为前置。它不代表 Android 真机 VPN/TUN 或远程多协议链路已经验证；完整应用发布仍按 `AI_UPDATE_GUIDE.md` 的 Windows/Android 构建流程执行。

节点导入测试覆盖 SS2022、普通 SS 的 AEAD/传统加密与新旧链接格式、SSR、VMess 两种链接、VLESS/Reality、Trojan、Hysteria/Hy2、TUIC、AnyTLS、HTTP(S)、SOCKS 和 Mieru；同时核对 YAML/JSON 字段保留、混合与 Base64 订阅、SS 的 IPv6/obfs 参数。这些测试验证解析及内核参数校验，不代表已连接远程服务端；测试项目只记录在维护文档与 Actions，不写进 Release 更新说明。

## 来源与许可

编译器摘取自 [MasterAlanLab/Avalon](https://github.com/MasterAlanLab/avalon/blob/ea4d8ffc4842535f84e8def918fbf71d3e6b5609/lib/features/chains/chains.dart)，实际来源提交为 `ea4d8ffc4842535f84e8def918fbf71d3e6b5609`。保留 `Copyright (C) 2026 MasterAlanLab and Avalon contributors`，该代码为 AGPL-3.0，完整条款保存在 `lib/features/chains/LICENSE`。原 Bettbox/FlClash 的 GPL-3.0 许可、版权声明和本 fork 的个人自用/责任声明保留。Avalon 不为本 fork 提供支持，也不向 Avalon 或 Bettbox 原作者自动提交变更。

`Build Smart` 在构建前将该许可与根目录 `NOTICE` 复制到已有的 `assets/data/` 资源目录，随 Windows 便携包和已签名 APK 一起分发。不要通过修改已签名 APK 来补资源；需要补充许可时从对应源码重新构建。
