# 任务下发明细测试规格（明细数据 + 条件匹配）

> **变更说明（2026-09-14）**：Kafka 评估创建 `task_instance` 时 `uk_task_code` 冲突不再让整条消息失败并跳过 offset。`task_code` 为 `INST_EVAL_{taskDefId}_{yyyyMMdd}_{无连字符UUID}`；插入走独立事务，冲突最多换码重试 8 次；单条明细失败仅跳过该明细。调用 `handleTaskDistribution` 前的消费入口不再重复打印消息 value，完整报文只在 Handler 打一次。
>
> **变更说明（2026-09-09）**：XXL `syncHasVisitTask` 仅性能优化、业务口径不变。默认每批门店 2000（服务端上限 2000）；判定「是/否」改为按 `target_entity_code` 分组聚合，不再整行 `selectList`；DTS 门店改为批量只查 `id/account_no/has_visit_task__c`。批量 DTS 查询失败时本批降级逐门店 `getByAccountNo`，单店异常仍只跳过该条，不中止 Job。XXL 参数若仍配 `30000` 会被截到 2000，游标扫完全量结果不变。
>
> 由原 `task_distribution_detail_*_test_spec` 合并，去除日期后缀。
>
> **变更说明（2026-08-13）**：`POST .../listGroupByTarget` 的 `targetEntityName` 改为模糊匹配（`target_entity_name LIKE`）；`targetEntityCode` 仍精准；两者均传时仍为 OR。
>
> **变更说明（2026-08-12）**：`POST .../export` CSV 表头对齐前端任务明细列表：`对象名称,对象编码,归属部门,最近拜访时间,任务,任务编码,任务说明,任务类型,关联任务组,状态,下发人,开始时间,截止时间,反馈原因,关联任务规则`（去掉对象类型/关联任务包/关联任务包规则/反馈原因其他双列；新增任务编码、关联任务组；反馈原因取 content 优先）。
>
> **变更说明（TGR-016 · 2026-08-04）**：`/list`、`/listByPackage` 宽泛浏览 id 降序窗口由 **10000 → 1000**（OP 部门过滤宽泛浏览同为 1000）；精准等值筛选仍全量；`/export` 仍全量；`statusStats` / `statusStatsByListByPackage` **可保留但非列表首屏必调**（全量聚合、不受 1000 窗口限制）。
>
> **变更说明（TGR-008 / TGR-011 · 2026-08-10）**：
> - **去重**：仅 3 值 **`MONTH`（默认单月）/ `DAYS`（单日）/ `GLOBAL`（全局）**；历史 `NONE`/`LEGACY`→`GLOBAL`；空按 `is_repeat` 推断（1→GLOBAL，否则 MONTH）。
> - **下发群**：**仅**任务包 `task_package_distribution_ext.distribution_object_group_id` 一次 `doLatest`；子 TASK 规则不绑定下发群。
> - **DDL**：删除 `uk_task_pkg_def_target_code`；刷数将历史 NONE/LEGACY→GLOBAL、空→MONTH。

---

## 第一篇：明细触发、API 与 Action 同步

### 功能模块：任务下发明细触发

### 一、业务说明

遍历 TaskInstance 数据，判断任务包类型，在到达下发时间（distributed_at）时触发创建 task_distribution_detail。任务包下若有多个普通任务(TASK)，则为每个(任务包+普通任务+目标实体)创建一条明细，分别关联 task_package_id 和 task_def_id。

表字段 **`object_code`**：对象编码语义，与 `task_definition.object_code` 一致；接口返回 `TaskDistributionDetailDTO` 时带出 `objectCode`（表已无 `object_type` 列）。

表字段 **`feedback_reason`**（2026-06-11）：反馈原因，存储用户选择的反馈理由（字符串，可 null）；接口 **`TaskDistributionDetailDTO.feedbackReason`** 回显。

表字段 **`feedback_reason_content`**（2026-06-11）：反馈原因补充内容（如选择「其他」时填写的说明文本，字符串，可 null）；接口 **`TaskDistributionDetailDTO.feedbackReasonContent`** 回显。任务定义侧反馈选项配置见 **`task_definition.feedback_*`** 字段（`task_definition_test_spec.md`）。

**反馈 API**（2026-06-15）：**`POST /sales/task/distribution/detail/feedback/submit`** 提交未完成反馈；**`POST .../feedback/update`** 修改已提交反馈；**`POST .../feedback/close`** 关闭任务明细。均校验明细关联 TASK 的 **`feedback_enabled`**；关闭另须 **`feedback_close=true`**。

**任务组关联（2026-08-03 · TGR-002）**：**`task_distribution_detail` 不存 `task_group_id`**（任务组可改绑，冗余会过期）。明细仍仅 **`task_package_id`** 指向任务包；按任务组筛选时：
- 先查 **`task_definition.id`**（`task_type=PACKAGE AND task_group_id=?`）得到包 id 列表，再 **`task_package_id IN (...)`**；或 SQL JOIN `task_definition pkg ON pkg.id = detail.task_package_id`。
- **`TaskDistributionDetailDTO`** 无 **`taskGroupId`** 字段；组维度统计/筛选见 **`doc/任务组结构改造_test_spec.md`**、**`doc/任务组_test_spec.md`**。

### 二、定时任务

- 原 XXL-JOB `triggerTaskDistributionDetail`（扫描 PENDING 实例并下发明细）已移除，对应 `TaskDistributionTriggerService` 已删除；本模块其余 Job 见 `TaskDistributionDetailJob`：`syncPackageTaskStatusCompleted`（扫描进行中任务包，子 TASK 全部 `end_time` 到期则 TASK/PACKAGE 过期）、**`expireInProgressDetailsPastEndTime`**（按明细**判断截止**全表批量过期进行中明细：任务截止已到但判断截止未到则保持 `IN_PROGRESS`；未配置判断截止则等同任务截止；可与前者分调度并存）、`syncReadyPackagesAndTasksToInProgress`、`syncInProgressPackagesByCrowd`、`refreshInProgressPackageCronDistributedAt`、`completeInProgressDetailsByCrowdForCronCompletionJudgment`（对象群完成判断：扫启用包且包 `end_time` 放宽 **16** 天，**仅更新明细 `status=IN_PROGRESS`**）、`scanInProgressTaskDelaySyncStrategy`（DELAY 完成判断，**仅扫 `IN_PROGRESS` 明细**）、**`syncTaskDistributionDetailOwningDepartment`**（补全归属部门与部门路径）、**`refreshTaskDistributionDetailStatusStatsCache`**（预热 `statusStats` / `statusStatsByListByPackage` 两处 Redis）、**`syncHasVisitTask`**（同步销客 `has_visit_task__c`：按门店编码游标分批，默认每批 2000、上限 2000；分组聚合是否有未结束明细后批量读 DTS 再逐条更新，口径与实时完成回写一致）等。

- **用例（回归 · 2026-09-09）`syncHasVisitTask` 性能优化不改口径**
  - 前置：存在 STORE 明细，`final_end_time` 为空或大于 Job 启动时 `now-2天`；对应 `account_obj.account_no` 有记录
  - 预期：
    - 某门店只要有一条 `final_end_time IS NULL` 的未删除 STORE 明细 → 同步值为「是」（销客 `yes`）
    - 否则（仅有 `final_end_time > cutoff` 的明细）→ 「否」（销客 `no`）
    - DTS 当前值已一致则跳过更新；查不到 account / 无 id 记跳过
    - 全量扫描结果与优化前一致；单批门店数即使 XXL 仍配 30000 也按 2000 截断后多批跑完
    - 批量 `mapHasVisitTaskFieldsByAccountNos` 抛错时本批降级 `getByAccountNo`，Job 不中止；单店 DTS/销客异常仍只跳过该条并继续下一家

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

- **用例10a：提交未完成反馈**
  - 接口：`POST /sales/task/distribution/detail/feedback/submit`
  - 请求 Body 示例：
    ```json
    {
      "id": 1,
      "//id": "任务下发明细主键，必填",
      "feedbackReason": "缺货",
      "//feedbackReason": "反馈原因，必填",
      "feedbackReasonContent": "货架无陈列",
      "//feedbackReasonContent": "反馈原因补充内容，可选"
    }
    ```
  - 业务：校验明细存在且 `status=IN_PROGRESS`；关联 TASK（`task_def_id`）的 `feedback_enabled=true`，否则业务错误「当前任务不允许反馈」；写入 `feedback_reason`、`feedback_reason_content`
  - 预期：`Response.success`；明细字段更新成功

- **用例10b：修改已提交反馈**
  - 接口：`POST /sales/task/distribution/detail/feedback/update`
  - 请求 Body 与用例10a 同构（`id`、`feedbackReason` 必填；`feedbackReasonContent` 可选）
  - 业务：校验关联 TASK `feedback_enabled=true`；明细已存在非空 `feedback_reason`，否则「尚未提交反馈，无法修改」
  - 预期：`Response.success`；反馈字段被覆盖更新

- **用例10c：关闭任务明细（反馈关闭）**
  - 接口：`POST /sales/task/distribution/detail/feedback/close`
  - 请求 Body 示例：
    ```json
    {
      "id": 1,
      "//id": "任务下发明细主键，必填"
    }
    ```
  - 业务：校验明细 `status=IN_PROGRESS`；关联 TASK 须 `feedback_enabled=true` 且 `feedback_close=true`，否则「当前任务不允许关闭」；将 `status` 置为 `CLOSED` 并写入 `final_end_time`
  - 预期：`Response.success`；明细状态为 CLOSED

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
  - 必传：aggregationFilter（EXECUTION_TYPE、TASK_GROUP 或 MONTH；**PACKAGE 同 TASK_GROUP，兼容旧值**）；targetEntityId、targetEntityCode、targetEntityName 至少传一个
  - aggregationFilter=EXECUTION_TYPE：按明细 `taskExecutionType` 反查 `task_execution_type_option`（status=1）得到 `taskExecutionTypeName` 作为 groupKey，groupId 为 null；**组间按字典 `sortOrder` 升序**；编码为空或未命中字典的明细**合并为「其他」并排在最后**
  - aggregationFilter=TASK_GROUP（或 PACKAGE）：按明细所属任务包 **`task_definition.task_group_id`** 分组，**groupKey 为任务组 `groupName`**（`task_group.group_name`；无名称时回退为 taskGroupId 字符串），**groupId 为 taskGroupId**；响应每组另含 **`taskGroup`**（`TaskGroupDTO` 主表字段：id、groupName、groupCode、remark、strategyTags、status 等）；无 `task_group_id` 的明细合并为 **「未关联任务组」** 并排最后
  - aggregationFilter=MONTH：按明细 `taskMonth` 分组（`taskMonth` 由 `end_time` 所在自然月生成），groupKey 为 **`yyyy-MM`**（如 `2026-03`），groupId 为 null；**组间按月份倒序**（新月份在前）；`taskMonth` 为空（即 `end_time` 为空）的明细合并为 **「其他」** 并排最后
  - 可选筛选：startTime、endTime、status、taskExecutionType；目标条件为列 **精准匹配**（trim），无 id 且编码+名称均传时为 `(code OR name)`；有 id 时与编码/名称组合见服务层 `applyDetailByTargetEntityMatch`
  - 预期结果：返回 `List<TaskDistributionDetailAggregatedGroupDTO>`，每条含 groupKey、groupId、**taskGroup**（按任务组聚合时有值）、list（单条为 `TaskDistributionDetailDTO`）；`list` 内填充 `taskPackage`（单元素列表，含 **taskGroupId/taskGroupName**）、`taskDefinition`（包下全部 TASK 子任务），均为 `task_definition` **主表映射**，**不返回** `taskRuleList`、`packageDistributionExt`、`childTaskList`（**与 `/detail` 全量结构不同**）
  - 响应示例（aggregationFilter=TASK_GROUP）：
    ```json
    {
      "code": 0,
      "message": "success",
      "data": [
        {
          "groupKey": "华东陈列任务组",
          "groupId": 3,
          "taskGroup": {
            "id": 3,
            "groupName": "华东陈列任务组",
            "groupCode": "RWZ26031800000001",
            "remark": "备注",
            "strategyTags": null,
            "status": 1
          },
          "list": [
            {
              "id": 1001,
              "taskPackageId": 268,
              "taskDefId": 501,
              "taskTitle": "任务标题",
              "taskPackage": [
                {
                  "id": 268,
                  "taskName": "某任务包",
                  "taskGroupId": 3,
                  "taskGroupName": "华东陈列任务组"
                }
              ],
              "taskDefinition": []
            }
          ]
        }
      ]
    }
    ```
  - **性能**：明细一次 `selectList`；任务包/独立任务 `selectBatchIds` 批量查主表，子任务 `parent_id IN` 批量查，任务组 `task_group.id IN` 批量查，不调用 `TaskDefinitionService#findById`
  - 回归：去除分页，全量查询；aggregationFilter 必填且支持 EXECUTION_TYPE、TASK_GROUP（PACKAGE 兼容）、MONTH

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
      "//recentWindow": "宽泛浏览时 /list total 基于「命中筛选后 id 降序最近若干条」（默认 1000；OP 部门过滤宽泛浏览同为 1000）；精准等值全量；/export 仍全量；statusStats 非首屏必调",
      "owningDepartmentCodes": ["97302222", "550425786"],
      "//owningDepartmentCodes": "可选：department_path_json JSON 数组与任一编码命中即保留（OR）"
    }
    ```
  - 字段说明：`objectCode` **必传**；`page` 当前页；`pageSize` 每页条数；`taskPackageId` 任务包 ID；`taskDefId` 普通任务 ID；`taskInstanceId` 任务实例 ID；`targetEntityType` 目标实体类型；`targetEntityId` 目标实体 ID（精准）；**`targetEntityCode` / `targetEntityName`**：仅传编码则 **`target_entity_code = trim(code)`**；仅传名称则 **`target_entity_name = trim(name)`**；**均传**则 **`(target_entity_code = trim(code) OR target_entity_name = trim(name))`**（**非 LIKE**）；**均不传则不按目标编码/名称筛**；**`owningDepartmentCodes`**：非空时，明细 **`department_path_json`**（JSON 数组，如 `["97302222","550425786"]`）与入参**任一** dept_code 命中即保留（`JSON_CONTAINS`，OR）；`taskName` 任务名称（**模糊**：`task_title` LIKE **或** 关联 `task_definition.task_name` LIKE，二者命中其一即可）；`status` 明细状态；**`taskExecutionType`** 任务执行类型编码（**精准匹配** `task_execution_type`，入参 **trim** 后与库值相等）；**时间（`buildListQueryWrapper`）**：**`startTimeFrom` 与 `endTimeFrom` 同时非空**时，对明细 **`end_time` 闭区间**：`end_time >= startTimeFrom AND end_time <= endTimeFrom`（此时 **`startTimeFrom` 不再**作为 `start_time` 下限，**`endTimeFrom` 不再**作为单独的 `end_time` 下限）；**否则**：`startTimeFrom`/`startTimeTo` 分别对 `start_time` 下/上界（可只传一端）；**单独**的 `endTimeFrom` 表示 `end_time` 下限（含）、`endTimeTo` 表示 `end_time` 上限（含）。**`startTimeTo`、`endTimeTo` 在「双 From 」模式下仍生效**（与上述条件 AND）。时间字符串推荐 `yyyy-MM-dd HH:mm:ss`（亦支持 ISO-8601，如 `2026-03-01T00:00:00`）。
  - 可选筛选：taskPackageId、**taskGroupId**（精准：明细所属 PACKAGE 的 `task_group_id`，exists 子查询）、taskDefId、taskInstanceId、targetEntityType、targetEntityId、targetEntityCode、targetEntityName、taskName、status、taskExecutionType（精准）、startTimeFrom、startTimeTo、endTimeFrom、endTimeTo、owningDepartmentCodes
  - 预期结果：返回 `Response.success`，data 为 `PageResult<TaskDistributionDetailDTO>`；**宽泛浏览**时 **`total` ≤ 1000**（先对命中 `buildListQueryWrapper` 的明细按 **`id` 降序**仅取最近 **1000** 条再 `COUNT`/分页）；**精准等值筛选**（`taskPackageId`、`taskDefId`、`taskInstanceId`、`targetEntityType`、`targetEntityId`、`targetEntityCode`、`targetEntityName`、`status`、`taskExecutionType` 任一有值）时 **全量** 命中行参与 `total` 与分页；每条记录为一条下发明细（平铺 1 对 1），除表字段外填充：`taskPackage`（任务包 `TaskDefinitionDTO` 单元素列表）、`taskDefinition`（该包下全部 `task_type=TASK` 子任务）；**`taskPackage[0]` 另回填 `taskGroupId`/`taskGroupName`**（按包 `task_group_id` 批量查 `task_group.group_name`，供前端「关联任务组」列）；**仅 `objectCode=STORE`** 时填充 **`lastVisitClosedTime`（最后巡店时间，`yyyy-MM-dd HH:mm:ss`；按 `target_entity_code`→`account_obj.account_no` 批量查 `last_visit_closed_time` 毫秒时间戳转换）**，其它 objectCode 为 null；**列表轻量**：`taskPackage`/`taskDefinition` 元素为 `task_definition` 主表映射，**不返回** `linkedTemplateDefinitionList`，**不返回** `completionScript`（为 null）；任务包仍填充 `packageDistributionExt`（与详情中 PACKAGE 下发扩展一致）；`taskInstance` 不集成（为 null）；**`samePackageEntityDetailList`、`taskPackageFilteredDetailList` 均不填充（为 null）**；**与** `POST .../detail`、`POST .../detailByTarget` **全量任务定义结构不同**（后者仍含关联模板、完成脚本等）
  - 回归：仅查询 `is_deleted=0` 的明细
  - **回归（taskGroupId · SQL 别名）**：传 `taskGroupId` 时 exists 相关列须用裸名 `task_package_id`（勿写 `task_distribution_detail.task_package_id`）；`pageTaskDistributionDetailRecentWindow` 外层 `FROM task_distribution_detail d` 时带表名前缀会报 `Unknown column`
  - **回归（性能 · TGR-016）**：宽泛浏览时 `/list` 与 `/listByPackage` 共用 id 降序窗口（默认 **1000**；**OP 部门过滤宽泛浏览同为 1000**）；精准等值筛选全量；索引见 `dpc/sql/update_tables.sql` 2026-06-18 段；**`POST .../export`** 仍全量流式导出；**`statusStats*` 非列表首屏必调**

- **用例12i（回归）：精准等值筛选全量 vs 宽泛浏览 1000 条窗口**
  - **精准**：入参 `objectCode` + `targetEntityCode`（或 `taskPackageId` / `status` 等任一项精准等值）
  - 预期：`/list`、`/listByPackage` 的 `total` 为**全量**命中行（或全量去重组合数），不受 1000 条窗口限制
  - **宽泛**：入参仅 `objectCode`（可叠加 `taskName`、`owningDepartmentCodes`、时间区间，**不含**上述精准等值字段）
  - 预期：`total` ≤ 1000；更早明细不在结果集

- **用例12f（回归）：owningDepartmentCodes 匹配 department_path_json**
  - 入参：`objectCode` 必传，`owningDepartmentCodes`: `["97302222", "550425786"]`
  - 预期：`/list`、`/listByPackage`、`/export` 等共用 `buildListQueryWrapper` 的接口，返回 `department_path_json` **包含任一**入参 dept_code 的明细，**或**归属部门无值（`department_path_json` 为 null/`[]`/空数组，或 `owning_department_code` 为空）的明细；不传或空数组时不按部门路径筛

- **用例12g（回归）：OP 数据资源部门权限过滤（/list、/listByPackage）**
  - 前置：请求头带 `op-account-code`（或网关透传 `opAccountCode`），服务调用 `infra-oauth` `findAccountAppDataResource(appCode, serviceCode, accountCode)`
  - **管理员**：返回数据 resources 的 `values` 中含 `key=sales-task-admin`
    - 预期：不做部门拦截，行为与改前一致（`owningDepartmentCodes` 仅由 Body 决定）
  - **部门范围**：含 `key=sls-sales-task-dept`，递归其 `values` **每一层**非空 key（含中间节点与叶子；例父 `715326994` + 其子部门均纳入）
    - 预期：服务端将上述编码写入 `owningDepartmentCodes` 参与 `department_path_json` 筛选；**当前登录人挂载 `deptCode`，以及其作为负责人管理的部门，永远并入权限集合**（即使 infra 未配置这些部门编码也会并入）；管理部门来自 EHR `POST /ehr/api/contact/v1/departments/list`，`list` 为当前用户 userId（优先 `opUser.userId`，为空则用请求头 `userId`），`fieldType=2`（deptLeaderId），`status=0`（未删除），可返回多个部门；Body 未传部门时，非管理员按 **OP 权限部门 ∪ 登录人挂载部门 ∪ 管理部门** 全集做 OR 过滤（`owning_department_code IN` / `JSON_CONTAINS`）；Body 已传时与权限部门合并：精确命中 **或** 请求部门位于权限部门子树内（勾选父部门后可选其子部门），否则返回空分页（`total=0`）
    - **回归**：挂载部门为「通州销售组」，管理部门含「市区销售2组」和「通州销售组」时，请求市区销售2组放行，权限集合外的部门返回空分页；EHR 管理部门查询失败时仍保留挂载部门权限
    - **回归**：权限树为 `715326994 → [子部门…]` 时，请求 `deptCode`/`owningDepartmentCodes`=`715326994` 必须命中权限（不得因仅收集叶子而过滤为空）
    - **回归**：仅配置父部门 `715326994`（或权限集合含父不含某 EHR 子部门）时，请求其子部门编码仍应放行（父权覆盖子树）
  - **无权限**：无 `sales-task-admin`、无有效 `sls-sales-task-dept` 子节点，且登录人无挂载 `deptCode`、也无管理部门
    - 预期：`/list`、`/listByPackage` 直接返回空分页，不查库
  - **infra-oauth 查询失败或异常**：返回 `false`，列表/统计为空、导出仅表头
  - **外勤 JWT**（无 `opAccountCode`）：跳过数据资源过滤
  - **`op.config.enable=false` 或未配置**：跳过数据资源过滤，与管理员一致

- **用例12a（回归）：targetEntityCode/targetEntityName 精准 + OR**
  - 入参：`objectCode` 与库中一致，`targetEntityCode` 传**与库完全一致**的门店编码，`targetEntityName` 不传
  - 预期：返回行满足 `target_entity_code = trim(入参)`；仅传 `targetEntityName` 时满足 `target_entity_name = trim(入参)`；两字段均传时满足 `(target_entity_code = trim(code) OR target_entity_name = trim(name))`

- **用例12e（回归）：startTimeFrom + endTimeFrom 同时有值 → 按明细 end_time 闭区间**
  - 入参：`objectCode` 必传，另传 `startTimeFrom`、`endTimeFrom` 均有值（如 `2026-03-01 00:00:00`、`2026-03-15 23:59:59`），不传或传空 `startTimeTo`/`endTimeTo` 亦可
  - 预期：`/list`、`/listByPackage`、`/export`、`/statusStats`、`/statusStatsByListByPackage` 等共用 `buildListQueryWrapper` 的接口，筛选等价于 **`end_time >= startTimeFrom AND end_time <= endTimeFrom`**；**不传** `endTimeFrom` 而仅传 `startTimeFrom` 时，仍为 **`start_time >= startTimeFrom`**（与改前一致）

- **用例12d（回归）：流式导出 CSV**
  - 接口：`POST /sales/task/distribution/detail/export`（**筛选字段与用例12 `POST .../list` 一致**，同一 `TaskDistributionDetailListRequest`；**必传 `objectCode`**；**不分页**，默认**按筛选全量**导出；`page`/`pageSize` **无效**）
  - **OP 部门过滤**：与 `/list`、用例12g 一致；无权限时仅返回 CSV 表头（无数据行）
  - 预期：`Content-Type: text/csv;charset=UTF-8`，`Content-Disposition: attachment; filename="task_detail_yyyyMMddHHmmss.csv"`，响应体为 **UTF-8 BOM**；**首行为中文表头**（与前端任务明细列表列一致）：`对象名称,对象编码,归属部门,最近拜访时间,任务,任务编码,任务说明,任务类型,关联任务组,状态,下发人,开始时间,截止时间,反馈原因,关联任务规则`；**仅 `objectCode=STORE`** 时「最近拜访时间」列有值（DTS `account_obj.last_visit_closed_time`→`yyyy-MM-dd HH:mm:ss`），其它 objectCode 该列为空；数据列依次为明细 **`target_entity_name`（对象名称）、`target_entity_code`（对象编码）、`owning_department_name`、最近拜访时间、`task_title`、本行 `task_def_id` 对应 **`task_definition.task_code`（任务编码）**、`task_description`**（任务类型列优先 **`task_execution_type_name`**，否则编码）、**关联任务组**（本行 `task_package_id` 对应 PACKAGE 的 **`task_group_id`→`task_group.group_name`**）、**`status` 中文枚举**（进行中、已完成、已关闭、已过期）、**`created_by`（下发人）**、**`start_time`、`end_time`**（`yyyy-MM-dd HH:mm:ss`）、**反馈原因**（优先 **`feedback_reason_content`**，空则回退 **`feedback_reason`**）、**关联任务规则**（本行 `task_def_id` 对应 **`task_definition.task_name`**）；按 **`id` 升序**；服务端按主键游标 **`id > lastId`** 分批查询并批量解析任务定义/任务组及 DTS 最近拜访时间后写入，**流式输出**（**不在内存中一次性组装全量 CSV 或全表明细**）

- **用例12b：按 objectCode+targetEntityCode 去重查询下发明细（分页）**
  - 接口：`POST /sales/task/distribution/detail/listByPackage`（与网关前缀一致；若无前缀则与 `/list` 同前缀）
  - 必传：`objectCode`（与用例12一致）
  - 请求 Body：与用例12完全一致（含 `page`、`pageSize`、`objectCode` 及筛选字段）
  - 业务说明：与用例12 **共用**「宽泛浏览 1000 条窗口 / 精准等值全量」口径（见用例12i）。**宽泛浏览**时：先按明细 `id` 降序取最近 **1000** 条命中行，再在该子集上按 **`task_package_id` + `target_entity_code`** 分组，每组取 **`id` 最大**代表行，`total` 为子集内不同组合数。**精准等值筛选**（`taskPackageId`、`targetEntityCode`、`status` 等任一有值）时：对命中行**全量** `GROUP BY` 取代表行，`total` 为全量去重组合数。仅参与 **`task_package_id`、`target_entity_code` 均非空** 的明细分组。`records` 中每条为代表明细：`taskPackage`/`taskDefinition` 与用例12 `/list` 同为轻量批量加载；**不填充** `samePackageEntityDetailList`、`taskPackageFilteredDetailList`（均为 null）
  - 预期结果：`PageResult` 结构与用例12 相同（`taskInstance` 不集成；`samePackageEntityDetailList`、`taskPackageFilteredDetailList` 均为 null）；**仅 `objectCode=STORE`** 时代表行含 **`lastVisitClosedTime`**，其它 objectCode 为 null
  - **回归（与 /list 一致）**：代表行 `taskPackage`、`taskDefinition`（含 `taskPackage[0].childTaskList` 内各子任务）上 **`linkedTemplateDefinitionList` 均为 null**（服务端不显式填充模板详情列表，避免与详情接口同 payload）
  - 实现说明（性能）：宽泛浏览时去重 `COUNT` / `GROUP BY` 在「最近 1000 条」子查询内完成；精准搜索直接全量 `GROUP BY`；代表行 **`selectBatchIds`** 批量加载；本页 `task_definition` / 下发扩展 **按页批量预取**（与 `/list` 同 `DistributionListLiteCaches`）

- **用例12h：按 objectCode 对 target 聚合（种子 20 条去重，编码精准、名称模糊，每行含 detailCount）**
  - 接口：`POST /sales/task/distribution/detail/listGroupByTarget`（**独立**于 `/list`、`/listByPackage`，不返回整包 DTO 嵌套；仅汇总展示字段 + `detailCount`）
  - 必传：`objectCode`；**`page`、`pageSize` 由服务端忽略**；`PageResult.total` = 本次实际返回的组数（**≤20**），`page`=1，`pageSize`=20，`totalPage` 为 0 或 1
  - 业务：在 `is_deleted=0`、**`status = IN_PROGRESS`** 且 `object_code`、`target_entity_code` 均非空的明细上：① **仅传 `objectCode`**（不传其它可选筛选）时，先按 **`id` 倒序 `LIMIT 20`** 取进行中明细，对其 **`target_entity_code` 去重**（顺序为种子中出现顺序），再对去重后的编码在**同一基础条件**（仅 objectCode+进行中+未删除+编码非空）下按组算 **`detailCount`** 与组内 **`MAX(id)` 代表行**；② **任一带可选筛选**（含 `targetEntityCode`/`targetEntityName`/`taskTitle`/`owningDepartmentName`/`taskGroupId`/`taskPackageId`/`taskDefId`/`taskExecutionType`）时，种子 20 条与后续聚合的 `WHERE` **均含全量可选条件**，`detailCount` 为各目标在该全量条件下的进行中条数。`targetEntityCode` 为 **trim 后精准等值**；`targetEntityName` 为 **trim 后模糊匹配**（`target_entity_name LIKE`；可选；**两者均传时为 OR**）；**`taskTitle`** 模糊匹配明细 **`task_title`**；**`owningDepartmentName`** 为模糊；**`taskGroupId`** 按所属 PACKAGE 的 **`task_group_id`**（exists，与 `/list` 一致）；**`taskPackageId`** 精准匹配 **`task_package_id`**；**`taskDefId`** 精准匹配 **`task_def_id`**；**`taskExecutionType`** 精准匹配 **`task_execution_type`**（trim，与 `/list` 一致）。代表行展示字段取组内 **`id` 最大**的一条。
  - 请求 Body 示例：
    ```json
    {
      "objectCode": "STORE",
      "taskGroupId": 1001,
      "//taskGroupId": "可选：按所属包 task_group_id 筛选（与 /list 一致，exists 子查询）",
      "taskPackageId": 10001,
      "//taskPackageId": "可选：精准匹配 task_package_id（与 /list 一致）",
      "taskDefId": 1001,
      "//taskDefId": "可选：精准匹配 task_def_id（子任务 id）",
      "taskExecutionType": "VISIT",
      "//taskExecutionType": "可选：精准匹配 task_execution_type（trim）",
      "targetEntityCode": "WD35025932",
      "//targetEntityCode": "可选：精准等于 target_entity_code（trim）",
      "targetEntityName": "阳西县联兴食品批发商行",
      "//targetEntityName": "可选：模糊匹配 target_entity_name（trim 后 LIKE）；与编码同时传时为 OR",
      "taskTitle": "陈列",
      "//taskTitle": "可选：模糊匹配明细 task_title",
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
  - 回归：无 `objectCode` 时业务错误；仅查 `is_deleted=0` 且 **`status=IN_PROGRESS`**；仅 objectCode 时种子不带目标/标题/部门筛选，返回组数为最近 20 条内去重后的目标数（≤20）；仅传名称时命中 **LIKE**；编码与名称均传时命中 **OR**（编码等值或名称模糊）
  - 回归（taskPackageId/taskDefId）：传 `taskPackageId` 或 `taskDefId` 时种子与 `detailCount` 均按对应精准条件过滤（与 `/list` 一致）
  - 回归（性能/语义）：接口为 **1 次种子列表 + 1 次分组聚合（`listMaxIdAndCountByTargetEntityCodes`）+ 1 次 `selectBatchIds`**；无全库按目标分组取 TOP N

- **用例12f：下发明细状态统计（完成/进行中/过期/关闭）**
  - 接口：`POST /sales/task/distribution/detail/statusStats`（**非列表首屏必调**，TGR-016；接口可保留供按需调用）
  - 必传：`objectCode`；**筛选字段与 `/list` 一致**（同一 `TaskDistributionDetailListRequest`）；`page`、`pageSize` **忽略**
  - 请求 Body 示例（仅 objectCode，与改前兼容）：
    ```json
    {
      "objectCode": "STORE" // 对象编码，精准匹配 object_code，必传
    }
    ```
  - 带列表筛选时示例（与 `/list` 同参，统计口径一致）：
    ```json
    {
      "objectCode": "STORE", // 对象编码，必传
      "taskPackageId": 10001, // 任务包ID，可选，精准
      "taskDefId": 20002, // 普通任务ID，可选，精准
      "status": "IN_PROGRESS", // 状态，可选，精准；传则仅该状态桶可能非 0
      "taskExecutionType": "VISIT", // 任务执行类型，可选，精准 trim
      "targetEntityCode": "WD35025932", // 目标实体编码，可选，精准 trim；与 targetEntityName 均传时为 OR
      "targetEntityName": "某某门店", // 目标实体名称，可选，精准 trim
      "taskName": "巡店", // 任务名称，可选，模糊
      "owningDepartmentCodes": ["97302222"], // 归属部门路径编码，可选，OR 匹配 department_path_json
      "startTimeFrom": "2026-03-01 00:00:00", // 与 endTimeFrom 同时有值时筛 end_time 闭区间下界；仅单独有值时筛 start_time 下限
      "endTimeFrom": "2026-03-15 23:59:59" // 与 startTimeFrom 同时有值时筛 end_time 闭区间上界
    }
    ```
  - 预期结果：`Response.success`，`data` 返回四个状态数量，未命中状态返回 `0`；统计行集合与同 Body 调 `/list`（忽略分页窗口差异：statusStats **全量**命中行按 status 聚合，**不**截取最近 1000 条）一致
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
  - 回归：仅统计 `is_deleted=0`；无 `objectCode` 时业务错误；与 `/list` 共用 `buildListQueryWrapper`，筛选字段语义一致
  - **部门过滤**：与 `/list` 共用 `buildListQueryWrapper`，`owningDepartmentCodes` 命中路径 **或** 无部门明细均计入统计
  - **OP 部门过滤**：与用例12g 一致（`sales-task-admin` 不拦截；`sls-sales-task-dept` 按权限部门 + **无部门明细全员可见**）；无权限时四类计数均为 `0`
  - **缓存（Redis）**：仅当 Body **无**除 `objectCode` / `owningDepartmentCodes`（及无效的 page/pageSize）外的其它筛选时，key 为 **`RedisConstants.taskDistributionDetailStatusStatsKey(objectCode, owningDepartmentCodes)`**（`objectCode` trim；有部门范围时后缀 `:depts:` + 排序后部门编码），**30 分钟**过期；携带 `taskPackageId`/`status`/时间等任一列表筛选时**直查库、不读写 Redis**；Redis 异常时降级查库
- **用例12g：下发明细状态统计（listByPackage 去重维度）**
  - 接口：`POST /sales/task/distribution/detail/statusStatsByListByPackage`（**非列表首屏必调**，TGR-016；接口可保留供按需调用）
  - 必传：`objectCode`；**筛选字段与 `/listByPackage` 一致**（同一 `TaskDistributionDetailListRequest`）；`page`、`pageSize` **忽略**
  - 说明：与 **`listByPackage`** 相同的**去重维度**：在 `is_deleted=0`、筛选命中、`task_package_id IS NOT NULL`、`target_entity_code IS NOT NULL` 的明细上，对每个 `(task_package_id, target_entity_code)` 取组内 **`MAX(id)`** 代表行，再按代表行 `status` 归入 completed / inProgress / closed；**全量命中行参与分组**，**无**「最近 1000 条 id」截断（与 **`POST .../listByPackage` 列表**不同，列表仍保留 1000 条预截断）。**不统计已过期**：代表行为 **`EXPIRED`** 的组合**不计入**本接口任一状态桶，响应中 **`expiredCount` 恒为 `0`**。
  - 请求 Body 示例（仅 objectCode，与改前兼容）：
    ```json
    {
      "objectCode": "STORE" // 对象编码，精准匹配 object_code，必传
    }
    ```
  - 带列表筛选时示例（与 `/listByPackage` 同参，统计口径一致）：
    ```json
    {
      "objectCode": "STORE", // 对象编码，必传
      "taskPackageId": 10001, // 任务包ID，可选，精准
      "taskDefId": 20002, // 普通任务ID，可选，精准
      "status": "IN_PROGRESS", // 状态，可选，精准；传则仅该状态桶可能非 0
      "taskExecutionType": "VISIT", // 任务执行类型，可选，精准 trim
      "targetEntityCode": "WD35025932", // 目标实体编码，可选，精准 trim；与 targetEntityName 均传时为 OR
      "targetEntityName": "某某门店", // 目标实体名称，可选，精准 trim
      "taskName": "巡店", // 任务名称，可选，模糊
      "owningDepartmentCodes": ["97302222"], // 归属部门路径编码，可选，OR 匹配 department_path_json
      "startTimeFrom": "2026-03-01 00:00:00", // 与 endTimeFrom 同时有值时筛 end_time 闭区间下界；仅单独有值时筛 start_time 下限
      "endTimeFrom": "2026-03-15 23:59:59" // 与 startTimeFrom 同时有值时筛 end_time 闭区间上界
    }
    ```
  - 预期结果：`Response.success`，`data` 含 `completedCount`、`inProgressCount`、`closedCount`；**`expiredCount` 恒为 `0`**；无命中状态时前三项为 `0`；统计代表行集合与同 Body 调 `/listByPackage`（忽略列表 1000 条窗口）筛选口径一致
  - 回归：无 `objectCode` 时业务错误；与 `/listByPackage` 共用 `buildListQueryWrapper`，筛选字段语义一致；仅 objectCode 时 **`completedCount` + `inProgressCount` + `closedCount`** 等于全量下「代表行 `status` 不为 **`EXPIRED`**」的 `(task_package_id, target_entity_code)` 组数
  - **部门过滤**：与 `/listByPackage` 共用 `buildListQueryWrapper`，`owningDepartmentCodes` 命中路径 **或** 无部门明细均计入统计
  - **OP 部门过滤**：与 `/listByPackage` 一致；无权限时四类计数均为 `0`
  - **缓存（Redis）**：仅当 Body **无**除 `objectCode` / `owningDepartmentCodes`（及无效的 page/pageSize）外的其它筛选时，key 为 **`RedisConstants.taskDistributionDetailStatusStatsByListByPackageKey(objectCode, owningDepartmentCodes)`**（`objectCode` trim；有部门范围时后缀 `:depts:` + 排序后部门编码），**30 分钟**过期；携带 `taskPackageId`/`status`/时间等任一列表筛选时**直查库、不读写 Redis**；Redis 异常时降级查库

- **用例12fg-cache（回归）：状态统计 Redis 按 objectCode**
  - 步骤：对同一 `objectCode`（**不带**其它列表筛选）连续两次调用 `POST .../statusStats` 或 `POST .../statusStatsByListByPackage`
  - 预期：第二次与第一次统计结构一致；`statusStats` 与 `statusStatsByListByPackage` 使用**不同 Redis key 前缀**，互不串缓存；两接口携带 `taskPackageId`/`status` 等筛选时均不走 Redis；`statusStats` 与同条件 `/list`、`statusStatsByListByPackage` 与同条件 `/listByPackage` 筛选口径一致（后者另按代表行去重且 `expiredCount` 恒为 0）

- **用例12c：手动指定目标列表同步下发明细（启用任务包，不校验 task_status）**
  - 接口：`POST /sales/task/distribution/detail/syncInProgressPackageByManualTargets`
  - 说明：与 `TaskPackageStatusTransitionJobServiceImpl#syncInProgressPackagesByCrowd` 落库逻辑一致（占位成功后先按当前时刻重算子 TASK 起止时间；重算后 **`start_time`、`end_time` 均非空**的子 TASK 参与；子 TASK 逐条 × 目标编码、独立事务插入、唯一键冲突跳过），**不调用分群接口**，由调用方传入 `targets` 及 `objectCode`、`objectName`。判重与分群一致：<strong>仅读任务包</strong> **`task_rule.repeat_window_type`**（`MONTH`/`DAYS`/`GLOBAL`；历史 NONE/LEGACY→GLOBAL），空则按包 **`is_repeat`** 推断；**不读**子 TASK 规则。任务包须 **`task_type=PACKAGE`**、**`status=1`**、未删除、未超截止时间；**不校验 `task_status`**；**不校验 `distributed_at` / 1h 窗口**；并发占位使用独立 Redis key **`sls:task:distribution:push:manual:pkg:{id}`**（与 Job 冷却 key 分离，Job 冷却期内仍可手动下发），结束删 key。DTS 补全口径同用例 7；**`target_entity_name` 优先用手动传入**。
  - **异步行为**：接口**一步提交**后**立即返回**成功（不阻塞 HTTP 线程）；Controller 将整段同步委托给 `IOAsyncUtil` 后台执行。服务内每条明细插入再通过 **`IOAsyncUtil` + `IOExecutorManager` 线程池**异步提交，**全部插入完成（`CompletableFuture.join`）后**再释放手动 Redis 占位，避免槽位提前释放。本次**新插入行数**不在响应中返回，可在应用日志中检索关键字 `syncInProgressPackageByManualTargets 完成`（含 `taskPackageId`、`inserted`）；失败时打错误日志。
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
  - 字段说明：`taskPackageId` 启用任务包 ID（`status=1`，不要求 `task_status=IN_PROGRESS`）；`objectCode`/`objectName` 写入明细 `object_code`/`object_name`，`targetEntityType` 与 `objectCode` 一致；`targets[].targetEntityCode` 必填；`targets[].targetEntityName` 可选。落库路径与分群一致：每条明细在 **`insertTaskDistributionDetailAsync`** 内 `REQUIRES_NEW` 插入提交后，于**同一条异步任务**中调用 **`TaskDistributionDetailOwningDepartmentSyncJobService#fillOwningDepartmentIfAbsent`** 尝试补全 **`owning_department_*` / `department_path_json`**（失败仅 warn）。补全按 `object_code` 分支：**STORE** → `account_obj.account_no` + `data_own_department`；**PERSON** → `personnel_obj.user_master_id__c`（`getLatestByUserMasterId`）+ `owner_department_id`（经 `resolveDepartmentIdFromDataOwn`）再查 `department_obj` 写部门与路径。预期结果：`Response.success`（`data` 为空或与网关统一的无业务体表示），**不**同步返回插入行数；插入结果以日志为准。

- **用例12d：按任务包 id 立即触发分群下发同步**
  - 接口：`POST /sales/task/distribution/detail/triggerSyncInProgressPackagesByCrowd`
  - 说明：调用 `syncInProgressPackagesByCrowd(maxScanCount, ids)`，`maxScanCount` 取 `SyncInProgressPackagesByCrowdJobParamDTO.DEFAULT_MAX_SCAN_COUNT`。**同步**先执行 `assertTaskPackagesNotBusyForCrowdSync`：须 **`status=1`（启用）**；**不校验 `task_status`**；若 **`status!=1`** 返回业务错误「任务包须为启用状态(status=1)才可下发…」；若任务包 **`end_time` 非空且当前时间已超过截止时间**则返回业务错误「任务包已超过截止时间，无法下发…」；若 `ids` 中任一任务包 **手动/立即触发 Redis key** `sls:task:distribution:push:manual:pkg:{id}` 存在（**不读** Job 冷却 key）则返回业务错误「以下任务包正在下发同步中…」；若 id 不存在、已删除或非 `PACKAGE` 则返回「任务包不存在、已删除或非 PACKAGE 类型…」。校验通过后将 **`distributed_at` 置为 now-1 分钟**，再执行 **`transitionReadyPackagesAndTasksToInProgress`**（此时发布时间已「到期」，未开始包可推进为进行中），再 **异步**提交分群同步。**显式 `ids` 时不套 Job 的 1h `distributed_at` 窗口**（仅启用 + 未超截止 + id 限定），保证点击即可下发；占位用手动 key、结束即删。HTTP **立即**返回成功；处理条数见日志 `triggerSyncInProgressPackagesByCrowd 完成`（含 `ids`、`handled`）。
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
  - **taskMonth 口径**：由明细 `end_time` 所在自然月推导（存库为当月 1 日）；`end_time` 为空时分组键为 `unknown`
  - 预期结果：返回按 taskMonth（`yyyy-MM`）分组的列表，月份倒序

- **用例14a（回归）：明细 taskMonth 由 end_time 生成**
  - 前置：下发明细 `end_time=2026-05-15 18:00:00`
  - 预期：库表/接口 `taskMonth=2026-05-01`；子任务 `end_time` 变更同步后 `taskMonth` 随 `end_time` 月份更新
  - 前置：`end_time` 为空
  - 预期：`taskMonth` 为 null

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
2. 对每条参与匹配的 `task_distribution_detail` 先创建一条 `task_instance`。`task_code` 为 `INST_EVAL_{taskDefId}_{yyyyMMdd}_{无连字符UUID}`（同任务、同明细多次建实例也可防撞，且控制在 `VARCHAR(64)` 内）；插入使用独立事务，若撞 `task_instance.uk_task_code` 则换码最多重试 8 次；重试耗尽或其它插入失败仅跳过该明细，不抛给 Kafka、不影响同批其它明细。
3. `task_instance` 需要写入 `source_data`（Kafka 消息 value）、`task_result_data`（`TaskDistributionTaskResult` 序列化 JSON）以及关联的 `task_distribution_detail_id`。
4. 若该明细所有条件均 `matched=true`，则继续将明细状态推进为 `COMPLETED`；若 `object_code=STORE` 且该 `target_entity_code` 下已无 `status=IN_PROGRESS` 且 `final_end_time` 为空的其它明细，则实时调用纷享销客将 `has_visit_task__c` 置为「否」（与全量 Job `runSyncHasVisitTask` 单条逻辑一致，失败仅 warn 不影响主流程）。
5. `TaskDistributionDetailSyncService.evaluateConditionCalculationByInstance(TaskInstanceDTO)` 在**完整跑通**条件评估并返回结果后，若 **`task_instance.id` 非空**会将对应 `task_instance.status` 更新为 `COMPLETED`，并写入 `completed_at`（仅内存实例无 id 时跳过实例表更新）。
6. `evaluateConditionCalculationByInstance` 在 **`task_instance.id` 非空**时执行后会新增一条 `task_instance_execution_log`，通过 `task_instance_id` 与任务实例绑定，记录本次条件计算结果摘要（DELAY 扫描仅内存实例、无 id 时跳过写日志）；`completion_script`（Groovy）**抛异常**时仍会写日志（`event_data` 含 `completionScriptException=true` 及错误信息），且**不会**将 `task_instance` 置为已完成，便于下次重试；脚本正常执行（含返回 false）时仍按原逻辑置实例完成（同上，仅 id 非空时更新实例表）。
7. **完成判定唯一依据**：`evaluateConditionMatch` 不再读取 `condition_repo`/不再做字段逐条对比；执行前按 `task_definition.condition_ids` 反查条件库明细列表，注入变量 `conditionDetailList`（与 `testTaskWithConditionDetails` 一致），再执行 `task_definition.completion_script`（Groovy 片段，返回布尔）。脚本参数另有：`mappedResults`（原始列表）、`mappedResultMap`（`mapped_col -> mapped_col_val`）。若 `task_result_data` 解析结果中带有 **`completionScriptData`**（如 DELAY 同步扫描将 DynamicHttp 解析结果写入 `TaskDistributionTaskResult`），则额外注入 Groovy 变量 **`data`**，与仅走 Kafka/映射结果、不带 `completionScriptData` 的链路兼容。**仅 `templateType=TARGET`** 时：先剥离 `@` 行，再将脚本中 **`{{fieldCode}}`** 按 `conditionDetailList` 的 `fieldCode` 匹配，替换为对应 `defaultValue` 首个 `value` 的 Groovy 字面量（**`dataTypeDefinition=NUMBER`** 时转为 **long 数字字面量**，非字符串）；COMMON/TEMPORARY 不做占位替换。
8. **DELAY 同步扫描回归**（`scanInProgressTaskDelaySyncStrategy` / `TaskInProgressDelaySyncStrategyScanJobServiceImpl`）：XXL-JOB **异步提交**扫描（不阻塞调度线程），结果见日志 **`DELAY 扫描完成`**。进行中 TASK **准入**为「绑定 **`templateType=TARGET`** 模板 **或** `completion_script` 的 `@` 行能解析 **`dynamic_http_endpoint.id`**」（**可无 `templateIds`**，仅凭 `@` 行 id 亦可）；二者皆无则跳过。**执行 DynamicHttp 仍必须有 endpointId**（仅 TARGET、无 `@` 行时 CRON 窗口通过后仍跳过）。**CRON 时间窗**（与用例 7.1 一致）：读**子 TASK 自身** `task_rule`（`task_definition.rule_id`）；`completion_judgment_type=CRON` 且 `nextAt` 相对 **`cronWindowReferenceNow`** 严格在未来且间隔 &lt; 1 小时。**Redis 去重**：CRON 窗口命中后若 **`RedisConstants.taskDelaySyncScanTaskKey(taskDefId)`** 存在（TTL **60 分钟**）则跳过，避免重复拉数；首次进入明细处理前写入该 key。对每个 `targetEntityCode` 首次拉数后调用 `evaluateDelaySyncWithPersistedInstance`；**本批内待判定编码** `IOAsyncUtil` 并发（每波最多 **5** 个），**单个编码异常仅记 `completed=false` 并继续**（不中断同波其它 Future 及后续明细批次）。明细按 id 游标每批最多 **20000** 条。Job 参数可选 **`ids`**（任务包 id 列表）。
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
- **`templateType=TARGET`**：走 **`executeTargetTemplateGroovyScript`**。**`code`** 中 **`@smatBi(2)`**、**`@中文名称(2)`** 等形式：取 **`@` 行最后一对括号内**纯数字为 **`dynamic_http_endpoint.id`**（多对括号时仅取最末一对，如 **`@foo(bar(123))`→123**），先按 id 调 DynamicHttp（**`targetEntityCode`** 同 DELAY 扫描），响应 **`data`** 注入 Groovy 变量 **`data`**，再剥离 **`@`** 行、**`{{fieldCode}}`** 占位替换后执行脚本（不走 **`evaluateDelaySyncWithPersistedInstance`**）。响应含 **`executionLogs`**、**`dynamicHttpInvokeResult`**。
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

- 用例4.0：`task_instance.uk_task_code` 冲突时换码重试，Kafka 不跳过整条消息（回归）
  - 前置准备：同用例 1；库中已存在 `task_code` 与即将生成的短随机码冲突的历史实例（或同任务同日高并发评估，复现 `Duplicate entry '...INST_EVAL_...' for key 'task_instance.uk_task_code'`）。
  - 执行步骤：消费/模拟 Kafka 任务下发（如 `online-shop-ease` / `genkishoporders`），触发 `evaluateInstanceMatchForInProgressDetails`。
  - 预期结果：
    - 冲突时日志含 `task_instance.uk_task_code 冲突，重新生成编码`，随后插入成功，新 `task_code` 形如 `INST_EVAL_{taskDefId}_{yyyyMMdd}_{32位无连字符UUID}`。
    - 该明细仍会创建实例并进入后续条件计算；同批其它明细不受影响。
    - 不再因 `DuplicateKeyException` 导致「任务下发 Kafka 消息处理失败，已跳过并提交 offset」。
    - 8 次换码仍失败时仅跳过该明细（warn），消息整体仍提交 offset，其它明细继续处理。

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

- **用例5.1：replayTaskDistributionForInProgressTaskInstances（重放 Kafka 下发链路）**
  - XXL-JOB 任务名：`replayTaskDistributionForInProgressTaskInstances`
  - 触发逻辑：
    1. 分页查询 `task_instance.status = IN_PROGRESS`，且 `source_data`、`task_result_data` 非空（每页默认 200 条，按 id 升序，直至无下一页）
    2. 对每条从 `task_result_data` 解析 `TaskDistributionTaskResult`，取 `taskExecutionEventCode` 作为业务 key，`source_data` 作为消息 value
    3. 调用 `TaskDistributionKafkaHandler#handleTaskDistribution(key, value)`，重走模板字段映射 → 进行中明细实例匹配 → 条件计算（与 Kafka 消费链路一致）
    4. 单条异常记录日志，不中断整批
  - 预期结果：执行成功；日志可见本次成功调用 `handleTaskDistribution` 的条数；匹配成功的明细可推进完成态
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
  - 说明：包/子 TASK 的 `task_status` 对完成判断无业务依赖（完成判断扫包只看启用 + `end_time` 放宽窗口）；明细是否过期由 **`expireInProgressDetailsPastEndTime`（判断截止）** 单独控制
  - 请求 JSON：无（调度中心仅配置 JobHandler 名称即可）

- **用例6.1：refreshInProgressPackageCronDistributedAt**
  - XXL-JOB 任务名：`refreshInProgressPackageCronDistributedAt`
  - **任务参数**（可选）：`maxScanCount` 正整数，单次扫描 `task_definition` 行数上限，缺省 **20000**
  - 触发逻辑：
    1. 查询 `task_type = PACKAGE` 且 `task_status = IN_PROGRESS`、**`status = 1`（启用）**、`is_deleted = 0`，按 `id` 升序，**`LIMIT maxScanCount`**
    2. 对每条读取 `task_rule`（`task_definition.rule_id`）；若 **`distribution_type` 不为 CRON / FIXED**（忽略大小写）或无 `rule_id`、无 `distribution_type` 文本，跳过。**`IMMEDIATE`（手动下发）不刷新**
    3. 调用 **`TaskRuleTimeResolver#resolveScheduledDistributeAt`** 写回 **`task_definition.distributed_at`**：**CRON** → 解析 `distribution_config.cron`，取相对**当前时刻**的下次触发时间；**FIXED** → 解析 `distribution_config` 中 **`dateTime`**（`yyyy-MM-dd HH:mm:ss`）
  - 预期结果：命中类型且**启用**的进行中任务包 **`distributed_at`** 按上款刷新；**停用（status=0）不参与**；解析失败或类型不支持的包跳过并打日志；返回值为本次成功 **`UPDATE` 影响行数**
  - 请求 JSON：无（调度中心仅配置 JobHandler 名称与可选任务参数即可）

- **用例6.2：expireInProgressDetailsPastEndTime（按明细判断截止全表批量过期）**
  - XXL-JOB 任务名：`expireInProgressDetailsPastEndTime`
  - **任务参数**：无（不按条数截断；一次调度内由 Service 按明细 `id` 游标分批扫描候选行并 UPDATE）
  - **Service**：`TaskDistributionDetailJobService#expireInProgressDetailsPastEndTime()` → `TaskDistributionDetailService#expireInProgressDetailsPastEndTime(LocalDateTime referenceTime)`，`referenceTime` 为调度开始时刻（单次调用内各批共用该时刻）
  - **候选扫描**：`status=IN_PROGRESS` 且 `end_time` 非空且 `end_time <= referenceTime`（任务截止已到）
  - **过期判定**（经子 TASK `task_definition.rule_id` → `task_rule`，`TaskRuleTimeResolver#resolveJudgmentDeadline(rule, detail.startTime, detail.endTime)`）：
    1. **未配置** `task_judgment_deadline_type/config`（前端「任务截止时间」）→ 有效过期点 = 明细 `end_time`，与任务截止一致
    2. **`AFTER_TASK_DEADLINE`**（如截止后 15 天 + HH:mm）→ 有效过期点 = 任务截止后 N 天该时刻；**任务截止已到但判断截止未到 → 不置 `EXPIRED`，明细保持 `IN_PROGRESS`，完成判断 Job 仍可命中**
    3. 仅当有效过期点 `<= referenceTime` 时置 `EXPIRED`，并写 `final_end_time = referenceTime`
  - **与完成判断关系**：完成判断入口（CRON 分群 / DELAY 同步策略）仅处理 `status=IN_PROGRESS` 的明细；一旦本 Job 置为 `EXPIRED`，后续完成判断不再命中该明细
  - 可与 **用例6** 分调度并行（用例6 只推进 PACKAGE/TASK 定义状态，不更新下发明细）
  - 预期结果：执行成功；宽限期内明细仍为进行中；到达判断截止后置过期；日志中可见累计 `UPDATE` 影响行数；异常时 XXL 侧可见失败日志
  - 请求 JSON：无（调度中心仅配置 JobHandler 名称即可）
  - **回归**：
    - 未配置判断截止：`end_time` 已到 → 置过期（与改造前一致）
    - 配置截止后 15 天：`end_time` 已到、判断截止未到 → **仍为 `IN_PROGRESS`**
    - 判断截止已到 → 置 `EXPIRED`，且完成判断 Job 不再更新该明细

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
  - **Job 层异步**：XXL 调度线程在解析任务参数后**立即提交** `IOAsyncUtil`（`IOExecutorManager` 线程池）执行，**不阻塞**后续调度轮次；**包级占位改 Redis**（`sls:task:distribution:push:pkg:{id}`，`SET NX` + TTL **60** 分钟）；**成功下发后不删 key**，靠 TTL 作冷却；未真正下发的跳过（无包/无群/无子 TASK 等）仍删 key 以便重试；**不再用 DB `distribution_push_completed` CAS**；明细判重仍靠步骤 5 及库表唯一约束。手动下发使用独立 key `sls:task:distribution:push:manual:pkg:{id}`，不受 Job 冷却影响
  - 触发逻辑：
    1. 查询 `task_definition.task_type = PACKAGE` 且 **`status = 1`（启用）**、`is_deleted = 0`，`distributed_at` 非空，且 **`now - 1h <= distributed_at <= now`**（已到发布时间且落在近 1 小时窗口，避免昨日调度点被扫到），且 **`end_time IS NULL OR end_time >= now`**；**不判断 `task_status` / `distribution_push_completed`**；可选 **`id IN (...)`**；`maxScanCount` 默认 20000，按 `id` 倒序；**逐包 Redis 占位成功后处理**；成功下发保留冷却 key，跳过则释放。**无 ids 的定时 Job：包规则 `distributionType=IMMEDIATE` 直接跳过**（释放 Redis 占位）。**显式 ids（点击触发）仍处理 IMMEDIATE**
    2. **去重窗口（仅 3 值，默认 MONTH，仅读任务包规则）**：只加载包 **`task_rule.repeat_window_type`**（空则按包 **`is_repeat`**：1→`GLOBAL`，否则 `MONTH`）；**不读**子 TASK 规则。内存判重键仍按子 TASK 维度拼装：
       - **MONTH**：`task_def_id + target` + **`start_time` 自然月** `yyyy-MM`（单月去重，默认）
       - **DAYS**：再加 **`start_time` 自然日** `yyyy-MM-dd`（单日去重）
       - **GLOBAL**：`task_def_id + target_entity_code`（全局/终身去重；历史 NONE/LEGACY 归一为此）
    3. 查询任务包下 `task_type = TASK` 且未删除的子任务；若无命中则跳过后续
    3.1 **下发前重算起止时间（本轮新明细）**：以**当前调度时刻 `now`** 在**内存**中置子 TASK **`startTime=now`**，并按子任务规则 **`deadlineType`/`deadlineConfig`** 重算 **`end_time`**（**RELATIVE** / **ABSOLUTE** / **MONTH**；其中 **MONTH=当月月底** 以 `now` 所在月为基准），同步 **`task_month`**（取 **`end_time` 所在自然月**）。**库表**：仅回写子 TASK / 包的 **`end_time`/`task_month`**，**不**改写 **`task_definition.start_time`**，**不** UPDATE 已存在 **`task_distribution_detail`** 的起止时间；本轮新插入明细才带 `start=now`、重算后的 `end`。重算后内存仍缺起止的子 TASK 不参与本轮写明细。避免跨月再次下发仍沿用旧截止月，同时保护历史明细开始时间
    4. **按任务包层对象群拉取**：读包 **`task_package_distribution_ext.distribution_object_group_id`**，调用一次 `/dwh/data-labeling/data/crowd/data/latest`；**不读**子 TASK `distribution_object_group_*`；完成群 **`completion_object_group_*` 不得**用作下发群。包层群为空则跳过该包。
    5. 将 `data.list` 按固定批大小 **500** 切片；每批查库已存在明细，按<strong>任务包</strong>去重窗口构建判重键（各子 TASK 共用同一窗口类型）；同一次调度内已插键另集合并；pending Future 达 200 时提前 join
    6. 对每个 `targetEntityCode`（trim）按子 TASK 的 **`object_code`** 查 DTS：**`STORE` / `DEALER`** → **`account_obj`**；**`PERSON`** → **`personnel_obj`**
    7. 对包下全部有效子 TASK：判重键已存在则跳过；否则异步插入明细；`task_package_id` 仍指向任务包
    8. 本包明细异步插入全部 join 完成后（含分群 latest 为空、未写明细）：插入一条 **`task_instance`** 审计日志，`task_title` / `target_entity_name` 均为 **「下发操作」**，`source_data`/`task_result_data` 为本次分群 latest JSON，`status=COMPLETED`，`created_by=JOB_DISTRIBUTION_PUSH`；落库失败仅 warn，不回滚明细
    8.1 **下发后回写下次 `distributed_at`**：调用 **`TaskRuleTimeResolver#resolveScheduledDistributeAt`**（与 `refreshInProgressPackageCronDistributedAt` 同口径：CRON→下次触发 / FIXED→`dateTime`）；解析结果须**严格晚于**当前时刻才 `UPDATE` 任务包；**IMMEDIATE 不回写**，保留点击下发时写入的时间；无规则、类型不支持、解析为空或未晚于当前则跳过并 warn
    8.2 **成功下发后保留 Redis 冷却**：不删 `sls:task:distribution:push:pkg:{id}`，TTL **60** 分钟内 Job 再扫该包会占位失败而跳过
    9. 未真正下发的跳过路径删除 Redis 占位；成功路径不删；并将 DB **`distribution_push_completed` 置回 `0`**（自愈）
  - 预期结果：仅处理**启用**且满足下发/截止时间、且 **`distributed_at` 落在近 1 小时**的任务包（**不要求 `task_status=IN_PROGRESS`**）；同包多子 TASK 可配置不同下发群并各自产明细；**表级**：已删除 `uk_task_pkg_def_target_code`；保留含 start/end 的唯一键作同窗并发幂等；成功下发后 Redis 冷却 key **保留至 TTL**；每包成功走完分群拉取后可查到 **「下发操作」** 的 `task_instance` 记录；CRON 包下发后 **`distributed_at` 推进为下次触发**
  - **回归**：单次分群 Job 跑完某包后，该包 Redis **冷却 key 仍在**（TTL 内）、**`distribution_push_completed` 为 `0`**；TTL 到期后可再占位
  - **回归（下发操作日志）**：`syncInProgressPackagesByCrowd` 处理完某包后，`task_instance` 新增一行：`task_title=下发操作`、`target_entity_name=下发操作`、`status=COMPLETED`，`source_data` 含分群 latest；空 list 跳过写明细时仍会落该审计行
  - **回归（去重窗口）**：默认未配置按 **MONTH**；`DAYS` 同日跳过、跨日可再下发；`MONTH` 同月跳过、跨月可再下发；`GLOBAL`/`is_repeat=1` 同目标终身一条
  - **回归（多群）**：同包两子 TASK 配置不同 `distribution_object_group_id`，Job 分别 `doLatest`，明细 `task_def_id` 不同、`task_package_id` 相同
  - **回归（跨月截止）**：子 TASK 规则 **`deadlineType=MONTH`（当月月底）**，7 月首次下发后 `end_time` 为 7 月底；8 月再次跑 **`syncInProgressPackagesByCrowd`** 时，下发前重算后子 TASK 与**新插入**明细的 **`end_time` 为 8 月底**；**`start_time`** 为当次下发时刻
  - **回归（不看 task_status）**：任务包 **`status=1`**、**`now-1h<=distributed_at<=now`**、未超 `end_time`，即使 **`task_status` 非 IN_PROGRESS** 也可被扫描并下发
  - **回归（1h 窗口）**：`distributed_at` 早于 **`now - 1h`**（如昨天）的启用包**不被扫描**；窗口内已到点的包可下发
  - **回归（手动下发不进定时 Job）**：包规则 **`distributionType=IMMEDIATE`**，即使 **`distributed_at`** 落在近 1 小时，XXL **`syncInProgressPackagesByCrowd`（无 ids）跳过**；**`triggerSyncInProgressPackagesByCrowd`** 仍下发
  - **回归（下发后重置 distributed_at）**：CRON 包下发完成后 **`distributed_at`** 写为 `resolveScheduledDistributeAt` 的下次触发（须晚于当前）；写回后直至该时刻再次到达前不会因旧调度点被扫到
  - **回归（Redis 冷却不影响手动下发）**：Job 成功下发后冷却 key 仍在，调用 **`POST .../syncInProgressPackageByManualTargets`** 仍可下发（使用独立 key `sls:task:distribution:push:manual:pkg:{id}`）
  - 请求 JSON：无（调度中心仅配置 JobHandler 名称即可）

| 编号 | 场景 | 步骤/入参 | 预期 |
| --- | --- | --- | --- |
| DIST-DEDUP-01 | DAYS 单日去重 | `repeatWindowType=DAYS`，同日两次分群同一目标 | 第二次跳过；跨日可再插入 |
| DIST-DEDUP-02 | MONTH 单月去重（默认） | 未传或 `MONTH`，同月两次、跨月一次 | 同月跳过；跨月可插入 |
| DIST-DEDUP-03 | GLOBAL 全局去重 | `GLOBAL` 或历史 `NONE`/`LEGACY`/`is_repeat=1` | 同目标终身一条 |
| DIST-CROWD-01 | 仅包层对象群 | 包 ext 有下发群，子 TASK 规则无/有 distribution_object_group | 只按包 ext 调一次 doLatest；子规则群忽略 |
| DIST-CROWD-02 | 包层群为空 | 包 ext 无 `distribution_object_group_id` | 跳过该包，不写明细 |
| DIST-TIME-01 | 1h 发布时间窗口 | `distributed_at` 为昨天 | 不被扫描 |
| DIST-TIME-02 | 下发后回写 CRON | CRON 包下发完成 | `distributed_at` 推进为下次触发（晚于当前） |
| DIST-REDIS-01 | Job 冷却不影响手动 | Job 刚下发某包（冷却 key 仍在） | 手动接口仍可成功写入明细 |

- **用例7.1：completeInProgressDetailsByCrowdForCronCompletionJudgment（TGR-009：基于对象群 + IN/NOT_IN 完成判定）**
  - XXL-JOB 任务名：`completeInProgressDetailsByCrowdForCronCompletionJudgment`
  - **任务参数**（可选）：`maxScanCount` 正整数，单次扫描任务包行数上限，缺省 **20000**（Executor 填纯数字即可）
  - **请求 JSON 示例**（文档约定；当前实现仅解析纯数字）：
```json
{
  "maxScanCount": 20000 // 每批扫描进行中启用任务包条数上限；≤0 时服务内默认 20000
}
```
  - **Service**：`TaskPackageStatusTransitionJobService#completeInProgressDetailsByCrowdForCronCompletionJudgment`
  - **触发逻辑**：
    1. Job 入口固定 **`cronWindowReferenceNow = now`**；循环查 `task_definition`：`task_type=PACKAGE`、**`status=1`（启用）**、`is_deleted=0`，且 **`end_time IS NULL OR end_time >= referenceNow - 16天`**（保留 `end_time` 判断，放宽 16 天以覆盖「截止后 15 天」判断截止）；**不按包 `task_status` 过滤**；按 `id` 倒序分批 + `id < 本批最小 id` 游标
    2. 对每包加载启用未删子 TASK（`task_type=TASK`、`parent_id=包.id`、`rule_id` 非空），读各自 **`task_rule`**
    3. **准入**：仅当 **`completion_standard_type=OBJECT_GROUP`**（**禁止**用 `has_action` 推断）；须有 **`completion_object_group_id`** 与合法 **`membership_operator`（IN|NOT_IN）**
    4. **CRON 窗口（可选）**：若子规则 `completion_judgment_type=CRON`，须命中 1h 完成判断窗口（与 DELAY 扫描一致）；未配 CRON 则本 Job 调度时直接判定
    5. 调用 **`DataCrowdFeignService#doLatest(completion_object_group_id)`**（**完成群**，≠ 下发群 `distribution_object_group_*`）；同包同完成群编码缓存 latest
    6. 拉取该子 TASK 下 **`status=IN_PROGRESS`** 明细，按成员关系判定后批量置 **COMPLETED** + `final_end_time`：
       - **IN**：`target_entity_code` **在**完成群内 → 完成
       - **NOT_IN**：`target_entity_code` **不在**完成群内 → 完成（PRD：群 ABC→BCD 后 A 完成；群为空则视为全部不在群）
    7. **无论是否更新明细**，完成判断执行完后都写一条 **`task_instance`** 审计快照（`created_by=JOB_CRON_CROWD_COMPLETION`，`task_title=CRON分群完成判断-latest快照(完成数：x)`，`x` 为本轮置为完成的明细行数，0 表示执行过但无符合条件；`source_data`/`task_result_data`=latest JSON，latest 为空时为 `{}`）。落库失败仅 warn，不回滚明细。未执行完判断的跳过（CRON 窗口未命中、完成群为空、membership 非法、分群接口抛错）不写这条实例
    8. **包级 Redis 去重**（对齐 DELAY 扫描）：处理包前写 `sls:task:cron:crowd:completion:pkg:{packageId}`（TTL **60** 分钟），并发实例见 key 则跳过该包；**整轮 Job 结束（finally）清空本轮写入的 key**（崩溃未清时靠 TTL 兜底）。明细完成仍靠 `IN_PROGRESS→COMPLETED` 幂等
  - **时间线用例（NOT_IN）**：
    | 时刻 | 完成群 | 门店 A/B/C/D 明细 | 预期 |
    |------|--------|-------------------|------|
    | T0 | ABC | A,B,C 进行中 | 无明细被更新；仍写一条 `task_instance`，`task_title=CRON分群完成判断-latest快照(完成数：0)` |
    | T1 群变 BCD | BCD | A 不在群 → **COMPLETED**；B,C 仍在群保持进行中；D 由下发 Job 新写（本 Job 不负责新下发） |
  - **预期**：仅 OBJECT_GROUP 子 TASK 的进行中明细按 IN/NOT_IN 更新；不读下发群；停用包/子任务不参与；返回值为本轮 UPDATE 行数之和
  - **回归**：
    - `completion_standard_type` 非 OBJECT_GROUP、完成群空、membership 非法、分群失败 → 该 TASK 不更新，且**不写**完成判断 `task_instance`；同包多子 TASK 各自完成群/运算符互不影响
    - 判断已执行但无明细被更新（无 `IN_PROGRESS` 明细，或 IN/NOT_IN 均不命中）→ 明细状态不变，仍插入一条 `task_instance`，`task_title=CRON分群完成判断-latest快照(完成数：0)`
    - 判断已执行且更新 N 条明细 → `task_title=CRON分群完成判断-latest快照(完成数：N)`
    - 包 `end_time` 已过但未超过 16 天、明细仍 `IN_PROGRESS` → **本 Job 仍扫包并完成判断**
    - 包 `end_time` 已超过 16 天 → 本 Job 不再扫该包
    - 明细已被过期 Job 置 `EXPIRED` → 本 Job 不再更新该明细
    - 两实例并发扫同一包：后者见 Redis 跳过；首轮结束后 key 已删，下一调度可再扫（明细已完成则 UPDATE 0）

- **用例8：syncReadyPackagesAndTasksToInProgress**
  - XXL-JOB 任务名：`syncReadyPackagesAndTasksToInProgress`
  - 触发逻辑：
    1. 查询 `task_definition.task_type = PACKAGE` 且 `task_status = NOT_STARTED`、**`status = 1`（启用）** 的任务包
    2. 过滤 `distributed_at <= now`（且 `distributed_at` 非空）
    3. 将命中的 PACKAGE 状态更新为 `IN_PROGRESS`，**`distribution_push_completed` 置为 `0`（空闲/未占用）**；包级 **`task_month`** 取包 **`end_time` 所在自然月**（无包截止时再取首个子 TASK 截止月）
    4. 将该 PACKAGE 下 `task_type = TASK` 且 `task_status = NOT_STARTED` 的子任务逐条更新：状态为 `IN_PROGRESS`；**`start_time` 置为当前调度时间**；**`end_time`** 按子任务关联的 **`task_rule.deadlineType`** 与 **`task_rule.deadlineConfig`（JSON 字符串）** 解析：`RELATIVE` 时为 **（当前日期 + `days` 天）** 与配置 **`time`**；`ABSOLUTE` 时为 **`date`** 与 **`time`** 拼接；**`MONTH`** 时按 **`monthDimension` / `monthDay` / `time`** 以**当前调度时刻**为基准月解析（见 `TaskRuleMonthDeadlineSupport`）；**`task_month` 取该子 TASK `end_time` 所在自然月**（截止月，**非**开始月）。规则缺失或解析失败时仍推进状态与 `start_time`，**`end_time`/`task_month` 不写入**，并打告警日志；**单条子任务解析失败不影响同包其它子任务及整段事务提交**
  - 预期结果：符合时间条件且**启用**的任务包及其子 TASK 同步推进为进行中；**停用（status=0）不参与**；**`task_month` 与 `end_time` 截止月一致**；子 TASK 的 `start_time`/`end_time` 符合上述规则；不符合条件的数据保持原状态
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
  - **单条补全（分群/手动下发后 `fillOwningDepartmentIfAbsent`，回归）**：
    - **STORE**：同本用例步骤 2～5（`account_obj` + `data_own_department`）
    - **PERSON**：`target_entity_code` → **`DtsPersonnelObjService#getLatestByUserMasterId`** → 读 **`owner_department_id`**，经与 `data_own_department` 相同的 **`resolveDepartmentIdFromDataOwn`** 解析部门 id → **`department_obj#getById`** → 写 `owning_department_*` / `department_path_json`；人员缺失或 `owner_department_id` 不可解析则跳过（仅日志）
  - **回归**：接口 **`TaskDistributionDetailDTO`** 中 **`departmentPath`** 由 **`department_path_json`** 反序列化为 `List<String>`；库表 DDL 见 **`doc/sql/update_tables.sql`** 中 **`task_distribution_detail`** 三列追加语句

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
