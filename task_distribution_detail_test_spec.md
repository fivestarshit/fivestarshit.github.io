# 任务下发明细测试规格（明细数据 + 条件匹配）

> 由原 `task_distribution_detail_*_test_spec` 合并，去除日期后缀。

---

## 第一篇：明细触发、API 与 Action 同步

### 功能模块：任务下发明细触发

### 一、业务说明

遍历 TaskInstance 数据，判断任务包类型，在到达下发时间（distributed_at）时触发创建 task_distribution_detail。任务包下若有多个普通任务(TASK)，则为每个(任务包+普通任务+目标实体)创建一条明细，分别关联 task_package_id 和 task_def_id。

表字段 **`object_code`**：对象编码语义，与 `task_definition.object_code` 一致；接口返回 `TaskDistributionDetailDTO` 时带出 `objectCode`（表已无 `object_type` 列）。

### 二、定时任务

- 原 XXL-JOB `triggerTaskDistributionDetail`（扫描 PENDING 实例并下发明细）已移除，对应 `TaskDistributionTriggerService` 已删除；本模块其余 Job 见 `TaskDistributionDetailJob`：`syncPackageTaskStatusCompleted`（扫描进行中任务包，子 TASK 全部到期则 TASK 过期、子 TASK 全部 EXPIRED 则 PACKAGE 过期）、**`expireInProgressDetailsPastEndTime`**（按明细 `end_time` 全表批量过期进行中明细，可与前者分调度并存）、`syncReadyPackagesAndTasksToInProgress`、`syncInProgressPackagesByCrowd`、`refreshInProgressPackageCronDistributedAt`、`completeInProgressDetailsByCrowdForCronCompletionJudgment`（CRON 完成判断 + 分群 latest 批量明细完成）、`scanInProgressTaskDelaySyncStrategy`、**`syncTaskDistributionDetailOwningDepartment`**（补全归属部门与部门路径）、**`refreshTaskDistributionDetailStatusStatsCache`**（预热 `statusStats` / `statusStatsByListByPackage` 两处 Redis）等。

### 三、任务包解析

- **用例2：任务包类型识别**
  - 通过 task_rule_id → task_definition.rule_id（或 task_template_definition.rule_id）→ task_definition 解析
  - 若 task_def 的 task_type=PACKAGE，则视为任务包
  - 若 task_def 为 ACTION/TASK 且有 parent_id，则取父级为任务包
  - 预期：非任务包类型实例不触发明细创建

### 四、幂等与去重

- **用例3：已下发明细的实例跳过**
  - 若 task_distribution_detail 中已存在该 task_instance_id 的记录，则跳过创建
  - 仍将实例 status 更新为 DISTRIBUTED
  - 预期：不重复插入明细

- **用例4：唯一键冲突处理**
  - 表唯一键：以库表为准，含 `uk_task_pkg_def_target_code`（`task_package_id`, `task_def_id`, `target_entity_code`）及 `uk_task_pkg_def_obj_end_start`（`task_package_id`, `task_def_id`, `object_code`, `end_time`, `start_time`）等（详见 `doc/sql/update_tables.sql`）
  - 插入时若发生唯一键冲突，跳过该条，继续插入其余
  - 预期：不因单条冲突导致整体失败

### 五、TaskPackageFilterService（占位实现）

- **用例5：占位筛选逻辑**
  - 若任务实例 target_entity_id 非 PENDING，则返回该实体作为筛选结果
  - 否则返回空列表
  - 预期：后续可扩展基于 condition_ids、condition_repo 的真实筛选

### 六、多任务明细

- **用例6：任务包下多个普通任务**
  - 任务包 P 下有普通任务 T1、T2，筛选得到实体 E1、E2
  - 预期：创建 2×2=4 条明细：(P,T1,E1)、(P,T1,E2)、(P,T2,E1)、(P,T2,E2)

- **用例7：任务包下无普通任务**
  - 任务包 P 下无 task_type=TASK 子任务
  - 预期：每条目标实体创建 1 条明细，task_def_id=task_package_id

### 七、数据校验

- **用例8：task_distribution_detail 字段**
  - task_package_id、task_def_id、object_code、target_entity_type 等按业务非空；`task_instance_id`、`target_entity_id` 默认可空（如分群下发时销客未返回可先落库，后续刷数补全）
  - status 默认 IN_PROGRESS
  - `start_time`、`end_time` 可空；触发下发创建明细时从对应子任务 `task_definition.start_time` / `end_time` 冗余写入；手工创建接口可选传，不传则从 `task_definition` 继承
  - 预期：插入记录符合表结构约束

### 八、API 接口

- **用例9：新增任务下发明细**
  - 接口：`POST /task/distribution/detail/create`
  - 请求 Body 示例：
    ```json
    {
      "taskDefId": 2,
      "taskInstanceId": 100,
      "objectCode": "STORE",
      "targetEntityType": "STORE",
      "targetEntityId": "S001",
      "targetEntityName": "某某门店",
      "targetEntityCode": "STORE001",
      "executorId": "USER001",
      "executorName": "张三",
      "startTime": "2026-03-01T00:00:00",
      "endTime": "2026-03-31T23:59:59"
    }
    ```
  - 字段说明：`startTime` / `endTime` 为可选；不传则从关联 `task_definition` 的 `start_time` / `end_time` 写入明细表。
  - 必传：taskDefId、taskInstanceId、objectCode、targetEntityType
  - 可选：targetEntityId（未传时使用 taskInstanceId_taskDefId 占位）、targetEntityName、targetEntityCode、executorId、executorName、startTime、endTime
  - 预期结果：返回 `Response.success`，data 为新建记录的自增 id

- **用例10：查询任务下发明细详情**
  - 接口：`POST /task/distribution/detail/detail`
  - 请求 Body：`{ "id": 1 }`
  - 返回包含：taskPackage（任务包列表）、taskDefinition（普通任务列表）；`taskInstance` 不集成（为 null）
  - 预期结果：返回 `Response.success`，data 为 `TaskDistributionDetailDTO`

- **用例11：按 target 全量查询并按聚合方式分组（detailByTarget）**
  - 接口：`POST /task/distribution/detail/detailByTarget`
  - 请求 Body 示例：
    ```json
    {
      "targetEntityId": "S001",
      "targetEntityCode": "STORE001",
      "//targetEntityName": "可选：精准等于 target_entity_name（trim）；与 targetEntityCode 均传且无 targetEntityId 时为 OR",
      "aggregationFilter": "EXECUTION_TYPE",
      "startTime": "2025-01-01 00:00:00",
      "endTime": "2025-12-31 23:59:59",
      "status": "IN_PROGRESS",
      "taskExecutionType": "VISIT"
    }
    ```
  - 必传：aggregationFilter（EXECUTION_TYPE 或 PACKAGE）；targetEntityId、targetEntityCode、targetEntityName 至少传一个
  - aggregationFilter=EXECUTION_TYPE：按 taskExecutionTypeName 分组，groupKey 为类型名，groupId 为 null
  - aggregationFilter=PACKAGE：按 taskPackageId 分组，groupKey 为包 ID 字符串，groupId 为 taskPackageId
  - 可选筛选：startTime、endTime、status、taskExecutionType；目标条件为列 **精准匹配**（trim），无 id 且编码+名称均传时为 `(code OR name)`；有 id 时与编码/名称组合见服务层 `applyDetailByTargetEntityMatch`
  - 预期结果：返回 `List<TaskDistributionDetailAggregatedGroupDTO>`，每条含 groupKey、groupId、list（单条为 `TaskDistributionDetailDTO`，字段形态与 detail 接口一致，为全量关联填充，**与用例12 普通 `/list` 的轻量 `taskDefinition`/`taskPackage` 不同**）
  - 回归：去除分页，全量查询；aggregationFilter 必填且仅支持 EXECUTION_TYPE、PACKAGE

- **用例12：查询任务下发明细列表（分页）**
  - 接口：`POST /task/distribution/detail/list`
  - 必传：`objectCode`（对象编码，与 `task_definition.object_code` 一致）
  - 请求 Body 示例：
    ```json
    {
      "page": 1,
      "pageSize": 20,
      "objectCode": "STORE",
      "taskPackageId": 1,
      "taskDefId": 2,
      "taskInstanceId": 100,
      "targetEntityType": "STORE",
      "targetEntityId": "S001",
      "targetEntityCode": "WD35025932",
      "//targetEntityCode": "可选：精准等于 target_entity_code（trim）；与 targetEntityName 均传时为 (code OR name)",
      "targetEntityName": "某某门店全称",
      "//targetEntityName": "可选：精准等于 target_entity_name（trim）；与编码均传时为 OR",
      "taskName": "陈列",
      "//taskName": "可选：任务名称模糊（明细 task_title 或子任务定义 task_name，LIKE %值%，trim）",
      "status": "IN_PROGRESS",
      "taskExecutionType": "MANUAL",
      "//taskExecutionType": "可选：任务执行类型编码，精准匹配 task_execution_type（trim）",
      "startTimeFrom": "2026-03-01 00:00:00",
      "startTimeTo": "2026-03-31 23:59:59",
      "endTimeFrom": "2026-03-15 00:00:00",
      "endTimeTo": "2026-04-15 23:59:59",
      "//recentWindow": "/list 的 total 与分页仅基于「命中筛选后按 id 降序最近 10000 条」；更早明细不在结果集；/export 仍全量",
      "owningDepartmentCodes": ["97302222", "550425786"],
      "//owningDepartmentCodes": "可选：department_path_json JSON 数组与任一编码命中即保留（OR）"
    }
    ```
  - 字段说明：`objectCode` **必传**；`page` 当前页；`pageSize` 每页条数；`taskPackageId` 任务包 ID；`taskDefId` 普通任务 ID；`taskInstanceId` 任务实例 ID；`targetEntityType` 目标实体类型；`targetEntityId` 目标实体 ID（精准）；**`targetEntityCode` / `targetEntityName`**：仅传编码则 **`target_entity_code = trim(code)`**；仅传名称则 **`target_entity_name = trim(name)`**；**均传**则 **`(target_entity_code = trim(code) OR target_entity_name = trim(name))`**（**非 LIKE**）；**均不传则不按目标编码/名称筛**；**`owningDepartmentCodes`**：非空时，明细 **`department_path_json`**（JSON 数组，如 `["97302222","550425786"]`）与入参**任一** dept_code 命中即保留（`JSON_CONTAINS`，OR）；`taskName` 任务名称（**模糊**：`task_title` LIKE **或** 关联 `task_definition.task_name` LIKE，二者命中其一即可）；`status` 明细状态；**`taskExecutionType`** 任务执行类型编码（**精准匹配** `task_execution_type`，入参 **trim** 后与库值相等）；**时间（`buildListQueryWrapper`）**：**`startTimeFrom` 与 `endTimeFrom` 同时非空**时，对明细 **`end_time` 闭区间**：`end_time >= startTimeFrom AND end_time <= endTimeFrom`（此时 **`startTimeFrom` 不再**作为 `start_time` 下限，**`endTimeFrom` 不再**作为单独的 `end_time` 下限）；**否则**：`startTimeFrom`/`startTimeTo` 分别对 `start_time` 下/上界（可只传一端）；**单独**的 `endTimeFrom` 表示 `end_time` 下限（含）、`endTimeTo` 表示 `end_time` 上限（含）。**`startTimeTo`、`endTimeTo` 在「双 From 」模式下仍生效**（与上述条件 AND）。时间字符串推荐 `yyyy-MM-dd HH:mm:ss`（亦支持 ISO-8601，如 `2026-03-01T00:00:00`）。
  - 可选筛选：taskPackageId、taskDefId、taskInstanceId、targetEntityType、targetEntityId、targetEntityCode、targetEntityName、taskName、status、taskExecutionType（精准）、startTimeFrom、startTimeTo、endTimeFrom、endTimeTo、owningDepartmentCodes
  - 预期结果：返回 `Response.success`，data 为 `PageResult<TaskDistributionDetailDTO>`；**`total` ≤ 10000**（与 **`/listByPackage`** 一致：先对命中 `buildListQueryWrapper` 的明细按 **`id` 降序**仅取最近 **10000** 条，再在该子集上 `COUNT` 与分页；**非**先无筛选扫全表）；每条记录为一条下发明细（平铺 1 对 1），除表字段外填充：`taskPackage`（任务包 `TaskDefinitionDTO` 单元素列表）、`taskDefinition`（该包下全部 `task_type=TASK` 子任务）；**仅 `objectCode=STORE`** 时填充 **`lastVisitClosedTime`（最后巡店时间，`yyyy-MM-dd HH:mm:ss`；按 `target_entity_code`→`account_obj.account_no` 批量查 `last_visit_closed_time` 毫秒时间戳转换）**，其它 objectCode 为 null；**列表轻量**：`taskPackage`/`taskDefinition` 元素为 `task_definition` 主表映射，**不返回** `linkedTemplateDefinitionList`，**不返回** `completionScript`（为 null）；任务包仍填充 `packageDistributionExt`（与详情中 PACKAGE 下发扩展一致）；`taskInstance` 不集成（为 null）；**`samePackageEntityDetailList` 不填充（为 null）**，避免每行额外查库；`taskPackageFilteredDetailList` 为 null；**与** `POST .../detail`、`POST .../detailByTarget` **全量任务定义结构不同**（后者仍含关联模板、完成脚本等）；同包同目标实体下多子任务浅层列表见 **`POST .../listByPackage`** 的 `samePackageEntityDetailList`
  - 回归：仅查询 `is_deleted=0` 的明细
  - **回归（性能）**：`/list` 与 `/listByPackage` 共用「命中筛选后按 `id` 降序最近 1 万条」截取思路；仅传 `objectCode` 时依赖组合索引 `idx_detail_list_object_deleted_id`（`object_code`,`is_deleted`,`id`）等支撑内层 `WHERE` + `ORDER BY id DESC LIMIT 10000`；本页 `task_package` / `task_definition` / `package_distribution_ext` 为**按页批量查询**后组装。**`POST .../export`** 仍按筛选全量流式导出，**不使用**该 1 万条上限

- **用例12f（回归）：owningDepartmentCodes 匹配 department_path_json**
  - 入参：`objectCode` 必传，`owningDepartmentCodes`: `["97302222", "550425786"]`
  - 预期：`/list`、`/listByPackage`、`/export` 等共用 `buildListQueryWrapper` 的接口，仅返回 `department_path_json` JSON 数组**包含任一**入参 dept_code 的明细（如路径 `["ROOT","97302222","LEAF"]` 命中 `97302222`）；不传或空数组时不按部门路径筛

- **用例12a（回归）：targetEntityCode/targetEntityName 精准 + OR**
  - 入参：`objectCode` 与库中一致，`targetEntityCode` 传**与库完全一致**的门店编码，`targetEntityName` 不传
  - 预期：返回行满足 `target_entity_code = trim(入参)`；仅传 `targetEntityName` 时满足 `target_entity_name = trim(入参)`；两字段均传时满足 `(target_entity_code = trim(code) OR target_entity_name = trim(name))`

- **用例12e（回归）：startTimeFrom + endTimeFrom 同时有值 → 按明细 end_time 闭区间**
  - 入参：`objectCode` 必传，另传 `startTimeFrom`、`endTimeFrom` 均有值（如 `2026-03-01 00:00:00`、`2026-03-15 23:59:59`），不传或传空 `startTimeTo`/`endTimeTo` 亦可
  - 预期：`/list`、`/listByPackage`、`/export` 等共用 `buildListQueryWrapper` 的接口，筛选等价于 **`end_time >= startTimeFrom AND end_time <= endTimeFrom`**；**不传** `endTimeFrom` 而仅传 `startTimeFrom` 时，仍为 **`start_time >= startTimeFrom`**（与改前一致）；**`POST .../statusStatsByListByPackage`** 仅按 `objectCode` 统计，**不使用**上述时间筛选

- **用例12d（回归）：流式导出 CSV**
  - 接口：`POST /sales/task/distribution/detail/export`（**筛选字段与用例12 `POST .../list` 一致**，同一 `TaskDistributionDetailListRequest`；**必传 `objectCode`**；**不分页**，默认**按筛选全量**导出；`page`/`pageSize` **无效**）
  - 预期：`Content-Type: text/csv;charset=UTF-8`，`Content-Disposition: attachment; filename="task_detail_yyyyMMddHHmmss.csv"`，响应体为 **UTF-8 BOM**；**首行为中文表头**：`对象类型,对象名称,对象编码,归属部门,最后巡店时间,任务,任务说明,任务类型,关联任务包,状态,下发人,开始时间,截止时间,关联任务包规则`；**仅 `objectCode=STORE`** 时「最后巡店时间」列有值（DTS `account_obj.last_visit_closed_time`→`yyyy-MM-dd HH:mm:ss`），其它 objectCode 该列为空；数据列依次为明细 **`object_name`（对象类型）、`target_entity_name`（对象名称）、`target_entity_code`（对象编码）、`owning_department_name`、最后巡店时间、`task_title`、`task_description`**（任务类型列优先 **`task_execution_type_name`**，否则编码）、**关联任务包**（本行 `task_package_id` 对应 PACKAGE 的 **`task_definition.task_name`**）、**`status` 中文枚举**（进行中、已完成、已关闭、已过期）、**`created_by`（下发人）**、**`start_time`、`end_time`**（`yyyy-MM-dd HH:mm:ss`）、**关联任务包规则**（任务包 `rule_id` → **`task_rule.rule_name`**，无则 **`rule_code`**）；按 **`id` 升序**；服务端按主键游标 **`id > lastId`** 分批查询并批量解析任务包/规则及 DTS 最后巡店时间后写入，**流式输出**（**不在内存中一次性组装全量 CSV 或全表明细**）

- **用例12b：按 objectCode+targetEntityCode 去重查询下发明细（分页）**
  - 接口：`POST /sales/task/distribution/detail/listByPackage`（与网关前缀一致；若无前缀则与 `/list` 同前缀）
  - 必传：`objectCode`（与用例12一致）
  - 请求 Body：与用例12完全一致（含 `page`、`pageSize`、`objectCode` 及筛选字段）
  - 业务说明：在相同筛选条件下，**先按明细 `id` 降序取最近 10000 条**命中行，再在该子集上按 **`task_package_id` + `target_entity_code`** 分组；每个组合在该子集内取 **`id` 最大**的一条作为代表行；分页 `total` 为**该子集内**不同 `(task_package_id, target_entity_code)` 组合数（**非**全表去重；更早历史明细若未进入前 1 万条则不参与分组）。仅参与 **`task_package_id`、`target_entity_code` 均非空** 的明细分组。`records` 中每条为代表明细：`taskPackage`/`taskDefinition` 与用例12 `/list` 同为轻量；本接口**另**填充：`samePackageEntityDetailList`（仅代表行所在 **`taskPackageId`** 下任务明细，不再按实体拆分；子列表按 `task_def_id`、`id` 升序）；`taskPackageFilteredDetailList`（**同一 object_code + target_entity_code**、本页 `IN(target_entity_code)` 且仍满足列表筛选；**全量**命中行、**无 1 万条截断**，按 `task_package_id`、`task_def_id`、`id` 升序拉取后按 `target_entity_code` 拆分；**可跨多个 task_package_id**）
  - 预期结果：`PageResult` 结构与用例12 相同（`taskInstance` 不集成）；**仅 `objectCode=STORE`** 时代表行及嵌套明细含 **`lastVisitClosedTime`**，其它 objectCode 为 null；**区别**：用例12 `/list` 的 `samePackageEntityDetailList` 恒为 null，本接口按上项填充
  - **回归（与 /list 一致）**：代表行 `taskPackage`、`taskDefinition`（含 `taskPackage[0].childTaskList` 内各子任务）上 **`linkedTemplateDefinitionList` 均为 null**（服务端不显式填充模板详情列表，避免与详情接口同 payload）
  - 实现说明（性能）：去重 `COUNT` / `GROUP BY` 在「最近 1 万条」子查询内完成；代表行主键 **`selectBatchIds`** 批量加载；同一页内 **`task_package_id`** 等对 `task_definition` **去重预取**；`samePackageEntityDetailList` **最多扫库 1 万行**（与去重子集口径一致）；`taskPackageFilteredDetailList` 为**整页编码 IN + 列表筛选的全量**一次查询（可能行数较大，与去重 1 万条解耦），内存按编码分发
  - **回归（精准 OR）**：`targetEntityCode` 与 `targetEntityName` **均传**时，批量补数请求体不再错误地只带 `target_entity_name` 条件（应与列表 OR 一致：由本页 `IN(target_entity_code)` 承接目标范围），避免 `taskPackageFilteredDetailList` 为空

- **用例12h：按 objectCode 对 target 聚合（种子 20 条去重，目标精准，每行含 detailCount）**
  - 接口：`POST /sales/task/distribution/detail/listGroupByTarget`（**独立**于 `/list`、`/listByPackage`，不返回整包 DTO 嵌套；仅汇总展示字段 + `detailCount`）
  - 必传：`objectCode`；**`page`、`pageSize` 由服务端忽略**；`PageResult.total` = 本次实际返回的组数（**≤20**），`page`=1，`pageSize`=20，`totalPage` 为 0 或 1
  - 业务：在 `is_deleted=0`、**`status = IN_PROGRESS`** 且 `object_code`、`target_entity_code` 均非空的明细上：① **仅传 `objectCode`**（不传其它可选筛选）时，先按 **`id` 倒序 `LIMIT 20`** 取进行中明细，对其 **`target_entity_code` 去重**（顺序为种子中出现顺序），再对去重后的编码在**同一基础条件**（仅 objectCode+进行中+未删除+编码非空）下按组算 **`detailCount`** 与组内 **`MAX(id)` 代表行**；② **任一带可选筛选**（含 `targetEntityCode`/`targetEntityName`/`taskTitle`/`owningDepartmentName`/`taskDefId`/`taskExecutionType`）时，种子 20 条与后续聚合的 `WHERE` **均含全量可选条件**，`detailCount` 为各目标在该全量条件下的进行中条数。`targetEntityCode`、`targetEntityName` 为 **trim 后精准等值**（可选；**两者均传时为 OR**）；**`taskTitle`、`owningDepartmentName`** 为模糊；**`taskDefId`** 精准匹配 **`task_def_id`**；**`taskExecutionType`** 精准匹配 **`task_execution_type`**（trim，与 `/list` 一致）。代表行展示字段取组内 **`id` 最大**的一条。
  - 请求 Body 示例：
    ```json
    {
      "objectCode": "STORE",
      "taskDefId": 1001,
      "//taskDefId": "可选：精准匹配 task_def_id（子任务 id）",
      "taskExecutionType": "VISIT",
      "//taskExecutionType": "可选：精准匹配 task_execution_type（trim）",
      "targetEntityCode": "WD35025932",
      "//targetEntityCode": "可选：精准等于 target_entity_code（trim）",
      "targetEntityName": "阳西县联兴食品批发商行",
      "//targetEntityName": "可选：精准等于 target_entity_name（trim）；与编码同时传时为 OR",
      "taskTitle": "陈列",
      "//taskTitle": "可选：模糊匹配 task_title 或子任务 task_definition.task_name",
      "owningDepartmentName": "华东",
      "//owningDepartmentName": "可选：模糊匹配 owning_department_name"
    }
    ```
  - 预期结果：`Response.success`，`data` 为 `PageResult`，`records` 至多 **20** 条，元素含 `objectCode`、`targetEntityCode`、`targetEntityId`、`targetEntityName`、`taskTitle`、`owningDepartmentName`、`detailCount`（Long）
  - 响应示例（结构）：
    ```json
    {
      "code": 0,
      "message": "success",
      "data": {
        "records": [
          {
            "objectCode": "STORE",
            "targetEntityCode": "WD35025932",
            "targetEntityId": "5f2e9e6f2f2a0c0012abcd34",
            "targetEntityName": "阳西县联兴食品批发商行",
            "taskTitle": "3月陈列巡检",
            "owningDepartmentName": "某某大区",
            "detailCount": 6
          }
        ],
        "total": 3,
        "page": 1,
        "pageSize": 20,
        "totalPage": 1
      }
    }
    ```
  - 回归：无 `objectCode` 时业务错误；仅查 `is_deleted=0` 且 **`status=IN_PROGRESS`**；仅 objectCode 时种子不带目标/标题/部门筛选，返回组数为最近 20 条内去重后的目标数（≤20）；编码与名称均传时命中 **OR** 条件
  - 回归（性能/语义）：接口为 **1 次种子列表 + 1 次分组聚合（`listMaxIdAndCountByTargetEntityCodes`）+ 1 次 `selectBatchIds`**；无全库按目标分组取 TOP N

- **用例12f：下发明细状态统计（完成/进行中/过期/关闭）**
  - 接口：`POST /sales/task/distribution/detail/statusStats`
  - 必传：`objectCode`（统计接口默认仅需该字段）
  - 请求 Body 示例：
    ```json
    {
      "objectCode": "STORE"
    }
    ```
  - 预期结果：`Response.success`，`data` 返回四个状态数量，未命中状态返回 `0`
  - 响应示例：
    ```json
    {
      "code": 0,
      "message": "success",
      "data": {
        "completedCount": 56,
        "inProgressCount": 129,
        "expiredCount": 8,
        "closedCount": 3
      }
    }
    ```
  - 回归：仅统计 `is_deleted=0`；无 `objectCode` 时业务错误；传参仅 `objectCode` 即可完成统计
  - **缓存（Redis）**：key 为 **`RedisConstants.taskDistributionDetailStatusStatsKey(objectCode)`**（`objectCode` 已 trim），**30 分钟**过期；Redis 异常时降级查库

- **用例12g：下发明细状态统计（listByPackage 去重维度、仅 objectCode、全量）**
  - 接口：`POST /sales/task/distribution/detail/statusStatsByListByPackage`
  - 说明：与 **`listByPackage`** 相同的**去重维度**：在 `is_deleted=0`、`object_code` = 请求 `objectCode`（trim）、`task_package_id IS NOT NULL`、`target_entity_code IS NOT NULL` 的明细上，对每个 `(task_package_id, target_entity_code)` 取组内 **`MAX(id)`** 代表行，再按代表行 `status` 归入 completed / inProgress / closed；**全表该 objectCode 下命中行参与分组**，**无**「最近 1 万条 id」截断（与 **`POST .../listByPackage` 列表**不同，列表仍保留 1 万条预截断）。**仅 `objectCode` 参与统计**：`taskPackageId`、`status`、`targetEntityCode` / `targetEntityName`、时间等**均忽略**；**`page`、`pageSize` 忽略**。**不统计已过期**：代表行为 **`EXPIRED`** 的组合**不计入**本接口任一状态桶，响应中 **`expiredCount` 恒为 `0`**。
  - 请求 Body 示例（`//` 为字段含义说明，实际调用请去掉注释或按网关是否支持 JSONC 处理）：
    ```json
    {
      "objectCode": "STORE"
    }
    ```
  - 字段说明：仅需 **`objectCode` 必传**（与 Body 校验一致）；其余字段可传但**不参与**统计与缓存键。
  - 预期结果：`Response.success`，`data` 含 `completedCount`、`inProgressCount`、`closedCount`；**`expiredCount` 恒为 `0`**；无命中状态时前三项为 `0`
  - 回归：无 `objectCode` 时业务错误；**`completedCount` + `inProgressCount` + `closedCount`** 等于全量下「代表行 `status` 不为 **`EXPIRED`**」的 `(object_code, target_entity_code)` 组数
  - **缓存（Redis）**：key 为 **`RedisConstants.taskDistributionDetailStatusStatsByListByPackageKey(objectCode)`**（`objectCode` trim），**30 分钟**过期；Redis 异常时降级查库

- **用例12fg-cache（回归）：状态统计 Redis 按 objectCode**
  - 步骤：对同一 `objectCode` 连续两次调用 `POST .../statusStats` 或 `POST .../statusStatsByListByPackage`
  - 预期：第二次与第一次统计结构一致；`statusStats` 与 `statusStatsByListByPackage` 使用**不同 Redis key 前缀**，互不串缓存

- **用例12c：手动指定目标列表同步下发明细（进行中任务包）**
  - 接口：`POST /sales/task/distribution/detail/syncInProgressPackageByManualTargets`
  - 说明：与 `TaskPackageStatusTransitionJobServiceImpl#syncInProgressPackagesByCrowd` 落库逻辑一致（仅 **`start_time`、`end_time` 均非空**的子 TASK 参与；子 TASK 逐条 × 目标编码、独立事务插入、唯一键冲突跳过），**不调用分群接口**，由调用方传入 `targets`（`targetEntityCode` / `targetEntityName`）及写入明细用的 `objectCode`、`objectName`。判重键与分群一致：按任务包关联 **`task_rule.is_repeat`**，重复下发模式下含 **`start_time`、`end_time`**。任务包须 **`task_type=PACKAGE`** 且 **`task_status=IN_PROGRESS`**、未删除；入口先 **CAS** 将 **`distribution_push_completed` 由 0→1**（与分群 Job 互斥），失败返回业务错误；**处理结束（成功或异常）`finally` 置回 0**。`target_entity_id` / `target_entity_name` 经 DTS 补全：**`objectCode=STORE`/`DEALER`** → `account_obj`；**`objectCode=PERSON`** → `personnel_obj`（`user_master_id__c`）；其它 `objectCode` 不查 DTS；**`target_entity_name` 优先用手动传入**；若无满足条件的子 TASK 则返回业务错误提示。
  - **异步行为**：接口**一步提交**后**立即返回**成功（不阻塞 HTTP 线程）；Controller 将整段同步委托给 `IOAsyncUtil` 后台执行。服务内每条明细插入再通过 **`IOAsyncUtil` + `IOExecutorManager` 线程池**异步提交，**全部插入完成（`CompletableFuture.join`）后**再释放 `distribution_push_completed`，避免槽位提前释放。本次**新插入行数**不在响应中返回，可在应用日志中检索关键字 `syncInProgressPackageByManualTargets 完成`（含 `taskPackageId`、`inserted`）；失败时打错误日志。
  - 请求 Body 示例：
    ```json
    {
      "taskPackageId": 10001,
      "objectCode": "STORE",
      "objectName": "门店",
      "targets": [
        {
          "targetEntityCode": "WD35025932",
          "targetEntityName": "某某门店"
        },
        {
          "targetEntityCode": "YQWD00000016",
          "targetEntityName": ""
        }
      ]
    }
    ```
  - 字段说明：`taskPackageId` 进行中任务包 ID；`objectCode`/`objectName` 写入明细 `object_code`/`object_name`，`targetEntityType` 与 `objectCode` 一致；`targets[].targetEntityCode` 必填；`targets[].targetEntityName` 可选。落库路径与分群一致：每条明细在 **`insertTaskDistributionDetailAsync`** 内 `REQUIRES_NEW` 插入提交后，于**同一条异步任务**中调用 **`TaskDistributionDetailOwningDepartmentSyncJobService#fillOwningDepartmentIfAbsent`** 尝试补全 **`owning_department_*` / `department_path_json`**（失败仅 warn）。预期结果：`Response.success`（`data` 为空或与网关统一的无业务体表示），**不**同步返回插入行数；插入结果以日志为准。

- **用例12d：按任务包 id 立即触发分群下发同步**
  - 接口：`POST /sales/task/distribution/detail/triggerSyncInProgressPackagesByCrowd`
  - 说明：调用 `syncInProgressPackagesByCrowd(maxScanCount, ids)`，`maxScanCount` 取 `SyncInProgressPackagesByCrowdJobParamDTO.DEFAULT_MAX_SCAN_COUNT`，逻辑与 XXL Job `syncInProgressPackagesByCrowd` 相同。**同步**先执行 `assertTaskPackagesNotBusyForCrowdSync`：若任务包 **`end_time` 非空且当前时间已超过截止时间**则返回业务错误「任务包已超过截止时间，无法下发…」；若 `ids` 中任一任务包 **`distribution_push_completed=true`**（正在下发同步中，与 Job 占位一致）则返回业务错误「以下任务包正在下发同步中…」；若 id 不存在、已删除或非 `PACKAGE` 则返回「任务包不存在、已删除或非 PACKAGE 类型…」。校验通过后 **异步**提交分群同步，HTTP **立即**返回成功；处理条数见日志 `triggerSyncInProgressPackagesByCrowd 完成`（含 `ids`、`handled`）。
  - 请求 Body 示例：
    ```json
    {
      "ids": [10001, 10002]
    }
    ```
  - 字段说明：`ids` 为任务包 `task_definition.id` 列表（必填非空）；重复 id 会去重。预期：`Response.success` 无业务体或网关统一空 data；失败为业务异常提示。

- **用例14：查询历史记录（按 taskMonth 分组）**
  - 接口：`POST /task/distribution/detail/history`
  - 请求 Body：`{ "status": "COMPLETED", "targetEntityId": "S001", "targetEntityCode": "STORE001" }`
  - 必传：status；targetEntityId、targetEntityCode 至少传一个
  - 预期结果：返回按 taskMonth 分组的列表

### 九、Action 完成时同步任务明细状态

- **用例13：task_instance_action 执行完成后同步 task_distribution_detail**
  - 触发：调用 `POST /task/instance/action/update` 将 action 的 status 更新为 COMPLETED 或 FAILED
  - 流程：
    1. 根据 task_instance_action_id 获取动作信息
    2. 通过 task_def_id 解析关联的普通任务（若 task_def 为 ACTION 则取父级 TASK）
    3. 查询 task_distribution_detail（task_instance_id + task_def_id 匹配）
    4. 根据 action.status 更新明细：COMPLETED→COMPLETED，FAILED→CLOSED
  - 预期：匹配的 task_distribution_detail 的 status 被批量更新

---

## 第二篇：条件匹配、task_instance、模板联调与定时任务

### 功能模块：任务下发明细条件匹配

### 一、变更说明

在执行 `TaskDistributionDetailSyncService.evaluateInstanceMatchForInProgressDetails`（及后续 `evaluateConditionCalculationByInstance`）时：
1. 从 `task_result_data` 解析出的 `mappedResults` 中选取目标实体编码时：除 `isSearchPrimaryKey=true` 外，还要求该条目的 **`objectCode`** 与当前 TASK 对应的 **`task_definition.object_code`** 一致（二者均为空视为一致）；否则不命中明细、不创建 `task_instance`。
2. 对每条参与匹配的 `task_distribution_detail` 先创建一条 `task_instance`。
3. `task_instance` 需要写入 `source_data`（Kafka 消息 value）、`task_result_data`（`TaskDistributionTaskResult` 序列化 JSON）以及关联的 `task_distribution_detail_id`。
4. 若该明细所有条件均 `matched=true`，则继续将明细状态推进为 `COMPLETED`。
5. `TaskDistributionDetailSyncService.evaluateConditionCalculationByInstance(TaskInstanceDTO)` 在**完整跑通**条件评估并返回结果后，若 **`task_instance.id` 非空**会将对应 `task_instance.status` 更新为 `COMPLETED`，并写入 `completed_at`（仅内存实例无 id 时跳过实例表更新）。
6. `evaluateConditionCalculationByInstance` 在 **`task_instance.id` 非空**时执行后会新增一条 `task_instance_execution_log`，通过 `task_instance_id` 与任务实例绑定，记录本次条件计算结果摘要（DELAY 扫描仅内存实例、无 id 时跳过写日志）；`completion_script`（Groovy）**抛异常**时仍会写日志（`event_data` 含 `completionScriptException=true` 及错误信息），且**不会**将 `task_instance` 置为已完成，便于下次重试；脚本正常执行（含返回 false）时仍按原逻辑置实例完成（同上，仅 id 非空时更新实例表）。
7. **完成判定唯一依据**：`evaluateConditionMatch` 不再读取 `condition_repo`/不再做字段逐条对比；执行前按 `task_definition.condition_ids` 反查条件库明细列表，注入变量 `conditionDetailList`（与 `testTaskWithConditionDetails` 一致），再执行 `task_definition.completion_script`（Groovy 片段，返回布尔）。脚本参数另有：`mappedResults`（原始列表）、`mappedResultMap`（`mapped_col -> mapped_col_val`）。若 `task_result_data` 解析结果中带有 **`completionScriptData`**（如 DELAY 同步扫描将 DynamicHttp 解析结果写入 `TaskDistributionTaskResult`），则额外注入 Groovy 变量 **`data`**，与仅走 Kafka/映射结果、不带 `completionScriptData` 的链路兼容。**仅 `templateType=TARGET`** 时：先剥离 `@` 行，再将脚本中 **`{{fieldCode}}`** 按 `conditionDetailList` 的 `fieldCode` 匹配，替换为对应 `defaultValue` 首个 `value` 的 Groovy 字面量（**`dataTypeDefinition=NUMBER`** 时转为 **long 数字字面量**，非字符串）；COMMON/TEMPORARY 不做占位替换。
8. **DELAY 同步扫描回归**（`scanInProgressTaskDelaySyncStrategy` / `TaskInProgressDelaySyncStrategyScanJobServiceImpl`）：**仅处理**绑定 **`templateType=TARGET`** 的进行中 TASK；**COMMON/TEMPORARY** 等非 TARGET 模板直接过滤跳过。TARGET 从子 TASK **`completion_script`** 的 **`@xxx(endpointId)`** 解析 **`dynamic_http_endpoint.id`** 后直接 invoke。对每个 `targetEntityCode` 首次拉数后调用 `evaluateDelaySyncWithPersistedInstance`；同一 `targetEntityCode` 复用布尔结果。明细按 id 游标每批最多 **20000** 条，判定缓存跨批复用。Job 参数可选 **`ids`**（任务包 `task_definition.id` 列表）：非空时仅扫描 **`parent_id`** 命中这些包 id 的子 TASK；支持 JSON `{"maxScanCount":20000,"ids":[101]}` 或逗号分隔 `20000,101,102`。
9. 返回值：`conditionMatchResults` 固定仅 1 条，`ConditionRepoDTO.defaultValue/description` 为脚本片段内容，`matched=true/false` 为脚本执行结果；同响应中携带 `conditionDetailList`（`task_definition.condition_ids` 反查条件库明细，与脚本注入变量一致）。
10. 新增 `TaskDistributionDetailSyncService.evaluateScriptCompletionByInstance(TaskInstanceDTO)`：基于实例中的 `task_result_data` 解析 `mappedResults`，按 `taskDefId` 查询 `task_definition` 与 `task_rule`；当 `task_rule.completion_type=SCRIPT_BASED` 时，执行 `task_rule.completion_script`（Groovy）并返回布尔结果。执行参数包含：`mappedResults`（原始列表）、`mappedResultMap`（`mapped_col -> mapped_col_val`）、`taskResult`、`taskDefId`、`taskCode`、`taskExecutionEventCode`。

### 二、API 接口

- 接口：`POST /sales/task/biz/template/field/testTaskDistribution`
- 请求 Body 示例（模拟 Kafka 消息；`value` 为 JSON 对象，服务端序列化为字符串后作为映射源）：
```json
{
  "key": "genkishoporders",
  "value": {
    "orderId": "123",
    "items": [
      {
        "commodityCode": "A01",
        "baseUnitQuantity": "12"
      }
    ]
  }
}
```

- 接口（`extractMappedFieldsByIds` 测试，路径名沿用）：`POST /sales/task/biz/template/field/testTaskDistributionByDynamicGroup`
- `biz_template_field_map.extract_rule`（`data_type=JSON`）支持链式数组路径，例如 `groupDataList[*].rawDataList[*].a`：先按 `groupDataList` 展开，再对每个元素下的 `rawDataList` 展开，取字段 `a`，`mappedResults` 中每条 `mappedColVal` 为对应分组下 `a` 的 JSON 数组字符串。
- **映射源（二选一，非 TARGET）**：① 请求传入 **`value`**（JSON 对象/数组，与 `testTaskDistribution` 的 `value` 语义一致），直接作为 `extractMappedFieldsByIds` 的 jsonSource；② 未传 **`value`** 时须传 **`bizTemplateConfigId`**，服务端查询 `biz_template_config`，将 **`groovy_execute_param_sample_json`** 解析为 JSON 作为映射源。
- **`templateType=TARGET`**：走 **`executeTargetTemplateGroovyScript`**。**`code`** 中 **`@smatBi(2)`** 等形式：括号内数字为 **`dynamic_http_endpoint.id`**，先按 id 调 DynamicHttp（**`targetEntityCode`** 同 DELAY 扫描），响应 **`data`** 注入 Groovy 变量 **`data`**，再剥离 **`@`** 行、**`{{fieldCode}}`** 占位替换后执行脚本（不走 **`evaluateDelaySyncWithPersistedInstance`**）。响应含 **`executionLogs`**、**`dynamicHttpInvokeResult`**。
- 请求 Body 示例（动态 value + Groovy 扩展绑定）：
```json
{
  "fieldIds": [13, 14, 15], // 非 TARGET 时必填：字段映射主键列表（biz_template_field_map.id）
  "key": "genkishoporders", // 可选：与 Kafka key 语义一致；执行 Groovy 时注入变量 key
  "value": { // 可选：映射源；与 bizTemplateConfigId 二选一（优先 value）
    "orderId": "123",
    "items": [{ "commodityCode": "A01", "baseUnitQuantity": "12" }]
  },
  "bizTemplateConfigId": 1, // 未传 value 时必填：用于读取 groovy_execute_param_sample_json
  "conditionRepos": [
    {
      "fieldCode": "commodityCode2", // 可选：与 mappedResults.mappedCol 对齐
      "operator": "EQ",
      "defaultValue": { "value": "YQ03002" }
    }
  ],
  "groovyBindings": {
    "threshold": 10 // 可选：额外 Groovy 变量；在注入 key/value/mappedResults/conditionDetailList 之后合并，同名键可覆盖内置变量
  },
  "code": "value?.items?.size() > 0 && threshold > 5" // 可选：Groovy 片段
}
```

- 请求 Body 示例（**TARGET** 占位符 + Groovy）：
```json
{
  "templateType": "TARGET",
  "value": {},
  "groovyBindings": {
    "conditionDetailList": [
      {
        "conditionName": "测试",
        "objectType": "STORE",
        "fieldCode": "count",
        "operator": ">=",
        "defaultValue": [
          { "value": 1 }
        ]
      }
    ]
  },
  "targetEntityCode": "WD11010068",
  "code": "@smatBi(2)\nreturn 1 >= {{count}}"
}
```
说明：`@smatBi(2)` 触发 endpointId=2 的 DynamicHttp；`{{count}}` 替换后执行 `return 1 >= 1`；**`data`** 来自 HTTP 响应（覆盖 groovyBindings 中同名变量）。

- 响应 `data` 结构示例：

```json
{
  "mappedResults": [
    {
      "mappedCol": "amount",
      "mappedColVal": "99.00",
      "index": null,
      "logicalName": "金额",
      "remark": "",
      "extractRule": "",
      "isSearchPrimaryKey": false,
      "objectCode": "STORE",
      "dataType": "DECIMAL"
    }
  ],
  "conditionDetailList": [
    {
      "fieldCode": "commodityCode2",
      "operator": "EQ",
      "defaultValue": { "value": "YQ03002" }
    }
  ],
  "key": "genkishoporders", // 回显请求 key
  "value": { "orderId": "123" }, // 回显请求 value
  "groovyBindings": { "threshold": 10 }, // 回显请求 groovyBindings
  "groovyResult": 1, // 传入 code 且脚本执行成功时：Groovy 返回值
  "groovyError": null,
  "dynamicHttpEndpointId": 2,
  "dynamicHttpInvokeResult": {
    "success": true,
    "httpStatus": 200,
    "durationMs": 120,
    "errorMessage": null
  },
  "executionLogs": [
    "解析 @ 定制化指令: dynamic_http_endpoint.id=2",
    "DynamicHttp executeVariables.targetEntityCode=WD11010068",
    "DynamicHttp 调用完成: success=true, httpStatus=200, durationMs=120, errorMessage=null",
    "注入 Groovy 变量 data（来自 DynamicHttp 响应 data 字段）",
    "Groovy 脚本校验通过，开始执行",
    "Groovy 执行成功, returnType=Boolean"
  ]
}
```

- `mappedResults`（字段映射相关 HTTP 接口）：返回体为 **`List<IndexAggregatedMappedFieldRow>`**，每行 `index` + `mappedFields`；**公共字段**（扁平结果中 `index == null`）**并入**每个有下标的行的 `mappedFields` 前部，**不单独成行**；仅公共字段时返回一行 `index=null`。Groovy 注入的 `mappedResults` 仍为**扁平** `List<MappedFieldResult>`。
- 传入 `code` 时，脚本内默认绑定 **`key`**、**`value`**（请求体原样）、**`mappedResults`**、**`conditionDetailList`**（来自 **`conditionRepos`**，未传则为空列表），再合并 **`groovyBindings`**（同名键覆盖前述变量）；与 `detailTaskWithConditions` / 任务完成脚本等场景兼容；脚本需符合 `GroovyScriptSecurityUtils` 白名单（禁止 import/循环等）。

- 接口（SCRIPT_BASED 判定测试）：`POST /sales/task/biz/template/field/testEvaluateScriptCompletionByInstance`
- 请求 Body 示例：
```json
{
  "id": 123 // task_instance.id
}
```

### 三、用例设计

- 用例1：条件全部匹配，创建 task_instance 并推进明细状态
  - 前置准备：存在 `task_distribution_detail`，且其 `target_entity_code` 能从 `mappedResults` 中 **`isSearchPrimaryKey=true` 且 `objectCode` 与当前 TASK 的 `task_definition.object_code` 一致** 的条目对应的 `mappedColVal` 中解析得到；并且该明细配置了可用的 `target_entity_field_mapped_id`（能在 `biz_template_field_map` 查到非空 `mapped_col`）。
  - 执行步骤：调用接口 `POST /sales/task/biz/template/field/testTaskDistribution`，使用前置数据对应的 `key/value`。
  - 预期结果：
    - 返回 `detailConditionMatchResults` 中包含该明细的条件匹配明细。
    - 该明细对应 `task_distribution_detail.status` 更新为 `COMPLETED`。
    - 在 `task_instance` 新增记录满足：
      - `task_distribution_detail_id` 等于该明细 `id`
      - `source_data` 等于请求入参 `value`
      - `task_result_data` 为 `TaskDistributionTaskResult` 的 JSON 序列化结果，且包含 `task_execution_event_code`

- 用例2：部分条件不匹配，创建 task_instance 但不推进明细状态
  - 前置准备：同用例1，但配置使得至少有一条条件 `matched=false`。
  - 执行步骤：调用接口 `POST /sales/task/biz/template/field/testTaskDistribution`。
  - 预期结果：
    - `task_distribution_detail.status` 保持 `IN_PROGRESS`。
    - 仍会为该明细创建 `task_instance`，并写入 `source_data` / `task_result_data` / `task_distribution_detail_id`。

- 用例3：明细缺少 target_entity_code，不创建 task_instance
  - 前置准备：构造一条 `task_distribution_detail` 其 `target_entity_code` 为空或不参与过滤命中。
  - 执行步骤：调用接口 `POST /sales/task/biz/template/field/testTaskDistribution`。
  - 预期结果：该明细不参与条件匹配，也不应新增 `task_instance`（无 `task_distribution_detail_id = detail.id`）。

- 用例4：明细映射字段不存在，不创建 task_instance
  - 前置准备：构造一条 `task_distribution_detail` 使得 `target_entity_field_mapped_id` 无法解析到 `biz_template_field_map.mapped_col`（为空或记录不存在）。
  - 执行步骤：调用接口 `POST /sales/task/biz/template/field/testTaskDistribution`。
  - 预期结果：该明细不参与条件匹配，不应新增 `task_instance`（无 `task_distribution_detail_id = detail.id`）。

- 用例4.1：主键条目的 objectCode 与 TASK 的 object_code 不一致，不创建 task_instance（回归）
  - 前置准备：存在 `task_distribution_detail` 与对应 TASK；`mappedResults` 中虽有 `isSearchPrimaryKey=true` 的条目，但其 `objectCode` 与 `task_definition.object_code` 不一致（或 TASK 有 `object_code` 而主键条目 `objectCode` 为空）。
  - 执行步骤：调用接口 `POST /sales/task/biz/template/field/testTaskDistribution`。
  - 预期结果：无法解析出与明细一致的 `targetEntityCode`，不新增 `task_instance`。

- 用例4.2：completion_script（Groovy）+ conditionDetailList 注入（回归）
  - 前置准备：对应 TASK 的 `task_definition.completion_script` 为非空 Groovy 片段，返回布尔；可选配置 `condition_ids`，脚本内可通过变量 `conditionDetailList` 读取条件库明细（与测试接口 `detailTaskWithConditions` 注入方式一致）。
  - 执行步骤：触发与用例1相同的条件评估链路（接口或 Job 反查 `task_result_data`）。
  - 预期结果：仅当 `completion_script` 执行结果为 `true` 时，`evaluateConditionMatch` 返回的单一 `ConditionMatchResult.matched=true`，明细可置为 `COMPLETED`；配置 `condition_ids` 不会触发额外的字段比对，仅作为脚本可用数据。

- 用例4.3：`extractMappedFieldsByIds` 联调（`testTaskDistributionByDynamicGroup`）
  - 前置准备：已知 `biz_template_config.id`，且该行 `groovy_execute_param_sample_json` 已维护为与字段映射匹配的示例 JSON；已知一组 `biz_template_field_map.id`。
  - 执行步骤：调用 `POST /sales/task/biz/template/field/testTaskDistributionByDynamicGroup`，传入 `bizTemplateConfigId` + `fieldIds`；可选传入 `conditionRepos` 与 `code` 联调条件脚本。
  - 预期结果：返回体 `data` 含 `mappedResults`（**按 index 聚合**后的 `List<IndexAggregatedMappedFieldRow>`）；公共字段（原 `index=null`）复制进每行 `mappedFields` 前部；可选请求 `code` 时另含 `groovyResult`/`groovyError`，且 Groovy 中可读取 `conditionDetailList`（来自 `conditionRepos`）；脚本内 `mappedResults` 绑定仍为扁平列表；配置不存在或 `groovy_execute_param_sample_json` 为空时接口返回业务错误提示。

- 用例4.3.1：TARGET 模板 Groovy 联调（`templateType=TARGET`）
  - 前置准备：无字段映射 id 要求；`code` 可含以 `@` 开头的定制化行。
  - 执行步骤：调用 `POST /sales/task/biz/template/field/testTaskDistributionByDynamicGroup`，仅传 `templateType=TARGET`、`code`、`groovyBindings`（如 `conditionDetailList`、`data`）；可不传 `fieldIds`/`bizTemplateConfigId`（服务端走 `BizTemplateFieldMapService#executeTargetTemplateGroovyScript`）。
  - 预期结果：`mappedResults` 为空列表；`@` 行已剥离、`{{fieldCode}}` 已按 `defaultValue` 替换；`groovyResult` 为脚本返回值；失败时 `groovyError` 非空。

- 用例4.4：SCRIPT_BASED 完成脚本判定（新增）
  - 前置准备：
    - 已有 `task_instance`，其 `task_result_data` 可解析为 `TaskDistributionTaskResult`，且包含 `taskDefId` 与 `mappedResults`；
    - `task_definition(rule_id=R1)` 存在；
    - `task_rule(id=R1)` 配置：`completion_type=SCRIPT_BASED`，`completion_script` 示例：
```json
"return mappedResults != null && mappedResults.any { it.mappedCol == 'commodityCode' && it.mappedColVal == 'YQ03002' }"
```
  - 执行步骤：调用 `TaskDistributionDetailSyncService.evaluateScriptCompletionByInstance(taskInstance)`。
  - 预期结果：
    - 方法会将 `mappedResults` 作为脚本参数注入执行；
    - 脚本返回布尔值 `true/false`；
    - `true` 代表该实例满足脚本完成条件（可由上层据此推进完成态）。

### 四、定时任务（XXL-JOB）

- **用例5：evaluateConditionMatchForInProgressTaskInstances**
  - XXL-JOB 任务名：`evaluateConditionMatchForInProgressTaskInstances`
  - 触发逻辑：
    1. 分页查询 `task_instance.status = IN_PROGRESS`，且 `task_result_data`、`task_distribution_detail_id` 非空（每页默认 200 条，按 id 升序，直至无下一页）
    2. 对每条再校验 `task_result_data` 文本非空后，调用 `TaskDistributionDetailSyncService.evaluateConditionMatchForInProgressDetail`
    3. 单条异常记录日志，不中断整批
  - 预期结果：执行成功；满足条件且评估完整返回的实例被置为 `COMPLETED`（见变更说明第 4 点）
  - 请求 JSON：无（调度中心仅配置 JobHandler 名称即可）

- **用例6：syncPackageTaskStatusCompleted（进行中任务包关联 TASK 到期过期）**
  - XXL-JOB 任务名：`syncPackageTaskStatusCompleted`
  - 触发逻辑（单次调度，默认扫描上限 20000 个进行中任务包）：
    1. 查询 `task_type = PACKAGE` 且 `task_status = IN_PROGRESS`，按 `id` 升序 `LIMIT maxScanCount`
    2. 对每个任务包查询其下 `task_type = TASK` 且 `parent_id = 任务包.id` 的子任务；若无子 TASK 则跳过
    3. **任务包过期判定**（仅依据全部子 TASK 的 `end_time`，与子 TASK 当前 `task_status` 无关）：每个子 TASK 须 `end_time` 非空且 `end_time <= now`；任一子 TASK 无 `end_time` 或未到期则跳过该任务包
    4. 判定通过后：
       - 仅将 `task_status = IN_PROGRESS` 的子 TASK 置为 `EXPIRED`（**不更新** `task_distribution_detail` 下发明细）
       - 将该 PACKAGE 置为 `EXPIRED`
  - 预期结果：任务包过期**只**看全部子 TASK 结束时间是否均已到期；非 `IN_PROGRESS` 子 TASK 不被修改；存在 `end_time` 未到期的子 TASK 时任务包保持 `IN_PROGRESS`
  - 请求 JSON：无（调度中心仅配置 JobHandler 名称即可）

- **用例6.1：refreshInProgressPackageCronDistributedAt**
  - XXL-JOB 任务名：`refreshInProgressPackageCronDistributedAt`
  - **任务参数**（可选）：`maxScanCount` 正整数，单次扫描 `task_definition` 行数上限，缺省 **20000**
  - 触发逻辑：
    1. 查询 `task_type = PACKAGE` 且 `task_status = IN_PROGRESS`、`is_deleted = 0`，按 `id` 升序，**`LIMIT maxScanCount`**
    2. 对每条读取 `task_rule`（`task_definition.rule_id`）；若 **`distribution_type` 不为 CRON / FIXED / IMMEDIATE**（忽略大小写）或无 `rule_id`、无 `distribution_type` 文本，跳过
    3. 调用 **`TaskRuleTimeResolver#resolveScheduledDistributeAt`** 写回 **`task_definition.distributed_at`**：**CRON** → 解析 `distribution_config.cron`，取相对**当前时刻**的下次触发时间；**FIXED** → 解析 `distribution_config` 中 **`dateTime`**（`yyyy-MM-dd HH:mm:ss`）；**IMMEDIATE** → **当前时间**
  - 预期结果：命中类型的进行中任务包 **`distributed_at`** 按上款刷新；解析失败或类型不支持的包跳过并打日志；返回值为本次成功 **`UPDATE` 影响行数**
  - 请求 JSON：无（调度中心仅配置 JobHandler 名称与可选任务参数即可）

- **用例6.2：expireInProgressDetailsPastEndTime（按明细 end_time 全表批量过期）**
  - XXL-JOB 任务名：`expireInProgressDetailsPastEndTime`
  - **任务参数**：无（不按条数截断；一次调度内由 Service 循环多批 UPDATE，每批最多 50 万行，直至本批影响行数为 0）
  - **Service**：`TaskDistributionDetailJobService#expireInProgressDetailsPastEndTime()` → `TaskDistributionDetailService#expireInProgressDetailsPastEndTime(LocalDateTime referenceTime)`，`referenceTime` 为调度开始时刻（单次调用内各批共用该时刻）
  - 触发逻辑：`IN_PROGRESS` 且 `end_time <= referenceTime` 的 `task_distribution_detail` **全部**置过期（不按 `task_def_id`）；可与 **用例6** 分调度并行，用于任务定义未同步 EXPIRED 但明细已到期等场景
  - 预期结果：执行成功；日志中可见**累计** `UPDATE` 影响行数；异常时 XXL 侧可见失败日志
  - 请求 JSON：无（调度中心仅配置 JobHandler 名称即可）

- **用例6.3：refreshTaskDistributionDetailStatusStatsCache（状态统计双缓存预热）**
  - XXL-JOB 任务名：`refreshTaskDistributionDetailStatusStatsCache`
  - **任务参数**：由 **`RefreshDetailStatusStatsCacheJobParamDTO.fromXxlJobParam`** 解析（`com.yqsl.sls.business.taskdistributiondetail.dto`）。**推荐 JSON**；或英文逗号分隔多个 `object_code`（如 `STORE,DEALER`）；**未传、JSON 解析失败、或解析后无有效编码时，默认仅刷新 `STORE`**（常量 **`RefreshDetailStatusStatsCacheJobParamDTO.DEFAULT_OBJECT_CODE`**）。
  - **请求 JSON 示例**（调度中心「任务参数」文本）：
```json
{
  "objectCodes": [
    "STORE",
    "DEALER"
  ]
}
```
  - **字段说明**（注释含义）：
    - `objectCodes`：需要预热/刷新的对象编码列表；每个编码依次删除 **`RedisConstants.taskDistributionDetailStatusStatsKey(code)`** 与 **`taskDistributionDetailStatusStatsByListByPackageKey(code)`**，再分别调用 **`TaskDistributionDetailService#countStatusStats`**、**`countStatusStatsByListByPackageFilter`** 写回与接口直调一致的统计结果（TTL 见 `RedisConstants.TASK_DISTRIBUTION_DETAIL_STATUS_STATS_TIMEOUT_MINUTES`）
  - **Service**：`TaskDistributionDetailJobService#refreshDetailStatusStatsCachesBatch` → **`TaskDistributionDetailService#refreshDetailStatusStatsCaches`**；同一 Job 在 **`finally`** 中还会调用 **`TaskDefinitionService#warmListStatsCacheForLatestDefinitions(50)`**，从 `task_definition` 按 **`id` 倒序**、**`is_deleted = 0`** 各取至多 **50** 条 **`task_type = PACKAGE`** 与 **`task_type = TASK`** 的 **`id`**，分别构造与 **`POST /sales/task/definition/listStats`** 相同的 **`TaskDefinitionStatsQueryRequest`** 并走 **`listStats`**（写回 **`RedisConstants.taskDefinitionListStatsKey(taskType, id)`** 缓存，与接口一致）；listStats 预热失败仅 **warn**，不吞掉明细缓存刷新的异常
  - 预期结果：执行成功；XXL 日志中可见成功刷新的 `objectCode` 条数；单个编码失败仅打错误日志，不中断后续编码；日志中另可见 listStats 预热返回的统计行数或预热失败说明

- **用例7：syncInProgressPackagesByCrowd**
  - XXL-JOB 任务名：`syncInProgressPackagesByCrowd`
  - **任务参数**（Executor 中「任务参数」文本）：**推荐 JSON**，反序列化为 **`SyncInProgressPackagesByCrowdJobParamDTO`**（`com.yqsl.sls.business.taskdistributiondetail.dto`），由 Job 解析后调用 Service。字段均可选，缺省见 DTO 内常量。
  - **JSON 示例**（与逗号 `20000,1001,1002` 等价）：
```json
{
  "maxScanCount": 20000,
  "ids": [1001, 1002]
}
```
  - **兼容**：参数非以 `{` 开头时，按 **逗号分隔** `maxScanCount,id1,id2,...`（首段为扫描上限，其后均为任务包 id）。**`ids`** 与下述步骤 1 既有条件**取交集**；不传或空数组表示不按 id 过滤。
  - **Service**：`TaskPackageStatusTransitionJobService#syncInProgressPackagesByCrowd(int maxScanCount, Collection<Long> ids)`，`ids` 非空时等价于首轮查询增加 **`id IN (...)`**（null 元素忽略、去重）
  - **Job 层异步**：XXL 调度线程在解析任务参数后**立即提交** `IOAsyncUtil`（`IOExecutorManager` 线程池）执行，**不阻塞**后续调度轮次；**不使用 Redis 全局锁**，以便新任务包能及时进入扫描；防重依赖步骤 1 的 **`distribution_push_completed` 批量 CAS**、步骤 5 及库表唯一约束等
  - 触发逻辑：
    1. 查询 `task_definition.task_type = PACKAGE` 且 `task_status = IN_PROGRESS`、**`status = 1`（启用，与 `TASK_DEF_CONFIG_STATUS_ENABLED` 一致）**、`is_deleted = 0`，**`distribution_push_completed = 0`（空闲）**，`distributed_at` 非空，且 **`distributed_at <= now`**（已到发布时间），且 **`end_time IS NULL OR end_time >= distributed_at`**（任务包结束时间未配置，或结束时间不早于下发时间）；若调用方传入 **任务包 id 集合**（XXL 第三段起 / Service `ids`），再增加 **`id IN (...)`** 与上式取交集；单次扫描条数有上限（Job/调用参数 `maxScanCount`，默认 20000），按 `id` 倒序取前 N 条；对本轮命中的 **ID 列表** 执行 **批量 UPDATE**（`WHERE id IN (...)` 且仍为 **`status = 1`**、`distribution_push_completed=0` 及与查询一致的 `distributed_at`、`end_time` 等条件）**一次性置为同步中（1）**；**逐包 `selectById` 处理**（不再一次载入全部 `TaskDefinition` 实体列表），缩短与其它调度重叠的时间窗；**每包**的 **`task_rule` 查询、扩展表、子任务、分群、明细异步插入与 `join` 等均在同一 **`try`/`finally`** 中，**本分群包处理结束（含空列表、`continue`、任一步抛错）在 `finally` 将 `distribution_push_completed` 置回 `0`**
    2. 按任务包查询 `task_package_distribution_ext`，读取 `distribution_object_group_id`；读取 **`task_rule`**（`task_definition.rule_id`）得 **`is_repeat`**：为 **1** 时表示允许同一目标、同一子任务在不同任务周期重复下发（内存判重键在 `task_def_id + target_entity_code` 基础上增加 **`start_time`、`end_time`**）；否则判重键仅为 **`task_def_id + target_entity_code`**
    3. 查询任务包下 `task_type = TASK` 且未删除、**`start_time` 与 `end_time` 均非空**的子任务；若无命中则跳过后续
    4. 调用数据分群接口 `/dwh/data-labeling/data/crowd/data/latest`，得到 `data.total`、`data.list`（`targetEntityCode`）；若 **`data.total` 非空且非负**：将任务包及包下子 TASK 的 **`task_definition.distribution_task_count`** 更新为该值（与创建任务包时分群总数语义一致；超过 `Integer.MAX_VALUE` 则打日志跳过）
    5. 将 `data.list` 按固定批大小 **500**（`EXISTING_DETAIL_KEYS_BATCH_SIZE`）切片；每批复制编码列表（非 subList 视图）后查库判重，批末 **join** 本批异步插入；pending **`CompletableFuture` 达 200**（`DETAIL_INSERT_FUTURES_FLUSH_THRESHOLD`）时提前 **join** 并清空，避免大分群 OOM；每批根据本批涉及的 `target_entity_code` 查询库中已存在明细（`task_package_id` + `target_entity_code IN (...)` + `is_deleted=0`），按 **`is_repeat`** 构建该批判重键（见步骤 2）；同一次调度内已成功插入的键另集合并入判重，防止 `data.list` 重复编码重复插入
    6. 对每个 `targetEntityCode`（trim）按子 TASK 的 **`object_code`** 查 DTS：**`STORE` / `DEALER`** → **`account_obj.account_no`**（`DtsAccountObjService#getByAccountNo`）；**`PERSON`** → **`personnel_obj.user_master_id__c`** 最新一条（`DtsPersonnelObjService#getLatestByUserMasterId`，`last_modified_time` 降序）；**`PRODUCT` / `OTHER` 等** 不查 DTS。写入 `target_entity_id`（优先 `_id` 否则 `id`）、`target_entity_name`（人员优先 `full_name` 否则 `name`；客户用 `name`）
    7. 对每个子 TASK：若判重键已存在则跳过；否则将 `task_distribution_detail` 插入任务提交到 **`IOAsyncUtil`（`IOExecutorManager` 线程池）**异步执行（仍为 **单条 `REQUIRES_NEW` 事务**）；**pending Future 达 200 或每编码批结束**时 **join** 释放内存；**每条插入成功提交后**，在同一异步任务内调用 **`TaskDistributionDetailOwningDepartmentSyncJobService#fillOwningDepartmentIfAbsent`**（与定时 Job 内 DTS 补全逻辑一致）尝试写入 **`owning_department_code` / `owning_department_name` / `department_path_json`**；补全失败仅 **warn**，不影响判重键与插入成功语义；本包所有异步插入 **join 完成后**再进入 `finally` 释放槽位；单包分群响应处理完毕后将 **`objectList` 等大对象引用置空**；插入若触发唯一键冲突则记日志并跳过（并发幂等）；非重复键失败仅打错误日志，可依赖后续调度补数
    8. （已合并进步骤 1）每包处理完毕后 **`distribution_push_completed` 置回 `0`**，下一调度可再次扫描（若仍满足查询条件）
  - 预期结果：仅处理**进行中且启用**的任务包；停用（`status != 1`）不参与首轮扫描与占位；有效分群对象会按子 TASK 生成任务下发明细；每条 `task_distribution_detail` 插入为 **独立事务**（`REQUIRES_NEW`），整段 Job 不再包在大事务内；**表级唯一约束**（见 `doc/sql/update_tables.sql`）：`uk_task_pkg_def_target_code` = `UNIQUE(task_package_id, task_def_id, target_entity_code)`；`uk_task_pkg_def_obj_end_start` = `UNIQUE(task_package_id, task_def_id, object_code, end_time, start_time)`；任务包在**处理过程中**为 **`distribution_push_completed=1`**，**处理结束后为 `0`**
  - **回归**：单次分群 Job 跑完某包后，该包 **`distribution_push_completed` 为 `0`**（空闲）
  - 回归：重复调度或并发下，**`is_repeat` 非重复下发**时同一 `(任务包, 子任务, target_entity_code)` 仅保留一条有效明细；**`is_repeat=1`** 时同一三元组可在不同 **`start_time`/`end_time`** 下各有一条；多实例可同时跑本 Job，同一任务包由 **`distribution_push_completed` 批量 CAS（或逐条未占位到的行）** 与明细判重保证幂等
  - 请求 JSON：无（调度中心仅配置 JobHandler 名称即可）

- **用例7.1：completeInProgressDetailsByCrowdForCronCompletionJudgment（CRON 完成判断 + 分群 latest 明细完成）**
  - XXL-JOB 任务名：`completeInProgressDetailsByCrowdForCronCompletionJudgment`
  - **任务参数**（可选）：`maxScanCount` 正整数，单次扫描 `task_definition`（任务包）行数上限，缺省 **20000**（与 `refreshInProgressPackageCronDistributedAt` 一致：Executor 中填纯数字即可）
  - **请求 JSON 示例**（调度中心「任务参数」文本；与纯数字 `20000` 等价，便于后续扩展字段）：
```json
{
  "maxScanCount": 20000
}
```
  - **字段说明**（注释含义）：
    - `maxScanCount`：每批查询进行中任务包条数上限（`LIMIT`，多批循环直至无数据），≤0 或未传时服务内使用默认 20000
  - **说明**：当前 Job 实现仅解析**纯数字**参数（`\\d+`）；上表 JSON 为文档约定示例，若调度中心填 JSON 需与运维约定改为 JSON 解析或仍填数字。
  - **Service**：`TaskPackageStatusTransitionJobService#completeInProgressDetailsByCrowdForCronCompletionJudgment(int maxScanCount)`
  - 触发逻辑：
    1. 循环查询 `task_definition` 直至无数据：条件为 `task_type = PACKAGE`、`task_status = IN_PROGRESS`、`is_deleted = 0`、`rule_id` 非空，且 **`end_time IS NULL OR end_time >= now`**；按 `id` 倒序每批 **`LIMIT maxScanCount`**；下一批增加 **`id < 本批最小 id`** 游标，避免重复扫描，直至某批查询结果为空
    2. 对每条读取 **`task_rule`**：若 **`completion_judgment_type` 不为 CRON**（忽略大小写）则跳过
    2.1. **CRON 时间窗**：从 **`completion_judgment_config`**（JSON，与下发 **`distribution_config`** 同类）读取 **`cron`**，按 **`TaskRuleTimeResolver#resolveNextCronFireFromJson`**（与 **`resolveScheduledDistributeAt`** 内 CRON 解析一致）计算相对当前时刻的**下次触发时间** `nextAt`；仅当 **`now` 与 `nextAt` 的间隔严格小于 1 小时**（`Duration.between(now, nextAt) < 1h`）时才继续后续分群与明细更新；若 `nextAt` 早于 `now` 则跳过并打告警；否则跳过（未到临近判定点窗口）
    3. 分群编码：仅使用 **`task_rule.distribution_object_group_id`**（trim），为空则跳过（不调分群接口）
    4. 调用 **`DataCrowdFeignService#doLatest(code)`**（网关 `/dwh/data-labeling/data/crowd/data/latest`）；失败记 warn 并跳过该包
    5. 取响应 **`data.list`**（对象编码列表），按固定批大小（500）分段；每段内做去空、trim、批内去重后对 **`task_distribution_detail`** 执行 **`UPDATE`**：`task_package_id` = 当前包、`is_deleted = 0`、`status = IN_PROGRESS`、`target_entity_code IN (...)` → **`status = COMPLETED`**，**`final_end_time = now`**（重复编码在后续批次再次命中时因状态已变更通常更新 0 行，不影响最终业务结果）
    6. 本包走完步骤 5 的批量更新后：**插入一条 `task_instance` 审计**：`task_rule_id` = 当前 **`task_rule.id`**；`source_data` = 本次 **`DataCrowdLatestRespDTO`** 的 JSON 序列化（完整 latest 结构，含 `code`/`msg`/`data`/`requestId` 等）；`task_code` 由 **`CodeGenerateUtils.generateCode("INST_CRON_CROWD_" + taskPackageId + "_")`** 生成；`task_title`/`task_description` 标明 CRON 分群 latest 快照及 **`task_package_id`、crowdCode、本次 UPDATE 累计行数**；`status = COMPLETED`，`distributed_at`/`completed_at` = 当前时刻，`triggered_by_data_change = 0`；`created_by`/`updated_by` 优先继承任务包，否则 **`JOB_CRON_CROWD_COMPLETION`**。插入失败仅 **warn**，**不回滚**已提交的明细更新
  - 预期结果：仅仍为进行中的明细被更新；已 COMPLETED/CLOSED/EXPIRED 不受影响；返回值为本轮 **`UPDATE` 影响行数之和**；**不修改** `task_definition.distribution_push_completed`，可与 **`syncInProgressPackagesByCrowd`** 并行调度；满足路径的包在 **`task_instance`** 中可追溯当次分群响应
  - **回归**：规则非 CRON、无群编码、`data.list` 空、分群接口报错时该包不产生明细更新；同一目标在多子任务下有多条进行中明细时，一次 **`IN`** 更新可一次命中多条；**有明细更新或更新行数为 0 但 list 非空时**均会尝试写入 **`task_instance`** 快照（便于对比分群返回与库中命中差异）

- **用例8：syncReadyPackagesAndTasksToInProgress**
  - XXL-JOB 任务名：`syncReadyPackagesAndTasksToInProgress`
  - 触发逻辑：
    1. 查询 `task_definition.task_type = PACKAGE` 且 `task_status = NOT_STARTED` 的任务包
    2. 过滤 `distributed_at <= now`（且 `distributed_at` 非空）
    3. 将命中的 PACKAGE 状态更新为 `IN_PROGRESS`，**`distribution_push_completed` 置为 `0`（空闲/未占用）**，并同步更新其 `task_month` 为**当前时间所在自然月**（存为当月1日，如 `2026-04-01`）
    4. 将该 PACKAGE 下 `task_type = TASK` 且 `task_status = NOT_STARTED` 的子任务逐条更新：状态为 `IN_PROGRESS`，`task_month` 与 PACKAGE 一致；**`start_time` 置为当前调度时间**；**`end_time`** 按子任务关联的 **`task_rule.deadlineType`** 与 **`task_rule.deadlineConfig`（JSON 字符串）** 解析：`RELATIVE` 时为 **（当前日期 + `days` 天）** 与配置 **`time`**；`ABSOLUTE` 时为 **`date`** 与 **`time`** 拼接；**`MONTH`** 时按 **`monthDimension` / `monthDay` / `time`** 以**当前调度时刻**为基准月解析（见 `TaskRuleMonthDeadlineSupport`）。规则缺失或解析失败时仍推进状态与 `start_time`，**`end_time` 不写入**，并打告警日志；**单条子任务解析失败不影响同包其它子任务及整段事务提交**
  - 预期结果：符合时间条件的任务包及其子 TASK 同步推进为进行中，且任务月与调度时当前月份一致；子 TASK 的 `start_time`/`end_time` 符合上述规则；不符合条件的数据保持原状态
  - 请求 JSON：无（调度中心仅配置 JobHandler 名称即可）

- **用例9：syncTaskDistributionDetailOwningDepartment（归属部门与部门路径补全）**
  - XXL-JOB 任务名：`syncTaskDistributionDetailOwningDepartment`
  - **任务参数**（可选）：由 **`SyncOwningDepartmentJobParamDTO.fromXxlJobParam`** 解析（见 `com.yqsl.sls.business.taskdistributiondetail.dto`）
    - **JSON**：`{"maxScanCount":5000,"createdWithinDays":14}` — `createdWithinDays` 为创建时间窗口天数，缺省或非法 **7**；`maxScanCount` 为兼容字段，**当前实现不参与查询**（可省略）
    - **纯数字**：仅设置 `maxScanCount`（仍兼容解析），`createdWithinDays` 用默认 **7**
    - **逗号分隔**：`5000,14` 依次为 `maxScanCount`、`createdWithinDays`（两段均为非负整数；`maxScanCount` 同上不参与 DISTINCT）
  - **Service**：`TaskDistributionDetailOwningDepartmentSyncJobService#syncOwningDepartmentFromDts(int maxScanCount, int createdWithinDays)`
  - **触发逻辑**：
    0. **单次 DISTINCT**：一次性查询步骤 1 中<strong>全部</strong>不同的 `target_entity_code`（无 `LIMIT`）；对每个编码<strong>只查 DTS 一次</strong>，再对该编码下仍满足「缺部门 + 时间窗口」的<strong>所有明细行</strong>执行一条批量 `UPDATE`。按编码顺序依次处理，累计返回值为本次调度 **`UPDATE` 影响行数之和**（非编码条数）
    1. **DISTINCT 目标编码**：`task_distribution_detail` 上 `is_deleted = 0`，**`object_code = 'STORE'`（仅门店）**，`target_entity_code` 非空且非 `''`，**`created_at` ≥ 当前调度时刻往前 `createdWithinDays` 天**，且 **`owning_department_code` 为 NULL 或空字符串**；`ORDER BY target_entity_code`；批量 `UPDATE` 条件与上述一致（含 `object_code`）
    2. 对每个去重后的 **`target_entity_code`**（DTS 账号用列值 **trim** 后匹配）作为 **`account_obj.account_no`**，经 **`DtsAccountObjService#getByAccountNo`** 查询 DTS（与 `AccountObjEntity` 同源 SQL：`SELECT * FROM account_obj WHERE account_no = ?`）
    3. 读取 **`data_own_department`**：若为 JSON 数组字符串则取**首个元素**作为部门主键 id；否则整段 trim 后作为 id
    4. 以该 id 查 **`department_obj`**（`DtsDepartmentObjService#getById`），取 **`dept_code`**、**`name`** 写入明细的 **`owning_department_code`**、**`owning_department_name`**
    5. 将当前部门行的 **`dept_parent_path`** 按 **`.`** 拆分为 id 序列（如 `999999.1002.1004`），对每个 id 批量查 **`department_obj`**，按路径顺序收集 **`dept_code`**，序列化为 **`department_path_json`**（JSON 数组字符串，如 `["ROOT","MID","LEAF"]`）；路径为空或无有效分段时写入 **`[]`**
  - **预期结果**：能解析账户与部门时，对应明细三字段被更新；账户或部门缺失、`data_own_department` 不可解析时跳过该编码并打 debug/warn 日志；返回值为本次调度累计成功 **`UPDATE`** 明细行数
  - **回归**：接口 **`TaskDistributionDetailDTO`** 中 **`departmentPath`** 由 **`department_path_json`** 反序列化为 `List<String>`；库表 DDL 见 **`dpc/sql/update_tables.sql`** / **`doc/sql/update_tables.sql`** 中 **`task_distribution_detail`** 三列追加语句

- **用例12t（回归，【测试】全量改明细状态）**
  - 接口：`POST /sales/task/biz/template/field/testUpdateAllDistributionDetailStatus`（挂在模板字段映射 Controller，与现有 `/runSyncHasVisitTask` 等测试接口并列；**仅测试环境使用**）
  - 请求 Body 示例：
    ```json
    {
      "status": "IN_PROGRESS",
      "//status": "必填：目标状态，枚举名 IN_PROGRESS / COMPLETED / CLOSED / EXPIRED（与 task_distribution_detail.status 一致，trim 后校验）"
    }
    ```
  - 业务：`TaskDistributionDetailService#testBulkUpdateAllNonDeletedDetailStatus`；仅更新 **`is_deleted = 0`** 且 **当前 `status` 为空或与目标不一致** 的行；每批最多约 **50 万** 行，循环直至本批影响 **0**；终态写入 **`final_end_time = 当前时间`**，**`IN_PROGRESS`** 时将 **`final_end_time` 置空**
  - 预期：`Response.success`，`data.updatedRows` 为累计更新行数（Long/Number 均可）；非法 `status` 业务错误；`status` 为空或缺字段校验失败
