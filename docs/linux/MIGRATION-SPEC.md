# fqapp：Arch Linux x86_64 桌面迁移执行计划

版本：2026-11-10；性质：设计与实施任务书；本轮仅只读调查并写本文。
基线：`repository root`，HEAD `c29b27945d5a866a20415aac0cb234508514f80e`；调查开始时 `git status --short` 无输出。
所有“应”“验收”均为未来要求；本轮没有安装、代码改动、编译、测试、运行、打包或 CI 结果。
合并计划 v2，已完成三项独立 v1 审查并按意见修订；v2 尚未经审查者复审。以本文件为执行任务书；source-* 为原始输入，不覆盖本文件。

## 1. 目标、范围与证据规则

- 首要交付：可安装、可升级、可恢复的 Arch Linux x86_64 全功能桌面客户端。
- 保留小说、漫画、书架分类、历史与进度、缓存、下载、备份、本地 TXT/EPUB、中文编码、字体、真人听书、短剧漫剧加密媒体、AI 阅读、账号登录及导入、局域网分享。
- 系统朗读、媒体键、常亮、文件选择、导出、窗口与全屏、输入与无障碍均属于桌面可用性范围。
- Wayland 原生、Wayland 会话内 XWayland、纯 X11 分别记录结果；某一模式通过不外推其他模式。
- 基础阅读版可以阶段交付，但只能标记“阅读阶段预览”；登录、媒体或 TTS 未通过时不能称最终全功能版。
- Android 的电子墨水硬件刷新、音量键拦截、系统亮度、悬浮窗、前台服务等不保证 Linux 等价；明确能力与替代交互，不能伪造成功返回。
- 非目标：本轮实施、安装 SDK、运行构建、清理目录、操作真实用户资料、提交推送、发布包、另行委派。
- Linux ARM/aarch64、其他发行版、macOS、Flatpak/AppImage/AUR 发布暂未承诺；不得把 x86_64 成功当成这些平台验收。
- 不改 API 内容源、账号协议、加密算法、数据语义；不借移植重写 UI、换框架、统一解除 Windows guard。
- 无工期承诺：工作量按决策门结果条件化；需要新增 WebView/TTS 原生桥时单独估范围，不能隐藏到“加 runner”。
- 证据状态仅用“已核实静态事实 / 待实现 / 未运行验证 / 阻塞”；计划命令不是通过证据。

> 🧠 **From Hindsight memory (Key decisions and rationale)** — 既往记录是未完成的只读 Arch 可行性审查，建议完整移植 runner、Rust/C、媒体及桌面通道，保留加密保护并分期交付；没有构建或运行通过证据。本文把这些作为历史线索，已对关键代码重新核对。

Hindsight 已先搜索、列出五页，并阅读 Key decisions and rationale、Conventions and patterns；后者未建立本项目测试惯例，不能据其杜撰规范。
结构发现先 `search_graph(desktop)`，再追踪 `desktopCoreLibraryPath` 入站调用（定位 `DesktopMedia.open`），并读取 Rust `desktop_media.open` 图谱源码。
图谱首轮结果有分页，未当作穷尽清单；平台 guard 清单另用当前源码文字检索补足。
对下列 27 个核心证据文件及 22 个测试/调用方文件执行精确路径 coverage；均无记录问题，没有遗漏行报告，分页 `has_more=false`。
其中 `pubspec.lock`、`LICENSE` 为 `not_tracked`，已直接读取相关内容；其余为 `metadata_match`。coverage 是 best effort，不是完整性证明。
本轮还直接读取关键函数、配置、锁定版本和测试用例标题；外部包归档只在内存读取，没有安装或解压落盘。

## 2. 当前源码证据索引（绝对路径与起始行）

| ID | 当前证据 | 对计划的约束 |
|---|---|---|
| E01 | `pubspec.yaml:21`、`:60`、`:64`；`pubspec.lock:598` | Dart ^3.12.2；FRB 2.13.0；media_kit 1.2.6 / video 2.0.1；不能随手升级解锁移植 |
| E02 | `pubspec.yaml:66`、`:70` | 当前只加 Windows 媒体配套包；TTS 4.2.5、WebView 本地 fork、window_manager、SMTC 均需逐项审计 |
| E03 | `rust/src/lib.rs:38`；`rust/Cargo.toml:46` | desktop_fetch/media 模块及 reqwest blocking 仅 Windows |
| E04 | `rust/build.rs:1`；`native/CMakeLists.txt:8` | build.rs 非 Windows 返回；C11 crypto 源列表已存在；原生 CMake 已配置 PIC |
| E05 | `windows/CMakeLists.txt:67`、`:93` | Windows 用 cargo --release --locked 并安装 DLL；Linux 可复用责任划分，不照搬路径 |
| E06 | `lib/services/desktop_media.dart:14`、`:75`、`:113` | 手写媒体 FFI 只找 DLL，另有工作目录 fallback；open/free/close 生命周期必须保留 |
| E07 | `lib/services/rust_bootstrap_io.dart:14`；`lib/src/rust/frb_generated.dart:69` | iOS process 静态加载；其他原生走 FRB 默认；开发目录 rust/target/release 不是已验收 Linux 安装查找规则 |
| E08 | `flutter_rust_bridge.yaml:7`；`rust/Cargo.toml:8` | API 输入 crate::api，输出 lib/src/rust；产物含 cdylib/staticlib/rlib；媒体手写 C 导出不属 FRB 自动 API |
| E09 | `lib/main.dart:81`、`:100`、`:256`、`:313` | 桌面初始化、关闭保存、导航 key、桌面框架仅 Windows 装配 |
| E10 | `lib/services/desktop_platform.dart:26`、`:75`、`:193` | 现有桌面层可复用，但初始化 Windows-only；通道分派覆盖播放器、备份、导入、下载、阅读、TTS、账号 |
| E11 | `lib/services/desktop_platform.dart:433`、`:554` | 常亮调用 kernel32；非 UTF8 TXT 调 Win32 54936 编码转换，Linux 不能直接复用该分支 |
| E12 | `lib/services/desktop_platform.dart:31`、`:44` | 视频 active 特判只有 Windows；阅读 inactive 可见语义已经包含 Linux/macOS，避免误称全仓均未适配 |
| E13 | `lib/services/platform_capabilities.dart:10` | 视频入口只 Android/Windows；iOS 注释明确首版没有播放器实现 |
| E14 | `lib/widgets/desktop_login.dart:95`；`third_party/webview_windows/windows/webview_bridge.cc:637` | 登录读原生 Cookie，自带域过滤、会话字段及大小校验；不能换成 document.cookie |
| E15 | `lib/services/secure_key_provider.dart:118`；`lib/services/encrypted_hive.dart:112` | 密钥超时/故障返回 null；新数据部分可落明文，已有加密箱无 key 拒绝打开 |
| E16 | `lib/services/encrypted_hive.dart:142` | 错 key/损坏箱分支保留隔离文件并继续新空箱；不能把“保留文件”混同“已恢复数据” |
| E17 | `lib/services/imported_book_store.dart:167`、`:209`、`:516`、`:1014` | 桌面导入协议包含 decodedText；EPUB 有解析逻辑；普通 Dart 解码不等于 Win32 GB18030 支持 |
| E18 | `lib/services/library_backup_service.dart:19`、`:124` | capture 与 restore 分开；AI 预校验、分类先行、缺项合并；没有证据表明整目录/所有缓存都在备份中 |
| E19 | `lib/services/backend_service.dart:77`、`:238`、`:277` | backend 运行目录与启动存在；lanShare 是初始化输入；包目录不能当可写 runtime |
| E20 | `rust/src/desktop_media.rs:427`、`:526`；`rust/src/desktop_fetch.rs:120` | 已有 loopback 随机 token、Range、取消和错误分类；移植应复用，不自造无鉴权媒体服务器 |
| E21 | `lib/services/system_tts.dart:28`、`:211` | 系统 TTS 通道已有播放状态机；Linux 桥应兑现其回调与取消合同 |
| E22 | `.github/workflows/windows.yml:38`、`:50`、`:60`、`:74` | 已有 Windows 构建及定向测试；Flutter 固定 3.47.9；不动既有平台发布行为 |
| E23 | `.github/workflows/native-crypto.yml:29`、`:52` | Ubuntu native crypto/JNI/音频回归已存在；不是 Linux Flutter 图形桌面验收 |
| E24 | `LICENSE:1`；`native/CMakeLists.txt:25` | 根 GPL-3.0 文本，音频 tempo 注释 LGPL；仍须核对文件头与传递依赖，不能推定所有资源可再分发 |

直接目录检查：仓库没有 `linux/` runner；工作流文件为 android-apk、windows、native-crypto、contributors，没有 Linux 应用发布链。
主机 PATH 本次查无 Flutter/Dart；cargo/rustc/cc/cmake/ninja/pkg-config 存在；不代表 Rust/C 构建已成功。
只读 pkg-config 输出 mpv 2.5.0（客户端 API 元数据，不是 mpv 应用版本）、GTK 3.24.52、libsecret 0.21.8.2、epoxy 1.5.10；不证明会话服务、显卡或声音可用。

### 2.1 当前平台 guard 调用方地图

以下是文本命中位置，用于任务拆分；不是未经逐项分类就批量替换的清单。
- `lib/main.dart:81`、`:100`、`:252`、`:256`、`:313`、`:607`：装配、框架、导航、布局及系统行为。
- `lib/pages/drama_page.dart:266`、`:538`、`:594`、`:1551`、`:1576`、`:1699`、`:1775`、`:1842`、`:2396`、`:2439`、`:3957`、`:3998`、`:4659`：多入口与内联播放。
- `lib/pages/player_page.dart:871`、`:1104`、`:1977`；`lib/widgets/video_player_chrome.dart:825`、`:2333`：播放及窗口 UI。
- `lib/pages/settings_page.dart:79`、`:122`、`:140`、`:141`、`:197`；`lib/pages/audio_page.dart:700`：设置、听书适配。
- `lib/pages/category_page.dart:325`；`lib/pages/comic_reader_page.dart:200`；`lib/pages/detail_page.dart:553`。
- `lib/pages/home_page.dart:292`；`lib/pages/search_page.dart:657`、`:686`；`lib/pages/reader/reader_page_build.dart:6`。
- 加上 E10、E12、E13 的定义/策略命中；历史“41 处”不作为当前验收计数，未来按同一检索口径重新生成并逐项定责。

## 3. 逐功能能力矩阵

共同状态：所有 Linux 能力均未运行验收；“复用”仅指源码候选。W=Wayland 原生，XW=XWayland，X=X11，三者分别出报告。

| 功能 | 当前基础/缺口 | Linux 目标与完成标准 | 任务 / 场景 |
|---|---|---|---|
| 启动、后端、资源 | E03–E10、无 runner | 安装目录只读、任意 cwd 启动，FRB 与媒体共享正确 core，失败可重试 | T10–T13 / V01 |
| 小说搜索/详情/章节/阅读 | Dart/Rust 业务复用候选 | 在线与离线阅读、分页/滚动/书签/查找/批注/换源语义保持 | T20 / V02 |
| 漫画 | 桌面布局 guard，E17 数据路径需核对 | 图片加载/缩放/翻页/缓存/重启进度，缺图重试 | T20 / V02 |
| 书架、分组、历史、统计 | E18 缺项合并 | 多来源 ID 不串书、分类与进度持久，升级不重置 | T21 / V03 |
| 章节/图片/音视频缓存下载 | E10/E19，媒体依赖 E20 | 下载取消、断网恢复、容量反馈、离线复播；缓存不可误写 /usr | T21/T30 / V03,V06 |
| 备份与恢复 | E18 非全量目录备份 | 既有格式兼容；说明覆盖与排除，失败可重试且原数据可恢复 | T22 / V04 |
| TXT 导入/导出 | E11/E17 Win32 编码路径 | UTF8/BOM、UTF16 LE/BE、GBK/GB18030；文件名中文/空格，错码有反馈 | T23 / V05 |
| EPUB | E17 既有解析 | spine、封面、目录、中文、缺项/损坏拒绝且不留半本 | T23 / V05 |
| 自定义字体 | E10 通道 pickFont | 选择、复制持久化、重启及缺失回退；不长期依赖外部绝对路径 | T23 / V05 |
| 真人听书 | E10/E20，媒体桥 | 在线/离线、倍速、字幕跟随、跳章、后台与媒体键，无双重播放 | T30/T31 / V06 |
| 系统 TTS | E21；flutter_tts 无 Linux | 中文可用音色、语速/音量、完成/错误/取消，章节连续与高亮正确 | T40 / V07 |
| 短剧/漫剧 | E13/E20，多播放入口 | CENC、普通媒体、Range、seek、预热、切集、弹幕/字幕、离线、内联/全屏均通过 | T30/T32 / V06 |
| AI 阅读 | E18/E19，业务复用 | 流式、取消、网络错误、模型配置、备份合并；密钥脱敏与加密不退化 | T24 / V08 |
| 账号登录/退出 | E14 WebView2 fork | 官方登录、HttpOnly Cookie 原生读取、域白名单、过期/退出清理，安全持久 | T41 / V09 |
| 账号书架/历史导入 | E10/E14、独立服务测试 | 预览、分页/分段捕获、取消/重试、不重复覆盖已有记录 | T41 / V09 |
| 局域网分享 | E19 lanShare 输入 | 显式开启、范围/权限与原行为兼容、关闭撤销监听、路径受限 | T24 / V10 |
| 文件下载/分享/外部链接 | E10 桌面通道 | 文件选择取消、拒绝写入、磁盘满、导出路径；URL scheme 受控 | T23/T24 / V05,V10 |
| 桌面窗口/输入/无障碍 | E09/E10/E12 | 中文 IME、缩放、多屏、键盘焦点、语义、全屏还原、关闭保存 | T12/T32 / V11 |
| 系统媒体控制 | Windows SMTC | Linux MPRIS 单一播放所有者，播放/暂停/定位/上下首/元数据 | T31 / V07,V11 |
| 常亮与阅读亮度 | E11 Win32 | 持有/释放 Idle inhibit；亮度仅应用遮罩需准确命名，无全局背光写权限 | T42 / V11 |
| Android 专有设备行为 | E10 对部分设备通道分派 | 电子墨水硬件/音量拦截/前台服务/原生悬浮窗明确不等价；保留桌面阅读与窗内浮层 | T42 / V12 |
| 安全密钥与账号/AI数据 | E15/E16 | keyring 缺失/锁定时可恢复阻塞，不以明文保存受保护新数据 | T13 / V03,V12 |

最终范围内的未实现能力必须列在版本限制中并阻塞“全功能”验收；硬件不等价项按已声明的平台语义验收，不删除原 Android 行为。

## 4. 目标架构与最小改动地图

保持 Flutter 页面/业务服务 → 现有 AppMethodChannel/PlatformChannels → 桌面适配层 → media_kit、文件系统、平台桥的结构。
保持 BackendService → FRB → fqapi_core，以及 DesktopMedia → 同一 core C ABI → C crypto → loopback → libmpv 的链路。
只把真正共用的桌面行为复用；Win32、SMTC、WebView2 留在 Windows 实现，Linux 增加必要桥，不新建泛用平台框架。
先列能力（视频渲染、文件操作、TTS、登录、系统媒体、常亮），各实现成功装配后再启用对应入口；能力不足须明确反馈，不伪造 channel success。
不把常亮/TTS/SMTC 故障扩大成阅读不可启动；但密钥不可用不能通过写明文绕过。

| 改动域 | 最小到达范围（未来新增路径为候选） | 调用方 / 测试 / 配置 / 导出 |
|---|---|---|
| runner | 新 `linux/CMakeLists.txt`、`linux/runner/`、插件注册及应用 ID | E09 启动；runner 生命周期/关闭保存；新 Linux CI；资源安装完整性 |
| Rust/C | E03/E04 在 Windows/Linux 精确 cfg，blocking feature 同步 | E20 桌面 fetch/media；现有 Rust tests；C11/PIC；保留 C 导出 open/close/free 与 FRB 导出 |
| 构建调度 | Linux CMake 依赖 cargo locked；目标/输出目录明确 | 参考 E05；Cargo.lock、pubspec.lock 不顺带升级；Debug/Release 路径不能混用 |
| 动态加载 | E06/E07 统一实际安装位置；避免两份 core | FRB init、媒体 isolate 与 close；测试任意 cwd、缺库、错架构、缺符号；无业务 API 新导出 |
| 桌面装配 | E09/E10、2.1 调用方逐类修改 | 保留 Windows 初始化；桌面 frame/navigation/事件注册恰一次；对应 desktop/widget 测试 |
| 文件与编码 | E11/E17、备份/下载/字体通道 | 现有 FileSelector/导入协议、TXT/EPUB fixtures、路径权限；必要时才加编码实现 |
| 存储 | E15/E16/E18/E19 | 所有 EncryptedHive 调用方分类，bootstrap 重试、密钥/迁移测试；不更换箱名或重加密全库 |
| 播放系统 | E10/E12/E13/E20、2.1 视频入口 | 生命周期、播放器事件、池、内联/全屏/听书；media 包配置；C ABI 不变优先 |
| TTS/账号/会话 | E14/E21、系统媒体/常亮 | Linux 原生桥或经验证依赖；通道事件/错误合同；pubspec 与 Linux 注册仅在选型后变更 |
| 打包/发布 | 新 `packaging/arch/PKGBUILD`、desktop/icon、新 Linux workflow | 文件清单、许可证、签名/来源、依赖闭包、卸载不删数据；不改 Android/Windows 包脚本语义 |

C 编译只有一条所有权链：Linux Rust build.rs 用 cc 编 crypto 静态对象再进 cdylib，或 CMake 静态库链接 Rust，二选一；优先前者复用 Windows。
不能同时编两份 crypto 或把 JNI 桥当 Linux 桌面导出；确认 PIC、C11 atomics、可见性、线程/取消和资源释放。
音频 tempo 当前 native CMake 有独立模块；先确认 media_kit 的既有倍速能力是否满足产品听感/变速合同，缺口才移植该模块，不能默认丢弃音频要求。
Linux 构建约定建议在 T11 固化：首目标 `x86_64-unknown-linux-gnu`，CMake 声明 cargo 输出/依赖，选定 CARGO_TARGET_DIR 与 profile 后所有加载/安装消费者使用同一路径。
最终布局候选 `bundle/fqapp`、`bundle/lib/libfqapi_core.so`、`bundle/lib/` 插件、`bundle/data/` ICU/AOT/assets；按选定 runner 模板复核，不能把此候选当现成目录。
runner/插件的 RUNPATH 与间接依赖分别检查；候选 `$ORIGIN/lib` 只解决对应对象的相对加载，不以全局 LD_LIBRARY_PATH 掩盖缺库。
FRB 生产初始化可经现有 externalLibrary 参数明确指定 bundle 内 core；手写媒体 FFI 复用同一受控路径，不手改生成绑定以塞 Linux 专例。
实施阶段检查 `file`/`readelf -h -d` 的架构、NEEDED、RUNPATH，`nm -D` 核对 FRB 与 fq_desktop_media_open/close/free；这些是 ABI 交付检查，不是只有启动的 smoke。
Windows custom target/生成脚本的 FRB 重生成责任也要核对：若 API 未变不引无关生成差异；若必须重生成，codegen 与 Rust/Dart 版本保持一致并审阅产物。


## 5. 技术选型决策门（先证据，后引依赖）

### D01 工具链、runner 与会话

复用 Windows CI 的 Flutter 3.47.9 / FRB 2.13.0 作为候选，先验证官方 SDK 可获得性及 Dart ^3.12.2；不因 PATH 缺失随手装最新。
按选定 SDK 模板在实施的隔离 checkout 生成最小 Linux runner，仅审阅并引入 linux 相关文件；不得运行生成器覆盖整个现有工程。
官方依赖映射 Arch：clang、cmake、ninja、pkgconf、gtk3、C/C++ 标准库；插件另要求 libsecret、mpv、libepoxy，最终以锁定源码 pkg-config 合同为准。
D01 出口：SDK/Rust 版本与架构记录、runner diff、W/XW/X 支持假设和待实测列表；入口不开功能总闸。
来源：[Flutter Linux setup](https://docs.flutter.dev/platform-integration/linux/setup)、[Linux FFI/build](https://docs.flutter.dev/platform-integration/linux/building)。

### D02 media_kit_libs_linux：系统 libmpv 存在并不充分

本轮直接读取官方归档：media_kit 1.2.6 `lib/src/player/native/core/native_library.dart:32`、`:55` 支持显式路径/环境值及系统 libmpv.so/.so.2/.so.1 加载。
但 video 2.0.1 `linux/CMakeLists.txt:15` 仅 `MEDIA_KIT_LIBS_AVAILABLE` 真时编完整纹理/输出模块并链接 mpv、epoxy；否则编 `MEDIA_KIT_LIBS_NOT_FOUND` 分支。
候选配套包 linux 1.2.1（当前项目未锁入）`linux/CMakeLists.txt:10` 设置该选项，`:18` 默认涉及 mimalloc 下载，`:111` 提供动态查找分支；插件 `:16` 设置 LC_NUMERIC=C。
结论：按未经修改的锁定 video 构建合同，应优先加 Linux 专用配套包；它不是“捆绑 libmpv 的唯一方式”，也不能凭 pub.dev 标签认定只装系统 mpv 就完整。
候选 A：Linux 专用包 + Arch 系统 mpv/epoxy，明确处理 mimalloc 下载/系统链接和初始化注册顺序；不要重新加 umbrella 导致移动包带额外库。
候选 B：仅当 A 的下载/allocator/维护代价不可接受时，评估受控 CMake 激活替代，必须兑现插件完整编译、locale 与链接合同，不能只设变量就宣称等价。
D02a 出口：锁定候选构建合同、依赖/文件清单和离线构建办法，允许受控集成试验；不要求先有首帧。D02b 出口：由 T29 产生纹理首帧/seek/硬软解 W/XW/X 证据后定案；失败回到 D02a 审核候选 B。T30 开始不依赖 D02b，T30 完成与发布依赖 D02b。
归档来源：[media_kit 1.2.6](https://pub.dev/api/archives/media_kit-1.2.6.tar.gz)、[video 2.0.1](https://pub.dev/api/archives/media_kit_video-2.0.1.tar.gz)、[libs_linux 1.2.1](https://pub.dev/api/archives/media_kit_libs_linux-1.2.1.tar.gz)。
Arch 当前包来源：[mpv 官方包页](https://archlinux.org/packages/extra/x86_64/mpv/)；发布时重新核对包内容/SONAME，不把 pkg-config API 版本当发行版本。

### D03 密钥、Cookie、TTS 与系统集成

锁定 secure_storage 9.2.4 / linux 1.2.3；后者 CMake 要 libsecret-1>=0.18.4，存在 libsecret 不代表桌面已有可解锁 Secret Service。
Secret Service 用系统现有 provider，不内置明文 fallback，不强行让所有桌面依赖 gnome-keyring；定义未配置/锁定/超时的重试与诊断。
账号方案先评估现成 Linux WebView 是否提供原生 HttpOnly Cookie 与清理/隔离；不满足时才做最小 WebKitGTK 桥，优先复用现有账号服务协议。
外部浏览器仅在官方有可验证的回调/会话交接协议时可作等价登录；不能要求用户提取 Cookie 代替最终登录能力。
flutter_tts 4.2.5 官方不列 Linux；比较 Speech Dispatcher 等系统接口与最小原生桥，必须验证中文音源、取消/完成回调、速率、错误映射和许可。
MPRIS 与 Idle inhibit 优先系统接口；选现成包须核对支持与维护成本，否则在 runner 最小实现，不提前堆 dbus/wakelock/播放器替代包。
来源：[TTS 4.2.5](https://pub.dev/packages/flutter_tts/versions/4.2.5)、[secure storage 9.2.4](https://pub.dev/packages/flutter_secure_storage/versions/9.2.4)、[linux 1.2.3 归档](https://pub.dev/api/archives/flutter_secure_storage_linux-1.2.3.tar.gz)。
来源：[WebKitGTK CookieManager](https://webkitgtk.org/reference/webkit2gtk/stable/method.CookieManager.get_cookies.html)（证实原生异步 URI Cookie API，不证明候选 Flutter 插件已暴露 HttpOnly 合同）。
来源：[MPRIS 2.2](https://specifications.freedesktop.org/mpris/latest/)、[Portal Inhibit](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Inhibit.html)（Idle flag、request close 的生命周期需兑现）。

## 6. 阶段、依赖及可执行任务表

任务表为未来实施要求；每行验收必须绑定版本、命令/场景、输入 fixture 和实际产物。任务可细拆，但不能跳过阻塞条件。

| ID / 阶段 | 前置依赖 | 交付物与实施动作 | 完成标准 / 验证方法 | 阻塞条件 |
|---|---|---|---|---|
| T00 / P0 基线 | 无 | 保存改动清单，复核 E01–E24，按2.1每个 guard 定责 | 评审证据与 HEAD 一致；未知有负责人，依赖版本表完整 | 基线漂移或未保护他人改动 |
| T01 / P0 工具链 | T00,D01 | 隔离构建环境、SDK/Rust/C/GTK/plugin 版本清单 | SDK 与 Dart/FRB 匹配，doctor 的 Linux 项可用；只在实施阶段执行 | 当前无 Flutter/Dart，来源或版本不可得 |
| T09 / P1 资料所有权 | T01 | 单资料与key命名空间跨进程单写者，先于任何key/runtime/箱写入 | 双进程首次启动/恢复/崩溃释放场景，见15.3 | 第二实例可替换key或写资料 |
| T10 / P1 runner | T01 | 最小 linux runner、应用 ID、插件注册、资源安装 | 从包位置任意 cwd 启动；ICU/AOT/assets/fonts 齐全；V01/V11 | runner 模板或插件不兼容 |
| T11 / P1 Rust/C | T01,T00 | 精确 Linux cfg、blocking、C11/PIC、cargo 构建依赖 | ELF 架构/导出正确，原生 crypto 与 Rust Range/取消测试通过 | C atomics、链接缺符号或重复对象 |
| T12 / P1 桌面装配 | T10 | 初始化/关闭保存、frame、导航、文件通道共用部分 | 无 MissingPlugin、重复监听；窗口关闭前保存，异常退出可恢复 | 复用代码仍触发 Win32/SMTC |
| T13 / P1 密钥与加载 | T10,T11,T09,D03 | core 加载路径、keyring 探测、重试和保护策略 | FRB/媒体同库；缺 key 不写敏感明文；V01/V03/V12 | 系统密钥持久化/加载不可靠 |
| T20 / P2 基础阅读 | T12,T13 | 小说/漫画/搜索/书架/阅读桌面入口与布局 | V02；在线失败与离线均能反馈，重启进度一致 | 后端/字体/存储链不通 |
| T21 / P2 数据缓存 | T13,T20 | 缓存、下载、历史、分类可写位置与恢复 | V03；断网/磁盘满/取消不损坏已有记录 | 原子性或路径范围未保证 |
| T22 / P2 备份迁移 | T13,T21 | 备份覆盖表、导入预检、隔离恢复和回滚手册 | V04；旧格式及损坏/部分失败不毁原资料 | 误称备份含所有本地书/缓存或无法回滚 |
| T23 / P2 本地文件 | T12,D03 | TXT 编码方案、EPUB/字体/文件导入导出 | V05；GB18030 fixture 与拒绝写入均正确 | 中文解码无等价实现或失败被吞 |
| T24 / P2 AI/分享 | T13,T21 | AI 流式/取消、局域网开关/授权边界 | V08/V10；断线重试不泄密，关闭分享撤销暴露 | 外网绑定/日志泄密/路径越界 |
| T29 / P3 候选媒体验证 | T10,T11,T13,D02a | 当前候选最小完整插件注册与普通媒体画面/音频集成，记录allocator/locale/依赖；不新建通用实验框架 | 取得D02b的W/XW/X首帧/seek/硬软解证据，失败回D02a | 候选缺库、无纹理或无法离线构建 |
| T30 / P3 媒体基础 | T11,T13,D02a（完成需D02b） | CENC/Range/FFI + 系统 mpv + 完整视频插件 | V06；真人听书及视频在线离线/seek/错误分类正确 | 只有声音无纹理或缺 native ABI |
| T31 / P3 媒体会话 | T30,D03 | MPRIS、播放所有权、媒体键、退出释放 | V07/V11；听书/TTS/视频互斥，恢复不双播 | 元数据含凭证或状态漂移 |
| T32 / P3 多入口 | T12,T30 | 首页/搜索/详情/短剧流/播放器/浮层能力逐项启用 | V06/V11，内联/全屏/切页/失焦/最小化一致 | 任一入口绕过能力判断 |
| T40 / P4 TTS | T12,T13,D03 | Linux 系统朗读桥、音源诊断、设置说明 | V07，中文语音及完成/取消合同通过 | 无可用中文引擎或回调不可靠 |
| T41 / P4 账号 | T12,T13,D03 | 原生登录/Cookie读取清理、书架历史导入 | V09，真实官方账号验证另记，不入 CI | HttpOnly 不可读取或安全域限制不满足 |
| T42 / P4 桌面会话 | T12,T31,D03 | 常亮/亮度/设备能力边界、W/XW/X 行为 | V11/V12，失败可见，释放 inhibit、无特权后台 | compositor/portal 差异未解释 |
| T50 / P5 包 | T10,T11,D02 | PKGBUILD、bundle 布局、启动器、依赖许可清单 | V13，包不包含开发路径/密钥/私有资料 | 隐式网络下载、许可或依赖闭包未解决 |
| T51 / P5 CI | T01,T11,T50 | Linux job、锁定环境、定向回归与产物报告 | V01–V10 可自动部分无 skip 假绿；已有平台回归通过 | FFI 被跳过、图形会话未覆盖却宣称通过 |
| T52 / P5 干净安装 | T20–T24,T30–T32,T40–T42,T50,T51 | 干净 Arch 三会话/升级/回滚完整报告 | V11–V13，全功能矩阵逐格有证据 | 任一最终能力未验收 |
| T60 / P6 三审发布门 | T52 | 至少3个新独立审查及问题闭环；发布说明 | 审查分别覆盖构建包/安全迁移/产品会话；修复后复查变更 | 自审代三审、必需项未知或失败 |

依赖关键路径：T00→T01→T10/T11→T12/T13→数据与媒体→完整产品/会话→T52→T60。
T50/T51 可在基础链可构建后提前准备，但最终包必须重新绑定 T52 验收的同一 head；不能发布早期阅读包冒充完整结果。
账号、TTS 选型调查可与 runner 调查并行；落地仍受密钥、通道和会话合同约束。规划与独立审查已获用户授权，实施尚未开始。

## 7. 最小有价值验证计划

不为“程序启动了”另堆无断言 smoke；优先扩展已存在的实质性回归，新增只用于现有测试无法捕获的平台/安全边界。
所有数据测试用合成资料或明确授权的脱敏副本，在临时用户/目录与测试 keyring 中运行；不清空真实目录，不锁定或重置用户日常 keyring。

| 场景 | 优先复用现有测试（路径相对仓库） | 必要扩展 / 真实验证与断言 |
|---|---|---|
| V01 ABI/启动 | `test/rust_host_integration_test.dart:150`（可 skip）；E22 CI | 用 FQAPP_RUST_HOST_LIB 指定本次 .so，确认非 skip；启动/静态资源/取消/超时/停启；包在随机 cwd、无源码目录可用 |
| V02 阅读漫画 | 现有 reader/comic/widget 测试按改动选择 | 确认每条链在线、缓存、断网、重启进度、中文显示；键盘与语义，不只截图 |
| V03 密钥数据 | `test/encrypted_hive_test.dart:184`、`:198`、`:211`；`test/secure_key_provider_test.dart:11` | 无服务/锁定/超时/重启一致；区分无 key 与错 key 隔离；秘密明文不得出现，恢复不覆盖旧箱 |
| V04 备份 | `test/library_backup_test.dart:149`；现有 groups/AI backup 测试按变动选择 | 合成旧版→新版合并、重复恢复、坏 AI/分类未就绪、独立子进程崩溃注入（15.4）；说明本地书/下载/凭证排除项并独立迁移 |
| V05 本地文件 | `test/desktop_platform_test.dart:31`；`test/imported_book_store_test.dart:61`、`:187` | 新增 GBK/GB18030 生僻字/坏序列，UTF16 截断；EPUB 异常路径/大包；文件选择真实取消/权限不足/中文路径 |
| V06 原生媒体 | `test/native_crypto_media_test.cjs:54`；`rust/src/desktop_fetch.rs:246`、`:276`、`:287` | CENC front/tail moov、seek/Range失败/取消，媒体关闭后端口撤销；W/XW/X 真窗口有画面声音、倍速/离线/切集 |
| V07 系统语音媒体 | `test/system_tts_test.dart:123`、`:257` | Linux 回调契约新增小回归；真中文音源、停止后的迟到 done 不推进章节；MPRIS 命令与 owner 一致 |
| V08 AI | `test/ai_reading/ai_client_redaction_test.dart:79`、`:212` | 网络/SSE错误、取消、备份；合成 key/query/Cookie/URL 不得进入日志或报告；不消耗真实模型预算代替确定性测试 |
| V09 账号导入 | `test/fanqie_library_import_service_test.dart:51`、`:82` | 原生 HttpOnly、跨域拒绝、退出清 Cookie、分段导入取消；真实账号手动记录仅结论，不上传会话资料 |
| V10 LAN | 现有 backend/lan_share 测试先核对断言再扩展 | 另一台受控设备访问开关、受限文件/目录穿越；媒体 loopback 不可被 LAN 获得；防火墙拒绝有提示不自动放开 |
| V11 生命周期 | `test/desktop_inactive_lifecycle_test.dart:13`；现有 player 生命周期回归 | 失焦/最小化/锁屏按15.1的明确合同；中文 IME、HiDPI、多屏、全屏退出、关闭保存；分别标 W/XW/X |
| V12 失败边界 | V03/V07 + 设备通道现有测试 | keyring/portal/音源/音频设备缺失，resume 重连、桌面总线退出；无假成功、无后台残留/数据清空 |
| V13 包与回滚 | 新增一份安装验收记录即可 | 干净 Arch pacman 安装/升级/降级/卸载保留数据；最小依赖、图标入口、空缓存与离线缺依赖，旧版回退读取独立快照 |

测试证据文件同样检查 coverage，均 metadata_match；上述明确行号是本次读取的用例位置，其余名称仅为后续选择候选，未宣称逐条审计。
现有 lost-key 测试验证“隔离旧箱并打开空箱”，不能擅自改断言称其是恢复；若调整故障策略，先记录原合同并扩展失败/重试案例。
执行建议（仅未来命令）：`flutter pub get --enforce-lockfile`、`flutter analyze --no-pub`、按表选 `flutter test --no-pub <files>`；FFI job 额外断言未跳过。
Rust 使用 `cargo test --manifest-path rust/Cargo.toml --locked` 并确认 desktop 模块测试实际参与；构建用目标匹配的 `cargo build --release --locked`。
复用 native-crypto workflow 的 node 定向用例；它们会编译测试驱动，所以本轮未执行，不能写“C 测试通过”。
图形自动化可用 headless X/虚拟 compositor 做确定性事件验证；软件渲染、虚拟显示、容器不替代真实 GPU/音频/portal/keyring。
真实运行报告要写包版本、会话后端、compositor、GPU/驱动、音频系统、缩放、系统依赖版本、输入场景和失败记录。
W 验证记录 GDK_BACKEND=wayland 且实际连接 Wayland；XW 记录 Wayland 会话中强制 x11 后实际连接 XWayland；X 在纯 X11 登录会话运行，不能仅靠环境变量标签判定。
全屏/置顶/窗口位置在 compositor 的限制下按实际能力反馈；不能用 X11 专有窗口 API 给 Wayland 原生伪造成功。软解降级须仍有画面/声音且明确性能边界。


## 8. 数据迁移、恢复与版本回滚

- 先盘点 path_provider 的实际 support/cache 路径、箱名、runtime、device pool、账号捕获、本地书及字体、下载索引；包 ID 固定后才能定迁移路径。
- 不从 Windows 直接复制 DLL、系统密钥库、浏览器 profile 或 Hive 密钥到 Linux；跨平台优先既有备份格式，目标机生成独立用途密钥。
- 迁移清单必须明确：书架/历史/分组/AI 哪些在备份中，本地 TXT/EPUB 原文件/导入章节/字体/离线媒体是否另行迁移；缓存路径不能盲改绝对前缀。
- 账号与 AI 凭证默认重新授权/安全配置；若备份确含敏感配置，按其现有格式明确风险与权限，不能无检查公开分享备份。
- 在源应用完成保存后导出，保留原件；目标先预检格式/大小/路径/容量/密钥服务，再写独立 staging；应用恢复沿用缺项合并与预校验。
- 若无法提供跨箱原子提交，使用恢复前隔离快照、可重入操作记录及启动恢复提示；不把跨箱部分写入称事务。
- 中断/磁盘满/损坏只清理本次明确归属的 staging，保留源备份、旧箱、隔离箱和此前可用数据；禁止自动 rm 数据目录。
- keyring 锁定/暂时无服务：阻塞受保护写入、可重试；错 key/损坏：展示隔离与恢复入口，不能让空界面误导为数据已丢失或已恢复。
- 不为通过安装验证接受敏感新箱明文；可将严格策略限于 Linux 初始化或明确敏感调用方，避免悄悄改变所有平台历史行为。
- 升级前关闭写入、保存进度、保留版本对应数据快照与旧包；升级检测 schema/迁移标记，先兼容读再必要迁移，不顺带全库重写。
- 代码回滚与数据回滚分开：pacman 降级旧包不能撤销 schema；旧版只打开匹配的升级前副本，保留新版数据等待人工合并。
- keyring 条目命名/应用 ID/用途分离保持稳定；回滚保留原 key，不重置 keyring，不静默覆盖不能读取的旧 key。
- 验证用两套合成目录与测试 keyring，从 N→N+1→N，核对书/章/分组/历史/AI 条目与媒体可读性；真实用户只做非破坏性导出核对。

## 9. 威胁与权限边界

| 边界/威胁 | 必须措施 | 失败判定 |
|---|---|---|
| core 动态加载劫持 | 发布从安装 bundle 的受控绝对路径加载；拒绝 cwd 开发 fallback；确认 FRB 与媒体同一库；审核 LIBMPV_LIBRARY_PATH 继承策略 | 可用可写 cwd 同名库替换 core，或错误库仍启动 |
| Secret Service/本地文件 | 敏感箱 fail closed，目录仅用户可读写；最小权限与用途独立 key；日志不输出密钥 | 缺服务写入明文、换 key 覆盖导致无提示空库 |
| 登录 WebView | 域/导航/弹窗/权限白名单，原生 Cookie API，退出清理；profile 独立且权限收紧 | document.cookie 冒充 HttpOnly、任意域 Cookie 导出 |
| Rust 媒体本机 HTTP | 保留 127.0.0.1、随机令牌、请求/路径限制、关闭撤销与取消 | 绑定所有网卡、会话 URL 泄露或关闭后仍可读 |
| LAN 分享 | 用户主动开启，限制可分享目录与资源、保留现有权限语义，关闭停监听 | 未开启暴露、路径穿越、把媒体 token/key 经共享返回 |
| 输入文件与资源 | EPUB/备份/字体按大小、路径和类型校验，导入错误保持原文件；选文件不授权执行命令 | 解压越界/符号链接逃逸/超量资源导致不可恢复写入 |
| 日志/CI/崩溃 | 仅类别/状态/脱敏 ID；Cookie、token、媒体 URL 查询、key、账号页面截图均排除上传 | 任一敏感字节进入 AppLog/stdout/native stderr/报告 |
| 系统集成 | 用户级 D-Bus/MPRIS/portal；最小 Idle inhibit；不用 sudo 改背光、防火墙或全局电源策略 | 启动需要 root、关闭后 inhibit/后台服务遗留 |

同一用户恶意进程能读内存或监听会话总线是桌面安全边界限制；不宣传 loopback/Secret Service 能抵御整个已失陷用户会话。
MPRIS 元数据默认只含展示所需内容，不发送可复用的播放/解密 URL；日志测试还需覆盖第三方播放器错误与 WebView 原生错误。

## 10. Arch 包、CI、许可与可重现性

首选候选：Arch 原生 PKGBUILD + `.pkg.tar.zst`，应用私有 bundle 保持 runner 的相对布局，`/usr/bin` 启动器只定位它，不修改用户目录。
包目录候选 `/usr/lib/fqapp/`（最终按打包规范复核），可写 runtime/support/cache 必须走 XDG/path_provider 的用户路径。
desktop 文件、图标、应用 ID/WM class、中文名称及参数转义一起验证；不自动注册无实现的 URL/MIME 协议，不创建开机启动服务。
`depends` 依据 ELF NEEDED、运行时 dlopen、插件、会话 API 三份清单合并；仅 ldd 不足以发现 mpv/密钥/TTS 等间接运行需求。
`makedepends` 包含选定 Flutter/Rust/clang/CMake/Ninja/pkgconf，系统库头文件与最终 `depends/optdepends` 分开；中文音源是否必需由最终 TTS 合同决定。
Secret Service provider/portal backend 常为用户桌面选择，不让包无条件替换桌面；安装说明给检测与配置路径，缺失时阻塞相关能力并明确状态。
PKGBUILD 的 prepare/build/check/package 各归其责；不得在 package() 拉网络、启动 app、迁移用户数据或读宿主 keyring。
使用源版本/发布归档固定输入、pubspec.lock/Cargo.lock、Flutter/Rust/FRB codegen 精确版本、Actions 提交固定；不在 CI `pub upgrade`。
D02 的 mimalloc 默认下载是可重现性决策门：预取并验证可追溯来源或系统动态方案；禁止构建时靠未记录网络结果。
CI 增加 Arch 环境 job（固定基础镜像 digest/仓库快照策略）和 Linux GUI 验证分层；Ubuntu native job 继续保留并注明它不是 Arch 安装证据。
推荐流水线：锁定取依赖→分析/定向测试→Rust/C→Flutter release→ELF/导出/依赖检查→打包→干净安装→有显示会话的产品验收。
无图形/真实账号的共享 runner 只能验自动部分；发布门单独要求受控真实会话报告，不上传账号资料，不允许 skip 变绿色验收。
缓存 key 必须覆盖工具链、架构、锁文件、Rust/C 源、build.rs、runner/plugin CMake 和 assets；不得恢复旧 release 二进制冒充新构建。
产物清单绑定源码 head、工具链/依赖清单、.BUILDINFO/构建日志、测试结果；发布归档校验用于来源和完整性，非无意义全仓 SHA 检查。
可复现先承诺“固定输入可重复构建并说明差异”；bit-for-bit 需两次独立干净构建比较、处理时间/路径差异后才能声明。
许可核对根 GPL、vendored WebView/Flutter patch、crypto、tiny_aes/kissfft/tempo、mpv/FFmpeg、字体/图标/第三方素材；输出许可证/NOTICE/对应源码与必要构建信息。
尤其 pubspec 有上游 APK 提取素材注释；不能因为根 GPL 就认定素材可随 Linux 包再分发，未解决授权阻塞正式发布。
包升级/降级/卸载不得删用户 support/cache/keyring；是否提供清缓存由显式产品操作决定，不写 pacman hook 清理。
官方依据：[PKGBUILD 手册](https://man.archlinux.org/man/PKGBUILD.5.en)；Arch Wiki 本轮被反爬拒绝，未伪称读取成功，实施时补核官方打包细则。

## 11. Android、Windows、iOS 回归与最终门禁

- Android：现有 APK/原生 crypto/JNI/tempo 与相关测试保留；确认未拉入 umbrella 媒体包、未改变 ExoPlayer、16KiB 对齐、前台音频/设备插件及备份策略。
- Windows：沿用 E22 analyze/定向测试/打包及既有媒体校验；重点 DLL/Win32 编码、SMTC、WebView2、关闭保存和焦点逻辑无回归。
- iOS：确认 E07 process 静态链接、生成代码及 Pod 依赖不受 Linux 改动影响；macOS/iOS 有工具链时执行原构建/测试，缺环境明确未验证。
- iOS 现有视频不支持边界保持；不能把 Linux capability 错开到 iOS，也不把本次移植包装为 iOS 视频实现。
- 共享业务变动触发对应平台读书/备份/账号/AI 回归；Linux 专用 runner 修改不要求无差别重跑所有业务测试，但仍须完整发布门覆盖受影响平台。
- T60 输入必须是同一最终 head 的功能矩阵、选型记录、依赖与许可清单、三会话真实报告、恢复/回滚记录及平台回归；任一未知如实保留并阻塞相关声明。

## 12. 风险登记、未决问题与交付边界

| 风险 | 级别 / 触发条件 | 缓解与关闭证据 |
|---|---|---|
| R01 无 SDK/runner，静态可行被当成可运行 | 高 / 当前即存在 | T01/T10/T52，包级实测前不承诺通过 |
| R02 video 插件编成缺库分支或隐式下载 | 高 / D02 未关闭 | 检查完整编译单元、CMake cache、locale、依赖清单与真实首帧 |
| R03 新数据明文/错 key 空箱掩盖资料 | 高 / keyring 故障 | T13，失败矩阵、隔离提示和恢复路径；不删除 counterexample |
| R04 原生加载路径与两份 core | 高 / 打包或随机 cwd | T11/T13，导出及实例身份核对、缺库失败测试 |
| R05 Cookie/TTS 无等价桥 | 高 / 插件实际合同不足 | T40/T41，先官方合同再真实验证，不能裁掉最终范围 |
| R06 Wayland GPU/窗口控制/portal 差异 | 高 / 只有 Xvfb 证据 | T32/T42/T52，W/XW/X 独立报告及必要硬解失败软件回退 |
| R07 备份误认为完整迁移 | 高 / 本地书/缓存/凭证缺项 | T22，迁移覆盖表和独立文件迁移恢复验证 |
| R08 Arch 滚动升级 SONAME 漂移 | 中高 / 系统升级后 | T50/T51 固定验收快照与更新矩阵，重构建包；禁止部分降级系统核心库 |
| R09 日志或 LAN 暴露凭证/解密媒体 | 高 / native/第三方错误 | T24/T30/T41 脱敏测试与监听/路径负向场景 |
| R10 许可/再分发权未清 | 高 / 素材或 codec 权利不明 | T50 逐项清单与来源审计；未解决不发布 |
| R11 Windows/Android/iOS 被共享层误伤 | 高 / guard/锁文件大改 | 第11节平台门禁与最小定向差异；不统一扩大平台判断 |

未决 Q1：发布验收的 compositor/GPU 基线与三会话覆盖设备由谁提供？默认至少一种 Wayland 桌面及一种 X11 环境，缺设备不虚报通过。
未决 Q2：选择配套包还是受控 CMake 替代？源码支持 A 为优先候选，mimalloc/离线构建与纹理实测决定最终方案。
未决 Q3：哪种 Linux WebView 暴露 HttpOnly Cookie 并满足官方登录？哪个中文 TTS provider 满足现有状态机？需 D03 验证。
未决 Q4：备份对本地书/下载/字体/AI 配置精确覆盖什么？实施前逐字段审计模型及所有 store，而非按本文猜测全量覆盖。
未决 Q5：无 Secret Service 的首次安装允许哪些非敏感操作？敏感落盘必须阻塞；具体 UX 不得以新明文箱换启动成功。
未决 Q6：素材、mpv/FFmpeg 构建选项和源码提供义务是否满足发布许可？当前只识别风险，未完成法律/全部文件头审计。
未决 Q7：源码包与二进制包的维护责任、发布签名、CI Arch 快照与缓存保存政策？不先扩成多包格式或跨架构工程。

本轮交付：此文件；已完成静态证据与官方依赖源码核对，未实施任何任务，也未计入后续三位独立审查者。
未检查：实际构建、运行、CI、干净 Arch 安装及全部备份字段；主要风险仍是媒体插件构建合同、密钥失败恢复、登录/TTS 与三种桌面会话的真实行为。


## 13. 双方案合并裁决与流程补充（优先于原始输入）

### 13.1 交付身份和证据边界

- 本任务为详细计划及至少三项独立计划审查，不是实施；T60 的实施后发布审查不能替代本次计划三审。
- Codex 请求 gpt-6.1-sol/high；Claude Code 请求 claude-fable-5-2/high，但后者 provider 报 executedModel=deepseek/deepseek-v4.1-flash-1017-cm。保留其规划输入，不能声称已取得 Claude 模型独立结论。三项新审查各为全新上下文，不以规划者自审充数。
- 当前所有验收均为未来要求；原始输入对 Android/Windows 的勾选仅表示源码实现线索，不能表示本次回归通过。
- 首发格式取 Arch 原生 PKGBUILD/.pkg.tar.zst；不扩展 Flatpak/AppImage；三种会话 W/XW/X 均单独验收。架构 x86_64，其他架构不在承诺范围。

### 13.2 原始方案分歧处理

1. 媒体：采用 D02 对锁定源码合同的分析，优先 Linux 配套包+系统 mpv，保留受控替代决策门；不以 README 一句话断言所有替代均不可能，不恢复 umbrella。
2. 密钥：Linux 受保护新写入 fail closed，涵盖 Hive、设备池与实际敏感配置。允许阅读基础 UI 提示与重试，不用明文换成功。跨平台既有行为不擅自统一变更。
3. 备份：原始 Claude Code 文档“AI段失败不阻断书架恢复”与当前源码相反，不采纳。library_backup_service.dart:128 起先 prepareEncoded，失败发生在 shelf/history 写入前；groups 未就绪也在写入前拒绝。保留该合同。跨箱 commit 仍非事务，需要隔离快照与可重入恢复。
4. 数据回滚：原始方案“只换二进制”和“旧版忽略字段”不足以覆盖存储 schema。采用第8节匹配版本独立快照，禁止旧程序直接写新版迁移数据。
5. 备份覆盖：原始方案对缓存、本地书、AI凭证覆盖的概括不能替代逐字段审计；T22 输出明确携带/排除/独立迁移清单。保留离线资源原件，不能以“可重建”为由删除或丢弃。
6. TTS/MPRIS/登录：可分期，不从最终功能清单降为可选。系统服务缺失应有明确反馈；无中文音源或无可靠完成/取消事件不得宣称TTS通过。
7. AI：“无 Android 前台服务”不等于 Linux 只能前台运行。明确前台、失焦、最小化、锁屏、挂起/恢复、关闭进程的请求/取消/持久化合同，实测后记录。桌面关闭仍退出，后台常驻服务不是默认新增功能。
8. 版本：pkg-config mpv=2.5.0 是 API 元数据，不能写为播放器应用版本。speech-dispatcher pkg-config 缺失不能独自证明运行服务未安装；T01 分别查包、可执行文件和服务。
9. 最小改动：能力命名沿用现有辅助函数，只有实际需要才新增；不按另一方案一次创建一组通用 getter，不新增未要求的跨平台框架。

### 13.3 端到端必验链（绑定 V01–V13）

- 安装→任意工作目录启动→core与资源→keyring→书架开箱→首页；无库/无服务/无权限各有可恢复错误。
- 搜索→详情→在线阅读→缓存→断网→退出→重启续读；漫画同样验证图片与进度。
- 文件选择→TXT/EPUB/字体导入→中文内容→重启；取消/损坏/超限/权限不足不留下半本或覆盖原文件。
- 导出合成备份→独立目标目录预检→恢复书架/分组/历史/已看集/AI→重复恢复→中断重试；无真实目录清空步骤。
- 官方登录→原生 Cookie 读取/校验→书架历史预览→合并→退出清会话；跨域拒绝，不上传账号截图。
- 真人听书/系统TTS/视频相互切换→失焦/最小化/锁屏→媒体键→seek/倍速/断网/离线→退出释放；视频所有入口同能力语义。
- LAN默认关闭→主动开启→受控第二设备访问→拒绝越界/未授权写→关闭撤销；不自动修改防火墙。
- 旧包数据快照→新包升级→恢复验证→旧包+对应独立快照回滚；旧、新资料均保留。

### 13.4 任务依赖与实施批次补充

- T10 的“启动成功”依赖 T11/T13，拆为先runner编译，后与core/密钥集成验收；不能在仅生成runner时关闭整项。
- T11 只实现编译/ABI，T30 才做媒体端到端；阶段阅读预览不要求媒体已经验收，必须诚实关闭所有媒体入口。
- T31 的TTS互斥最终验收依赖 T40，先实现会话再在 T40 完成后复验；T42 与 T31 的关系允许常亮先行，但发布必须全量集成。
- T50/T51 可早建骨架，最终依赖 T40/T41 等选型输出与锁文件，T52 用最终同一包验收，不能测试旧包后发布新包。
- T60 是未来实施后发布门，本轮另有 R-A/R-B/R-C 三项独立计划审查。审查记录须有问题ID/严重度/计划位置/证据/修订位置/剩余限制；计划修订不等于运行风险关闭。

## 14. 本轮审查记录

状态：v1三项独立审查已完成：A确认2项、B确认0项、C确认3项。v2已采纳5项意见并由主代理检查修订；不冒称审查者已复审v2，不代表实现或发布放行。详见 REVIEW-RESOLUTION.md。


## 15. 三审修订：明确合同与可重复验证（v2，本节优先）

### 15.1 A-02：媒体生命周期验收合同

本节为 Linux 实施预期，不是当前运行结论；T31/T32/T40负责，V07/V11按表断言。
“可见失焦”指inactive且窗口仍可见；hidden/minimized须与单纯失焦区别。听书与TTS沿用现有后台播放开关，不新增常驻服务。恢复只作用于同一媒体owner、同一内容且曾因系统可见性自动暂停的会话；手动暂停/停止/换源/换owner清除自动恢复意图，迟到事件不能改回。

| 状态/输入 | 真人听书、TTS：后台开 | 真人听书、TTS：后台关 | 视频内联 | 视频独立页/全屏 |
|---|---|---|---|---|
| resumed正常播放 | 继续 | 继续 | 页面与项目可见时继续 | 当前页可见时继续 |
| inactive但仍可见 | 继续，不当后台 | 继续，不当后台 | 保持既有手动播放意图 | 保持既有手动播放意图 |
| hidden/最小化 | 继续并保存进度 | 自动暂停并记录恢复意图 | 暂停并记录可见性恢复意图 | 暂停并记录可见性恢复意图 |
| 可靠锁屏事件 | 继续并保存进度 | 自动暂停 | 暂停 | 暂停 |
| 回到resumed/解锁 | 已在播放则不重复start | 仅先前系统自动暂停且owner未变时恢复 | 仅仍在当前可见项目且系统暂停时恢复 | 仅当前页可见且系统暂停时恢复 |
| 手动暂停→失焦→回焦 | 保持暂停 | 保持暂停 | 保持暂停 | 保持暂停 |
| 挂起/恢复 | 挂起前尽力保存；恢复后重连，只有挂起前正在播且owner不变才恢复 | 同左，且恢复时须窗口可见 | 同左，且项目可见 | 同左，且页面可见 |
| 关闭窗口/detached/正常退出 | 停止、保存、释放所有权和会话 | 同左 | 同左 | 同左 |

锁屏事件来源需T42核实（桌面会话/portal等），不能假定Flutter总能报告；无法观察锁屏的环境须记录支持限制，不把无事件等同未锁屏，不用轮询窗口位置猜测。若该限制影响后台关的暂停保证，阻塞该会话的完整验收，不能静默改合同。
挂起保存是尽力行为，意外断电不能承诺保存最后一秒；恢复先核网络、音频设备和有效会话，不重复创建播放器。系统切音频设备错误显式提示。
最少序列：后台开/关分别执行播放→inactive→hidden→resumed；手动暂停→inactive→resumed；自动暂停→换owner→resumed；迟到done/焦点回调；锁屏/解锁；挂起/恢复；四种媒体分别运行。

### 15.2 A-01：选型与媒体验证依赖图

D02拆为a合同与试验准入、b真实集成定案；新增T29为现有产品集成的最小先行子任务，不另建媒体框架。
单向路径：T01→T10/T11→T09/T13→D02a→T29→D02b→T30完成→T31/T32→T52。
D02a可以在工具链阶段开始文档审计；T29必须等runner/core/密钥可用。T30的通用CENC/Range实现可在D02a之后进行，最终验收等待D02b，不能通过先关门再取证。
T29失败只回候选审计，不解除安全门禁；普通媒体首帧不等于CENC产品播放通过，T30仍需完整V06。

### 15.3 C-01/C-02：密钥操作状态与单写者资料所有权

责任：T09负责跨进程所有权，D03/T13负责key状态，T22负责恢复/升级持锁，V01/V03/V04提供证据。优先最小单实例单资料策略，不新增多profile功能。

- 在任何key读取/创建、runtime部署、Hive开箱、设备池初始化和恢复前，取得与共享资料及两个key用途命名空间一致的跨进程排他所有权。锁由系统进程/文件锁机制持有，不仅凭PID文件存在与否；不可由读取尚未初始化的Hive来决定锁。
- 第二次图标/终端启动明确提示已有实例并退出；仅在现有机制安全可复用时转交激活。第二实例不得先初始化key或runtime再检查锁。不新增复杂IPC。
- 锁持有到保存、停后端、关闭箱及所有key操作完成；异常终止后锁可由系统释放。恢复、升级、回滚前确认旧进程退出，不能删除“疑似过期”锁来绕过仍活跃进程。
- key生命周期：未开始→读中→已确认存在/创建写中→持久确认→可用于加密。超时/取消/断连属于结果未知，不等于操作撤销、key不存在或可以重建。
- 第一次创建生成候选A后，写A的底层操作未明确结束时保持未决，不因timeout清pending、cooldown结束或UI重试生成B。UI可显示失败/重试诊断，但不得开启第二次创建或放行依赖key的写入。
- 底层写实际完成后，先重读确认同一用途条目等于A，再缓存并开放敏感写；若失败/不一致继续阻塞并保留资料，不旋转key。一次read-back本身不能代替“旧写已结束”。读操作超时同样不得据此推断空条目。
- Hive用途、设备池用途分别追踪完整底层Future和确认结果；provider实例之间共享同一用途操作责任，避免各自pending产生竞态。保留用途隔离，不引通用密钥框架。
- 永不结束的操作保持阻塞，不以无限重试换可用性。进程退出、provider失联或原生请求的最终完成无法确认时，下次启动不能无条件“读空→生成新key”；T13须定义持久未决标记和恢复流程，验证目标provider的调用结束语义。证明不了旧请求不会迟写则阻塞创建，提示修复Secret Service，不能自动重置keyring。
- 未决标记仅含用途/操作状态，不含key；与受限资料目录一起保留并由同一锁保护。既有可用key及加密箱不被覆盖；错key/损坏仍按现有隔离证据处理，空箱不等于恢复。

可重复验收：用现有SecureKeyStorage fake与可控Completer安排写A超时→UI重试→旧写A迟到→持久确认，断言不存在写B、未决时无受保护写；安排读迟到/写报错/确认不一致/永不返回。新进程须能用持久key读回成功写入的合成Hive与设备池。
双进程验收：同一合成资料与测试key命名空间同时首启；第二实例在key创建前退出，不能改条目/箱/池；第一实例崩溃后新实例可获取锁；恢复快照期间第二实例仍不能写；最终全新进程核对key与数据匹配。不得用日常keyring执行故障注入。
进程被强制终止而原生key写仍可能在provider中完成的场景必须在隔离服务验收；仅证明锁释放不足以关闭C-01。

### 15.4 C-03：崩溃恢复、I/O故障与断电证据

T22先确定快照、操作记录、提交/flush、原子替换及目录持久化责任；同一跨进程锁覆盖预检、快照和恢复。测试使用两套合成资料及独立测试keyring，原备份与恢复前资料保留。
第一层准确称“进程崩溃恢复”：独立子进程通过测试专用同步屏障停在下列点，由控制进程强制终止，不执行正常Hive.close/teardown；全新进程重启后检查持久状态。优先复用现有测试夹具，必要屏障只在测试注入，不能给生产应用增加崩溃开关。
最少中断点：快照完成/恢复标记写入边界、分类提交后、书架提交后、历史/已看集提交后、AI部分提交后、最终完成标记前后。每点记录实际已持久写集合，不假定跨箱事务。
重启断言：源备份及恢复前快照完整可读；无完成标记误报；中断恢复可重入；重复恢复不重复、不覆盖本地新值；所有书/章/组/进度/AI条目按逐字段预期核对，不只看总数。失败时保留原/新/隔离资料并可选择恢复前快照。
定点I/O失败：在可抛弃文件系统/受控I/O替身分别制造磁盘满、写拒绝、快照/标记原子替换失败；标注是模拟还是实际文件系统。模拟不能代替包级权限/磁盘满验证。
第二层只有可抛弃VM与磁盘镜像硬断电并重启才可标“断电恢复”；本任务与普通进程kill均不具备该证据，未执行则明确未验证。不得对主机或真实数据断电。

### 15.5 修订状态与实施放行边界

三项独立审查基于v1完成；A两项、B零项、C三项，共五项已在v2补充合同/任务/验证方法并由主代理检查。审查者未重新复审v2，不能改写原报告为通过。
本轮可交付详细修订计划；进入实施时先完成T00/T01及候选调查，密钥/恢复/媒体验收仍按新增条件阻塞。无构建、运行、包、许可或生产放行证据。
