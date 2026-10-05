# Smart 连接关闭高 CPU 修复

## 已复现的机制

当前依赖 `sing-shadowsocks2 v0.2.8` 的 SS2022 TCP `clientConn.Close` 同时对底层 Conn、reader、writer 调用 `sing/common.Close`。reader 没有 Close 或 Upstream；writer 没有 Close，但它的 Upstream 经 ExtendedWriter 包装回到底层 Conn，因此初始化 writer 后，底层连接会被关闭两次。

链式连接的底层 Conn 可以是 `tcpTracker`。旧实现每次都先调用底层 Close，随后才以 closed CAS 限制统计移除；这个 CAS 没有限制重复遍历。用真实 SS2022、deadline、refConn、outbound、callback 和 tracker 包装构造有限、无对象环的本地链，1、4、18 层在首次关闭时分别产生 2、16、262,144 次最底层 Close。重复关闭已关闭的 tracker 还会继续遍历。

这个机制能解释重复关闭调用及其分配开销；合成链的层数不代表用户实际代理跳数。已有 CPU 样本没有对象指针，不能据此证明实际连接存在对象环、无限递归或配置选择循环，也没有证明 LightGBM、内存泄漏或 OOM 是原因。

## 修复与清理职责

只修改 TCP tracker 的关闭入口：进入底层 Close 前用 closed CAS 取得关闭权，后续并发、重复及重入调用返回 nil。首次调用仍关闭原连接、返回原关闭错误，随后执行 manager.Leave；连接移除、Smart 目标成员清理和关闭通知仍发生一次。没有用互斥锁或 sync.Once 包住底层 Close，避免重入时等待自身。

SS2022 的 reader、writer 和底层连接清理路径保持原样。最内层 SS2022 对原始 transport 的两次 Close 保留，但不再在每一层 tracker 处倍增。

正式源码和 Go 回归位于 `core/smart.patch`；生成目录不是持久修改来源。保存补丁后重新运行 `tool/prepare_smart_core.dart`，已确认能从原 Bettbox 内核重建修复。原内核及来源 SHA 没有调整。

2026-10-05 合入 Smart Alpha `512b09d` 后，首次写入回调包装层另有 `sync.Once` 保护。保留本 fork 的 tracker CAS：两处各自保护不同入口，tracker 提前取得关闭权仍负责避免重入等待自身。回归同时覆盖新回调层的并发关闭与错误返回，以及经过该包装层的 tracker 重入关闭。新版本还改进异常确认、传输错误记录、深层统计解包及 WireGuard 按需初始化；这些改动不能替代真机 CPU、内存和功耗测量。

## 配置应用与顶部横条

`core/hub.go` 的关闭连接动作持有 runLock，`core/common.go` 的 setupConfig 和多项读取也需要该锁。因此连接关闭耗时会阻塞等待同一锁的配置动作及读取。hub.ApplyConfig 还会关闭旧 Smart 组，Smart.Close 等待其后台任务退出；若任务仍在关闭连接，该等待也可能受影响。

顶部横条由 loadingProvider 控制。正常 applyProfile 通过 safeRun 设置加载状态，并在 finally 清理。Dart setupConfig 的 15 秒超时不会取消原生任务。新增客户端回归确认：正常返回、15 秒超时，以及超时后的迟到原生回调，均能结束这条客户端加载流程，迟到回调不会恢复加载状态。未发现需要修改这条 finally 清理逻辑的证据。

已有导出记录显示首次配置完成，后续一次初始化没有完成记录。现有采样没有完整根调用栈和初始化阶段耗时，不能确定这次初始化究竟等待上述锁、Smart 退出，还是其他阶段；也不能把横条的全部历史表现归因于关闭路径。当前修复针对已复现且与 CPU 热点一致的缺陷，仍需后续短时真机验证实际功耗恢复。

## 本地验证

- 修复前真实 SS2022 有限链回归失败，修复后各层数的最底层 Close 均为 2 次。
- 重复、重入、并发关闭，首次错误返回，统计成员移除及一次通知通过；真实 net.Pipe 的 SS2022 读取在关闭后结束。
- 重新生成后的 Go 桥接和维护文档指定的 Smart 内核集成测试通过。
- 原有 15 项客户端回归及新增 2 项加载状态回归通过。

本次验证使用本机已有依赖离线完成，未操作手机，未验证修复后的 Android 真机功耗或完整 App 构建。原始诊断与分析辅助程序仅留在被忽略的 `.test`，不进入补丁或仓库。
