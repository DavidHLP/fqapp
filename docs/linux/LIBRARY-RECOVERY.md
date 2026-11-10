# 备份字段与 Linux 恢复边界

Linux 使用启动前恢复：备份页预检后保存待恢复操作，用户关闭窗口并重新启动；下一次启动在业务挂载前保全闭箱资料、重开恢复所需 stores、按既有合同合并并关闭/flush，再写完成记录。失败保留 pending 与快照并显示诊断；重启重入。直接在线 restore 仍被拒绝。非 Linux 恢复合同保持。

## 可移植文件覆盖表（当前源码审计）

| 分段 | 精确携带字段/内容 | 排除和合并行为 |
|---|---|---|
| 封套 | format=fqapp.library-backup，version=1/2，createdAt，excludedLocalRecords；最大16 MiB | v2 必须含非空 ai；UTF-8/BOM兼容，未知版本拒绝；不是任意 Hive dump |
| shelf | id、kind、title、cover、author、badge、ep、source（非番茄时）、intro、categories、creationStatus、wordNumber、seriesId、episodeId、addedAt | 在线 book/audio/manga/video/manju；本地 id/seriesId/分类身份排除；封面只保留无 userinfo 的 HTTP(S) URL；不包含封面二进制；按来源身份补缺，不覆盖本机收藏 |
| history | id、kind、title、cover、author、badge、ep、seriesId、episodeId；可选 bookId/chapterId/toneId、time/episode/positionVersion/textOffset、position/maxScroll/progress/duration/rate、positionUnit、autoAdvance/completed/fanqieImported | allowlist，非有限值/越界值拒绝；positionUnit 仅 manga/comic-page；local_ 排除；保留本机进度，audio/manga 重建 scoped key；不是阅读时长记录 |
| watched | 内容 id → 剧集稳定 id → 已看时间（毫秒）；最多100000集 | 集合补缺保留旧时间；不使用剧集下标；local_ 内容排除 |
| groups（可选，格式版本仍按既有规则） | version、可见 groups{id:{name,at,deleted:false}}、assignments{内容身份:{group,at}} | 不导出墓碑、本地书归属、悬空归属；结构/容量预校验；分类未就绪时有分类的备份拒绝；同名 remap、现有身份/归属保留 |
| ai | base64(gzip(JSON))；反馈 aggregate（四类反馈、修订、保护/认可改法、冲突、引用正文锚点）、prompts、candidates、trials、trialResults 摘要、usage、pending、createdAt、promptState.global/books、rates | feedback/prompts/candidates 必需，损坏拒绝后才能写书架；不带 API Key/provider/endpoint 配置、请求账本、运行明细、formal cache、试验 rawValidatedEdits；本地书反馈进入待绑定，不能承诺重导入自动关联 |
| AI 合并细则 | aggregate 重新按 revision 合并，提示词/候选按 ID 补缺，usage 走既有预算队列，本机提示词优先 | 不是所有 AI 值都简单“本机优先”：rates 按 updatedAt；trial 沿用既有写入；trialResults 保留本机 raw 输出；本批未改 AI 合同 |
| 本地书/字体/下载 | **不在可移植文件中** | TXT/EPUB 原文件、本地书架进度、字体文件、章节/图片/音视频下载与缓存须独立保留；不可只导 JSON 后删除源目录 |
| 其他 | **不在可移植文件中** | 阅读时长、书签、划线、应用设置、账号 Cookie/凭证、系统密钥库、设备池及浏览器 profile 不迁移；不要复制系统 keyring 来代替本机密钥初始化 |

正文、用户提示词和反馈属于用户资产，可能包含用户主动输入的敏感文本；“不含 API Key 字段”不代表任意用户文本经过秘密扫描。按书导出只筛选 AI 资产，仍含全局书架/进度。超限可省略试验明细，必需反馈/保护/提示词仍超限时明确失败；AI 箱不可用的导出按既有合同显式提示省略。

## 原始资料保全服务

`LinuxLibraryRecovery.preserveClosedProfile` 由启动前恢复模式调用。调用者必须停止后端、下载及其他写入，保存进度、关闭所有 Hive，并持续持有同一个 `LinuxProfileOwnership`；本服务不擅自关闭业务、不释放/删除锁、不访问 keyring。

它先盘点持锁目录，拒绝符号链接和检测到的活动 Hive 箱；再创建随机同级隔离目录（0700），逐文件复制实际原始内容到 `profile/`，单独保存源备份 bytes。它只跳过活实例的 `.fqapp-writer.lock`，保留密文 Hive、隔离文件、本地书与目录内的其他文件。复制后的 `sync -f` 成功后，flush 临时标记并原子 rename 为 `snapshot-ready`，再次 `sync -f`。异常保留源/部分副本，绝不删除或自动打开空箱。

`snapshot-ready` 只表示闭箱复制边界，不是恢复提交完成标记。该快照只覆盖传入资料目录；目录外的字体/下载/设置、后端 runtime、系统密钥等不在其中。只有停止所有写者且保留匹配密钥/应用版本时，才可把它作为该目录的原始副本。服务不能证明外部写者已经停止，不能代表整台机器/全应用一致快照。

## 恢复/回滚操作说明

1. 保留源 JSON、现有资料、隔离文件和匹配密钥。不要删除 pending 标记、旧箱或锁来试图解锁。
2. 在备份页选择文件并预览，确认后保存待恢复操作，关闭窗口并重新启动；不能直接调用在线跨箱合并或 AI 独立入口绕过恢复模式。
3. 已由受控离线生命周期产生的快照：检查 snapshot-ready 并逐文件核对；在新的独立资料目录复制 `profile/`，以匹配版本和原密钥做只读核对。保留快照、旧/新工作目录；禁止覆盖活动原目录或让旧程序直接写新版目录。
4. 缺密钥/错密钥/原有隔离空箱属于另一个安全恢复问题；不要在 clone 上开启正常业务写入冒充恢复成功。

## 冷启动状态与覆盖清单（续批）

- `.fqapp-restore.json` 是恢复 journal，与密钥命名空间的 `.purpose.pending` 安全标记不同；不会存密钥或清理安全标记。
- `.fqapp-restore-*` 同级 0700 目录保存原备份及完成后归档 receipt；`.fqapp-before-restore-*` 保存整个资料目录原件（不复制系统 keyring）。失败/孤立快照不自动清理。
- pending 在业务进程中只安排操作；快照和导入在下一次新进程完成，沿用同一资料/密钥命名空间锁。正常关闭仍走既有 flush、卸载、停下载/播放器、停后端、Hive.close、释放所有权顺序。
- 恢复启动先确认安全 provider，再进入恢复门；严格试开既有加密文件阻止错误密钥进入 EncryptedHive 的隔离后空箱路径。恢复完成前从不挂载 FqApp 或后台业务。
- 顺序为 snapshot → journal merging → stores init/AI预检 → groups → shelf → history/watched → AI → Hive.close/flush → complete。无跨箱原子性；中间状态靠同一备份补缺重入。AI沿用 revision/rate/prompt 等现有规则。
- 完成页面确认后将 journal 归档为 receipt，提示关闭重启进入正常业务；不在活跃 UI 重开 Hive。失败页面显示具体错误及快照位置，关闭重启重入；完整回退仍按上述离线保留副本流程，禁止覆盖原快照。
- 自动证据见 `test/library_recovery_matrix_test.dart`：真实独立 Flutter engine 在 snapshot、pending、groups、shelf、history、AI第一条提示词、完成前/后被 SIGKILL；另启进程重入/重复核对。合成 fixture 不覆盖所有 AI 资产组合，既有 AI tests 补充分段/合并合同。
- I/O覆盖：模拟 group ENOSPC、sync exit28、受控 journal临时路径写入失败；不等于真实磁盘满/包权限验收。没有 VM 断电证据。
