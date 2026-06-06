# 任务定义（PACKAGE+TASK）创建测试规格

## 功能模块：任务定义创建

### 一、变更说明
- **`task_type=TEMPLATE` 的任务定义**：已拆到独立表 **`task_template_definition`**，字段结构与 `task_definition` 一致，原 **`template_ids`** 列在新表中为 **`data_template_ids`**；**`template_type`** 表示模板类型（**TEMPORARY** 临时模板 / **COMMON** 常用模板）；**`rule_id`** 关联 **`task_rule.id`**（与 `task_definition.rule_id` 一致，无规则时为 null）。接口 **`TaskDefinitionDTO.templateIds`** 不变，服务端读/写与 `data_template_ids` 映射。列表/分页查询 **`taskType=TEMPLATE`** 时走 `task_template_definition`；未传 `taskType` 时仅查 `task_definition`（不含 TEMPLATE，与迁移后数据一致）。
- 任务定义分页接口 **`POST /sales/task/definition/list`** 性能：`childTaskCount` 与下发明细 **distributionTaskCount / distributionIssuedTaskCount** 为按当前页 id **批量 SQL 聚合**（`GROUP BY`）后回写，避免原逐行 `COUNT` 多次往返。
- 任务定义分页接口 **`POST /sales/task/definition/list`** 返回中新增 **`childTaskCount`**：当记录为任务包（`taskType=PACKAGE`）时，统计其直接子 `TASK` 数量（`parent_id=packageId` 且 `is_deleted=0`）；非任务包记录该字段可为 null/不关注。
- 任务定义分页接口 **`POST /sales/task/definition/list`** 已剥离下发统计聚合逻辑：不再在列表查询中实时聚合 **`distributionTaskCount` / `distributionIssuedTaskCount` / `issuedTaskPackageCount` / `completedTaskPackageCount`**（避免影响列表 RT）。
- 新增统计接口 **`POST /sales/task/definition/listStats`**：按 **`taskType + ids`** 批量返回上述 4 个统计字段。`taskType` 支持 `PACKAGE/TASK/ACTION`；其中 `issuedTaskPackageCount` / `completedTaskPackageCount` 按关联任务包维度统计（PACKAGE=自身、TASK=parent_id、ACTION=父 TASK 的 parent_id）。
- 任务定义分页接口 **`POST /sales/task/definition/list`** 请求新增 **`packageId`**：当传入时按 `task_definition.parent_id = packageId` 精确过滤（常用于查询某任务包下的子 TASK/ACTION）。
- 任务定义分页接口 **`POST /sales/task/definition/list`**：请求 **`taskName`**（模糊，trim）同时匹配 **`task_name`**、**`task_title`**、**`task_code`**（OR + LIKE，命中其一即可）；请求 **`targetEntityName`**（模糊，trim）表示存在 **`task_distribution_detail`** 行 **`target_entity_name`** 匹配且 **`task_def_id`** 或 **`task_package_id`** 与当前 **`task_definition.id`** 一致；**`taskType=TEMPLATE`** 时查 **`task_template_definition`**，**`taskName`** 同上三字段 OR 模糊，**`targetEntityName` 不参与筛选**。
- 任务定义分页接口 **`POST /sales/task/definition/list`**：请求新增 **`ids`**（Long 数组，去重去 null），按 **`id IN (...)`** 精确过滤；`taskType=TEMPLATE` 时作用于 `task_template_definition.id`，其余作用于 `task_definition.id`；与其它筛选条件为 AND 关系。
- 任务定义分页接口 **`POST /sales/task/definition/list`**：返回行 **`taskType=TASK`** 且 **`parentId`** 非空时，服务端按**当前页**去重后的 **`parent_id`** **一次性批量**查询父 **`task_definition`**（任务包），再按与 **`POST /sales/task/definition/detail`**（`findById`）相同的规则填充 **`TaskDefinitionDTO.taskPackage`** 后写回列表项；**非 TASK**、**parentId 为空**或父记录不存在时该字段为 **null**。**`taskType=TEMPLATE`** 列表分支不适用（无 TASK 行）。
- 任务定义相关列表查询（含 TEMPLATE 分支、按父级查询、条件查询）统一按 **`id` 倒序** 返回，确保最新数据在前。
- **`task_definition` 表**：已删除 `object_type` 列，对象维度统一使用 **`object_code`** 落库与接口返回（与 `task_object_option.object_code` 对齐）。
- 创建时默认运行状态：`task_definition.task_status` 为 `NOT_STARTED`（未开始）；当 `distributed_at` 到达后，由 XXL-JOB `syncPackageTaskStatusNotStartedToInProgress` 将任务包推进为 `IN_PROGRESS`（进行中）。
- **`task_definition.distribution_push_completed`**（仅 **`task_type=PACKAGE`**）：分群/手动下发明细同步**占用标记**。`0/false`：空闲，可被分群 Job 扫描；`1/true`：**处理中**（开始处理时置 `1`，本次处理结束 **`finally` 置回 `0`**）。新建任务包默认为 `0`；`NOT_STARTED→IN_PROGRESS` 迁移时显式置 `0`。详情/列表 **`TaskDefinitionDTO.distributionPushCompleted`**：`true` 表示当前正在同步处理。
- **`task_rule.is_repeat`**：是否需要重复下发（`0`-否，`1`-是，`NULL` 未配置）。创建/更新任务包时可在 **`taskRule` / `tasks[i].taskRule`** 上传 **`isRepeat`**（布尔），服务端落库 **`task_rule.is_repeat`**；详情 **`taskRuleList`** 中 **`isRepeat`** 为整型 `0`/`1`/`null`。
- **`task_rule.auto_close_on_deadline` / `sync_complete_task`**：是否截止自动关闭、是否同步完成任务（库表 `0`-否，`1`-是，`NULL` 未配置）。创建/更新任务包时可在 **`taskRule` / `tasks[i].taskRule`** 上传 **`autoCloseOnDeadline` / `syncCompleteTask`**（布尔）；详情 **`taskRuleList`** 中 **`TaskRuleDTO`** 对应字段为 **布尔** `true`/`false`/`null`，与 **`is_repeat`**（仍为整型 `0`/`1`/`null`）区分。
- **`task_rule.completion_judgment_type` / `completion_judgment_config`**：完成判断类型与配置。创建/更新任务包时可在 **`taskRule` / `tasks[i].taskRule`** 上传 **`completionJudgmentType` / `completionJudgmentConfig`**；其中类型枚举与 **`distributionType`** 一致（`CRON/FIXED/IMMEDIATE`），配置结构与 **`distributionConfig`** 一致（Map），服务端落库到 `task_rule` 对应列。
- **`task_rule.distribution_object_group_id` / `distribution_object_group_name`**：下发对象群 ID、名称（与 **`task_package_distribution_ext`** 中对象群字段语义一致）。可在 **`taskRule` / `tasks[i].taskRule`** 上传 **`distributionObjectGroupId` / `distributionObjectGroupName`**；若某处未传或为空串，创建/更新任务包时由请求体顶层 **`distributionObjectGroupId` / `distributionObjectGroupName`** 回填后再落库 **`task_rule`**。
- **`task_rule.task_judgment_deadline_type` / `task_judgment_deadline_config`**：任务判断截止时间类型与配置，类型与结构与 **`deadline_type` / `deadline_config`** 一致（可选）。创建/更新任务包时可在 **`taskRule` / `tasks[i].taskRule`** 上传 **`taskJudgmentDeadlineType` / `taskJudgmentDeadlineConfig`**（Map），服务端落库 **`task_rule`** 对应列；**PACKAGE 顶层**若填写 **`taskJudgmentDeadlineType`**，则 **`validatePackageRuleJudgmentDeadlineConfig`** 与截止时间同类校验（RELATIVE/ABSOLUTE 及 `days`/`time` 或 `date`/`time`）。
- **`task_rule.distribution_time_config` / `completion_time_config`**：下发/完成**周期 UI 配置**（JSON，可选），落库原样保留。**`createPackage` / `updatePackage`** 对 **`taskRule` 与 `tasks[].taskRule` 逐条**：**仅当 `distributionType=CRON` 且传了 `distributionTimeConfig`** 时，才校验并解析为 **`distributionConfig`**；**仅当 `completionJudgmentType=CRON` 且传了 `completionTimeConfig`** 时，才解析为 **`completionJudgmentConfig`**。转 cron **按步容错**（某步全部失败则跳过该步，已成功步骤保留）：**① `d`→分/时 ② `c`→日（固定日/周几；`b=日` 且未解析 `d` 时 `c` 可作 HH:mm）③ `b`/`a`→日/周/月维度**；**秒字段恒为 `0`**。含 **`LAST_DAY`** 时另写 **`monthLastDay`**（Spring 不支持 `L`）。整段无法解析时用默认 **`0 0 4 * * ?`**。非 CRON 不解析 TimeConfig。字段联动：**`a`**：`每1`/`每2`/`每3`；**`b`**：`日`/`周`/`月`；**月**推荐 **`c` 日期** + **`d` 时刻**。
- 创建任务包时：**先**完成各子 `TASK` 的规则/模板/条件等入参校验，**再**使用请求体中的 `distributionObjectGroupId` 调用数据分群接口 `/dwh/data-labeling/data/crowd/data/latest`（避免无效请求占用较慢的远程调用）：若返回 `total` 为 `null` 或 `≤0`，返回业务错误「`当前群组没有值`」；若有效则将 `total` 写入任务包 `task_definition.distribution_task_count`（总下发任务数），并同步写入其下每个子 `TASK` 的 `distribution_task_count`。
数据模板biz_template_config(预置值) + task_definition(TASK类型，随意创建)
->字段映射biz_template_field_map匹配 -> is_search_primary_key=true + task_definition的objectCode = 字段映射biz_template_field_map主键查询匹配
->映射数据mapping后的结果，根据is_search_primary_key + task_definition的id查询task_distribution_detail任务明细表
->根据task_definition(TASK类型) 绑定的task_definition(TEMPLATE类型)模板类型中的 condition_repo 获取字段判断条件
->组合后生成实例，实例进行条件判断后反写任务明细状态




`/sales/task/definition/createPackage` 按结构化入参创建：
- **防重复提交**：接口处理耗时较长，服务端取请求顶层 **`taskName`** 与 **`objectCode`**（trim 后拼接再 **MD5**）作为锁键后缀，使用 **Redisson** 互斥锁（键前缀 `sls-sales-task:lock:createPackage:taskNameObjectCode:` + 后缀），**整段创建流程持锁**（与盘点 `confirmCheckData` 一致）；未拿到锁返回业务错误「当前操作过于频繁，请稍等一下~」。首笔请求完成后释放锁，**仅 taskName+objectCode 均相同**时互斥；二者之一变化即不互斥。字段缺失或键计算失败时不加锁（与历史一致）。
- 顶层创建 `PACKAGE` 任务包；
- **`task_rule.rule_code`** / **`task_definition.task_code`**：**createPackage** 时由服务端按 **「类型前缀 + yyMMdd + 8 位当日不重复随机码」** 生成，**忽略**请求体中的 **`ruleCode`** / **`taskCode`**。规则：**任务包 GZB**、**子任务 GZR**；任务编码：**任务包 B**、**子任务 R**（示例 `GZB260422087d8ee`、`B260422087d8ey`）。**updatePackage** 保留库中已有编码。
- **`task_rule.has_action`**：任务包对应规则落库 **0**；每个子 TASK 对应规则与 **`tasks[i].hasAction`** 一致（true→1，false→0）。
- 在该任务包下创建多个 `TASK` 普通任务（`parent_id = packageId`）；
- 每个 `TASK` 的 `templateIds` 为 **TEMPLATE 任务定义 ID 数组**，**可不传或传空**；`hasAction=true` 时须传 **且仅能 1 个** id，类型为 `TEMPLATE`。子 TASK 的 **`objectCode`/`objectName` 与任务包顶层 **`objectCode`/`objectName`** 一致（不从模板反查）；绑定模板时仅从模板反填 `taskExecutionType`、`taskExecutionTypeName`、`taskExecutionEventCode`、`systemIds`。
- 创建 PACKAGE 时：顶层 **`objectCode`、`objectName`** 均必填（与 `task_object_option` 的编码、名称对应）；顶层 **`startTime`/`endTime`** 写入任务包 **`task_definition.start_time`/`end_time`**（可空）；**`updatePackage`** 时同样可更新上述时间字段。
- 子 TASK 的 `objectCode`/`objectName` 落库与任务包顶层 **`objectCode`/`objectName`** 相同（请求体中 `tasks[].objectCode`/`objectName` 可忽略）。

### 二、接口与请求示例

- 接口：`POST /sales/task/definition/createPackage`
- 测试接口：`POST /sales/task/definition/detailTaskWithConditions`
  - 入参示例：
```json
{
  "id": 123, // TASK 类型 task_definition.id
  "mappedResults": [
    {
      "mappedCol": "commodityCode2", // 条件字段编码（与 conditionDetailList[].fieldCode 对应）
      "mappedColVal": "YQ03002", // 实际值
      "index": 0, // 行组索引（数组场景）
      "logicalName": "商品明细-下单元气品编码", // 字段展示名
      "remark": "主数据商品编码", // 备注
      "extractRule": "items[*].commodityCode", // 提取规则
      "isSearchPrimaryKey": false, // 是否主键
      "objectCode": null // 对象编码
    }
  ]
}
```
  - 说明：返回 TASK 详情（含 `conditionDetailList`），并动态生成通用 Groovy 脚本；当传了 `mappedResults` 时会执行脚本并返回布尔结果 `matched`。脚本中非 `OR` 分支支持 **`operator`**：`EQ`、`NE`、`LIKE`、`GT`、`GTE`/`GE`、`LT`、`LTE`/`LE`。**`defaultValue`** 可为 **对象**或 **数组**：**数组长度大于 1** 时按多值（EQ/NE 为实际值是否落在该值集；LIKE 为任一模式命中；数值比较为对列表中任一期望值满足比较）；**长度为 1** 时与单对象一样按单个标量解析。**`LIKE`** 单值模式语义同 SQL：**`%`**、**`_`**；模式不含 `%`、`_` 时按「名称包含」自动补两端 `%`。若 id 非 TASK 类型会返回业务错误。
- 必填校验（节选）：`taskName`、`objectCode`、`objectName`、`distributionObjectGroupId`、`distributionObjectGroupName`、`distributionTypeCode`、`distributionTypeName`、`taskRule`、`tasks`；上述字符串字段均不可为空串。**`taskRule` 与每个 `tasks[i].taskRule` 均须传 `conditionMode`、`completionType`（非空、非空白串）**，由 Bean Validation（`@NotBlank`）在接口层强校验。
- 每个 `tasks[i]` 可传 `conditionRepos`：`ConditionRepoDTO` 数组；服务端逐项 `INSERT condition_repo`，将新 id 列表写入对应子 TASK 的 `task_definition.condition_ids`（JSON）；`condition_code` 由服务端生成；`objectType` 可省略，默认与任务包顶层 **`objectCode`** 一致；**`hasAction=true` 时 `conditionRepos` 至少 1 条**；`defaultValue` 可为 **JSON 对象、JSON 数组或 JSON 字符串**，落库仍为 `condition_repo.default_value` 字符串。**`condition_repo.template_id`**：绑定 **COMMON/TEMPORARY** 模板时，取 **`task_template_definition.data_template_ids`** 首元素（`biz_template_config.id`）；绑定 **TARGET** 模板时**不校验 data_template_ids**，**`template_id` 写 null**，条件行直接落库；**`dataTypeDefinition` 未传**时 TARGET 从 **`template_field_ids` JSON** 按 `fieldCode` 匹配 `mappedCol`/`logicalName` 补全。
- **`conditionRepos[].fieldCode`**（`mapped_col` 语义）：当子 TASK **`hasAction=true`** 且已绑定 **`templateIds`** 时**必填**；**COMMON/TEMPORARY** 须落在 **`template_field_ids`** 关联的 **`biz_template_field_map.mapped_col`** 集合内；**TARGET** 须落在 **`template_field_ids` JSON** 中的 **`mappedCol`**（无则 **`logicalName`**），**不依赖 data_template_ids**（**createPackage** / **updatePackage** 均校验；比对规则 `normalizeMappedColForCompare`）。
- **`conditionRepos[].operator`**（**createPackage** / **updatePackage**）：**必填**，须由请求体显式传递（非空、非仅空白）；**服务端不根据 `defaultValue` 推断或改写**，落库以请求体为准。
- **`conditionRepos[].operatorName`**（**createPackage** / **updatePackage**）：可选，操作符中文名称（如「大于等于」）；传入则原样写入 `condition_repo.operator_name`，未传保持 null。
- **`conditionRepos[].dataTypeDefinition`**：可选；请求体传入则原样落库 **`condition_repo.data_type_definition`**；**未传**且 **`fieldCode`** 非空时，服务端按 **`condition_repo.template_id`**（业务模板 id）查询 **`biz_template_field_map`**，若存在 **`mapped_col`** 与 **`fieldCode`** 规范化后一致的首条映射，则将其 **`data_type_definition`** 写入 **`condition_repo`**。
- **任务包子任务落库 `condition_repo` 前**（**createPackage** 写入新条件行时）：先按条过滤 **`ConditionRepoDTO`**——若某条 **`defaultValue` 经规范化后视为空**（`null`、空/空白串、空数组、空对象、单对象含空 **`value`**、数组剔除空 **`value`** 项后无剩余等），则**不写入该条**；**过滤后 `conditionRepos` 须至少保留 1 条** `ConditionRepoDTO`，否则接口报错。单条内若 **`defaultValue` 为 JSON 数组**，仍会**去掉**其中带 **`value` 键**且 **`value` 为 null 或空串**的元素；**该条**剔除后数组须至少 1 个元素，否则该条整项视为空并丢弃。**`updatePackage`** 子任务条件行与 `condition_ids` **一一对应**，**不能**删条；若某条 **`defaultValue` 无效**则接口报错（提示不可删除条件行）。
- **`tasks[i].hasAction=true`** 时：**`conditionRepos`** 至少 1 条，且 **`completionScript`** 必填（非空串）；**createPackage** / **updatePackage** 不做 Groovy 语法/关键字合法性校验，原样落库 **`task_definition.completion_script`**。
- **同时**存在非空 **`templateIds`**（至少 1 个有效 ID）与非空 **`conditionRepos`**（至少 1 条）时（与 **`hasAction`** 无关），对应 **`tasks[i].completionScript`** 亦必填；**`taskRule` 中不传** `completionScript`（落库 `task_rule` 时该字段为 null）。
- **任务包下发扩展**（**必填**）：**`distributionObjectGroupId`**、**`distributionObjectGroupName`**、**`distributionTypeCode`**、**`distributionTypeName`**（均不可为空串）；创建成功后写入表 **`task_package_distribution_ext`**，与任务包 **`task_definition.id`**（`task_type=PACKAGE`）**1:1**。详情/列表中 PACKAGE 行在 **`TaskDefinitionDTO.packageDistributionExt`** 中返回完整对象（含扩展表 **`id`**、**`taskPackageDefId`** 及四业务字段）。
- **任务包全量更新** **`POST /sales/task/definition/updatePackage`**：请求体与 **`createPackage`** 相同结构，并增加 **`id`**（已有任务包 **`task_definition.id`**）；每个 **`tasks[i]`** 须带 **`taskDefId`**（该子 TASK 的 **`task_definition.id`**），且 **`tasks` 条数须与当前任务包下子 TASK 数量一致**（不支持增删子任务，仅全量改内容）。服务端**原地更新**已关联的 **`task_rule`**（同一 **`rule_id`**）、**`task_package_distribution_ext`**、既有 **`condition_repo`**（**`hasAction=true`** 时 **`conditionRepos`** 条数与顺序须与 **`condition_ids` 一致**，按序 **`UPDATE`**，不 `INSERT` 新条件行），并对已存在的 **`task_distribution_detail`** 批量 **`UPDATE`** 冗余字段（任务标题/说明/执行类型/时间/对象等），**不新建**下发明细。
- **`POST /sales/task/definition/update`**（`TaskDefinitionDTO`）：**Body 须带 `id` 与 `taskType`**，用于区分落库表，避免 **`task_definition.id` 与 `task_template_definition.id` 数值相同**时误更新。**`taskType=TEMPLATE`** → 仅更新 **`task_template_definition`**；**`taskType=TASK` 或 `ACTION`** → 仅更新 **`task_definition`**；**`taskType=PACKAGE`** → 返回业务错误，须改用 **`/updatePackage`**。未传 `taskType` 时返回业务错误。
- 请求 JSON 示例：

```json
{
  "taskName": "3月门店巡检任务包", // 任务包名称（必填，task_definition.task_name）
  "taskTitle": "3月门店巡检任务包", // 任务包标题（可空，为空时默认同 taskName）
  "taskDescription": "用于按模板批量下发巡检任务", // 任务包说明（可空）
  "startTime": "2026-03-23 09:00:00", // 任务包开始时间（可空）
  "endTime": "2026-03-31 23:59:59", // 任务包结束时间（可空）
  "objectCode": "STORE", // 对象编码（必填）
  "objectName": "门店", // 对象名称（必填）
  "distributionObjectGroupId": "G1001", // 必填：下发对象群ID，落库 task_package_distribution_ext.distribution_object_group_id
  "distributionObjectGroupName": "华东门店群", // 必填：下发对象群名称
  "distributionTypeCode": "CIRCLE", // 必填：下发类型编码
  "distributionTypeName": "圈选下发", // 必填：下发类型名称
  "taskRule": { // PACKAGE 对应的 task_rule（必填）
    "ruleName": "任务包规则", // 可忽略：落库 task_rule.rule_name 与任务包 task_definition.task_name 一致
    "targetObjectType": "STORE", // 下发对象类型
    "conditionMode": "FACTOR", // 必填：条件模式 FACTOR/SCRIPT
    "distributionType": "IMMEDIATE", // 必填；CRON 时从 distributionConfig.cron 解析下次执行时间写入 distributedAt；FIXED 时 distributedAt 必填且需大于当前时间；IMMEDIATE 时 distributedAt=当前时间
    "distributionConfig": null, // 分发配置（Map）；CRON 场景需传 {"cron":"0 0/5 * * * ?"}
    "completionType": "ACTION_BASED", // 必填：完成类型 ACTION_BASED/OVERALL/SCRIPT_BASED 等
    "completionJudgmentType": "CRON", // 可选：完成判断类型，枚举与 distributionType 一致（CRON/FIXED/IMMEDIATE）
    "completionJudgmentConfig": {"cron":"0 0/5 * * * ?"}, // 可选：完成判断配置，结构与 distributionConfig 一致
    "actionExecutionMode": "ALL", // 执行模式：ALL/ANY
    "isRepeat": false, // 可选：是否重复下发，落库 task_rule.is_repeat（0/1）；不传则为 null
    "autoCloseOnDeadline": false, // 可选：是否截止自动关闭，落库 task_rule.auto_close_on_deadline（0/1）；不传则为 null
    "syncCompleteTask": false, // 可选：是否同步完成任务，落库 task_rule.sync_complete_task（0/1）；不传则为 null
    "distributionObjectGroupId": "G1001", // 可选：省略或空串时沿用顶层 distributionObjectGroupId，落库 task_rule.distribution_object_group_id
    "distributionObjectGroupName": "华东门店群", // 可选：省略或空串时沿用顶层名称，落库 task_rule.distribution_object_group_name
    "taskJudgmentDeadlineType": "RELATIVE", // 可选：任务判断截止时间类型，与 deadlineType 取值一致（RELATIVE/ABSOLUTE）；不传则不校验、不落库类型列
    "taskJudgmentDeadlineConfig": {
      "days": 3,
      "time": "18:00"
    }, // 可选：任务判断截止时间配置（Map），结构与 deadlineConfig 一致；与 taskJudgmentDeadlineType 同时有效时落库 task_judgment_deadline_config
    "distributionTimeConfig": {
      "a": "每1",
      "b": "日",
      "c": ["09:00", "18:00"]
    }, // 可选：解析后 distributionConfig={"cron":"0 0,0 9,18 * * ?"} 等，落库 distribution_time_config 保留本结构
    "completionTimeConfig": {
      "a": "每1",
      "b": "月",
      "c": ["LAST_DAY", "30"],
      "d": ["01:00", "00:00"]
    } // 可选：b=月 拆分模式；落库 completion_judgment_config 示例：{"cron":"0 0 0,1 30 * ?","monthLastDay":{"minutes":[0],"hours":[0,1]}}（30 号 0:00/1:00 + 每月末 0:00/1:00；Spring 不支持 L，月末单独 monthLastDay）
  },
  "tasks": [ // TASK 列表（必填，至少1个）
    {
      "taskName": "陈列检查", // TASK 名称（必填）
      "taskTitle": "陈列检查任务", // TASK 标题（可空）
      "taskDescription": "按陈列模板执行", // TASK 说明（可空）
      "startTime": "2026-03-23T09:00:00", // TASK 开始时间（可空）
      "endTime": "2026-03-31T23:59:59", // TASK 结束时间（可空）
      "taskExecutionType": "MANUAL", // 执行类型编码（可空）
      "taskExecutionTypeName": "手动执行", // 执行类型名称（可空）
      "taskExecutionEventCode": "store_display_check", // 监听事件编码（可空）
      "objectCode": "STORE", // 可忽略：子 TASK 落库 objectCode 与顶层 objectCode 一致
      "objectName": "门店", // 可忽略：子 TASK 落库 objectName 与顶层 objectName 一致
      "hasAction": true, // 是否有操作（必填）；true 时必须绑定非空 templateIds
      "templateIds": [
        4
      ], // hasAction=true 时必填且仅 1 个元素；objectCode/objectName 与任务包一致；执行类字段从模板反填
      "taskRule": { // TASK 对应的 task_rule（必填）
        "ruleName": "陈列检查规则", // 可忽略：落库与对应 TASK 的 task_name 一致
        "targetObjectType": "STORE", // 下发对象类型
        "conditionMode": "FACTOR", // 必填：条件模式
        "distributionType": "IMMEDIATE", // 分发类型
        "deadlineType": "RELATIVE", // 必填
        "deadlineConfig": {
          "days": 10,
          "time": "22:30"
        }, // 截止配置（Map）
        "completionType": "ACTION_BASED", // 必填：完成类型
        "actionExecutionMode": "ALL", // 执行模式（不在 taskRule 传 completionScript）
        "distributionObjectGroupId": "G1001", // 可选：与子 TASK 任务包顶层一致时可省略，由服务端回填
        "distributionObjectGroupName": "华东门店群" // 可选：同上
      },
      "completionScript": "baseUnitQuantity2>=15\nshopName2=测试2", // 非空时强校验：换行分条，每行 字段名+运算符+值；与模板+conditionRepos 同时存在时必填
      "conditionRepos": [
        {
          "conditionName": "陈列SKU条件", // 必填：条件名称
          "objectType": "STORE", // 可空：默认同顶层 objectCode
          // template_id 由服务端按绑定模板的 data_template_ids[0] 写入，请求体可不传 templateId
          "fieldCode": "commodityCode", // 可空：mapped_col
          "operator": "EQ", // 必填：须由请求体传递；服务端不推断
          "operatorName": "等于", // 可选：操作符中文名称，原样落库 condition_repo.operator_name
          "dataTypeDefinition": "STRING", // 可选：请求可传；未传且 fieldCode 能匹配业务模板字段 mapped_col 时由服务端从 biz_template_field_map 补全后落库 condition_repo
          "defaultValue": { "value": "A01" }, // 可空：JSON 对象、JSON 数组或 JSON 字符串（落库为字符串）
          "description": "下单品编码等于A01" // 可空
        },
        {
          "conditionName": "陈列SKU条件", // 必填：条件名称
          "objectType": "STORE", // 可空：默认同顶层 objectCode
          // template_id 由服务端按绑定模板的 data_template_ids[0] 写入，请求体可不传 templateId
          "fieldCode": "commodityCode", // 可空：mapped_col
          "operator": "EQ", // 必填：须由请求体传递；服务端不推断
          "operatorName": "等于", // 可选：操作符中文名称，原样落库 condition_repo.operator_name
          "dataTypeDefinition": "STRING", // 可选：请求可传；未传且 fieldCode 能匹配业务模板字段 mapped_col 时由服务端从 biz_template_field_map 补全后落库 condition_repo
          "defaultValue": { "value": "A01" }, // 可空：JSON 对象、JSON 数组或 JSON 字符串（落库为字符串）
          "description": "下单品编码等于A01" // 可空
        }
      ] // 可选：新建条件库记录后绑定到本子 TASK 的 condition_ids
    },
    {
      "taskName": "库存检查", // TASK 名称（必填）
      "taskTitle": "库存检查任务", // TASK 标题（可空）
      "taskDescription": "按库存模板执行", // TASK 说明（可空）
      "startTime": "2026-03-23T09:00:00", // TASK 开始时间（可空）
      "endTime": "2026-03-31T23:59:59", // TASK 结束时间（可空）
      "taskExecutionType": "MANUAL", // 执行类型编码（可空）
      "taskExecutionTypeName": "手动执行", // 执行类型名称（可空）
      "taskExecutionEventCode": "store_stock_check", // 监听事件编码（可空）
      "objectCode": "STORE", // 可忽略：子 TASK 落库 objectCode 与顶层 objectCode 一致
      "objectName": "门店", // 可忽略：子 TASK 落库 objectName 与顶层 objectName 一致
      "hasAction": false, // 是否有操作（必填）
      "taskRule": { // TASK 对应的 task_rule（必填）
        "ruleName": "陈列检查规则", // 可忽略：落库与对应 TASK 的 task_name 一致
        "targetObjectType": "STORE", // 下发对象类型
        "conditionMode": "FACTOR", // 必填：条件模式
        "distributionType": "IMMEDIATE", // 分发类型
        "deadlineType": "RELATIVE", // 必填
        "deadlineConfig": {
          "days": 10,
          "time": "22:30"
        }, // 截止配置（Map）
        "completionType": "ACTION_BASED", // 必填：完成类型
        "actionExecutionMode": "ALL" // 执行模式
      }
    }
  ]
}
```

### 启用/停用任务定义 `POST /sales/task/definition/updateStatus`

- 说明：更新 **`task_definition.status`** 或 **`task_template_definition.status`**（**1=启用，0=停用**）；先按 **`task_definition.id`** 命中更新，否则按 **`task_template_definition.id`**；均不存在则业务异常。
- 请求 JSON 示例：

```json
{
  "id": 1, // 任务定义主键（task_definition 或 task_template_definition）
  "enabled": true // true=启用(1)，false=停用(0)
}
```

### 停用任务包并关闭下发明细 `POST /sales/task/definition/disablePackageAndCloseDetails`

- 说明：仅 **`task_type=PACKAGE`**。**同步**完成入参校验后**立即返回**；**异步**在 IO 线程池执行：任务包 **`task_definition.status=0`**，并将 **`task_distribution_detail.task_package_id=id`** 且 **`is_deleted=0`** 的明细 **`status=CLOSED`**（写入 **`final_end_time`**）。关闭条数见应用日志 `closedDetailCount`。
- 请求 JSON 示例：

```json
{
  "id": 1001 // 任务包 task_definition.id（必填）
}
```

- 响应 `data` 示例（受理即返回，`closedDetailCount` 为 null）：

```json
{
  "packageId": 1001, // 任务包 id
  "closedDetailCount": null // 异步处理中，实际条数见服务端日志
}
```

- 异常（同步校验失败即返回，不提交异步）：`id` 不存在；非 PACKAGE；任务包已逻辑删除。
- 异步成功后（与 XXL `refreshTaskDistributionDetailStatusStatsCache` 的 `finally` 一致）：先删本任务包及子 TASK 的 **listStats** Redis key；按 **`objectCode`**（空则 `STORE`）**`refreshDetailStatusStatsCachesBatch`**（内部先删 statusStats 再重建）；**`warmListStatsCacheForLatestDefinitions(50)`** 预热前亦先删待预热 id 的旧 listStats key。

### 任务定义详情（task_definition 表）`POST /sales/task/definition/detail`

- 请求 Body：`{ "id": 1 }`（`id` 为 **`task_definition.id`**）
- **当 `taskType=PACKAGE`（任务包）时**：`data` 为 **`TaskDefinitionPackageUpdateRequestDTO`**，与 **`POST /sales/task/definition/createPackage`**、**`POST /sales/task/definition/updatePackage`** 请求体同构（含 **`id`**（任务包 **`task_definition.id`**）、顶层下发扩展四字段、**`taskRule`**（**`distributionConfig` / `deadlineConfig` / `taskJudgmentDeadlineConfig`** 为 **Map**，**`isRepeat`** 为 **Boolean**）、**`tasks[]`**（每项含 **`taskDefId`**、**`hasAction`**、**`taskRule`**、**`conditionRepos`**、**`completionScript`** 等））。子任务顺序为 **`start_time` 升序，再 `id` 升序**。任务包或子任务缺失 **`task_rule`** 关联时抛业务异常。
- **当 `taskType` 非 PACKAGE 时**：`data` 为 **`TaskDefinitionDTO`**：当前行自身含 `conditionDetailList`、`systemDetailList`、`taskRuleList` 等（与既有约定一致）。**`templateFieldIds` / `templateFieldDetailList`**：仅 **`task_template_definition`** 存字段映射；本接口只查 **`task_definition`**，故二者恒为空列表。**`dataTemplateDetailList`**：当前行及 **`childTaskList`** 子行均为 **`null`**（`task_definition.template_ids` 为任务模板定义 ID，非业务模板）；**仅 `linkedTemplateDefinitionList` 内嵌的模板对象**按 `data_template_ids` 填充 `dataTemplateDetailList`。子 **TASK** 行上 **`packageDistributionExt`** 为 `null`；**`childTaskList`**：`parent_id = id` 且未逻辑删除的子 **`task_definition`**；每个子元素同样填充规则/条件/系统选项；**子行上 `templateFieldDetailList` 恒为空**（字段映射见子项 **`linkedTemplateDefinitionList`** 内嵌的模板详情）。
- **`linkedTemplateDefinitionList`**：**当前行**为 **`taskType=TASK`** 且 **`templateIds` 非空**时，按 **`templateIds`**（**`task_template_definition.id`**）顺序逐条拉取模板并 enrich，与模板详情一致；**子任务**上同样填在 **`childTaskList`** 各元素上。无绑定或 ID 不存在时对应项跳过，列表可能短于 `templateIds`。

### 任务模板详情 `POST /sales/task/template/detail`

- 请求 Body：`{ "id": 1 }`（`id` 为 **`task_template_definition.id`**；由 `TaskTemplateService` 查询任务模板表，**不再**走 `task_definition` 表）
- 返回 `data` 为 **`TaskTemplateUpdateRequestDTO`**：与 **`POST /sales/task/template/createTemplate`** 请求体**字段一致**，并多出 **`id`**，便于直接回显并提交 **`updateTemplate`**。**不返回** `systemDetailList`、`templateFieldDetailList`、`dataTemplateDetailList`、`taskRuleList`、`conditionDetailList` 等扩展明细（与创建入参同构）。
- 说明：`TaskDefinitionService#findById` 仅查 **`task_definition`**；若其它内部逻辑需按 **`task_template_definition.id`** 取 **create 同构** 表单，应使用 **`TaskTemplateService#findById`**；若需带规则/条件等完整明细 DTO，应使用 **`TaskTemplateService#findDetailById`**（内部能力，非本 HTTP 接口）。
- 请求 JSON 示例：

```json
{
  "id": 1 // task_template_definition 主键
}
```

### 二（补充）、任务定义分页 `POST /sales/task/definition/list`

- 请求 Body（可空对象，空则默认 `page=1`、`pageSize=20`）：除分页外可选 **`taskType`**、**`ids`**、**`taskCode`**、**`taskName`**、**`taskTitle`**、**`objectName`**、**`objectCode`**、**`targetEntityName`**、**`packageId`**、**`taskExecutionType`**、**`status`**、**`taskStatus`** 等（与 `TaskDefinitionPageRequest` 一致）。**`ids`**：可选，按 `id IN (...)` 精确过滤（去重去 null）；`taskType=TEMPLATE` 时作用于模板表 id。**`taskExecutionType`**：可选，**精准匹配**（trim 后与库表 `task_execution_type` 相等）；`taskType=TEMPLATE` 时作用于 `task_template_definition.task_execution_type`，否则作用于 `task_definition.task_execution_type`。
- 返回：`taskType=TASK` 且 `parentId` 有值时 **`taskPackage`** 为所属任务包明细对象（**`TaskDefinitionDTO`**，由服务端 `buildTaskDefinitionDtoSameAsDetailApi` 组装，**含 `childTaskList` 等**；与 **`POST /sales/task/definition/detail` 在 `id` 为任务包 id 时返回的 `TaskDefinitionPackageUpdateRequestDTO` 形态不同**，列表侧仍为扁平 DTO）；同页多条子任务共用同一 `parentId` 时只查任务包一次。
- 请求 JSON 示例：

```json
{
  "page": 1,
  "pageSize": 20,
  "taskName": "陈列",
  "//taskName": "可选：模糊匹配 task_name、task_title、task_code（OR + LIKE，trim）",
  "targetEntityName": "某某门店",
  "//targetEntityName": "可选：由下发明细 target_entity_name 反查任务包/子任务（trim）；TEMPLATE 列表时不生效",
  "objectCode": "STORE",
  "taskExecutionType": "MANUAL",
  "//taskExecutionType": "可选：任务执行类型编码，精准匹配 task_execution_type（trim）"
}
```

### 二（补充）、任务定义统计 `POST /sales/task/definition/listStats`

- 作用：从列表接口剥离统计后，按 **`taskType + ids`** 批量查询以下字段：`distributionTaskCount`、`distributionIssuedTaskCount`、`issuedTaskPackageCount`、`completedTaskPackageCount`。
- **缓存（Redis）**：缓存 key 由**请求中的 `taskType`（服务端 trim 后大写）与单个 `id`** 唯一确定，实现为 **`RedisConstants.taskDefinitionListStatsKey(taskType, id)`** → **`sls:task:definition:listStats:{taskType}:{id}`**；value 为单条统计 DTO 的 JSON。**默认 30 分钟**过期。批量请求时**逐 id** 命中则用缓存、未命中则只查未命中 id 并回写；Redis 读写异常时**降级为直接查库**（不中断接口）。
- 请求约束：
  - `taskType` 必填，支持：`PACKAGE` / `TASK` / `ACTION`
  - `ids` 必填，Long 数组；服务端会去重、过滤 null
- 统计口径：**均排除** `task_distribution_detail.status = CLOSED`（已关闭）的明细；`is_deleted=0`。
  - `distributionTaskCount` / `distributionIssuedTaskCount`：
    - `TASK`：按 `task_distribution_detail.task_def_id = id` 统计（`completed` 为 `status=COMPLETED`）
    - `PACKAGE`：按 `task_distribution_detail.task_package_id = id` 统计（同上）
    - `ACTION`：固定返回 0（无直接下发明细口径）
  - `issuedTaskPackageCount` / `completedTaskPackageCount`（任务包维度，`task_package_id + target_entity_code` 去重，不含 CLOSED）：
    - `PACKAGE`：包 id = 自身 id
    - `TASK`：包 id = `parent_id`
    - `ACTION`：包 id = 父 TASK 的 `parent_id`

- 请求 JSON 示例（TASK）：

```json
{
  "taskType": "TASK",
  "ids": [1001, 1002, 1003]
}
```

- 请求 JSON 示例（PACKAGE）：

```json
{
  "taskType": "PACKAGE",
  "ids": [2001, 2002]
}
```

- 响应 `data` 示例：

```json
[
  {
    "id": 1001,
    "distributionTaskCount": 56,
    "distributionIssuedTaskCount": 23,
    "issuedTaskPackageCount": 40,
    "completedTaskPackageCount": 18
  },
  {
    "id": 1002,
    "distributionTaskCount": 0,
    "distributionIssuedTaskCount": 0,
    "issuedTaskPackageCount": 5,
    "completedTaskPackageCount": 1
  }
]
```

### 二（补充2）、清除并重建统计缓存 `POST /sales/task/definition/refreshStatsCache`

- 作用：与 XXL **`refreshTaskDistributionDetailStatusStatsCache`** 一致，手动触发 Redis 统计缓存先删后建。
- **异步**：`TaskDefinitionService#submitRefreshStatsCaches` 经 **`IOAsyncUtil`** 提交后台任务，HTTP **立即返回**；同步执行体为 **`#refreshStatsCaches`**（XXL Job 仍直接调同步方法）。
- 步骤：
  1. 按 `objectCodes`（trim、去空；未传或全空则 **`STORE`**）依次调用 **`refreshDetailStatusStatsCachesBatch`**，刷新下发明细 **`POST .../statusStats`**、**`POST .../statusStatsByListByPackage`** 对应 Redis；
  2. **`evictListStatsCacheForLatestDefinitions(listStatsWarmLimitPerType)`** 删除 PACKAGE/TASK 各最近 N 条定义的 listStats key；
  3. **`warmListStatsCacheForLatestDefinitions`** 查库写回 listStats 缓存；步骤 2–3 失败时 `listStatsWarmError` 有值，但不影响步骤 1 已完成的明细缓存刷新。

- 请求 JSON 示例（默认 STORE + listStats 各 50 条）：

```json
{}
```

- 请求 JSON 示例（多 objectCode + 自定义预热条数）：

```json
{
  "objectCodes": ["STORE", "DEALER"],
  "listStatsWarmLimitPerType": 50
}
```

- 响应 `data` 示例（异步受理，计数为 null）：

```json
{
  "objectCodes": ["STORE", "DEALER"],
  "detailStatusStatsRefreshedCount": null,
  "listStatsEvictedKeyCount": null,
  "listStatsWarmedRowCount": null,
  "listStatsWarmError": null
}
```

- 字段说明（注释含义）：
  - `objectCodes`：已受理、将参与刷新的对象编码列表
  - `detailStatusStatsRefreshedCount`：异步受理时为 null；后台完成后见日志 **`refreshStatsCaches 完成`**
  - `listStatsEvictedKeyCount` / `listStatsWarmedRowCount` / `listStatsWarmError`：异步受理时为 null

### 三、测试用例

| 编号 | 场景 | 步骤/入参 | 预期 |
| --- | --- | --- | --- |
| LIST-FUZZ-01 | 列表 taskName / targetEntityName | `POST .../list` 传 `taskName`、`targetEntityName` | `taskName` 命中 `task_name`、`task_title` 或 `task_code` 之一；`targetEntityName` 命中存在对应下发明细的任务定义行 |
| LIST-IDS-01（新增） | 列表 ids 精确过滤 | `POST .../list` 传 `ids=[id1,id2]`（可混入重复/null） | 仅返回命中 id 的记录；重复/null 被忽略；与其它筛选条件为 AND |
| LIST-ET-01（回归） | 列表 taskExecutionType 精准 | `POST .../list` 传 `taskExecutionType`（如与库中某条 `task_execution_type` 完全一致） | 仅返回该执行类型编码的行；传错大小写/多余空格（未 trim 一致）则不命中 |
| LIST-DIST-01（回归） | 列表接口不做统计聚合 | `POST .../list` | 接口可正常返回分页数据，统计字段不再作为列表实时聚合结果来源 |
| LIST-STATS-01（新增） | TASK 统计 | `POST .../listStats`，`taskType=TASK`，`ids=[taskId...]` | 返回每个 id 的 `distributionTaskCount`、`distributionIssuedTaskCount`，以及按任务包维度解析后的 `issuedTaskPackageCount`、`completedTaskPackageCount` |
| LIST-STATS-02（新增） | PACKAGE 统计 | `POST .../listStats`，`taskType=PACKAGE`，`ids=[pkgId...]` | 四个统计字段按任务包维度正确返回（去重逻辑同历史列表统计） |
| LIST-STATS-03（新增） | ACTION 统计 | `POST .../listStats`，`taskType=ACTION`，`ids=[actionId...]` | `distributionTaskCount` / `distributionIssuedTaskCount` 为 0；任务包维度统计按「父 TASK 的 parent_id」解析返回 |
| LIST-STATS-04（回归） | 排除已关闭明细 | 某包下存在 `CLOSED` 与其它状态明细，调用 `listStats` | 四个统计字段均不计入 `CLOSED` 行；停用包并关闭明细后重新查库（或缓存过期后）统计下降 |
| LIST-STATS-CACHE-01（回归） | listStats Redis 按 id | 连续两次 `POST .../listStats`，相同 `taskType` 与相同 `ids`（可含多个 id） | 第二次仍返回与第一次一致的各 id 统计行；命中缓存时行为与查库一致；等待超过缓存 TTL 或删除对应 key 后再请求应仍正确（以库为准） |
| LIST-STATS-JOB-01（回归） | XXL 与 listStats 预热 | 执行 **`refreshTaskDistributionDetailStatusStatsCache`**（见 `task_distribution_detail_test_spec` 用例 6.3） | 内部调用 **`refreshStatsCaches`**；PACKAGE/TASK 各至多 50 条最近 id 的 listStats key 先删后建；随后 **`POST .../listStats`** 带相同 id 应命中缓存 |
| LIST-STATS-REFRESH-01（新增） | 手动刷新统计缓存（异步） | `POST .../refreshStatsCache`，body `{}` 或 `{"objectCodes":["STORE"]}` | 立即 `code=0`；`objectCodes` 非空；计数均为 null；稍后日志可见 **`refreshStatsCaches 完成`** |
| LIST-PARENT-01（回归） | 列表 TASK 行任务包明细 | `POST .../list` 返回至少一条 `taskType=TASK` 且 `parentId` 指向存在任务包 | 该行的 **`taskPackage`** 非空，且 **`taskPackage.id` = `parentId`**，`taskRuleList`/`packageDistributionExt`/`childTaskList` 等与 **`findById(parentId)` 组装的 `TaskDefinitionDTO`** 一致；**注意**：单查 **`POST .../detail`** 且 **`id` 为任务包** 时 **`data`** 为 **`TaskDefinitionPackageUpdateRequestDTO`**，与列表中的 **`taskPackage`** 结构不同 |
| PKG-REG-01 | `objectCode` 回归 | 请求体省略 `objectCode` 或传 `""` | 参数校验失败（如提示 objectCode 不能为空） |
| PKG-REG-02 | 已下线字段 | 请求体仍传历史字段名 `packageTaskSource` 等 | 后端忽略或反序列化丢弃（以实际 Jackson 配置为准） |
| PKG-REG-03 | `objectName` 回归 | 请求体省略 `objectName` 或传 `""` | 参数校验失败（如提示 objectName 不能为空） |
| PKG-REG-04 | 下发扩展四字段必填 | 省略或空串 `distributionObjectGroupId` / `distributionObjectGroupName` / `distributionTypeCode` / `distributionTypeName` 任一项 | 参数校验失败（@NotBlank 或业务提示四字段均不能为空） |
| PKG-REG-05（回归） | createPackage 忽略 ruleCode | `createPackage` 在 **`taskRule`** / **`tasks[].taskRule`** 中传入任意 **`ruleCode`** | 新建 **`task_rule.rule_code`** 为 **GZB/GZR+yyMMdd+8位** 服务端生成，与请求体不一致；**task_code** 为 **B/R+yyMMdd+8位**；**updatePackage** 不修改已有编码 |
| PKG-REG-06 | 周期时间配置校验 | **`b=日`** 且 **`c`** 含 `25:00`；**`b=周`** 且 **`c`** 含 `星期一`；**`b=月`** 且 **`c`** 非 `DD HH:mm` | `BizException` |
| PKG-REG-07 | 周期转 cron | 传合法 **`distributionTimeConfig`**，`distributionType` 可省略 | 落库 **`distribution_config.cron`** 非空；**`distributionType=CRON`**；**`distribution_time_config`** 保留 UI 结构 |
| PKG-REG-08 | cron 解析失败兜底 | 构造非法组合导致内部解析异常（或单测直接调 Converter） | **`distribution_config.cron`** 为 **`0 0 4 * * ?`** |
| TPL-REG-01 | `createTemplate` 单模板 | `dataTemplateIds` 传 2 个及以上元素 | 参数校验失败（dataTemplateIds 仅能包含一个业务模板ID） |
| TPL-REG-02 | 事件编码来自模板 | 所选 `biz_template_config` 行 `task_execution_event_code` 为空 | 业务异常：业务模板未配置 taskExecutionEventCode |
| TPL-REG-03 | 模板字段 ID 落库 | `createTemplate` 传 `templateFieldIds: [101,102]`（均为当前 `dataTemplateIds[0]` 下已存在的 `biz_template_field_map.id`） | `task_template_definition.template_field_ids` JSON 含 `[101,102]`；不再批量创建 `biz_template_field_map` |
| TPL-REG-04 | 无规则落库 | `createTemplate` 成功创建某模板任务 id | **`task_template_definition.rule_id`** 为空（模板不落 task_rule） |
| TPL-REG-05 | 模板类型落库 | `createTemplate` 传 `templateType: "TEMPORARY"` 或 `"COMMON"` | `task_template_definition.template_type` 为大写 **TEMPORARY** 或 **COMMON** |
| EXE-REG-01 | 执行类型字典 | `GET/POST executionTypeOptions` 返回 `records[]` | 单条仅含 `id`、`taskExecutionType`、`taskExecutionTypeName`，无 `taskExecutionEventCode` |
| DEF-DET-01 | 模板详情与创建同构 | `POST /sales/task/template/detail`，模板含 `systemIds`、`templateFieldIds`、`dataTemplateIds` | `data` 为 **`TaskTemplateUpdateRequestDTO`**：`systemIds` / `templateFieldIds` / `dataTemplateIds` 与库一致；**无** `systemDetailList`、`templateFieldDetailList`、`dataTemplateDetailList` |
| PKG-DET-01（回归） | PACKAGE 详情同构 update | `POST /sales/task/definition/detail`，`id` 为任务包 PACKAGE id，其下存在子 TASK | `data` 为 **`TaskDefinitionPackageUpdateRequestDTO`**：含 **`id`**、**`tasks[].taskDefId`**；**`taskRule`/`tasks[].taskRule`** 中 Map 字段为对象而非仅 JSON 字符串；**`tasks[].conditionRepos`** 与库中条件一致；可直接作为 **`updatePackage`**  body 基底（提交前仍须满足更新校验） |
| PKG-DET-02 | 详情非 PACKAGE | `POST /sales/task/definition/detail`，`id` 为 TASK/ACTION 等 | `data` 为 **`TaskDefinitionDTO`**；含 `childTaskList`/`taskRuleList` 等既有结构 |
| DEF-DET-02 | 详情 TASK 绑定模板 | `POST /sales/task/definition/detail`，`id` 为独立 TASK 且 `template_ids` 非空 | 根节点 `linkedTemplateDefinitionList` 按 `templateIds` 顺序含对应 `task_template_definition` enrich 结果（含 `templateFieldDetailList`/`dataTemplateDetailList` 等） |
| STA-01 | 启用停用 | `POST /sales/task/definition/updateStatus`，`enabled: true/false` | 对应表行 `status` 为 1 或 0；id 不存在时报错 |
| STA-02 | 停用包并关闭明细（异步） | `POST /sales/task/definition/disablePackageAndCloseDetails`，`id` 为 PACKAGE | 立即返回 `packageId`，`closedDetailCount=null`；稍后任务包 `status=0`、明细 `CLOSED`；日志可见状态统计缓存刷新与 listStats 预热 |
| TPL-DET-01 | 模板详情 dataTemplateIds | `id` 为 `task_template_definition.id` 且 `data_template_ids` 含有效 `biz_template_config.id` | 响应 `data.dataTemplateIds` 与库表一致；**无** `dataTemplateDetailList` 字段 |

### 四、固定类型创建模板接口（TEMPLATE）

- 接口：`POST /sales/task/template/createTemplate`
- 必填校验字段：`taskName`、`templateType`（**TEMPORARY**=临时模板，**COMMON**=常用模板）、`dataTemplateIds`（**且长度必须为 1**，业务模板 `biz_template_config.id`）、`taskExecutionTypeName`、`templateFieldIds`（至少 1 个 **`biz_template_field_map.id`**，且每条记录的 **`template_id`** 须等于 `dataTemplateIds[0]`）
- **`taskExecutionEventCode` 不在请求体传递**：由 `dataTemplateIds[0]` 对应的 **`biz_template_config.task_execution_event_code`** 反查写入 `task_template_definition`；若该字段在库中为空则创建失败。
- **`templateFieldIds`**：仅存 ID 列表至 **`task_template_definition.template_field_ids`**（JSON 数组）；**不再**在 createTemplate 内批量创建 `biz_template_field_map` 记录。字段映射需事先在业务模板侧维护好。
- **不再**在 createTemplate 流程中写入 **`task_rule`**（模板创建仅落库 `task_template_definition` 等主表数据；关联关系为 **`task_definition` / `task_template_definition.rule_id` → `task_rule.id`**）。
- 请求 JSON 示例（字段含义）：

```json
{
  "taskName": "终端盘点模板", // 必填：模板任务名称
  "templateType": "COMMON", // 必填：模板类型，TEMPORARY=临时模板，COMMON=常用模板；落库 task_template_definition.template_type（大写存储）
  "taskTitle": "终端盘点模板标题", // 可空：模板标题
  "taskDescription": "用于终端盘点任务下发", // 可空：模板说明
  "taskExecutionTypeName": "手动执行", // 必填：执行类型名称
  "taskExecutionType": "MANUAL", // 可空：执行类型编码
  "dataTemplateIds": [1001], // 必填：仅允许 1 个元素，业务模板ID（biz_template_config.id），落库 data_template_ids；createTemplate 会反查，不存在报错
  "packageSystemIds": [1], // 可空：模板任务关联系统ID列表（task_system_option.id，createTemplate 会反查，不存在/停用报错）
  "systemIds": [1], // 可空：兼容字段；当 packageSystemIds 为空时才使用
  "conditionIds": [2001, 2002], // 必填：条件ID列表
  "objectCode": "STORE", // 可空：对象编码
  "objectName": "门店", // 可空：对象名称（与 objectCode 成对落库 task_definition）
  "startTime": "2026-03-23T09:00:00", // 可空：开始时间
  "endTime": "2026-03-31T23:59:59", // 可空：结束时间
  "templateFieldIds": [101, 102] // 必填：已存在的 biz_template_field_map.id 列表，且 template_id 须等于 dataTemplateIds[0]；落库 task_template_definition.template_field_ids
}
```

### 五、任务执行类型选项接口

- 接口：`POST /sales/task/definition/executionTypeOptions`
- 请求 Body（可空，空则使用默认分页）：`page`、`pageSize` 默认分别为 `1`、`20`
- 数据来自表 `task_execution_type_option`（仅 `status=1` 启用项，停用不展示；未逻辑删除；按 `sort_order`、`id` 升序，数据库分页）；每条记录带字典表主键 `id`；**不再返回 `taskExecutionEventCode`**（该字段已从字典表移除，事件编码见 `biz_template_config` / `task_definition`）
- 回归：执行 `doc/sql/update_tables.sql` 中本表建表与初始化后，`data.records` 应与库中一致
- 请求 JSON 示例：

```json
{
  "page": 1, // 当前页码，默认 1
  "pageSize": 20 // 每页条数，默认 20
}
```

- 返回示例（`data` 为 `PageResult`：`records`、`total`、`page`、`pageSize`、`totalPage`）：

```json
{
  "records": [
    {
      "id": 1, // 字典表主键
      "taskExecutionType": "a", // 任务执行类型编码
      "taskExecutionTypeName": "销售订单" // 任务执行类型名称
    }
  ],
  "total": 3, // 总条数
  "page": 1, // 当前页
  "pageSize": 20, // 每页条数
  "totalPage": 1 // 总页数
}
```

### 六、任务对象选项接口

- 接口：`POST /sales/task/definition/objectOptions`
- 请求 Body（可空，空则使用默认分页）：`page`、`pageSize` 默认分别为 `1`、`20`
- 数据来自表 `task_object_option`（仅 `status=1` 启用项，停用不展示；未逻辑删除；按 `sort_order`、`id` 升序，数据库分页）；每条记录带字典表主键 `id`
- 返回字段新增：`groupMappingCode`（分组映射编码，用于映射转换 code）
- 请求 JSON 示例：

```json
{
  "page": 1, // 当前页码，默认 1
  "pageSize": 20 // 每页条数，默认 20
}
```

- 返回示例（`data` 为 `PageResult`）：

```json
{
  "records": [
    {
      "id": 1, // 字典表主键
      "objectName": "门店", // 对象名称
      "objectCode": "STORE", // 对象编码
      "groupMappingCode": "sales_channel" // 分组映射编码（用于映射转换 code）
    }
  ],
  "total": 4, // 总条数
  "page": 1,
  "pageSize": 20,
  "totalPage": 1
}
```

### 七、任务系统选项接口

- 接口：`POST /sales/task/definition/systemOptions`
- 请求 Body（可空，空则使用默认分页）：`page`、`pageSize` 默认分别为 `1`、`20`；可选 `systemName` 对 `system_name` **模糊**查询（`LIKE`）
- 数据来自表 `task_system_option`（仅 `status=1` 启用项，停用不展示；未逻辑删除；按 `sort_order`、`id` 升序，数据库分页）；每条记录含系统主键 `id`、系统名称、系统编码
- 请求 JSON 示例：

```json
{
  "page": 1, // 当前页码，默认 1
  "pageSize": 20, // 每页条数，默认 20
  "systemName": "销售" // 可选，系统名称模糊匹配
}
```

- 返回示例（`data` 为 `PageResult`）：

```json
{
  "records": [
    {
      "id": 1, // 系统ID（主键）
      "systemName": "销售任务中心", // 系统名称
      "systemCode": "SLS_SALES_TASK" // 系统编码
    }
  ],
  "total": 2, // 总条数（以库中初始化数据为准）
  "page": 1,
  "pageSize": 20,
  "totalPage": 1
}
```

### 三、测试用例（续）

- 用例1：正常创建 PACKAGE + 多个 TASK
  - 前置：`templateIds` 中 `1001/1002` 对应记录存在且 `task_type=TEMPLATE`
  - 预期：
    - 返回创建的任务包 **`task_definition.id`**
    - 生成 1 条 `PACKAGE` 任务定义
    - 生成 2 条 `TASK` 任务定义，且 `parent_id` 为上述任务包 id
    - 每个 `TASK.template_ids` JSON 为单元素数组（如 `[1001]`、`[1002]`）；`object_code`/`object_name` 与 PACKAGE 任务包一致；`task_execution_type` 等与所绑定 TEMPLATE 一致
    - `PACKAGE.distribution_task_count=2`

- 用例2：TASK hasAction=true 但 templateIds 为空或未传
  - 入参：任一 `tasks[i].hasAction=true` 且 `templateIds` 为 `null`、缺省或 `[]`
  - 预期：接口报错，事务回滚，不产生 PACKAGE/TASK 数据

- 用例2b：TASK hasAction=false 可不传 templateIds
  - 入参：`hasAction=false`，不传 `templateIds` 或 `templateIds=[]`
  - 预期：创建成功，对应 `TASK` 不落库 `template_ids`（或为空）

- 用例2c：TASK 提交 conditionRepos
  - 入参：某 `tasks[i].conditionRepos` 为含 1 条及以上合法 `ConditionRepo` 结构（含 `conditionName`、`operator`（非空）；`operatorName` 可选；`objectType` 可省略）
  - 预期：每条生成 `condition_repo` 记录；对应子 TASK 的 `condition_ids` JSON 为新生成 id 列表（顺序与数组一致）

- 用例2c3（回归）：conditionRepos 缺 operator
  - 入参：`hasAction=true`，`conditionRepos` 至少 1 条且 **`operator` 缺省、null、空串或仅空白**
  - 预期：接口报错（提示 `conditionRepos[i].operator 不能为空（须由请求体传递）`），事务回滚

- 用例2c2（回归）：单条 conditionRepos 内 defaultValue 数组过滤空 value；整条 ConditionRepoDTO 无有效 defaultValue 时丢弃该条
  - 入参（节选 `tasks[i].conditionRepos` 中一条，与 `POST /sales/task/definition/createPackage` 一致）：

```json
{
  "conditionName": "测试条件", // 必填
  "operator": "OR", // 必填：须由请求体传递
  "defaultValue": [
    { "value": null }, // 过滤掉
    { "value": "" } // 过滤掉；若仅此两类则该条内数组为空 → 整项 ConditionRepoDTO 丢弃
  ]
}
```

  - 若 `conditionRepos` 仅此一条且被整项丢弃，或单对象 `"defaultValue": { "value": "" }` / `{ "value": null }` / `null` / `""` / `[]` / `{}` 导致无有效条：**过滤后须至少保留 1 条 ConditionRepoDTO**，否则接口报错
  - 对照入参：两条 ConditionRepo，一条 `defaultValue` 全空被丢弃、另一条有效 → 仅落库有效条；`"defaultValue": [ { "value": "" }, { "value": "1" } ]` 时单条内过滤后为 `[ { "value": "1" } ]`，可正常落库（与 2c 一致）

- 用例2d：hasAction=true 但未传 conditionRepos
  - 入参：某 `tasks[i].hasAction=true` 且 `conditionRepos` 缺省、`null` 或 `[]`
  - 预期：接口报错，事务回滚

- 用例2e：templateIds 与 conditionRepos 均非空，但未传 tasks[].completionScript
  - 入参：某 `tasks[i].templateIds` 至少 1 个有效 ID，`conditionRepos` 至少 1 条合法项，`tasks[i].completionScript` 缺省、空串或仅空白（且不在 `taskRule` 上传）
  - 预期：接口报错（绑定模板且填写 conditionRepos 时 `tasks[].completionScript` 必填），事务回滚

- 用例2e2：conditionRepos.fieldCode 不在绑定模板 template_field_ids 的 mappedCol 范围内
  - 前置：该 `tasks[i].templateIds[0]` 对应 `task_template_definition`，其 `template_field_ids` 已配置（如对象数组含 `id`+`mappedCol` 或数字 id 数组）
  - 入参：`hasAction=true`，`conditionRepos` 至少 1 条且 **`fieldCode` 填写为模板中不存在的 mapped_col**（与库中 `biz_template_field_map.mapped_col` 规范化后不一致）
  - 预期：接口报错（提示 fieldCode 须为模板 template_field_ids 中的 mappedCol），事务回滚

- 用例2f：tasks[].completionScript 非空但格式非法
  - 入参：某 `tasks[i].completionScript` 为非空串，但不符合「换行分条 + 每行 字段名+运算符+值」；例如 `return true;`、无运算符的纯文本、字段名含中文或空格、或仅含空白换行
  - 预期：接口报错（提示 completionScript 格式/运算符/字段名等），事务回滚

- 用例3：TASK 的 templateIds 某项非 TEMPLATE 类型
  - 前置：某项 id 存在但 `task_type!=TEMPLATE`
  - 预期：接口报错，事务回滚，不产生 PACKAGE/TASK 数据

- 用例3b：TASK 的 templateIds 超过 1 个元素
  - 入参：`hasAction=true` 且 `templateIds: [1001, 1002]`
  - 预期：接口报错（最多仅允许 1 个模板 ID），事务回滚

- 用例4：tasks 为空
  - 入参：`tasks=[]`
  - 预期：接口报错，不产生数据

- 用例5：顶层 taskRule 为空
  - 入参：`taskRule=null`
  - 预期：接口报错，事务回滚，不产生 PACKAGE/TASK 数据

- 用例6：任一 TASK 的 taskRule 为空
  - 入参：`tasks[i].taskRule=null`
  - 预期：接口报错，事务回滚，不产生 PACKAGE/TASK 数据

- 用例7：PACKAGE 的 distributionType 为空
  - 入参：`taskRule.distributionType=null`
  - 预期：接口报错，事务回滚，不产生 PACKAGE/TASK 数据

- 用例8：PACKAGE 的 distributionType=CRON 但 distributionConfig 非法
  - 入参：`taskRule.distributionType=CRON` 且 `distributionConfig` 非 JSON 或缺少 `cron`
  - 预期：接口报错，事务回滚，不产生 PACKAGE/TASK 数据

- 用例8a：PACKAGE 的 distributionType=CRON 且 distributionConfig 正确
  - 入参：`taskRule.distributionType=CRON` 且 `distributionConfig` 含 `cron`（例如 `{"cron":"0 0/5 * * * ?"}`）
  - 预期：创建成功，且该规则的 `distributed_at` 被写入为 cron 下次执行时间（解析结果非空）

- 用例9：PACKAGE 的 distributionType=IMMEDIATE
  - 入参：`taskRule.distributionType=IMMEDIATE`
  - 预期：创建成功，且该规则的 `distributed_at` 被写入为当前系统时间

- 用例9b：PACKAGE 的 distributionType=FIXED 但 distributedAt 缺失
  - 入参：`taskRule.distributionType=FIXED` 且 `taskRule.distributedAt=null`
  - 预期：接口报错，事务回滚，不产生 PACKAGE/TASK 数据

- 用例9c：PACKAGE 的 distributionType=FIXED 且 distributedAt 传入
  - 入参：`taskRule.distributionType=FIXED` 且 `taskRule.distributedAt` 为**当前时间之后**（示例：`2026-03-23T10:30:00`）
  - 预期：创建成功，且该规则的 `distributed_at` 被写入为入参 distributedAt

- 用例9d：PACKAGE 的 distributionType=FIXED 但 distributedAt 小于等于当前时间
  - 入参：`taskRule.distributionType=FIXED` 且 `taskRule.distributedAt` <= 当前时间
  - 预期：接口报错，事务回滚，不产生 PACKAGE/TASK 数据

- 用例9e：PACKAGE 顶层 `taskRule.deadlineType=RELATIVE` 但 `deadlineConfig` 不符合格式
  - 入参：顶层 `taskRule.deadlineType=RELATIVE`，`deadlineConfig` 缺少 `days` 或 `time`，或 `time` 非合法时刻
  - 预期：接口报错（`validatePackageRuleDeadlineConfig`），事务回滚

- 用例9f：PACKAGE 顶层 `taskRule.deadlineType=ABSOLUTE` 但 `deadlineConfig` 不符合格式
  - 入参：顶层 `taskRule.deadlineType=ABSOLUTE`，`deadlineConfig.date` 非 `yyyy-MM-dd`，或缺少 `date`/`time`
  - 预期：接口报错，事务回滚
  - 补充：`RELATIVE/ABSOLUTE/MONTH` 的 `deadlineConfig.time` 在运行期解析后秒位统一归一化为 `59`（如 `23:30`、`23:30:00` 均按 `23:30:59` 计算）

- 用例9f-month（新增）：`deadlineType=MONTH` 合法配置
  - 入参（`tasks[i].taskRule` 或 PACKAGE 顶层均可）：
    ```json
    {
      "deadlineType": "MONTH",
      "deadlineConfig": {
        "monthDimension": "FISCAL_QUARTER_LAST",
        "monthDay": "END_OF_MONTH",
        "time": "23:59:59"
      }
    }
    ```
- `monthDimension` 允许：`CURRENT_MONTH`、`NEXT_MONTH`、`MONTH_2`、`MONTH_3`、`QUARTER_LAST`、`FISCAL_QUARTER_LAST`；`monthDay` 为 `END_OF_MONTH` 或 `01`–`31`（目标月有效日）；`time` 为 `HH:mm` / `HH:mm:ss`，解析后秒位统一归一化为 `59`（如 `23:30` → `23:30:59`，`23:30:00` 也会按 `23:30:59` 计算）
  - 预期：创建/更新成功；`NOT_STARTED→IN_PROGRESS` 时按迁移时刻解析 `end_time`：
    - `FISCAL_QUARTER_LAST`：财年按 **6 月起算**，财季为 `6-8`、`9-11`、`12-2`、`3-5`，财季末月为 `8/11/2/5`；如迁移时刻在 2026-06~08 → `end_time=2026-08-31 23:59:59`（配置 `END_OF_MONTH` + `23:59:59`）
    - `QUARTER_LAST`：自然季末月 3/6/9/12；如迁移时刻在 2026-10~12 → `end_time=2026-12-31 23:59:59`

- 用例9f-month-quarter（回归）：`QUARTER_LAST` 与 `FISCAL_QUARTER_LAST` 对比
  - 前置：迁移基准时刻 `2026-06-22`
  - `QUARTER_LAST` + `END_OF_MONTH` + `23:59:59` → `2026-06-30 23:59:59`
  - `FISCAL_QUARTER_LAST` + `END_OF_MONTH` + `23:59:59` → `2026-08-31 23:59:59`（财季 6-8，财季末 8 月）

- 用例9f-month-err（新增）：`deadlineType=MONTH` 非法 `monthDimension`
  - 入参：`monthDimension` 非上述枚举
  - 预期：接口报错，事务回滚

- 用例9g（回归）：PACKAGE 顶层 `taskRule.taskJudgmentDeadlineType=RELATIVE` 但 `taskJudgmentDeadlineConfig` 不符合格式
  - 入参：顶层 `taskRule.taskJudgmentDeadlineType=RELATIVE`，`taskJudgmentDeadlineConfig` 缺少 `days` 或 `time`，或 `time` 非合法时刻
  - 预期：接口报错（`validatePackageRuleJudgmentDeadlineConfig`），事务回滚

- 用例9h（回归）：PACKAGE 顶层 `taskRule.taskJudgmentDeadlineType=ABSOLUTE` 但 `taskJudgmentDeadlineConfig` 不符合格式
  - 入参：顶层 `taskRule.taskJudgmentDeadlineType=ABSOLUTE`，`taskJudgmentDeadlineConfig.date` 非 `yyyy-MM-dd`，或缺少 `date`/`time`
  - 预期：接口报错，事务回滚

- 用例10：TASK 的 deadlineType 缺失
  - 入参：任一 `tasks[i].taskRule.deadlineType` 为空
  - 预期：接口报错，事务回滚，不产生 PACKAGE/TASK 数据

- 用例11：TASK hasAction=true 但未绑定 templateIds（与用例2 回归重复时可合并）
  - 入参：任一 `tasks[i].hasAction=true` 且（未传 `templateIds` 或 `templateIds` 为空数组）
  - 预期：接口报错，事务回滚，不产生 PACKAGE/TASK 数据

- 用例12：updatePackage 禁止修改进行中的任务包
  - 前置：存在任务包 id，其 `task_status=IN_PROGRESS`
  - 入参：`POST /sales/task/definition/updatePackage`，携带顶层 **`id`**（任务包 `task_definition.id`）与对应 `tasks[i].taskDefId`（内容可为任意）
  - 预期：接口报错，事务回滚；不更新该任务包及其关联的 `task_rule`、`task_package_distribution_ext`、`condition_repo`、已存在的 `task_distribution_detail` 冗余字段

