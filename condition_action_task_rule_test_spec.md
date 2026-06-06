# 条件库、动作库、任务规则与任务实例测试规格

## 功能模块：条件库、动作库、任务规则、任务实例（TRD 4.2 新增）

### 一、条件库（condition_repo）

- **用例1：新增条件成功**
  - 接口：`POST /condition/repo/create`
  - 请求 Body 示例（JSON）：
    ```json
    {
      "conditionCode": "COND_STORE_LEVEL",
      "conditionName": "门店等级为A级",
      "objectType": "STORE",
      "templateId": 1,
      "fieldCode": "store_level",
      "operator": "EQ",
      "dataTypeDefinition": "STRING",
      "defaultValue": "{\"value\":\"A级\"}",
      "description": "筛选A级门店",
      "status": 1
    }
    ```
  - 预期结果：返回 `Response.success`，data 为新建记录的自增 `id`

- **用例2：更新条件成功**
  - 接口：`POST /condition/repo/update`
  - 请求 Body：携带完整 DTO（含 id）
  - 预期结果：返回 `Response.success`

- **用例3：删除条件（逻辑删除）**
  - 接口：`POST /condition/repo/delete?id={id}`
  - 预期结果：返回 `Response.success`，对应记录 `is_deleted` 置为 1

- **用例4：查询条件详情**
  - 接口：`POST /condition/repo/detail`
  - 请求 Body：`{ "id": 1 }`
  - 预期结果：返回 `Response.success`，data 为 `ConditionRepoDTO`

- **用例5：查询条件列表**
  - 接口：`POST /condition/repo/list` 或 `POST /condition/repo/list?templateId=1`
  - 预期结果：返回 `Response.success`，data 为 `List<ConditionRepoDTO>`

### 二、统一任务定义（task_definition）

任务与动作统一为一张表，通过 task_type（PACKAGE/TASK/ACTION）和 parent_id 区分子任务。

- **用例6：新增任务定义成功**
  - 接口：`POST /sales/task/definition/createPackage`
  - 请求 Body 示例（顶层任务/任务包）：
    ```json
    {
      "taskCode": "TASK_SPRING_2024",
      "taskName": "春耕铺货任务",
      "taskType": "TASK",
      "parentId": null,
      "taskSource": "rule",
      "status": 1
    }
    ```
  - 请求 Body 示例（子任务/原动作）：
    ```json
    {
      "taskCode": "ORDER_STANDARD",
      "taskName": "标准补货下单",
      "taskType": "ACTION",
      "parentId": 1,
      "variables": "[{\"name\":\"sku\",\"label\":\"补货商品\",\"type\":\"string\",\"required\":true}]",
      "completionLogic": "REQUIRE_PHOTO=FALSE",
      "conditionIds": [1, 2, 3],
      "status": 1
    }
    ```
    - 说明：`conditionIds` 为关联的 condition_repo ID 列表，可关联多个条件库；不传时为空。
    - **联动创建**：create 成功后会在事务内自动创建 `TaskRule`，并回写 **`task_definition.rule_id`** 指向该规则；同时处理 `TaskInstance`，未传值字段赋予默认值。
  - 预期结果：返回 `Response.success`，data 为新建记录的自增 `id`
    - **级联创建**：事务内自动创建对应的一条 TaskRule（rule_code=RULE_TD…），并写入 **`task_definition.rule_id`**、`TaskInstance`，未传字段赋予默认值

- **用例7：更新任务定义成功**
  - 接口：`POST /task/definition/update`
  - 预期结果：返回 `Response.success`

- **用例8：删除任务定义（逻辑删除，级联删除关联数据）**
  - 接口：`POST /task/definition/delete?id={id}`
  - 说明：delete 会在事务内级联删除该任务定义关联的 TaskInstance、TaskRule（按 **`task_definition.rule_id`** / **`task_template_definition.rule_id`** 定位规则）。
  - 预期结果：返回 `Response.success`

- **用例9：查询任务模板定义详情**
  - 接口：`POST /sales/task/template/detail`
  - 请求 Body：`{ "id": 1 }`（`id` 为 `task_template_definition` 主键）
  - 预期结果：返回 `Response.success`，data 为 `TaskTemplateUpdateRequestDTO`（与 `createTemplate` 请求体同构并含 `id`）

- **用例10：查询任务定义列表**
  - 接口：`POST /task/definition/list`
  - 预期结果：返回 `Response.success`，data 为 `List<TaskDefinitionDTO>`

- **用例10b：查询子任务列表（按父任务ID）**
  - 接口：`POST /task/definition/children?parentId={parentId}`
  - 预期结果：返回 `Response.success`，data 为 `List<TaskDefinitionDTO>`，仅包含该父任务下的子任务（原动作）

### 三、任务规则（task_rule）

- **字段说明**：`has_action` 表示是否包含操作（模板动作）。**`POST /sales/task/definition/createPackage`** 落库时：任务包对应 **`task_rule.has_action=0`**；子 TASK 对应规则与 **`tasks[].hasAction`** 一致（true→1，false→0）。

- **用例11：新增任务规则成功**
  - 接口：`POST /task/rule/create`
  - 请求 Body 示例（完整，含触发/下发/截止配置）：
    ```json
    {
      "ruleCode": "RULE_SPRING_2024",
      "ruleName": "春耕铺货任务",
      "description": "春季铺货任务规则",
      "targetObjectType": "STORE",
      "conditionMode": "FACTOR",
      "targetConditions": "{\"logic\":\"AND\",\"groups\":[]}",
      "targetConditionScript": null,
      "triggerType": "CRON",
      "triggerConfig": "{\"cron\":\"0 30 2 * * * ?\"}",
      "distributionType": "CRON",
      "distributionConfig": "{\"cron\":\"0 30 2 * * * ?\"}",
      "taskTitle": "春耕补货任务",
      "taskDescription": "每日 2:30 下发，截止为下发后第 10 天 22:30",
      "deadlineType": "RELATIVE",
      "deadlineConfig": "{\"days\":10,\"time\":\"22:30\"}",
      "completionType": "ACTION_BASED",
      "completionConditions": null,
      "completionScript": null,
      "actionExecutionMode": "ALL",
      "status": 1,
      "autoCloseOnDeadline": false, // 是否截止自动关闭：false-否，true-是；可空
      "syncCompleteTask": false, // 是否同步完成任务：false-否，true-是；可空
      "createdBy": "admin",
      "updatedBy": null
    }
    ```
  - 请求 Body 示例（直接下发 + 固定截止）：
    ```json
    {
      "ruleCode": "RULE_MANUAL_001",
      "ruleName": "手动下发任务",
      "description": "创建后立即下发",
      "targetObjectType": "STORE",
      "conditionMode": "FACTOR",
      "targetConditions": "{\"logic\":\"AND\",\"groups\":[]}",
      "triggerType": "IMMEDIATE_ON_DATA_CHANGE",
      "triggerConfig": null,
      "distributionType": "IMMEDIATE",
      "distributionConfig": null,
      "taskTitle": "手动补货任务",
      "taskDescription": "直接下发，截止 2024-03-31 18:00",
      "deadlineType": "ABSOLUTE",
      "deadlineConfig": "{\"date\":\"2024-03-31\",\"time\":\"18:00\"}",
      "completionType": "ACTION_BASED",
      "actionExecutionMode": "ALL",
      "status": 1
    }
    ```
  - 请求 Body 示例（固定时间触发 + 固定时间下发）：
    ```json
    {
      "ruleCode": "RULE_FIXED_001",
      "ruleName": "固定时间任务",
      "description": "指定时间触发并下发",
      "targetObjectType": "DEALER",
      "conditionMode": "FACTOR",
      "targetConditions": "{\"logic\":\"AND\",\"groups\":[]}",
      "targetConditionScript": null,
      "triggerType": "FIXED",
      "triggerConfig": "{\"dateTime\":\"2024-03-15 02:30:00\"}",
      "distributionType": "FIXED",
      "distributionConfig": "{\"dateTime\":\"2024-03-15 03:00:00\"}",
      "taskTitle": "固定时间补货任务",
      "taskDescription": "2024-03-15 02:30 触发，03:00 下发",
      "deadlineType": "ABSOLUTE",
      "deadlineConfig": "{\"date\":\"2024-03-20\",\"time\":\"23:59\"}",
      "completionType": "ACTION_BASED",
      "completionConditions": null,
      "completionScript": null,
      "actionExecutionMode": "ANY",
      "status": 1
    }
    ```
  - 字段说明：
    - `ruleCode`：规则唯一编码，必填
    - `ruleName`、`description`：规则名称、描述
    - `targetObjectType`：下发对象 STORE/DEALER/PERSON，默认 STORE
    - `conditionMode`：FACTOR(因子条件)/SCRIPT(脚本)，必填
    - `targetConditions`：因子条件 JSON，conditionMode=FACTOR 时使用
    - `targetConditionScript`：Groovy 脚本，conditionMode=SCRIPT 时使用
    - `triggerType`：CRON/FIXED/IMMEDIATE_ON_DATA_CHANGE；CRON/FIXED 时 `triggerConfig` 必填
    - `triggerConfig`：CRON 为 `{"cron":"秒 分 时 日 月 周"}`，FIXED 为 `{"dateTime":"yyyy-MM-dd HH:mm:ss"}`
    - `distributionType`：CRON/FIXED/IMMEDIATE(直接下发)；CRON/FIXED 时 `distributionConfig` 必填
    - `distributionConfig`：格式同 triggerConfig
    - `deadlineType`：RELATIVE/ABSOLUTE；RELATIVE 为 `{"days":N,"time":"HH:mm"}`，ABSOLUTE 为 `{"date":"yyyy-MM-dd","time":"HH:mm"}`
    - `completionType`：ACTION_BASED/SCRIPT_BASED，必填
    - `actionExecutionMode`：ALL(全部执行)/ANY(任一执行)，默认 ALL
    - `autoCloseOnDeadline`：是否截止自动关闭（`false`-否，`true`-是；可空；对应库表 `task_rule.auto_close_on_deadline` 存 `0`/`1`）
    - `syncCompleteTask`：是否同步完成任务（`false`-否，`true`-是；可空；对应库表 `task_rule.sync_complete_task` 存 `0`/`1`）
  - 预期结果：返回 `Response.success`，data 为新建记录的自增 `id`

- **用例12：更新任务规则**
  - 接口：`POST /task/rule/update`
  - 预期结果：返回 `Response.success`
  - **联动更新**：当规则 `status=1`（启用）时，会自动联动更新该规则下所有 `PENDING` 状态任务实例的：
    - `distributedAt` 计划下发时间：CRON → 按 cron 算出下次执行时间；FIXED → 解析 dateTime；IMMEDIATE → 当前时间
    - `scheduledExecuteAt` 计划执行时间：由 triggerType+triggerConfig 解析；IMMEDIATE_ON_DATA_CHANGE 时为 null
    - `triggeredByDataChange` 是否由数据变更实时触发：triggerType=IMMEDIATE_ON_DATA_CHANGE 时为 1
    - `deadline` 截止时间：RELATIVE → 计划下发时间 + N 天 + 指定时分；ABSOLUTE → 解析 date + time
  - 可先通过 `POST /task/instance/list`，Body 如 `{"page":1,"pageSize":20,"ruleId":[1]}` 或 `{"page":1,"pageSize":20,"taskPackageId":100}`（`ruleId` 非空则 IN；`taskPackageId` 为 PACKAGE 的 `task_definition.id` 时解析包与子任务 `rule_id` 后 IN；二者同传为交集；**total 与分页仅基于按 id 降序最近 1 万条命中行**，与下发明细 `/listByPackage` 截取思路一致）查看实例，再调用 update 修改规则，验证关联 PENDING 实例上述字段已更新

- **用例13：删除任务规则（逻辑删除）**
  - 接口：`POST /task/rule/delete?id={id}`
  - 预期结果：返回 `Response.success`

- **用例14：查询任务规则详情**
  - 接口：`POST /task/rule/detail`
  - 请求 Body：`{ "id": 1 }`
  - 预期结果：返回 `Response.success`，data 为 `TaskRuleDTO`

- **用例15：查询任务规则列表**
  - 接口：`POST /task/rule/list`
  - 预期结果：返回 `Response.success`，data 为 `List<TaskRuleDTO>`

### 四、任务规则与任务定义关联（已移除 task_rule_action_rel）

- **说明**：原 `task_rule_action_rel` 表及 `POST /sales/task/rule/action/*` 接口已废弃；任务规则与任务定义的关联改为 **`task_definition.rule_id` / `task_template_definition.rule_id`** 指向 **`task_rule.id`**。
- **回归**：创建任务定义后，对应表行 **`rule_id`** 非空且与 **`task_rule.id`** 一致；不再产生 `task_rule_action_rel` 记录。

### 五、任务实例（task_instance）

- **用例18：新增任务实例**
  - 接口：`POST /task/instance/create`
  - 请求 Body 示例（JSON）：
    ```json
    {
      "taskCode": "TASK_20240304_001",
      "taskTitle": "春耕补货-门店A",
      "taskRuleId": 1,
      "targetEntityType": "STORE",
      "targetEntityId": "STORE001",
      "targetEntityName": "测试门店A",
      "status": "PENDING"
    }
    ```
  - 预期结果：返回 `Response.success`，data 为新建记录的自增 `id`；库表 **`created_by`、`updated_by`** 均为 **`系统`**（与请求体是否携带审计字段无关，由服务端统一写入）

- **用例19：查询任务实例详情**
  - 接口：`POST /task/instance/detail`
  - 请求 Body：`{ "id": 1 }`
  - 预期结果：返回 `Response.success`，data 为 `TaskInstanceDTO`

- **用例20：查询任务实例列表**
  - 接口：`POST /task/instance/list`（JSON Body，分页）
  - 请求 Body 示例：
    ```json
    {
      "page": 1,
      "pageSize": 20,
      "//page": "当前页，默认 1",
      "//pageSize": "每页条数，默认 20",
      "ruleId": [1, 2],
      "//ruleId": "可选：规则 id 数组，去 null 去重后非空则 task_rule_id IN (...)",
      "taskPackageId": 100,
      "//taskPackageId": "可选：任务包 task_definition.id（须为 PACKAGE 且未删除）；服务端读取该包 rule_id 及 parent_id=该 id、is_deleted=0 的子任务定义上的 rule_id，合并去重后 task_rule_id IN (...)；与 ruleId 同时传时对两套 id 取交集；包不存在/非 PACKAGE/已删/解析后无任何 rule_id 时返回空页",
      "targetEntityId": "STORE001",
      "//targetEntityId": "可选：精准匹配 target_entity_id（trim）",
      "targetEntityName": "示例门店",
      "//targetEntityName": "可选：精准匹配 target_entity_name（trim）",
      "//recentWindow": "列表 total 与分页仅基于「命中 task_rule_id IN 后按 id 降序最近 10000 条」；更早实例不在本接口结果集中"
    }
    ```
  - **口径**：用于 **`task_rule_id IN (...)`** 的规则 id 集合若为空（既未传有效 **`ruleId`**，也未传 **`taskPackageId`**，或二者交集/解析结果为空），则 **不查全表**，直接返回 **`records` 为空列表、`total=0`** 的分页结果
  - **最近 1 万条**：在规则 IN 条件命中行中，先按 **`task_instance.id` 降序**仅保留 **最多 10000 条** 作为统计与分页全集；**`total` ≤ 10000**（与下发明细 **`/listByPackage`** 先截取再分页的思路一致，避免大表全量扫描）
  - **`targetEntityId` / `targetEntityName`**：可选；仅传 **ID** 则 **`target_entity_id = trim(id)`**；仅传 **名称** 则 **`target_entity_name = trim(name)`**；**均传**则 **`(target_entity_id = trim(id) OR target_entity_name = trim(name))`**（非 LIKE）；与 rule 条件 AND
  - 预期结果：返回 `Response.success`，data 为分页结构（含 `records`、`total`、`page`、`pageSize`、`totalPage` 等）；**`records` 按 id 倒序**

### 六、任务实例动作（task_instance_action）

- **用例21：新增任务实例动作**
  - 接口：`POST /task/instance/action/create`
  - 请求 Body 示例：`{ "taskInstanceId": 1, "taskDefId": 1, "actionName": "标准补货", "status": "PENDING", "sortOrder": 0 }`
  - 说明：`taskDefId` 关联 task_definition 中的子任务定义
  - 预期结果：返回 `Response.success`，data 为新建记录的自增 `id`

- **用例22：按任务实例ID查询动作列表**
  - 接口：`POST /task/instance/action/listByTaskInstanceId?taskInstanceId=1`
  - 预期结果：返回 `Response.success`，data 为 `List<TaskInstanceActionDTO>`

### 七、任务实例执行日志（task_instance_execution_log）

- **用例23：新增执行日志**
  - 接口：`POST /task/instance/execution/log/create`
  - 请求 Body 示例：`{ "taskInstanceId": 1, "eventType": "CREATED", "eventData": "{}", "operatorId": "admin" }`
  - 预期结果：返回 `Response.success`，data 为新建记录的自增 `id`

- **用例24：按任务实例ID查询执行日志列表**
  - 接口：`POST /task/instance/execution/log/listByTaskInstanceId?taskInstanceId=1`
  - 预期结果：返回 `Response.success`，data 为 `List<TaskInstanceExecutionLogDTO>`，按 `createdAt` 正序
