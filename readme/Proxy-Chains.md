# Bettbox 代理链路

工具 → 设置 → **代理链路**。点击「创建链路」，选择已有配置，按「客户端 → 第一跳 → … → 最后一跳 → 目标」添加节点或代理端点。可以上移、下移、移除各跳，预览路径，设置最大路径数，再保存。

支持以下来源：

- 配置中的节点，按节点名引用，每次生成运行配置时读取最新内容。
- 配置中的策略组，包括嵌套组、Smart 组、`use`、`include-all`、`include-all-proxies`、`include-all-providers`。多跳链路的第一跳直接引用原组名，跟随该组实时选择和 Smart 自动选路；后续组展开为节点副本。DIRECT、REJECT 等内置动作不作为独立中转节点。
- 已有 Provider 缓存和 inline Provider 的节点。HTTP Provider 使用 Bettbox 自己的缓存路径；file Provider 的相对路径以内核数据目录为准。Provider 尚未下载时先在资源页面同步。节点按 Provider 名与节点名引用，不依赖订阅的排列顺序。
- 本地或远程 HTTP(S)/SOCKS5 端点，支持地址、端口和可选认证。Android 的 `127.0.0.1` 指设备自身。
- 在「添加一跳」窗口顶部可按关键词搜索节点或策略组，忽略大小写，也可搜索 Provider 名。点击「添加外部节点」，使用「手动添加」或「订阅链接」，新添加的节点置于所有节点列表最前面，返回列表后即可选择。外部节点随当前链路保存，直接保存时加入来源 YAML 的 `proxies`，也进入本地快照和导出 YAML。复制、备份及链路库导入/导出保留节点及订阅所属关系。「删除已添加的节点」可以删除整批订阅或单个外部节点；相应跳和外部节点的前置引用同步移除，保存后生效。旧版未记录所属订阅的节点仍可单独删除。

配置 → 某个配置的编辑页左下角也有「添加节点」按钮。点击后两项带动画展开、背景变暗，点击空白或返回可收起。「手动添加」将节点放在当前配置的 `proxies` 最前面。「订阅链接」提供名称（可留空）和 URL 两个输入框，保存为当前 YAML 中的 HTTP `proxy-providers`，每 86400 秒更新，健康检查使用 `https://www.gstatic.com/generate_204`、间隔 600 秒，不添加特殊覆写；缓存路径为 `./proxies/<名称>.yaml`，不合法的路径字符替换且避免重名。名称留空时先读取订阅响应的 `profile-title` 或 Content-Disposition 名称，否则分配「新添加1」「新添加2」等名称，同名追加后缀。Provider 是否加入已有策略组遵循该组的 `use` / `include-all` 等设置，不修改已有组成员。

点击右下角「保存」才写入文件。通过此入口添加的手动节点和 Provider 同时记录在配置的本地补充数据中，随应用备份保存。机场主订阅仍按原 URL 更新完整配置，更新后将本地节点重新放在 `proxies` 最前面，并合回新增 Provider；同名时给本地补充项分配后缀，避免覆盖机场内容。原机场的规则和策略组继续更新，新增 Provider 保留独立更新机制。主动删除的本地补充项同步清除记录，主订阅更新不再恢复它们；直接编辑 YAML 后保存也同步更新已有补充项记录。旧版没有记录来源的节点不会被自动识别为手动添加，需通过新入口重新添加才能获得更新保留能力。

同一位置的「删除节点」可对当前 YAML 的 Provider 或全部 `proxies` 节点多选并确认删除。同步移除策略组的 `use`、成员引用及其他节点的 `dialer-proxy` 引用，没有其他成员或 Provider 的空组保留 DIRECT。验证通过后暂存修改，仍需点击保存才写入文件；如果还有规则等直接引用被删节点而导致内核验证失败，则保留编辑前内容并显示错误。机场本身下发的节点或 Provider 删除后仍可能随主订阅更新重新出现。

手动输入支持每行一条分享链接（包括 SS2022 的 `ss://`）、Mihomo YAML/JSON 节点对象、`- {...}` 列表、多行大括号对象、标准 YAML 列表，以及带 `proxies` 的完整配置。可混合分享链接与大括号对象。链接由当前打包内核的转换器识别，节点参数再由同一内核校验；任何无法识别或无效节点都使整批导入失败，避免悄悄丢节点。同名节点分配 `(2)` 等后缀，导入批次内部的 `dialer-proxy` 引用相应更新。

链路创建页的订阅链接接受 HTTP(S)，支持含 `proxies` 的 YAML/JSON、分享链接列表和 Base64 链接订阅。只读取节点，不导入规则、策略组或 Provider 定义，也不保存链接做自动更新；记录订阅名称用于整批删除。配置编辑页则直接保存 HTTP Provider，订阅内容需符合当前 Mihomo Provider 支持的格式。

直接点击「保存」会将链路写入当前配置 YAML，可以在同一配置中保存多个链路。生成与链路同名的 select 策略组，名称冲突时分配后缀，不改动原节点和原规则。可以勾选「加入已有策略组」，然后在代理页面选择其子策略。链路管理卡片的复制、删除按钮左侧提供「隐藏策略组」勾选框，默认勾选并写入 `hidden: true`，不显示在主策略组列表；取消勾选后可直接显示，隐藏不影响绑定组的子策略或规则引用。不自动改变既有规则或自动选中链路。

链路组内的可选路径按「入口节点或策略组 → 中间跳板节点或策略组 → 实际出口节点」命名，保留中文及 emoji，重名追加 `(2)` 等后缀。前置节点/组不重命名、不生成每个入口对应的出口副本：例如香港组 → 德国组，只复制德国落地节点，各副本的 `dialer-proxy` 直接填写香港组名称。切换入口在原香港组中进行，Smart 前置组继续自动选路。自定义端点和单独选择的 Provider 前置节点以原名加入运行节点表一次；三跳及以上仍需复制中间节点。旧链路重新加载后使用新逻辑，可能需要重新选择出口；已导出的 YAML 和本地配置需重新生成。

链路管理支持编辑、复制、启停、删除，以及链路库 JSON 导入/导出。这些操作同步更新来源 YAML：通过 `x-bettbox-chain-*` 标记识别生成内容，重新组合同配置的链路，删除时撤回对应生成组、节点副本、外部节点和入口组引用；仍被其他链路使用的外部节点保留。仅重写 `proxies` / `proxy-groups` 段，保留规则、Provider 和其他段落文本及用户后续修改。保存后关闭来源订阅的自动更新，删除最后一条链路时恢复原设置；手动更新订阅仍可能覆盖 YAML，需要重新保存链路。旧版仅存链路库的链路仍可按原方式运行，首次编辑保存或管理操作时写入 YAML。

只有明确点击「从链路创建本地配置」才创建新配置，也可导出含链路的完整 YAML。这两种快照不带管理标记，独立于来源配置的链路删除或隐藏操作。生成配置保留原规则和规则集定义，通过绑定的已有策略组选择链路；创建本地配置时同时保留原策略组选择。首次加载本地快照时，先将来源配置的已下载 HTTP Provider 和规则集缓存复制到新配置目录，再改写路径，已有新缓存不会被覆盖；同设备导出的 YAML 重新导入也可沿用尚存在的来源缓存，跨设备需正常同步资源。配置中的内置节点和链路副本是快照，HTTP Provider 保留自己的更新机制。全局脚本已应用，所以新配置默认关闭再次脚本覆写。JSON 引用原配置 ID，适合与 Bettbox 备份一起迁移；导入同 ID 链路会更新它。导出的配置、本地端点及备份可能含节点认证信息，按普通订阅凭据保存。

最大 16 跳，每条链路默认最多 64 条路径，可选择 16/64/256/1024，前置组成员数量不计入展开数。预览仅展示前 20 条。后续节点/出口组无法解析、落地 Provider 缓存缺失、组循环、路径数超限时会明确报错。前置组可直接引用尚未缓存的 Provider，由内核正常初始化。不能将链路加入其前置依赖的组；原 `include-all`/`include-all-proxies` 组会排除生成副本，避免自身链路循环。UDP 传输、Reality、ShadowTLS 或下游节点已有 `dialer-proxy` 时提供兼容提示；生成副本重新设置 `dialer-proxy`，原前置保持不变。

## 独立于上游的结构

不修改 Bettbox 原始 Go 内核、不改 Smart 补丁、不引入 Avalon 数据库。链路管理在用户保存和管理操作时更新来源文件；配置编辑页的节点添加和删除仅在用户保存时写回当前文件。`core/node_import.go` 作为独立 Go 桥接入口复用内核已有转换器和节点校验器。

| 文件 | 职责 |
| --- | --- |
| `lib/features/chains/compiler.dart` | 来自 Avalon 的独立 dialer-proxy 编译器 |
| `assembler.dart` | Bettbox 节点/组快照、过滤、名称分配与入口组绑定 |
| `integration.dart` | Provider 缓存解析与运行时接入 |
| `filter.dart` | 策略组与 Provider 共用的 `(?i)` 过滤兼容 |
| `model.dart` / `store.dart` | 版本化链路库与串行、原子写入 |
| `persistence.dart` | 来源 YAML 的链路写入和撤回，仅更新节点与组段落 |
| `view.dart` | 独立管理与编辑界面 |
| `lib/features/node_import/` | 两个入口的动画菜单、手动编辑、订阅节点/Provider 导入、删除及本地补充合并 |
| `core/node_import.go` | 仅提取节点，复用 Mihomo 分享链接转换及参数校验 |
| `avalon-source.json` / `LICENSE` | 实际移植来源和 Avalon 编译器许可 |

数据保存在应用数据目录的 `proxy-chains.json`，Windows 便携模式同样跟随 portable 目录。Bettbox 本地/WebDAV 备份会包含它；恢复遵守原覆盖/合并策略；旧备份在覆盖恢复时清空链路库。清空应用数据也清空链路库。

链路运行和备份的三个主要接入点：

1. `lib/views/tools.dart`：导入 `view.dart`、加入 `ProxyChainsItem` 和搜索入口。上游改 UI 时可以将这个入口移到新工具页面，不需要移植 Avalon 界面或重做导航枚举。
2. `lib/state.dart`：`patchRawConfig` 在脚本、过滤和组开关等处理完成后、写入/加载运行配置前调用 `applyProxyChains(profileId, rawConfig)`。仅对旧版未落盘链路补入运行配置，已落盘链路直接使用 YAML，避免重复生成或覆盖配置编辑页的修改。编辑器用 `includeProxyChains: false` 移除管理标记对应的生成内容后读取基础有效配置，避免旧链路影响编辑。`lib/controller.dart` 在重新应用配置前清空旧策略组、Provider 和高度缓存，加载失败时不保留旧配置列表。
3. `lib/controller.dart`：在备份中加入链路库；恢复时先校验版本，再按恢复策略合并/覆盖；清空数据时清空链路库。上游改备份格式时迁移这三个行为。

节点添加另接入 `lib/views/profiles/edit_profile.dart`，并通过 `ActionMethod.importNodes`、`lib/clash/core.dart` / `interface.dart`、`core/action.go` / `constant.go` 调用独立桥接文件。保持生成 JSON 枚举映射与方法名一致。UI 合并时保留配置页左下角入口和链路选节点窗口顶部入口。

这些接入点仍可能与上游同一区域的改动产生冲突，不能保证零冲突；主要功能留在独立目录，缩小冲突范围。上游新增链路功能或改变 `dialer-proxy` 语义时，先审阅再适配，不能直接选 ours/theirs。

## 后续维护与验证

日常仍合并 Bettbox `main`，更新 Smart `Alpha`；**不要把整个 Avalon 分支 merge 到本 fork**。Avalon 只作为链路编译器的只读参考。要更新它时，读取 `avalon-source.json` 中的实际基线，对比 Avalon 的 `lib/features/chains/chains.dart` 和相关测试，只移植所需编译器修正，保留本地适配与许可，通过验证后记录新的实际 SHA。

```sh
dart analyze lib/features/chains test/features/chains lib/state.dart lib/views/tools.dart lib/controller.dart
flutter test test/features/chains test/smart_group_test.dart test/views/proxies/smart_delay_test.dart test/views/proxies/delay_test_coordinator_test.dart test/controller_loading_test.dart
flutter test test/main_page_titles_test.dart
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
