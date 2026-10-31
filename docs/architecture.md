# 架构说明

## 模块划分

- `Sources/MacPulseCore` — 纯逻辑，不依赖 AppKit，可脱离 UI 测试。
  - 指标计算与格式化：`MetricsCalculator`、`MetricsFormatter`、`MetricCounter`、`NetworkCounterAccumulator`、`MetricTypes`
  - 历史：`MetricsHistory`（分钟桶、聚合、查询）、`HistoryRecorder`（会话记录与逐秒环形缓冲）、`HistoryPersistence` 与 `HistoryValidation`（JSON 存取与数值校验）
  - 进程表增量计算：`ProcessTable`
- `Sources/MacPulseApp` — 界面与系统读取。
  - `Monitoring/`：`SystemMetricsReader`（系统计数）、`ProcessSampler`（libproc）、`VolumeSpaceReader`、`NetworkPathMonitor`；`MetricsSampler`（主采样调度）、`DetailSampler`（详情页采样）、`MonitorStore`（主线程状态）、`HistoryRepository`（串行磁盘 I/O）
  - `Views/`：SwiftUI 视图与设计令牌；`AppDelegate`：菜单栏、弹层与仪表盘窗口

系统读取与纯计算严格分离：采样器只做调度和采集，计算全部落在 Core 的可注入纯函数里。测试分三层：核心计算测试只用夹具，不依赖真实系统；集成与进程测试按需调用真实系统接口；烟测直接读取真实计数器。

## 数据来源

| 指标 | 来源 |
|---|---|
| CPU 使用率与 user/system/idle/nice 分解 | `host_processor_info`（处理器 tick 差值） |
| 内存（active/wired/压缩器、swap） | `host_statistics64(HOST_VM_INFO64)` |
| 磁盘读写字节 | IOKit `IOBlockStorageDriver` 累计统计 |
| 网络收发、接口明细 | `getifaddrs`，逐接口展开 32 位计数回绕后累加 |
| 在线状态 | `NWPathMonitor`，事件驱动，无轮询 |
| 进程 CPU / 内存 | `proc_listallpids` + `proc_pidinfo`，仅当前权限可读的进程 |
| 卷容量 | `FileManager.mountedVolumeURLs` |

## 采样与生命周期

- 主采样默认 1 Hz，可在设置中选择 1 / 2 / 5 秒，在低优先级后台队列执行，快照与接口累计量一次投递。
- 采样有效性由 `SamplingValidity` 统一裁决：相邻样本间隔超过设定周期两倍（且不短于 5 秒）视为缺口并重建基线；正常的调度抖动不会让 5 秒档失效。
- `MetricsSampler` 与 `DetailSampler` 用代次校验取消：停止或切换后，迟到的结果直接丢弃，不回写界面状态。
- 详情采样约 2 秒一次，只在对应详情页打开时运行，关闭即停。
- 进程按 PID 加启动时间识别身份；PID 复用、计数器回退或采样间隔无效时重建基线，不产生负速率或伪零。
- 网络接口计数是 32 位：仅在「旧值处于高位、新值处于低位」的置信窗口内按回绕展开；其余递减（重置或窗口外回绕）标记为不确定，该间隔速率按缺失处理，不记为 0。备用的 NET_RT_IFLIST2 路由消息虽然声明 64 位字段，实测内核仍按 32 位截断（总收包 718 GB 时显示为 32 位余数），不能作为 64 位来源。

## 历史存储

- 分钟桶在内存中按 `minuteStart` 有序增量维护：完成一分钟是二分定位的插入或合并，查询按窗口二分跳过无关数据并线性合并两段有序数组，避免每次全量合并排序。
- 位置 `~/Library/Application Support/MacPulse/history-v1.json`，原子写。每完成 5 个分钟桶落盘一次，退出时保存当前未完成的分钟。
- 分钟桶按指标保存样本数、有效时长、均值累加量、采样峰值和收发字节积分。跨重启合并按有效样本数加权，与合并顺序无关。
- 保留 7 天；剪枝只看存储时间，时钟回拨产生的「未来」数据不会被剪掉，只在查询时隐藏。含回拨前片段的分钟在图表中始终保留分钟表示，不会被逐秒明细替换。
- 逐秒明细只在内存中保留 7200 个样本（约 2 小时），不写盘。
- 读取与写入使用同一套校验（条数 ≤ 100000、编码后 ≤ 64 MiB、数值语义与顶层字段一致）；被拒绝的写入保留原文件并提示，成功保存的文件必然可被再次读取。文件损坏或数值异常时保留原件并提示，不用空历史覆盖。

## 行为边界

- 流量合计始终来自分钟聚合，切换绘图粒度不会改变累计字节；当前分钟实时预览，不等待窗口结束。
- 跨边界的部分分钟不按 60 秒放大，缺失样本不参与平均；边界总量按实际覆盖比例估算，并在界面标注。
- `Scripts/install.sh` 先构建并校验 staging 再替换现有安装；桌面存在同名普通文件或无关应用时拒绝覆盖。
- 构建脚本面向 arm64 / macOS 13+，产物未签名。

## 本地化

- 界面固定为简体中文：`MacPulseCore/Localization.swift` 的 `L10n.tr` 恒取中文词，运行时没有语言开关，也不存在全局可变语言状态。历史上的语言偏好键会在启动时清除。
- 所有界面文案（菜单栏弹层、总览、四个详情页、设置窗口、右键菜单、历史错误提示）均经由 `L10n` 取词；`Tests/MacPulseCoreTests/L10nTests.swift` 固定关键中文文案。
- 新增文案时在 `L10n` 对应分组追加一条 `tr("中文", "English")`（第二参数仅为兼容保留，恒不选中），避免在视图中硬编码。
