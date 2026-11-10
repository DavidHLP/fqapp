# Arch code-review fixes handoff

本轮仅实现 SPEC01、SPEC02、T40；不代表完整迁移或发布验收。

## 候选与边界

- worktree：`/home/david/.t3/worktrees/fqapp/t3-e4fe5ae0-efdf23b376d0affc`；分支 `t3/arch-migration-review-fixes`；进入时干净，基线 `8e59698`。
- `2149f7b` 与已有 `ea48158`、`ca3c6b9` 与已有 `8ec6691` 分别具有相同 stable patch-id；没有重复应用。
- 已读两份 final 审查、MIGRATION-SPEC §15、共享指令及 diagnosing-bugs skill；自行实现，未委派。未改共享工作区、包装、CI、pubspec、锁文件、广泛 fixtures；未 push/PR/watch/清理工作树。SDK 自动增添的 analysis_options 排除项已恢复至进入时内容。
- Hindsight search/list/read 用于核对意图；图项目 `fqapp-review-fixes`，先查符号/snippet/caller，再检查逐路径 coverage。Dart acquire 图 inbound 为 0、snippet 只有声明，而源码明确有 main 调用，故使用源码精确 caller 检索补证；C++/设置页 parse_partial 也直接阅读。没有将图缺边当无调用者证明。

> 🧠 **From Hindsight memory (Conventions and patterns)** — 隔离后空箱不等于恢复；合成资料、构建与真实环境验收须分开报告。上述历史原则与当前审查合同一致；通过状态均来自本轮实际运行。

## 逐意见闭环

### SPEC01 — 已验证

保留 EncryptedHive eager/lazy 原来的隔离、保全并开新空箱合同。两入口共用的隔离操作通知诊断监听者；`HiveQuarantineEvent` 提供箱名和保全路径，磁盘上既有 `.unreadable-*` 文件是跨进程/跨重启可发现依据，不另存密钥或删除证据。

Linux 正常业务启动门扫描保全件；未确认时不挂载 RootShell。诊断明确说明密钥不匹配/文件损坏、原件路径、新空箱尚未恢复、退出后复制整个目录保全、在隔离副本用正确原密钥验证、不覆盖原件，以及现有备份冷启动恢复入口。明确确认后可继续当前资料；下次启动再次提示。运行后发生 lazy 隔离同样重新阻挡显示并要求确认。

没有新增 keyring 读写、自动删除/覆盖保全件或自动宣称恢复。原冷启动恢复门、关闭时 recovery drain 和锁释放顺序保持。

新增真实错密钥 eager/lazy 开箱至 AppBootstrap 的合成回归，断言业务不挂载且原密文字节不变；另测文件诊断重建、确认、迟到隔离和重挂载。原空箱及原文件保全断言均保留。

### SPEC02 — 已验证

`LinuxOwnershipBusy` 区分同 isolate 冲突和 fcntl EAGAIN/EACCES；打开锁文件的权限异常保留 FileSystemException。清理仅关闭本次尝试的句柄，既有 owner 不受影响。

生产最外层启动页捕获专用 busy 类型，显示已有实例和「关闭并退出」，点击以退出码 23 结束第二实例。此时尚未初始化 key/runtime/关闭写入钩子，不走已持有资料的正常退出分支；其他权限/key 故障仍保留重试。无新 IPC。

合成双进程断言第二进程状态 23、受保护写入屏障未执行；崩溃释放、全新进程加密 readback、同 isolate 原 owner 保留断言继续通过。新增真实只读目录锁文件权限失败仍可修复重试。UI 注入退出回调验证专用提示和点击，测试不调用 exit runner。

### T40 — 已验证

沿 `SystemTtsPreferences` 扩展 volume，不新增依赖或独立配置体系。范围 0..1，持久化及发送时处理 NaN/越界；未配置时不发送字段，native 不调用音量 setter，保留用户 daemon 原配置。明确设置时 Linux 通道传参，libspeechd 在既有 speech worker 上以 `round(volume*200-100)` 映射 -100..100。

设置页复用 GlassControls.slider 和可访问标签；修改语速/引擎时保留音量。Android/Windows 不发送新字段。新增边界/持久化/跨平台通道和设置滑条回归；真实隔离 libspeechd 会话测试非法 -0.01/1.01/NaN 拒绝、合法 0/.5/1 初始化，以及中文短句完成、取消与 daemon 断连。

## 本轮实际证据

证据目录：本 worktree 的 `build/review-evidence/`（忽略的本地产物，未提交）；原 `/tmp/fqapp-review*.log` 也保留。

- `fqapp-review-regression-final.log`：九文件 72 passed（encryption/bootstrap/ownership/TTS/settings/security close/recovery/chapter cache/audio preferences）。之后新增两个直接开箱→启动门用例和一个权限用例：`bootstrap-final6.log` 13 passed，`ownership-final.log` 5 passed。这些是重叠运行，不相加声称独立测试总数。
- `flutter-analyze-final.log`：full flutter analyze --no-pub，无 issues。`analyze-final.log`：已恢复原 analysis_options 的 Dart full analyze 无 issues。
- `native-final.log`：全桥 `-Wall -Wextra -Werror` 编译、whole archive 对真实 Flutter/GTK/WebKit/libspeechd 链接、ctest 1/1 passed。
- `runtime/fqapp-acceptance-qvdh13sb/flutter.log`：隔离 X11 全部 6 passed，普通首启/真实 Secret Service 合成 keyring、合成本地导入阅读、真实软件纹理/MPRIS、TTS 音量参数及完成/取消/断连、注入的 lifecycle。launcher `runtime-final.log` EXIT 0。隔离 HOME、私有 D-Bus、合成固定密码 keyring、null ALSA、软件渲染；没有触碰日常资料或日常 keyring。
- 早先独立 TTS 运行 `/tmp/fqapp-runtime-evidence/fqapp-acceptance-o1ncwblq/flutter.log` 1 passed；不是另一个物理会话证明。
- SIGKILL 恢复矩阵结果见下方最终收尾记录。

必要命令：SDK `/home/david/.local/share/fqapp-toolchains/flutter-3.47.9/bin/`；测试使用 `TMPDIR=$PWD/build/review-tmp flutter test --no-pub --no-track-widget-creation --reporter expanded` 加上述目标文件。native CMake cache `/tmp/fqapp-review-native`，依赖 prefix `/tmp/fqapp-native-deps`。为避开主机 /tmp 配额，最终 runtime 用忽略目录 `build/review-session.py` 运行现有 launcher，只替换证据根目录并设置独立 TMPDIR；生产 launcher 未修改。

## 原失败与排障记录

- 首轮 lazy 测试随机损坏字节触发 Hive 自身修复而非隔离；用真实错密钥复现后 eager/lazy 均通过，原底层保全断言保留。日志 `fqapp-review-tests.log` 未删除。
- 新设置测试先选错 Material Slider，改为现有 AppGlassSlider；另修正测试体内恢复平台 override，保留失败日志。
- 联动测试的真实 I/O 与 fake-async 日志 Future 混用造成测试等待；用可控 Completer 连接真实开箱和启动门，按已有 main 测试的全局日志生命周期安排真实 I/O 用例，断言全部保留。`bootstrap-final*.log` 保留原失败及最终通过。
- 主机 /tmp 后续明确返回 Disk quota exceeded errno 122；早期并行编译/扩大 runtime 普通启动超时未计通过。没有清理 /tmp、缓存、其他工作树或全局设置；改用本 worktree 忽略目录后全 runtime 6 项通过。只终止核对过 cwd/命令的本轮失效测试进程及其子进程，未终止其他代理验证。

## 尚未验证的交付边界

没有运行全仓 Flutter 全套、跨平台应用运行、物理 W/XW/X 三会话/扬声器音量标定、真实账号、生产 keyring 故障注入、磁盘断电、安装升级回滚或远程 CI。已有真实 null 音频会话证明参数进入真实 libspeechd 并被接受，不证明物理扬声器声压或语音引擎的感知音量线性。完整迁移放行仍归 root 的最终同 HEAD 验证/重包；本轮不作发布批准。

## 最终收尾记录

- `matrix-final.log`：8 个 SIGKILL 点（snapshot/pending/groups/shelf/history/ai-partial/before-complete/complete）全部走完，01:48 +1 All tests passed；原逐字段、重复恢复、不覆盖新值、源备份和保全快照断言未删改。
- `analyze-delivery.log`：最终新增联动/权限用例及恢复原配置后的 full Dart analyze，无 issues。
- 最终 diff --check 通过；本轮仅本地提交，分支保留供 root 按提交集成。上述失败日志、合成资料及缓存保留在原位置；没有通过清理凑绿。
