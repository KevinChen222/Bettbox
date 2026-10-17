# Bettbox Smart：AI 更新入口

每次只需引用本文件，说明**本次目标、发布模式和额外限制**，不用粘贴指南全文、旧聊天或之前的更新信息。例如：

> 按 readme/AI_UPDATE_GUIDE.md 更新两个上游并发布测试版，转正上一测试版。

> 按 readme/AI_UPDATE_GUIDE.md 修复【问题与复现步骤】并替换测试版，保留正式版。

只改代码时注明“不发布”。引用文档本身不启动更新或发布；明确要求按本指南更新时，授权修改本 fork、提交/推送指定分支、运行 Actions、下载产物及按指定模式发布和清理 Release。

## 默认维护与测试环境

以后默认在维护者这台 Ubuntu 24.04 x86_64 机器的 `/home/kevin-chen/project/bettbox_smart` 维护。先加载 `tool/linux-env.sh`，保留工作区已有改动；工具版本仍以项目要求及实际环境为准。

本机测试阶段只构建 **Linux x64 客户端/DEB** 和 **Android arm64-v8a APK**。安卓使用 `bash tool/build-android-local.sh --require-signing`，沿用原持久签名；Linux 按维护参考的本机 DEB 步骤构建。先运行与变更有关的定向测试，再构建交给维护者实测。Windows x64 包由 GitHub Actions 的 Windows runner 构建，不要求本机安装 Windows/MSVC 工具链。

维护者说“先本机测试”时，完成上述 Linux/Android 产物后交付路径，等待明确发布指令；不把构建成功当作维护者已完成实测。明确发布时，核实同一提交的 Windows、Android Actions 构建和本机 Linux DEB 构建检查全部成功，再按指定测试版/正式版规则发布。

例如：

> 按 readme/AI_UPDATE_GUIDE.md 更新两个上游，先构建本机 Linux 和 Android APK 供我测试，暂不发布。

## 必须遵守

- 唯一可写远端：`KevinChen222/Bettbox`，分支 `feat/smart-core`。只读上游为 `appshubcc/Bettbox:main` 和 `vernesong/mihomo:Alpha`；不能用 `main`/`Meta` 替代 Smart，也不向上游推送或发消息。
- 保留用户改动，不强推、不改写历史、不删除或移动旧标签。保留个人自用声明、开源许可和 NOTICE；密钥及密码不进入 Git、日志或产物。
- `core/Clash.Meta/` 保留 Bettbox 原内核；Smart 改动保存在 `core/smart.patch`，生成目录 `core/.smart-mihomo/` 和 `.test/` 不提交。冲突修复保存补丁前不能重新生成或构建，以免覆盖修复。
- 发布 Windows x64 便携包、Android **仅 arm64-v8a** APK 和适合本机 **Ubuntu 24.04 x86_64** 的 Linux x64 DEB。安卓沿用持久签名并核实 16 KB 页对齐；Linux 使用普通 AMD64 v3 内核（本机 Ryzen 5 5600H 支持），不额外维护 arm64、旧系统兼容版、RPM 或 AppImage。Windows/Android 使用本次提交成功的 Actions 产物，Linux 使用同一提交在本机构建并检查的 DEB；资产含三个安装包、SHA256SUMS 和 build-info。验证范围如实说明。
- 新版先发 test。**功能更新**：新 test 公开后转正上一 test；**bug 修复**：替换上一 test，保留正式版。最终各留一个测试版和正式版（首次只发 test），清理 Release 时保留标签；转正只改元数据。模式不明时先完成修复与构建，再询问。

## AI 按需读取

更新任务先读项目 `AGENTS.md`（如有）与 `core/smart-source.json`，检查工作区、分支及远端。当前集成 SHA 以来源 JSON 为准；近期改动查 Git，本次说明查 `Smart-Release-Notes.md`，构建和发布状态查 Actions/Release。不要要求用户重复粘贴历史，也不要把旧文档中的“本次”当作当前指令。

执行到对应阶段，**先读下表所列约束**，不用开聊时加载全部文档：

| 阶段 | 必读参考 |
| --- | --- |
| 上游合并与内核适配 | [维护参考](Smart-Maintenance.md)的“仓库与维护范围”“已实现的结构”及第 1–2 节；合并 Bettbox 或改链路时读 [Proxy-Chains.md](Proxy-Chains.md) 的维护部分 |
| 构建与验证 | 维护参考第 3 节及相关 workflow/构建配置；工具版本以当前项目要求为准 |
| 提交与发布 | 维护参考第 4–5 节及成功标准；发布前查询实际 Release，不复用旧聊天中的标签或状态 |

功能细节仅涉及时读 [Smart.md](Smart.md)、[Fork-Features.md](Fork-Features.md) 或相关源码。只有新代码或必要打包变化才发布；仅模型更新通常无需发布 App。更新日志只写本次功能、修复和必要工具链/打包变化，不写测试过程。
