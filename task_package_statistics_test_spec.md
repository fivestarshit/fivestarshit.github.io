# 任务包统计分析测试规格

## 变更说明
- **2026-09-02**：任务统计页 / 卡片明细弹窗：选中任务组后，「任务规则」下拉 `taskPackageOptions` 请求带 `taskGroupId`，仅返回该组下任务包；换组清空已选规则；清空任务组后恢复该视角全部包。`taskGroupOptions` 仍不传 `taskGroupId`，避免把自己滤没。
- **2026-08-27**：末级部门（`deptLevel=6`）`taskPackageOptions` / `taskGroupOptions` 改为按 `owning_department_code = deptCode` 读 `package_perf` / `group_perf` 快照（非末级仍 `parent_department_code = deptCode`）。
- **2026-08-19**：任务统计页顶部「任务规则」筛选项改为任务包规则口径：下拉走 `POST /sales/task/statistics/taskPackageOptions`（`taskPackageId` + keyword 搜索），查询/卡片明细传 `taskPackageId` 不再传 `taskRuleId`。
- **2026-08-18**：`refreshSnapshot` / XXL `refreshTaskPackageStatisticsSnapshot` **聚合前先执行**明细按判断截止过期同步（`expireInProgressDetailsPastEndTime` 同口径），再扫明细写快照；修复历史月（如 7 月）任务截止已过但明细仍为 `IN_PROGRESS` 时 `expiredCount=0`。须重跑受影响月份快照。
- **2026-08-18**：`storeVisitedInProgressCount`（已巡店进行中）口径改为 **`IN_PROGRESS` 或 `EXPIRED`**（仍须 STORE 且开始后已巡店）；`/cards/detail` `cardType=STORE_VISITED_IN_PROGRESS` 同步。须重跑快照。
- **2026-08-12**：`/cards/export` 与 `/distribution/detail/export` 任务明细 CSV 表头对齐前端列表：`对象名称,对象编码,归属部门,最近拜访时间,任务,任务编码,任务说明,任务类型,关联任务组,状态,下发人,开始时间,截止时间,反馈原因,关联任务规则`；`NEVER_VIEWED` 导出对齐列表为 `姓名,工号,职位,归属部门`。
- **2026-08-12**：明确 `/cards/detail` 任务类卡片经 `toListDisplayDtos` 与 `/distribution/detail/list` 同口径：`taskPackage[0]` 含 **`taskGroupId`/`taskGroupName`**（按包 `task_group_id` 批量回填组名）。
- **2026-08-11**：快照 Job 默认 `taskMonths`：自然日 **&lt; 16** 时额外前置**上月**（历史月写月末日），16 号起仍仅「本月起共未来 6 个月」。
- **2026-08-11**：`neverViewedCountDod` 改为**人数差** `(今人数 − 昨人数)`，不再 `(今−昨)×100`；其余占比类 `*Dod` 仍为百分点差。
- **2026-08-11**：快照**版本指针**优化——八张快照表增加 `build_id`；新增 `task_stats_snapshot_build_pointer(task_month,stat_date→current_build_id)`。Job 改为**先写新 build → 切指针 → 再 GC 旧 build**，刷新过程读侧仍可读旧版本，消除空窗。读接口一律按指针 `current_build_id` 过滤；跨日趋势反馈量经 `EXISTS` 指针关联。`fullRebuild` 仅影响历史月 GC 范围（整月其它日），不再「先删后写」。须执行 DDL（`update_tables.sql` 2026-08-11 段）并重跑快照。
- **2026-08-06**：`deptTree` 非管理员改为将有权限部门提升为 `list` 根（不再保留无权限祖先路径）。修复仅有登录人本部门权限时，前端默认选中祖先部门导致「请求部门与权限部门无交集」。
- **2026-07-17**：`deptTree` 支持 `op.config.filterDeptCodes`：权限裁剪后剔除配置部门及其全部子部门。
- **2026-07-17**：移除下发明细状态/反馈变更时的快照异步刷新钩子；快照仅由 **XXL-JOB** 或 **`POST /refreshSnapshot` 手动**触发。
- **2026-07-16**：`executionTrend` 全字段审计：`mergeTrend` 改用与库存行相同的维度键解析（防 `split("|")` 丢完成/反馈）；`feedbackCount`/`feedbackRequiredCount` 与 `totalCount` 同读 `trend_date=stat_date` 库存锚点行；`stat_date` 强制入折线点位。须重跑快照。
- **2026-07-16**：`executionTrend.totalCount` / `feedbackRequiredCount` 读侧固定为最新快照全量维度求和（与 `cards.totalCount` 一致）；修复跑批日 partial 维度求和导致与 cards 不一致。
- **2026-07-16**：`executionTrend` 反馈量改为合并历史各跑批日快照（`trend_date=stat_date`），可同时展示昨天/今天；完成量仍读最新一版做 MTD。反馈点为跑批日存量（非跨日累加）。
- **2026-07-16**：趋势反馈量入桶日改为**快照跑批日 `stat_date`**（不再按 `updated_at`）；完成量仍按 `final_end_time` 自然日。须重跑快照。
- **2026-07-16**：未来月 `stat_date` 与当月一致——写/读均为**跑批当天（今天）**，按日保留多日快照；`fullRebuild` 仅删当天 `(stat_date, task_month)`，支持较昨日日维度对比。**历史月不变**（写月末；读 MAX；fullRebuild 删整月）。
- **2026-07-15**：`task_distribution_detail` 新增 `last_visit_closed_time`（最近巡店时间）；快照 Job 回写；`/cards/detail` 门店三类卡片按该字段与 `start_time` 过滤，与快照计数对齐。须跑 DDL 并重跑快照。
- **2026-07-15**：快照 Job 防 OOM：去掉跨月长事务；扫描只取聚合必要列；`org_perf` 分桶超 3 万累加落盘；各表转换后立即写入并 clear；未查看按部门分批写。业务口径不变。
- **2026-07-15**：快照刷新默认 `taskMonths` 由「本月+下月+下下月」改为**本月起共未来 6 个月**（含本月）。
- **2026-07-15**：`refreshSnapshot` 当月无匹配任务包明细（`end_time` 落在 taskMonth 且 `task_package_id>0`）时，跳过删除/聚合/落库/未查看；不触发后续逻辑。
- **2026-07-15**：`trend_daily` / `feedback_reason` Job 补写 `department_path_json`（此前落库为空，选上级部门 JSON_CONTAINS 失效）；`summary`/`org_perf`/`package_perf`/`not_viewed` 原本已写入。须重跑快照。
- **2026-07-14**：cards 全部 `*Dod` / `neverViewedCountDod` 统一为 **百分点差 `(今日 − 昨日) × 100`**（例：反馈率 0.35 与 0.34 → `timelinessRateDod=1`）。
- **2026-07-14**：`executionTrend` 增加 **`totalCount`**（当月任务明细总数，与 cards.totalCount 口径一致；各日相同）；完成率 = `completedCount / totalCount`。须重跑快照。
- **2026-07-14**：`executionTrend` 增加 `feedbackRequiredCount`；`feedbackCount`/`completedCount` 读侧 **MTD 累计**。须重跑快照。
- **2026-07-14**：`NEVER_VIEWED` 明细/导出支持 **`keywords`**：模糊匹配姓名、工号、职位、归属部门编码或名称（OR）；与 `/cards/detail`、`/cards/export` 共用。
- **2026-07-14**：「有任务未查看」改为**月维度**：`eligible` 仍为 DTS 在职客户代表/区域业代；**已查看**=`task_user_login_record` 在对应 `taskMonth` 自然月内**任一日**有登录；当月登录过则不再计入未查看。需重跑快照生效。
- **2026-07-14**：`/cards/detail`、`/cards/export` 新增卡片类型 **`TOTAL`**（总任务数，与 `cards.totalCount` / overview.cards 一致）与 **`FEEDBACK_RATE`**（反馈率**分子**明细：关联 `task_type=TASK` 且 `feedback_enabled=true` 且 `feedback_reason` 非空，与 `timelinessRate` 分子 / `timelinessNumerator` 一致）。
- **2026-07-13**：`/cards/detail` 补齐 `taskRuleId` 过滤：经明细 `task_def_id` → `task_definition.rule_id`（`EXISTS`），与快照 `task_rule_id` 口径一致；此前明细接口忽略该字段导致与 cards 筛选不一致。
- **2026-07-13**：反馈相关明细统计统一口径——仅关联 `task_definition.task_type=TASK` 且 `feedback_enabled=true`（经明细 `taskDefId`）的明细计入；覆盖：已巡店无反馈、反馈量/反馈原因分布/趋势反馈量、主要反馈原因、反馈率（原已按此口径）。口径变更后须 `fullRebuild=true` 重跑快照。
- **2026-06-29**：初版。任务中心「任务统计」大盘采用快照表预聚合 + 读接口只读快照；与现有 `statusStats` Redis 轻量计数并存。
- 快照维度：`stat_date` + `task_month`（任务截止月份，取自明细 `end_time` 所在月）+ `owning_department_code` + `object_code` + `task_execution_type` + `task_package_id` + `task_def_id` + `task_rule_id`。
- 部门权限与 `POST /sales/task/distribution/detail/list` 同源：`owning_department_code IN (...)` OR `JSON_CONTAINS(department_path_json, dept_code)`；管理员不过滤；无权限返回空数据。
- 刷新策略：XXL-JOB 每 **15 分钟** + 每日凌晨 **02:00** 全量校准；与明细最终一致性容忍窗口 **T+15min**（仅定时/手动刷新，明细写路径不触发）；历史月份快照保留 **24 个月**。
- **有任务未查看（2026-07-14 月维度）**：getToken 仍按日写 `task_user_login_record`；Job 按 **taskMonth 自然月** 汇总：已查看=该月内任一日登录过的人；未查看=在职客户代表/区域业代 − 当月已登录；写入 `task_stats_snapshot_not_viewed`（`eligible_count`/`viewed_count`/`not_viewed_count` + `not_viewed_personnel_json`）；cards `neverViewedCount`=SUM(`not_viewed_count`)。
- **较昨日环比（2026-07-14 / 2026-08-11）**：cards 对比 `stat_date` 与 `stat_date-1`；占比类 `*Dod` = **`(今日 − 昨日) × 100`**（百分点差）；`neverViewedCountDod` = **人数差 `(今 − 昨)`**；**不再返回上月环比 `*Mom` 字段**。
- **`POST /sales/task/statistics/taskTypeBreakdown`**：`task_execution_type` 为空/空串的快照行归并为 **`OTHER` / 「其他」**；有编码时 `taskExecutionTypeName` 从 `task_execution_type_option` 查名称，未命中则回退编码本身。
- **`POST /sales/task/statistics/refreshSnapshot`**：手动触发快照刷新（与 XXL `refreshTaskPackageStatisticsSnapshot` 同参）；异步受理，立即返回；Body 可空；**Redis 防重复点击**（同操作人+同参数执行中不重复跑，不报错，`accepted` 默认 `true`）。
- **读快照 `stat_date`（2026-07-16 / 2026-08-11）**：当月/**未来月**=**今天**；历史月优先指针表 **`MAX(stat_date)`**，无指针再回退 summary；无记录时用**该月最后一天**。读数据另按指针 `current_build_id`（无指针回退 `build_id=0`）。
- **写快照（2026-08-11 版本指针）**：未显式传 `statDate` 时——当月/**未来月**=**今天**，历史月=**该月最后一天**；每次刷新分配新 `build_id` 写入全部事实表 → upsert 指针 → GC 旧 build（当月/显式日：同日其它 build；历史月 `fullRebuild=true`：整月其它行 + 其它日指针）。

---

## 一、指标口径

### 1.1 筛选维度（与 PRD 一致）
| 维度 | 请求字段 | 说明 |
|------|----------|------|
| 架构 | `deptCode` | EHR 部门树选中节点；**仅 orgPerformance** 未传时默认 `op.config.marketingDepartmentCode`；与 OP 权限取交集 |
| 任务截止月份 | `taskMonth` | `yyyy-MM`，默认当前月；明细冗余 `task_month` 与快照 `task_month`、扫明细筛选口径一致，均为 **`end_time` 所在自然月**（当月 1 日）；仅含 `task_package_id > 0` 的任务包下发明细 |
| 任务对象 | `objectCode` | STORE/DEALER/PERSON 等 |
| 任务类型 | `taskExecutionType` | 执行类型编码 |
| 任务包规则 | `taskPackageId` | 任务包 id |
| 任务规则 | `taskDefId` / `taskRuleId` | 子任务 id 或规则 id |

### 1.2 六大模块
1. **统计卡片**：状态分布 + 8 张指标卡（含门店巡店衍生 4 卡）
2. **任务执行趋势**：MTD 日序列完成量/反馈量
3. **反馈原因分布**：reason + count + percent
4. **任务类型占比**：环图 + 各类型执行柱图
5. **组织执行表现**：选中部门的**下一级**部门完成率/反馈率；末级部门按 targetEntityCode 实时聚合
6. **任务包表现**：任务项数、完成率、反馈率、主要反馈原因

### 1.3 状态桶
- `IN_PROGRESS` / `COMPLETED` / `EXPIRED` / `CLOSED`（快照按明细表 `status` 字段分桶；刷新快照前会先跑判断截止过期同步，将应过期但仍为进行中的明细置 `EXPIRED`）
- 复合：`expiredInProgressCount` = EXPIRED 且 final_end_time 为空或晚于 end_time 的进行中过期口径（Job 按 PRD 拆分写入）

### 1.4 门店巡店衍生（仅 objectCode=STORE）
| 卡片 | 判定 |
|------|------|
| 已巡店进行中 | `objectCode=STORE` ∧ (`IN_PROGRESS` ∨ `EXPIRED`) ∧ `last_visit_closed_time`/`start_time` 均非空 ∧ `last_visit_closed_time > start_time`（与快照 `visitedAfterStart` 一致） |
| 已巡店未反馈 | 同上「已巡店」条件 ∧ 需反馈(`TASK`+`feedback_enabled`) ∧ `feedback_reason` 为空/空白 ∧ 非 COMPLETED/CLOSED |
| 未巡店已过期 | `STORE` ∧ `EXPIRED` ∧ (`last_visit_closed_time` 为空 ∨ (`start_time` 非空 ∧ `last_visit_closed_time < start_time`)) |
| 有任务未查看 | 快照表 `task_stats_snapshot_not_viewed`（按部门汇总 + `not_viewed_personnel_json`）；**月维度**：当月任一日 getToken 登录过即不算未查看；cards 人数=SUM(`not_viewed_count`)，明细读 JSON 数组 |

`last_visit_closed_time`：Job 批量查 DTS 后写回 `task_distribution_detail.last_visit_closed_time`；`/cards/detail` 门店三类卡片按该列过滤，与快照计数对齐。

### 1.5 完成率 / 反馈率 / 环比
- **完成率** = `completedCount / totalCount`（分母含进行中+已完成+已过期+已关闭，不含逻辑删除）
- **反馈率** = `timelinessNumerator / timelinessDenominator`（接口字段名仍为 `timelinessRate`）；**分母** = 当月任务明细中，关联 `task_definition.task_type=TASK` 且 `feedback_enabled=true` 的条数（不限状态）；**分子** = 分母中 `feedback_reason` 非空的条数
- **反馈量 / 反馈原因分布 / 趋势反馈量 / 主要反馈原因**：同样仅统计「需反馈」明细（`task_type=TASK` 且 `feedback_enabled=true`）且已填 `feedback_reason` 的条数；`feedback_enabled=false` 或不存在关联 TASK 定义的明细一律不计
- **环比（月）**：~~cards 不再返回 `*Mom`~~（已移除）
- **较昨日（日）**：对比基准 = **stat_date-1** 同维度快照。占比类 / 反馈率 = **`(今日 − 昨日) × 100`**（百分点差，0~1）；有任务未查看 `neverViewedCountDod` = **人数差 `(今 − 昨)`**（例：51→0 人为 `-51`）。例：反馈率 34%→35% → `timelinessRateDod=1`

---

## 二、Job 用例

### 2.0 无参默认月份（回归）
- Handler：`refreshTaskPackageStatisticsSnapshot`
- 任务参数：**空**（或不传 `taskMonths` 的 JSON `{}`）
- 预期（16 号及以后）：`taskMonths` 默认为 **本月起共未来 6 个月**（含本月；如当前 2026-07-16 则为 `["2026-07","2026-08","2026-09","2026-10","2026-11","2026-12"]`）
- 预期（16 号之前）：额外前置**上月**（如当前 2026-08-11 则为 `["2026-07","2026-08",…,"2027-01"]`）；上月按历史月写 `stat_date=上月最后一天` 并随 Job 刷新

### 2.1 首次全量
- Handler：`refreshTaskPackageStatisticsSnapshot`
- 参数：`{"taskMonths":["2026-06"],"statDate":"2026-06-29","fullRebuild":true}`（`statDate` 可省略，当前月默认今天）
- 预期：写入新 `build_id` 行（summary/trend/feedback/org/package 等均有数据）→ 指针 `(task_month,stat_date)` 指向该 build → 再 GC 同日旧 build；刷新过程中读侧不应出现整表空窗

### 2.1.1 重跑历史月（回归）
- 参数：`{"taskMonths":["2026-05"],"fullRebuild":true}`（**不传 statDate**）
- 预期：先写 `stat_date=2026-05-31` 新 build → 切指针 → 再 GC 该 task_month 下其它行/其它日指针；读接口 `taskMonth=2026-05` 命中新版本

### 2.1.2 未来月按日写入（回归）
- 前置：当前自然月为 2026-07；参数 `{"taskMonths":["2026-08"],"fullRebuild":true}`（不传 statDate）
- 预期：写入 `stat_date=今天(2026-07-xx)`、`task_month=2026-08-01` 的新 build 并切指针；GC 仅清理同日旧 build，**不**清空 8 月其它 `stat_date`
- 连续两天各跑一次后：库内存在 `stat_date=D` 与 `stat_date=D-1`（同一 `task_month=2026-08`，各自指针）
- 读 `taskMonth=2026-08` 的 cards：`statDate=今天` 且命中今日指针 build；较昨日对比 `stat_date-1` 的指针 build（有昨日则 DoD 有效）

### 2.1.3 版本指针空窗（回归）
- 前置：某 `(stat_date, task_month)` 已有可读快照；在 Job 写入新 build 尚未切指针期间发起 cards
- 预期：仍返回旧 `build_id` 数据，计数不为空；指针切换后读到新 build；旧 build 随后被 GC

### 2.1.4 历史月已过期计数（回归 · 2026-08-18）
- 前置：7 月任务明细 `end_time` 落在 2026-07，`task_package_id>0`；判断截止已到（含「截止后 N 天」宽限期结束），但库内仍为 `status=IN_PROGRESS`（过期 Job 未跑或快照先于过期刷新）
- 参数：`{"taskMonths":["2026-07"],"fullRebuild":true}`
- 预期：Job 日志含 `[refreshSnapshot] 聚合前明细过期同步完成` 且 `updatedRows>0`（有应过期明细时）；聚合后 `task_stats_snapshot_summary.expired_count` 与 `status=EXPIRED` 明细数一致；`cards.expiredCount>0`；点「已过期」卡片明细 `cardType=EXPIRED` 能查到记录
- 说明：任务截止已到但**判断截止未到**的明细仍保持 `IN_PROGRESS`，不计入 `expiredCount`（与 `expireInProgressDetailsPastEndTime` 一致）

### 2.1.5 反馈原因含竖线（回归 · 2026-08-19）
- 前置：同一维度（部门+对象+类型+包+子任务）下，两条需反馈明细分别填写 `feedback_reason_content` 为 `客户不在|关门`、`其他|关门`（或任意后缀相同、前缀不同且含 `|` 的文案）
- 参数：`{"taskMonths":["2026-08"],"fullRebuild":true}`（或触发失败的那一月）
- 预期：`refreshSnapshot` **成功**，不再报 `Duplicate entry ... uk_build_feedback_dim`；`task_stats_snapshot_feedback_reason` 中对应维度仅 1 行，`reason_count` 为 2（或按 uk 前缀 191 合并后的合计）
- 读侧：`POST /sales/task/statistics/feedbackReasonDistribution` 能查到合并后的原因桶

### 2.1.6 末级部门包/组下拉（回归 · 2026-08-27）
- 前置：选中 `deptLevel=6` 末级部门；该部门有下发明细且快照已刷新；`package_perf` / `group_perf` 存在 `owning_department_code=该末级` 的行
- 请求：`POST /sales/task/statistics/taskPackageOptions`、`POST /sales/task/statistics/taskGroupOptions`（Body 含 `deptCode`、`taskMonth`、可选 `objectCode`）
- 预期：返回非空 `{ id, name }[]`；与 cards 同月同部门有数据时，下拉应能列出对应任务包/任务组
- 对比：非末级部门仍按 `parent_department_code = deptCode` 查下一级分桶

### 2.1.7 选任务组后任务规则仅该组（回归 · 2026-09-02）
- 前置：快照已刷新；任务组 A、B 各有不同任务包；当前部门/月份/对象下两包均能出现在未带 `taskGroupId` 的 `taskPackageOptions`
- 请求：`POST /sales/task/statistics/taskPackageOptions`
```json
{
  "deptCode": "D001", // 当前选中部门编码
  "taskMonth": "2026-09", // 任务截止月份 yyyy-MM
  "objectCode": "STORE", // 可选；任务对象
  "taskExecutionType": "TOUR", // 可选；任务类型
  "taskGroupId": 10001, // 当前选中任务组 id；按 package_perf.task_group_id 精确过滤
  "keyword": "" // 可选；任务包名称模糊；空则不按名称过滤
}
```
- 预期：仅返回任务组 `10001` 下的任务包 `{ id, name }[]`；不含任务组 B 的包
- 对比：去掉 `taskGroupId` 后，同一部门/月份/对象下应同时能看到组 A、组 B 的包
- 前端：换任务组清空已选 `taskPackageId`；`taskGroupOptions` 请求**不传** `taskGroupId`

### 2.2 定时 / 手动刷新
- XXL-JOB `refreshTaskPackageStatisticsSnapshot`：建议每 15 分钟 + 每日 02:00 全量（`fullRebuild=true`）
- 手动：`POST /sales/task/statistics/refreshSnapshot`（异步受理）
- **不再**由明细状态/反馈写路径触发快照刷新

### 2.3 跨月 / 空部门
- `taskMonths` 传多个月份分别聚合
- 某部门无明细：快照无行，接口 cards 各计数为 0；**当前月/未来月** `statDate` 仍返回今天；**历史月** `statDate` 返回该月最后快照日（无快照时为 null / 空数据）

### 2.3.1 历史月读快照（回归）
- 前置：`task_month=2026-05` 仅在 2026-05-31 写入过快照（`stat_date=2026-05-31`）；2026-06 起 Job 不再刷新 5 月
- 请求：`{"taskMonth":"2026-05", ...}`
- 预期：`cards.statDate=2026-05-31`（非今天）；各指标能查到 5 月最后一次快照数据
- 对比：请求 `taskMonth=当前月或未来月` 时 `statDate=今天`

### 2.4 反馈率（回归）
- 前置：当月存在关联 `task_type=TASK` 且 `feedback_enabled=true` 的明细 A、B、C；其中 A 已填 `feedback_reason`，B/C 未填；另存在 `feedback_enabled=false` 或非 TASK 明细 D
- 预期：`timeliness_denominator=3`（A+B+C），`timeliness_numerator=1`（A）；cards `timelinessRate=0.3333`；D 不计入分母
- 口径变更后须 `fullRebuild=true` 重跑快照

### 2.4.0 总任务数 / 反馈率明细弹窗（回归）
- 请求：`POST /sales/task/statistics/cards/detail`，筛选与 `POST /overview`（或 `/cards`）一致
  - `cardType=TOTAL`：返回当月任务包下发明细全量分页（不锁 status）；`total` 与同筛选 `cards.totalCount` 一致
  - `cardType=FEEDBACK_RATE`：仅返回已反馈明细（需反馈 TASK 且 `feedback_reason` 非空，即分子 A）；不计未填反馈的 B/C 与非需反馈的 D；`total` 与同筛选快照 `timelinessNumerator` / 反馈率分子一致
- 导出：`POST /cards/export` 传相同 `cardType`，列与任务明细导出一致

### 2.4.1 已巡店无反馈 / 反馈量需 feedbackEnabled（回归）
- 前置：门店明细 E：`feedback_enabled=true`、已巡店、无 `feedback_reason`、`IN_PROGRESS`；门店明细 F：`feedback_enabled=false`、已巡店、无 `feedback_reason`、`IN_PROGRESS`；明细 G：`feedback_enabled=true` 且已填 `feedback_reason`
- 预期：`storeVisitedNoFeedbackCount` 仅计 E（不计 F）；`feedbackCount` / 反馈原因分布 / 趋势反馈量仅计 G（不计未开启反馈但误填原因的明细，若有）
- 明细：`POST /cards/detail`，`cardType=STORE_VISITED_NO_FEEDBACK` 仅返回 E 类记录
- 口径变更后须 `fullRebuild=true` 重跑快照

### 2.5 有任务未查看明细（回归）
- 前置：执行 `refreshSnapshot` 写入 `task_stats_snapshot_not_viewed`（部门汇总行含 `not_viewed_personnel_json`）；DTS 在职 A、B 同部门；A 在 **taskMonth 内任一日**（非仅统计日）登录，B 整月未登录 → 该部门 `not_viewed_count=1`，JSON 含 B（不含 A）
- 请求：`POST /sales/task/statistics/cards/detail`，`cardType=NEVER_VIEWED`，`taskMonth=当前月`
- 预期：`records` 仅含 B；`total` 与 cards `neverViewedCount` 一致；响应 P95 仅查快照表（无 DTS 全量扫描）
- 回归（月维度）：A 仅在月初登录、统计日未登录，刷新后 A **仍不算**未查看
- 回归（keywords）：传 `keywords` 后仅返回姓名/工号/职位/归属部门编码或名称**任一包含**关键字的人员；`/cards/export` 同 Body 导出行一致
- 导出：`POST /sales/task/statistics/cards/export`，同参数；CSV 首行表头为 `姓名,工号,职位,归属部门`（与前端 NEVER_VIEWED 列表列一致）
- 未刷新快照：返回空分页（非实时兜底）

---

## 三、接口用例（节选）

### 3.1 架构树 `POST /sales/task/statistics/deptTree`

数据范围取营销系统子树（`op.config.marketingDepartmentCode`），再按当前账号数据资源权限裁剪，最后按 `op.config.filterDeptCodes` 剔除配置部门及其全部子部门。

**配置示例**

```yaml
op:
  config:
    # 未配置时使用下列默认黑名单；配置后覆盖默认值（非追加）
    filter-dept-codes:
      - "355661798"
      - "582580487"
      - "931062135"
      - "812864210"
      - "715512578"
      - "630031838"
      - "629770317"
      - "582659469"
```

**权限规则**

| 账号权限 | 返回 |
| --- | --- |
| 管理员（`sales-task-admin`）或未启用 OP / 无 accountCode | `{ "list": [ 营销系统根 + 完整子树 ] }`（外层塞营销系统） |
| 有部门权限（`sls-sales-task-dept` 各层 key + 登录人挂载部门 + 管理部门） | `{ "list": [ 有权限部门… ] }`，**不**含营销系统根；命中权限的部门**提升为 list 根**并**连同其全部子部门**展示；**不**保留无权限祖先 |
| 无任何部门权限 | `{ "list": [] }` |
| 仅登录人本部门（如 `911615779`），祖先为 `59310057` | `{ "list": [ { "deptCode": "911615779", ... } ] }`，根为本人部门，**不是**祖先 `59310057` |
| 登录人挂载部门之外还管理多个部门 | `{ "list": [ 挂载部门, 管理部门… ] }`，每个有权限部门各自提升为 list 根 |

**filterDeptCodes 规则（在权限裁剪之后执行）**

| 配置 | 行为 |
| --- | --- |
| 未配置或空 | 不做额外过滤 |
| 命中某 `deptCode` | 该部门节点及其 `subDeptList` 整棵子树均不返回 |
| 管理员且营销系统根在黑名单 | `{ "list": [] }` |

```json
{
  "deptCode": "573551785" // 兼容字段，已忽略
}
```

**响应示例（非管理员有权限：有 `715326994` 则该节点提升为 list 根，其下 EHR 子树全量返回）**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "list": [
      {
        "deptCode": "715326994", // 有权限部门作为根，不再包一层无权限祖先
        "deptName": "xx大区",
        "subDeptList": [
          {
            "deptCode": "32806049", // 子部门随完整子树返回
            "deptName": "子部门A",
            "subDeptList": []
          }
        ]
      }
    ]
  }
}
```

**回归：仅登录人本部门权限时，根为本人部门**

前置：`opUser.deptCode=911615779`，数据资源无额外部门；组织路径含祖先 `59310057 → … → 911615779`。

请求：

```json
{}
```

期望响应根节点为 `911615779`（不是 `59310057`）：

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "list": [
      {
        "deptCode": "911615779", // 登录人本部门，作为 list 根
        "deptName": "本人所属部门",
        "subDeptList": [] // 若有子部门则完整返回
      }
    ]
  }
}
```

说明：前端默认选中 `list[0].deptCode` 后请求 cards 时，`requestCodes` 与 `permittedCodes` 均为 `911615779`，不再出现「请求部门与权限部门无交集」。

**回归：管理部门并入权限部门树与统计拦截**

前置：`opUser.deptCode=通州销售组编码`，`opUser.userId`（或请求头 `userId`）为该用户 userId。EHR `POST /ehr/api/contact/v1/departments/list` 请求体为按负责人查询未删除部门，返回其管理的「市区销售2组」「通州销售组」。数据资源无额外部门。

管理部门查询请求：

```json
{
  "list": [10001], // fieldType 对应的取值，此处为当前用户 userId（部门负责人）
  "fieldType": 2, // 2=deptLeaderId，对应 user 表 userId
  "status": 0 // 0=未删除；-1=已删除；不传则返回全部
}
```

期望 `deptTree` 的 `list` 同时包含挂载部门与管理部门（重复编码只出现一次），且 cards 等走 `applyDeptScope` 的接口：请求管理部门编码放行，请求权限集合外的部门返回无数据。EHR 查询失败时仍保留挂载部门权限，不把已有权限清空。

### 3.2 统计卡片 `POST /sales/task/statistics/cards`

读 `task_stats_snapshot_summary` 聚合；「有任务未查看」读 `task_stats_snapshot_not_viewed`；卡片明细弹窗走 `/cards/detail`（`NEVER_VIEWED` 返回未登录人员列表，其它卡片查任务明细）。

**请求 Body**

```json
{
  "page": 1,                    // 可选，cards 不分页，继承公共字段可省略
  "pageSize": 20,               // 可选，cards 不分页，继承公共字段可省略
  "deptCode": "573551785",      // 可选，架构树选中部门；与 OP 权限取交集后过滤快照
  "taskMonth": "2026-06",       // 可选，任务截止月份 yyyy-MM，默认当前月
  "objectCode": "STORE",        // 可选，任务对象 STORE/DEALER/PERSON 等；不传汇总全部对象
  "taskExecutionType": null,    // 可选，任务执行类型编码
  "taskPackageId": null,        // 可选，任务包 ID
  "taskDefId": null,            // 可选，子任务 ID
  "taskRuleId": null            // 可选，任务规则 ID
}
```

**响应 Body**

```json
{
  "code": 0,                    // 业务码，0=成功
  "message": "success",         // 提示信息
  "data": {
    "statDate": "2026-06-29",              // 快照统计日；当月/未来月=今天，历史月=该 task_month 下 MAX(stat_date)
    "dataUpdatedAt": "2026-06-29T14:30:00", // 快照 summary 行最近 updated_at（多行取最大）

    "totalCount": 1000,                    // 【总任务数】进行中+已完成+已过期+已关闭之和
    "completedCount": 600,                 // 【已完成】status=COMPLETED 的任务数
    "inProgressCount": 200,                // 【进行中】status=IN_PROGRESS 的任务数
    "expiredCount": 150,                   // 【已过期】status=EXPIRED 的任务数
    "closedCount": 50,                     // 【已关闭】status=CLOSED 的任务数

    "completionRate": 0.6,                 // 【完成率】completedCount/totalCount，0~1，前端展示 ×100%
    "timelinessRate": 0.85,                // 【反馈率】timelinessNumerator/timelinessDenominator，0~1（字段名历史保留）

    "storeVisitedInProgressCount": 80,       // 【已巡店进行中】门店：last_visit_closed_time>start_time 且 status 为 IN_PROGRESS 或 EXPIRED
    "storeVisitedNoFeedbackCount": 20,       // 【已巡店无反馈】门店：需反馈(feedbackEnabled=true)、已巡店、无 feedback_reason、未完成/未关闭
    "storeNotVisitedExpiredCount": 30,       // 【未巡店已过期】门店：未巡店或 visit<start_time 且 EXPIRED

    "neverViewedCount": 3,                   // 【有任务未查看】人数（单位「人」）；在职客户代表/区域业代 − 当月（taskMonth）内任一日 getToken 登录人数
    "neverViewedCountDod": 1,                // 【有任务未查看较昨日】人数差(今−昨)；例 34→35 人为 1，51→0 人为 -51
    "neverViewedSupported": true,            // 【有任务未查看已接入】固定 true；false 表示历史版本未接入

    "inProgressRateDod": -2.4,               // 【进行中较昨日】(今占比−昨占比)×100
    "completedRateDod": -1.1,                // 【已完成较昨日】(今占比−昨占比)×100
    "storeVisitedInProgressRateDod": -2.4,   // 【已巡店进行中较昨日】(今占比−昨占比)×100
    "storeVisitedNoFeedbackRateDod": 0.5,    // 【已巡店无反馈较昨日】(今占比−昨占比)×100
    "closedRateDod": -0.8,                   // 【已关闭较昨日】(今占比−昨占比)×100
    "expiredRateDod": 1.2,                   // 【已过期较昨日】(今占比−昨占比)×100
    "timelinessRateDod": 1,                  // 【反馈率较昨日】例：0.34→0.35 → (0.35-0.34)×100=1
    "storeNotVisitedExpiredRateDod": -1.5,   // 【未巡店已过期较昨日】(今占比−昨占比)×100

    "statusBreakdown": [                     // 【状态环图】四态分布，percent 之和约等于 1
      {
        "status": "COMPLETED",               // 状态编码
        "statusName": "已完成",               // 状态中文名
        "count": 600,                        // 该状态任务数
        "percent": 0.6                       // 占 totalCount 比例 0~1
      },
      {
        "status": "IN_PROGRESS",
        "statusName": "进行中",
        "count": 200,
        "percent": 0.2
      },
      {
        "status": "EXPIRED",
        "statusName": "已过期",
        "count": 150,
        "percent": 0.15
      },
      {
        "status": "CLOSED",
        "statusName": "已关闭",
        "count": 50,
        "percent": 0.05
      }
    ]
  }
}
```

**字段与 UI 卡片对照**

| UI 卡片 | 主数值 | 占比（前端自算） | 较昨日箭头 |
|---------|--------|------------------|------------|
| 总任务数 | `totalCount` | — | — |
| 进行中 | `inProgressCount` | count/totalCount | `inProgressRateDod` |
| 已完成 | `completedCount` | count/totalCount | `completedRateDod` |
| 已巡店进行中 | `storeVisitedInProgressCount` | count/totalCount | `storeVisitedInProgressRateDod` |
| 已巡店无反馈 | `storeVisitedNoFeedbackCount` | count/totalCount | `storeVisitedNoFeedbackRateDod` |
| 已关闭 | `closedCount` | count/totalCount | `closedRateDod` |
| 已过期 | `expiredCount` | count/totalCount | `expiredRateDod` |
| 反馈率 | `timelinessRate` | 已是 rate | `timelinessRateDod` |
| 有任务未查看 | `neverViewedCount` | 人数，非占比 | `neverViewedCountDod` |
| 未巡店已过期 | `storeNotVisitedExpiredCount` | count/totalCount | `storeNotVisitedExpiredRateDod` |
| 完成率（环图旁） | `completionRate` | 已是 rate | — |

> `neverViewedCount` 不受 `objectCode`/`taskPackageId` 等任务维度筛选影响，仅按部门权限（`owning_department_code` + `department_path_json`）过滤。

### 3.3 卡片明细 `POST /sales/task/statistics/cards/detail`

- **任务类卡片**（`TOTAL`/`FEEDBACK_RATE`/`IN_PROGRESS`/`COMPLETED`/门店巡店等）：实时查询 `task_distribution_detail`；`data.records[]` 为 **`TaskDistributionDetailDTO`**，经 `toListDisplayDtos` 组装，字段与 `POST /sales/task/distribution/detail/list` 单条 record **完全一致**（含 `taskPackage[0].taskGroupId` / `taskGroupName`，供前端「关联任务组」列）。
- **维度筛选**（与 cards 快照一致，AND）：`objectCode` / `taskExecutionType` / `taskPackageId` / `taskDefId`；`taskRuleId` 经 `task_definition.rule_id` 过滤（明细表无该列）。注意：`taskRuleId` 与结果里的 `taskDefId` 是不同实体 ID，数值不会相等；传 `taskRuleId` 后返回的明细其关联 TASK 的 `rule_id` 应等于入参。
- **`TOTAL`（总任务数）**：与 `overview.cards.totalCount` / `cards.totalCount` 口径一致；仅月份扫描 + 维度/部门筛选，**不**额外锁 `status`；`total` 应对齐同筛选下卡片总任务数。
- **`FEEDBACK_RATE`（反馈率）**：返回反馈率**分子**明细——关联 `task_definition.task_type=TASK` 且 `feedback_enabled=true`，且 `feedback_reason` 非空；与 `timelinessRate`（=`timelinessNumerator`/`timelinessDenominator`）分子口径一致。
- **`NEVER_VIEWED`（有任务未查看）**：读 **`task_stats_snapshot_not_viewed`** 部门汇总行，cards 人数 `SUM(not_viewed_count)`；明细分页展开 `not_viewed_personnel_json`（元素含 `user_master_id`/`user_name`/`employee_number`/`position`），部门信息取自汇总行。可选 **`keywords`**：对姓名 / 工号 / 职位 / 归属部门编码或名称做**模糊包含**匹配（**OR**）；明细与导出共用同一过滤。

```json
{
  "page": 1, // 页码，默认 1
  "pageSize": 20, // 每页条数，默认 20
  "deptCode": "D001", // 部门编码（权限裁剪，可选）
  "taskMonth": "2026-06", // 任务截止月份；用于解析 statDate（与 cards 一致）
  "objectCode": "STORE", // 任务类卡片必传；NEVER_VIEWED 可省略（不参与过滤）
  "cardType": "NEVER_VIEWED", // 有任务未查看
  "keywords": "张三" // 可选；模糊匹配姓名/工号/职位/归属部门编码或名称（OR）
}
```

**总任务数明细请求示例：**
```json
{
  "page": 1, // 页码，默认 1
  "pageSize": 20, // 每页条数，默认 20
  "deptCode": "D001", // 部门编码，可选
  "taskMonth": "2026-06", // 任务截止月份 yyyy-MM
  "objectCode": "STORE", // 任务对象，可选（与 overview 筛选一致）
  "cardType": "TOTAL" // 总任务数明细
}
```

**反馈率明细请求示例：**
```json
{
  "page": 1, // 页码，默认 1
  "pageSize": 20, // 每页条数，默认 20
  "deptCode": "D001", // 部门编码，可选
  "taskMonth": "2026-06", // 任务截止月份 yyyy-MM
  "objectCode": "STORE", // 任务对象，可选
  "cardType": "FEEDBACK_RATE" // 反馈率分子明细（需反馈 TASK 且已填 feedback_reason）
}
```

**NEVER_VIEWED 响应示例：**
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "records": [
      {
        "userMasterId": "UM001", // 人员主数据ID
        "name": "张三", // 姓名
        "employeeNumber": "E10001", // 工号
        "position": "客户代表", // 职位
        "owningDepartmentCode": "D001", // 归属部门编码
        "owningDepartmentName": "销售组A", // 归属部门名称
        "departmentPathJson": "[\"573551785\",\"D001\"]" // 部门路径JSON
      }
    ],
    "total": 3,
    "page": 1,
    "pageSize": 20,
    "totalPage": 1
  }
}
```

**任务类卡片**请求示例：
```json
{
  "page": 1,
  "pageSize": 20,
  "deptCode": "D001",
  "taskMonth": "2026-06",
  "objectCode": "STORE",
  "cardType": "STORE_VISITED_IN_PROGRESS"
}
```

响应示例（结构同任务明细 list，仅示意关键字段）：
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "records": [
      {
        "id": 1001,
        "targetEntityName": "某某门店",
        "targetEntityCode": "S001",
        "owningDepartmentName": "销售组A",
        "taskTitle": "陈列检查",
        "taskDescription": "…",
        "taskExecutionTypeName": "陈列",
        "status": "IN_PROGRESS",
        "createdBy": "张三",
        "lastVisitClosedTime": "2026-06-15 10:00:00",
        "taskPackage": [
          {
            "id": 10, // 任务包 ID
            "taskName": "6月门店任务包", // 任务包名称
            "taskGroupId": 3, // 关联任务组 ID（PACKAGE.task_group_id）
            "taskGroupName": "华东陈列组" // 关联任务组名称（批量回填）
          }
        ],
        "taskDefinition": [ { "id": 101, "taskCode": "T001", "taskTitle": "陈列检查" } ]
      }
    ],
    "total": 100,
    "page": 1,
    "pageSize": 20,
    "totalPage": 5
  }
}
```

`POST /sales/task/statistics/cards/export`：
- **任务类卡片**：导出列与 `POST /sales/task/distribution/detail/export` **一致**，中文表头与前端明细列表对齐：`对象名称,对象编码,归属部门,最近拜访时间,任务,任务编码,任务说明,任务类型,关联任务组,状态,下发人,开始时间,截止时间,反馈原因,关联任务规则`（15 列）；**流式导出**：按主键游标 `id > lastId` 分批查库（每批最多 10000 条）边查边写，**不在内存中一次性加载全量明细**；`page`/`pageSize` 无效。
- **`NEVER_VIEWED`**：导出 CSV 中文表头 `姓名,工号,职位,归属部门`（与前端列表列一致）；`page`/`pageSize` 无效，导出全量。

### 3.4 趋势 `POST /sales/task/statistics/executionTrend`
返回 MTD 日序列。与 **cards 字段对应关系**：

| executionTrend | cards 对应 | Job 生成口径（读 `trend_daily`） |
|----------------|-----------|--------------------------------|
| `totalCount` | `totalCount` | 当月明细总数；读 `trend_date=stat_date` 库存行 SUM；历史日向前沿用（只增不减） |
| `feedbackRequiredCount` | `timelinessRate` 分母 | 需反馈 TASK 明细数；同上 |
| `feedbackCount` | `timelinessRate` 分子 | 需反馈且 `feedback_reason` 非空；写入 `trend_date=stat_date` 库存行；历史日向前沿用 |
| `completedCount` | `completedCount`（`date=stat_date` 累计值应对齐） | MTD 前缀和：有 `final_end_time` 按完成日，否则按 `stat_date`；**只读完成事件行，不读库存行** |

- **完成率** = `completedCount / totalCount`
- **反馈率** = `feedbackCount / feedbackRequiredCount`

**部门过滤**：`owningDepartmentCode` 存的是明细**归属末级部门**；选「营销」等上级时靠  
`owning_department_code IN (...) OR JSON_CONTAINS(department_path_json, 上级编码)`。  
Job 须写入 `department_path_json`（与 summary 同源）；历史空路径数据需重跑快照后上级筛选才生效。

```json
{
  "statDate": "2026-06-29",
  "points": [
    { "date": "2026-06-01", "completedCount": 10, "totalCount": 200, "feedbackCount": 3, "feedbackRequiredCount": 100 },
    { "date": "2026-06-02", "completedCount": 18, "totalCount": 200, "feedbackCount": 5, "feedbackRequiredCount": 100 }
  ]
}
```

### 3.5 反馈分布 `POST /sales/task/statistics/feedbackReasonDistribution`

读 `task_stats_snapshot_feedback_reason`；部门过滤与 cards/executionTrend 相同：  
`owning_department_code IN (...) OR JSON_CONTAINS(department_path_json, …)`。  
Job 须写入 `department_path_json`；历史空路径需重跑快照。
### 3.6 任务类型 `POST /sales/task/statistics/taskTypeBreakdown`
已指定 `taskExecutionType`/`taskPackageId`/`taskDefId` 时 `hidden=true`。

### 3.7 组织表现 `POST /sales/task/statistics/orgPerformance`

**`deptCode`**：架构树选中部门；**`orgPerformance` / `packagePerformance` / overview 中对应模块** 未传时默认 **`op.config.marketingDepartmentCode`（营销中心）**。

| 场景 | 数据来源 | 说明 |
|------|----------|------|
| 非末级部门 | `task_stats_snapshot_org_perf` | `parent_department_code = deptCode`，返回下一级部门（`org_code`/`owning_department_code`）聚合 |
| 末级部门（Infra `deptLevel = 6`） | 实时查 `task_distribution_detail` | 按 `targetEntityCode` 聚合；筛选 `end_time` 落在 `taskMonth` 对应自然月（非明细 `task_month` 字段） |

**快照写入口径**（Job）：`department_path_json` 来自 DTS `dept_parent_path`，**通常不含当前归属部门**；写 org_perf 时先拼完整链路 `chain = path + owning_department_code`（末级已等于 owning 则不重复追加），再对相邻层级 `(chain[i], chain[i+1])` 写入一行。例：path `["营销中心","华东","上海作战部"]`、owning `销售组A` → 含 `(上海作战部→销售组A)`；`parent_department_code=chain[i]`，`org_code=chain[i+1]`。同一 parent 下多任务维度行在读接口按 `org_code` 合并。

### 3.8 任务包表现 `POST /sales/task/statistics/packagePerformance`

| 场景 | 数据来源 | 说明 |
|------|----------|------|
| 非末级部门 | `task_stats_snapshot_package_perf` | `parent_department_code = deptCode`，读侧按 `taskPackageId` 合并分子分母后重算完成率/反馈率 |
| 末级部门（Infra `deptLevel = 6`） | 实时查 `task_distribution_detail` | 按 `taskPackageId` 聚合；`end_time` 落在 `taskMonth` 自然月 |

**快照写入口径**（Job）：与 org_perf 相同按部门链 `(parent→child)` 多视角写入；读接口在选中 `deptCode` 视角下合并同一任务包各分桶的 `total_count`/`completed_count`/`timeliness_*` 后计算比率。

```json
{
  "deptCode": "573551785", // 可选；不传默认营销中心
  "taskMonth": "2026-06",
  "objectCode": "STORE",
  "page": 1,
  "pageSize": 20
}
```
### 3.9 聚合 `POST /sales/task/statistics/overview` — 与分接口字段等价

读快照时 `stat_date` 按 `taskMonth` 自动解析（见变更说明）；历史月查询不再因固定「今天」而查不到数据。

### 3.10 下拉 `POST /sales/task/statistics/taskPackageOptions` / `taskGroupOptions`

- **任务统计页「任务规则」筛选项（2026-08-19）**：前端文案仍为「任务规则」，数据源与筛选参数为**任务包规则**——走 `taskPackageOptions`，选中值传 `taskPackageId`（不再走 `taskRuleOptions` / `taskRuleId`）。
- `taskPackageOptions`：Body 同 overview 维度 + 可选 `keyword`（包名称模糊）+ 可选 `taskGroupId`（按 `package_perf.task_group_id` 精确过滤）；返回 `{ id, name }[]`，最多 50 条。
- **任务组联动（2026-09-02）**：顶部筛选与卡片明细弹窗选中任务组后，拉「任务规则」须带当前 `taskGroupId`；换组清空已选 `taskPackageId`；未选任务组不传 `taskGroupId`，仍返回该部门/月份/对象/类型视角下全部包。
- `taskGroupOptions`：任务组下拉，同上维度 + `keyword`；**不要**传 `taskGroupId`（否则下拉只剩当前组）。
- **末级部门（2026-08-27）**：`deptLevel=6` 时两接口按 `owning_department_code = deptCode` 查快照；非末级仍 `parent_department_code = deptCode`。

`taskPackageOptions` 请求示例（已选任务组）：
```json
{
  "deptCode": "D001", // 当前选中部门编码
  "taskMonth": "2026-09", // 任务截止月份 yyyy-MM
  "objectCode": "STORE", // 可选；任务对象
  "taskExecutionType": "TOUR", // 可选；任务类型
  "taskGroupId": 10001, // 可选；选中任务组后传入，仅返回该组下任务包
  "keyword": "巡店" // 可选；任务包名称模糊
}
```
响应示例：
```json
{
  "code": 0, // 0 成功
  "message": "success", // 提示文案
  "data": [
    {
      "id": 58, // 任务包 id（task_definition.id，task_type=PACKAGE）
      "name": "巡店任务包A" // 任务包名称
    }
  ]
}
```

`taskRuleOptions` 仍保留供其它场景；任务统计顶栏不再调用。

### 3.11 手动刷新快照 `POST /sales/task/statistics/refreshSnapshot`
```json
{
  "taskMonths": ["2026-06"], // 任务截止月份，可空默认本月起共未来6个月（含本月）；自然日<16 时额外含上月
  "statDate": "2026-06-29", // 快照统计日，可空：当月/未来月默认今天，历史月默认该月最后一天
  "objectCodes": ["STORE"], // 对象编码，可空或 [] 表示全量
  "fullRebuild": true // 是否全量校准（影响历史月 GC 范围），可空默认 true；版本指针下始终先写新 build 再切指针
}
```
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "accepted": true, // 是否已受理异步刷新
    "statDate": "2026-06-29",
    "taskMonths": ["2026-06"],
    "objectCodes": ["STORE"],
    "fullRebuild": true,
    "message": "已受理异步刷新，执行结果见日志"
  }
}
```
重复点击（同 OP 账号 + 同请求参数且上次尚未执行完）：仍返回 `accepted: true`，`message` 为「刷新任务进行中或刚提交过，已忽略重复点击」，不再次触发 Job。

每个 `taskMonth`：若无匹配任务包明细（`end_time` 落在该月且 `task_package_id>0`，及可选 `objectCodes`），则**跳过**该月的聚合、落库、指针切换与未查看快照（保持原指针）。

---

## 四、权限回归
| 场景 | 预期 |
|------|------|
| 管理员 | 不过滤部门 |
| 单部门权限 | 仅本部门及子路径快照 |
| 多部门 | 并列根 + 并集查询 |
| 无权限 | 空分页/全 0 |
| 请求 dept 超范围 | 空结果 |

---

## 五、对账（TPS-023）
刷新完成后，随机抽 `deptCode + taskMonth`：
```sql
-- summary.total_count 应等于明细 COUNT（同部门谓词 + task_month）
SELECT SUM(total_count) FROM task_stats_snapshot_summary
 WHERE stat_date = ? AND task_month = ? AND owning_department_code = ?;
-- 与 task_distribution_detail 实时 COUNT 误差为 0
```

---

## 六、前端对接附录（TPS-022）
| UI 模块 | 接口 |
|---------|------|
| 顶部筛选 | deptTree + taskGroupOptions + taskPackageOptions（选组后带 taskGroupId） |
| 状态环图 | cards.statusBreakdown |
| 8 指标卡 | cards.*Count + *RateDod（较昨日）+ neverViewedCount |
| 趋势折线 | executionTrend |
| 反馈列表 | feedbackReasonDistribution |
| 类型环图+柱图 | taskTypeBreakdown |
| 组织列表 | orgPerformance |
| 任务包表格 | packagePerformance |

路由建议：任务中心 / 任务统计；筛选变更后并行 `overview` 或分模块请求。

---

## 七、性能（TPS-024）
- Job：id 游标分批 5000 条/批；百万明细单调度目标 < 10min
- 读接口 P95 < 500ms（仅快照表 + 索引）
- 索引见 `dpc/sql/update_tables.sql` 2026-06-29 任务包统计索引补充段，摘要如下：

| 表 | 索引 | 用途 |
|----|------|------|
| `task_distribution_detail` | `idx_detail_stats_snap_job (task_month,id)` | 快照 Job 游标扫描 |
| `task_distribution_detail` | `idx_detail_stats_snap_job_obj (task_month,object_code,id)` | Job 按对象过滤扫描 |
| `task_distribution_detail` | `idx_detail_stats_card_list (task_month,object_code,status,id)` | 卡片明细分页 |
| `task_stats_snapshot_summary` | `idx_summary_stat_query_obj_dept` 等 | cards / taskTypeBreakdown / 筛选 |
| `task_stats_snapshot_summary` | `idx_summary_stat_rule` | taskRuleOptions |
| `task_stats_snapshot_trend_daily` | `idx_trend_stat_query_obj_dept` | executionTrend |
| `task_stats_snapshot_feedback_reason` | `idx_feedback_stat_query_obj_dept` | feedbackReasonDistribution |
| `task_stats_snapshot_org_perf` | `idx_org_perf_stat_query_sort` | orgPerformance 排序 |
| `task_stats_snapshot_package_perf` | `idx_pkg_perf_stat_query_sort` | packagePerformance 排序 |
| `task_user_login_record` | `uk_user_master_login_date` | getToken 登录 upsert |
| `task_user_login_record` | `idx_login_date` / `idx_login_date_user_master` | 快照 Job 按 **taskMonth** 月区间查已查看人员 |
| `task_user_login_record` | `idx_login_dept_path_json_mvi` | 部门路径 JSON_CONTAINS（预留） |
| `task_stats_snapshot_not_viewed` | `uk_not_viewed_stat_month_dept` | Job 写入唯一键；部门 IN 过滤 |
| `task_stats_snapshot_not_viewed` | `idx_not_viewed_stat_month` | cards SUM：`stat_date` + `task_month` |
| `task_stats_snapshot_not_viewed` | `idx_not_viewed_task_month` | Job 按月删除 `deleteByTaskMonth` |
| `task_stats_snapshot_not_viewed` | `idx_not_viewed_stat_month_dept_name` | NEVER_VIEWED 明细 `ORDER BY owning_department_name` |
| `task_stats_snapshot_not_viewed` | `idx_not_viewed_dept_path_json_mvi` | 部门路径 `JSON_CONTAINS` 过滤 |
| 各快照表 | `*_dept_path_json_mvi` | JSON_CONTAINS 部门路径过滤 |
