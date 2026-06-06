# 任务模板接口测试用例

## 1. 任务模板分页列表

- 接口：`POST /sales/task/template/list`
- 说明：本接口**独立**分页查询 `task_template_definition`，**不再复用** `POST /sales/task/definition/list` 的 `pageList` 实现；筛选语义与原先 `taskType=TEMPLATE` 时一致。**`taskExecutionType`** 精准匹配 `task_execution_type`（trim）。**`taskType`** 仅允许 `TEMPLATE` 或省略，其它值返回业务错误。**列表按 `id` 倒序**（新记录在前）。

### 1.1 请求参数示例

```json
{
  "taskType": "TEMPLATE", 
  "//taskType": "仅允许 TEMPLATE 或省略；传其它类型报错",
  "templateType": "COMMON",
  "//templateType": "模板类型：TEMPORARY=临时模板，COMMON=常用模板；与库字段精确匹配（trim 后大写）；不传则不筛选",
  "taskCode": "TPL2026", 
  "//taskCode": "任务编码，模糊搜索",
  "taskName": "陈列", 
  "//taskName": "任务名称，模糊搜索",
  "taskTitle": "3月活动", 
  "//taskTitle": "任务标题，模糊搜索",
  "objectName": "阳西县联兴食品批发商行",
  "//objectName": "对象名称，模糊搜索",
  "objectCode": "FX000938",
  "//objectCode": "对象编码，模糊搜索",
  "taskExecutionType": "MANUAL",
  "//taskExecutionType": "任务执行类型编码，精准匹配 task_template_definition.task_execution_type（trim）；不传则不筛选",
  "status": [1], 
  "//status": "配置状态数组，IN 查询，1-启用，0-停用",
  "taskStatus": ["IN_PROGRESS", "COMPLETED"], 
  "//taskStatus": "（已废弃：task_template_definition 已删除 task_status）",
  "page": 1, 
  "//page": "分页参数，第几页，默认 1",
  "pageSize": 20, 
  "//pageSize": "分页参数，每页条数，默认 20"
}
```

### 1.2 返回结果示例

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "records": [],
    "total": 0,
    "page": 1,
    "pageSize": 20,
    "totalPage": 0
  }
}
```

---

## 2. 创建任务模板（createTemplate）

- 接口：`POST /sales/task/template/createTemplate`
- 说明：创建 TEMPLATE 类型任务模板，落库 `task_template_definition`；`dataTemplateIds` 仅允许 1 个元素（`biz_template_config.id`）。

### 2.1 请求参数示例

```json
{
  "taskName": "门店陈列检查模板", 
  "//taskName": "任务名称（必填）",
  "taskTitle": "门店陈列检查", 
  "//taskTitle": "任务标题（可选；不传则默认等于 taskName）",
  "taskDescription": "用于门店陈列自检的常用模板", 
  "//taskDescription": "任务描述（必填）",
  "taskExecutionTypeName": "门店拜访", 
  "//taskExecutionTypeName": "执行类型名称（必填）",
  "taskExecutionType": "VISIT", 
  "//taskExecutionType": "执行类型编码（可选）",
  "status": 1,
  "//status": "必传：配置状态，1-启用，0-停用；不传时服务端默认按 1 处理",
  "templateType": "COMMON", 
  "//templateType": "模板类型（必填）：TEMPORARY=临时模板，COMMON=常用模板",
  "dataTemplateIds": [4], 
  "//dataTemplateIds": "数据模板 ID 列表（必填且仅允许 1 个，对应 biz_template_config.id）",
  "conditionIds": [1, 2], 
  "//conditionIds": "关联条件 ID 列表（可选）",
  "objectCode": "STORE", 
  "//objectCode": "对象编码（必填）",
  "objectName": "门店", 
  "//objectName": "对象名称（必填）",
  "systemIds": [1], 
  "//systemIds": "关联系统 ID 列表（必填）",
  "startTime": "2026-04-01 00:00:00", 
  "//startTime": "开始时间（可选，格式 yyyy-MM-dd HH:mm:ss）",
  "endTime": "2026-04-30 23:59:59", 
  "//endTime": "结束时间（可选，格式 yyyy-MM-dd HH:mm:ss）",
  "completionScript": "a > 1",
  "//completionScript": "可选：完成标准 Groovy 片段；非空时经 GroovyScriptSecurityUtils.validateGroovyExpression 安全校验（禁 import/class/循环等）",
  "completionTimeConfig": {
    "a": "每1",
    "b": "周",
    "c": "周一",
    "d": "18:00"
  },
  "//completionTimeConfig": "可选：完成周期时间配置，与 taskRule.completionTimeConfig 结构一致（a/b/c/d）；模板侧仅存储与回显，不做 cron 解析",
  "templateFieldIds": [
    {
      "id": 4, 
      "//id": "必填：biz_template_field_map.id",
      "remark": "备注", 
      "//remark": "可选：备注",
      "mappedCol": "shopCode2", 
      "//mappedCol": "须与该 id 在 biz_template_field_map 表中的 mapped_col 一致（null/空白与库中空值等价；非空则 trim 后比较）",
      "logicalName": "订单-网点编码", 
      "//logicalName": "可选：逻辑名称（前端展示/传递用）",
      "requiredField": false
      ,"//requiredField": "可选：是否必填字段（前端展示/传递用）",
      "fieldStandardCode": "visit_route_code",
      "//fieldStandardCode": "可选：字段标准编码（如 DWH 维度字典 code），写入 template_field_ids JSON",
      "fieldStandardName": "拜访路线编码",
      "//fieldStandardName": "可选：字段标准名称，写入 template_field_ids JSON",
      "groupCode": "field_group_11",
      "//groupCode": "可选：分组编码（与数据字典维度分组 groupCode 对齐），写入 template_field_ids JSON",
      "groupName": "销售拜访路线",
      "//groupName": "可选：分组名称（与数据字典维度分组 groupName 对齐），写入 template_field_ids JSON",
      "dataTypeDefinition": "STRING",
      "//dataTypeDefinition": "可选：数据类型定义（NUMBER/STRING/BOOLEAN/DATE，与 biz_template_field_map.data_type_definition 一致）；创建/更新时服务端在校验通过后以库为准写入 template_field_ids JSON，请求传入值会被覆盖"
    }
  ]
  ,"//templateFieldIds": "必填：字段映射数组，不能为空；每项 id 须为 dataTemplateIds[0] 对应 biz_template_config 下已绑定的 biz_template_field_map.id，且 mappedCol 与库表 mapped_col 一致；对象整体 JSON 落库 template_field_ids（含 fieldStandardCode/fieldStandardName/groupCode/groupName 等可选扩展字段，及服务端回填的 dataTypeDefinition）"
}
```

### 2.2 校验规则（回归）

- **templateType=COMMON / TEMPORARY**（与历史一致）：
  - **dataTemplateIds**：非空且仅 1 个元素（`biz_template_config.id`）；反查 **taskExecutionEventCode**。
  - **templateFieldIds**：非空；每项 **`id`** 须存在且未删除，**`template_id`** = **`dataTemplateIds[0]`**，**`mappedCol`** 与库一致。
- **templateType=TARGET**（目标模板）：
  - **dataTemplateIds**：须为空或不传；若传非空列表则业务错误「TARGET 类型模板不需填写 dataTemplateIds」。
  - **templateFieldIds**：非空；每项 **dataTypeDefinition 必填**，仅允许 **NUMBER / STRING / BOOLEAN / DATE**（忽略大小写，落库大写）；**id 可空**（无 id 时以请求 JSON 落库）；可选 **operatorCode**（如 `<=`）、**operatorName**（如「小于等于」）原样写入 JSON；若传 **id** 仅校验映射行存在且未删除，**不以库覆盖 dataTypeDefinition**；**不校验** `template_id` 绑定与 **mappedCol**。
  - **COMMON/TEMPORARY**：若误传 operatorCode/operatorName，服务端保存前会清空，不落库。
  - **taskExecutionEventCode**：落库取自请求 **taskExecutionType**（可空）。
- **templateFieldIds（COMMON/TEMPORARY 补充）**：已逻辑删除（`is_deleted=1`）则拒绝。
- **fieldStandardCode / fieldStandardName / groupCode / groupName**：可选；由调用方传入时原样写入 **`task_template_definition.template_field_ids`** 的 JSON 对象中，服务端不做与 `biz_template_field_map` 或数据字典的交叉校验。
- **dataTypeDefinition**：可选；**创建/更新**时服务端在 **`validateTemplateFieldRefsForBizTemplate`** 校验通过后，以 **`biz_template_field_map.data_type_definition`**（与 `BizTemplateFieldMapDTO` 一致）写回每条 ref 并落库 JSON，**请求传入值以库为准覆盖**。**详情**查询时在 **`fillTemplateFieldDetailList`** 后合并到 `templateFieldIds`（含历史纯数字 id 数组落库时，会按 id 顺序补全带 `mappedCol`、`dataTypeDefinition` 的对象列表至领域 DTO，便于与 `templateFieldDetailList` 对齐）。
- **mappedCol**：请求值与库表 **`mapped_col`** 须一致（null/空白按空串比较，非空则去首尾空格后比较）；不一致时返回业务错误并带出 fieldMapId 与请求/库中值。
- **completionScript**：可空；非空时调用 **`GroovyScriptSecurityUtils.validateGroovyExpression`**（关键字/高风险片段校验）；通过后落库 **`task_template_definition.completion_script`**。**createTemplate** 与 **updateTemplate** 均相同处理。
- **completionTimeConfig**：可空；结构与 **`taskRule.completionTimeConfig`** 一致（`a/b/c/d`），模板侧仅做原样存储到 **`task_template_definition.completion_time_config`** 并在 detail/findById 回显，不做 cron 解析或业务计算。

### 2.3 返回结果示例

```json
{
  "code": 0,
  "message": "success",
  "data": 123
}
```

说明：创建成功后，详情接口 `POST /sales/task/template/detail` 返回的 `templateFieldIds` 为对象数组结构（与表 `task_template_definition.template_field_ids` 存储一致），示例见 **2.3**：

```json
{
  "templateFieldIds": [
    {
      "id": 4,
      "//id": "biz_template_field_map.id",
      "remark": "备注",
      "//remark": "备注（可选）",
      "mappedCol": "shopCode2",
      "//mappedCol": "映射列（须与库表一致）",
      "logicalName": "订单-网点编码",
      "//logicalName": "逻辑名称（可选）",
      "requiredField": false
      ,"//requiredField": "是否必填（可选）",
      "fieldStandardCode": "visit_route_code",
      "//fieldStandardCode": "可选：字段标准编码",
      "fieldStandardName": "拜访路线编码",
      "//fieldStandardName": "可选：字段标准名称",
      "groupCode": "field_group_11",
      "//groupCode": "可选：分组编码",
      "groupName": "销售拜访路线",
      "//groupName": "可选：分组名称",
      "dataTypeDefinition": "STRING",
      "//dataTypeDefinition": "与库 biz_template_field_map.data_type_definition 一致；详情中由服务端合并回填"
    }
  ]
}
```

---

## 3. 更新任务模板（updateTemplate）

- 接口：`POST /sales/task/template/updateTemplate`
- 说明：全量更新已有 `task_template_definition` 行；**请求体与 createTemplate 相同字段**，并增加 **`id`**（主键）。校验规则与 **§2.2** 一致（含 `templateFieldIds` / `mappedCol`）。**`task_code` 不修改**（沿用库中原值）。

### 3.1 请求参数示例

```json
{
  "id": 123,
  "//id": "任务模板主键 task_template_definition.id（必填）",
  "taskName": "门店陈列检查模板",
  "//taskName": "任务名称（必填）",
  "taskTitle": "门店陈列检查",
  "//taskTitle": "任务标题（可选）",
  "taskDescription": "用于门店陈列自检的常用模板",
  "//taskDescription": "任务描述（必填）",
  "taskExecutionTypeName": "门店拜访",
  "//taskExecutionTypeName": "执行类型名称（必填）",
  "taskExecutionType": "VISIT",
  "//taskExecutionType": "执行类型编码（可选）",
  "status": 1,
  "//status": "配置状态，1-启用，0-停用；不传时服务端默认按 1 处理",
  "templateType": "COMMON",
  "//templateType": "模板类型（必填）：TEMPORARY / COMMON",
  "dataTemplateIds": [4],
  "//dataTemplateIds": "必填且仅 1 个元素，biz_template_config.id",
  "conditionIds": [1, 2],
  "//conditionIds": "关联条件 ID 列表（可选）",
  "objectCode": "STORE",
  "//objectCode": "对象编码（必填）",
  "objectName": "门店",
  "//objectName": "对象名称（必填）",
  "systemIds": [1],
  "//systemIds": "关联系统 ID 列表（必填）",
  "startTime": "2026-04-01 00:00:00",
  "//startTime": "开始时间（可选）",
  "endTime": "2026-04-30 23:59:59",
  "//endTime": "结束时间（可选）",
  "completionScript": "a > 1",
  "//completionScript": "可选：完成标准 Groovy；非空时 validateGroovyExpression 校验",
  "completionTimeConfig": {
    "a": "每1",
    "b": "周",
    "c": "周一",
    "d": "18:00"
  },
  "//completionTimeConfig": "可选：完成周期时间配置，结构与 taskRule.completionTimeConfig 一致，模板侧仅存储回显",
  "templateFieldIds": [
    {
      "id": 4,
      "//id": "biz_template_field_map.id",
      "mappedCol": "shopCode2",
      "//mappedCol": "须与库表 mapped_col 一致",
      "fieldStandardCode": "visit_route_code",
      "//fieldStandardCode": "可选：字段标准编码",
      "fieldStandardName": "拜访路线编码",
      "//fieldStandardName": "可选：字段标准名称",
      "groupCode": "field_group_11",
      "//groupCode": "可选：分组编码",
      "groupName": "销售拜访路线",
      "//groupName": "可选：分组名称",
      "dataTypeDefinition": "STRING",
      "//dataTypeDefinition": "可选：由服务端按 biz_template_field_map 合并，落库以校验后为准"
    }
  ]
}
```

### 3.2 返回结果示例

```json
{
  "code": 0,
  "message": "success",
  "data": null
}
```

### 3.3 回归

- **用例**：`id` 不存在、非 TEMPLATE 类型、已逻辑删除 → 业务错误。
- **用例**：`templateFieldIds` / `mappedCol` 等与 createTemplate 相同的不合法组合 → 与创建接口一致报错。
- **执行类型字段**：`task_execution_type` / `task_execution_type_name` 随本接口写入 **`task_template_definition`**（更新时对两列单独 `SET`，编码可为 NULL 时也会落库）。`taskExecutionType` 可为空；`taskExecutionTypeName` 必填。若你在页面上看的是「任务包子任务 `task_definition`」或「下发明细 `task_distribution_detail`」里的冗余执行类型，**改模板不会自动级联**，需改任务包/子任务或另行刷明细数据。

---

## 4. 任务模板详情（detail）

- 接口：`POST /sales/task/template/detail`
- 说明：响应 `data` 为 **`TaskTemplateUpdateRequestDTO`**，字段与 **`POST /sales/task/template/createTemplate`** 请求体一致，并多出 **`id`**（`task_template_definition.id`），可直接作为 **`updateTemplate`** 的入参基底。**不返回** `taskRuleList`、`conditionDetailList`、`dataTemplateDetailList` 等扩展明细（与 `createTemplate` 同构）。

### 4.1 请求参数示例

```json
{
  "id": 123
  ,"//id": "必填：任务模板主键 task_template_definition.id"
}
```

### 4.2 响应结构说明

- 外层：`code`、`message`、`data`。
- `data`：**`TaskTemplateUpdateRequestDTO`** = **`TaskTemplateCreateRequestDTO` 全部字段** + **`id`**。
- 字段含义与 **§2.1 创建任务模板** 请求示例一致；**`dataTemplateIds`** 对应库表 **`data_template_ids`**（`biz_template_config.id`）。
- **`packageSystemIds`**：详情当前固定为 **`null`**（创建入参可选字段，库表无单独持久化时可不传）。

### 4.3 响应结果示例（`data` 与 createTemplate 同构 + `id`）

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 123,
    "//id": "任务模板主键，与 §3 updateTemplate 一致",
    "taskName": "门店陈列检查模板",
    "//taskName": "任务名称",
    "taskTitle": "门店陈列检查",
    "//taskTitle": "任务标题",
    "taskDescription": "用于门店陈列自检的常用模板",
    "//taskDescription": "任务描述",
    "taskExecutionTypeName": "门店拜访",
    "//taskExecutionTypeName": "执行类型名称",
    "taskExecutionType": "VISIT",
    "//taskExecutionType": "执行类型编码",
    "status": 1,
    "//status": "配置状态 1-启用 0-停用",
    "templateType": "COMMON",
    "//templateType": "模板类型 TEMPORARY/COMMON",
    "dataTemplateIds": [4],
    "//dataTemplateIds": "数据模板 ID 列表（与 create 一致，通常 1 个）",
    "conditionIds": [1, 2],
    "//conditionIds": "关联条件 ID 列表",
    "objectCode": "STORE",
    "//objectCode": "对象编码",
    "objectName": "门店",
    "//objectName": "对象名称",
    "systemIds": [1],
    "//systemIds": "关联系统 ID 列表",
    "packageSystemIds": null,
    "//packageSystemIds": "可选；详情当前为 null",
    "startTime": "2026-04-01 00:00:00",
    "//startTime": "开始时间",
    "endTime": "2026-04-30 23:59:59",
    "//endTime": "结束时间",
    "completionScript": "a > 1",
    "//completionScript": "完成标准 Groovy 脚本",
    "completionTimeConfig": {
      "a": "每1",
      "b": "周",
      "c": "周一",
      "d": "18:00"
    },
    "//completionTimeConfig": "完成周期时间配置（与 taskRule.completionTimeConfig 同结构，模板侧仅存储回显）",
    "templateFieldIds": [
      {
        "id": 101,
        "//id": "biz_template_field_map.id",
        "remark": null,
        "//remark": "备注",
        "mappedCol": "shopCode2",
        "//mappedCol": "映射列",
        "logicalName": "订单-网点编码",
        "//logicalName": "逻辑名称",
        "requiredField": false
        ,"//requiredField": "是否必填",
        "fieldStandardCode": "visit_route_code",
        "//fieldStandardCode": "可选：字段标准编码",
        "fieldStandardName": "拜访路线编码",
        "//fieldStandardName": "可选：字段标准名称",
        "groupCode": "field_group_11",
        "//groupCode": "可选：分组编码",
        "groupName": "销售拜访路线",
        "//groupName": "可选：分组名称",
        "dataTypeDefinition": "STRING",
        "//dataTypeDefinition": "与 biz_template_field_map.data_type_definition 一致；详情由服务端合并"
      }
    ]
  }
}
```

### 4.4 回归校验点

- `id` 不存在或已逻辑删除：`data` 为 `null`。
- `id` 存在：`data` 中 **`dataTemplateIds` / `conditionIds` / `systemIds` / `templateFieldIds`** 与库表及 **§2.1** 语义一致；**无** `taskCode`、`taskRuleList` 等 create 未包含的字段。

---

## 5. 任务定义详情（detail，任务模板关联回显）

- 接口：`POST /sales/task/definition/detail`
- 说明：该路由位于 `TaskDefinitionController#detail`，用于查询统一任务定义详情；当记录为 `PACKAGE` 时，响应 `data` 为 `TaskDefinitionPackageUpdateRequestDTO`（与 `createPackage/updatePackage` 同构，便于回显编辑）；非 `PACKAGE` 时返回 `TaskDefinitionDTO`。

### 5.1 请求参数示例

```json
{
  "id": 123,
  "//id": "必填：任务定义主键（task_definition.id 或 task_template_definition.id 对应的定义链路）"
}
```

### 5.2 响应结果示例（PACKAGE）

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 123,
    "//id": "任务包主键（task_definition.id）",
    "taskName": "终端陈列任务包",
    "taskTitle": "终端陈列任务包",
    "taskDescription": "任务包说明",
    "objectCode": "STORE",
    "objectName": "门店",
    "distributionObjectGroupId": "crowd_001",
    "distributionObjectGroupName": "华南门店分群",
    "distributionTypeCode": "CRON",
    "distributionTypeName": "定时下发",
    "taskRule": {
      "conditionMode": "FACTOR",
      "completionType": "ACTION_BASED"
    },
    "tasks": [
      {
        "taskDefId": 456,
        "//taskDefId": "子 TASK 主键",
        "taskName": "终端陈列检查",
        "taskExecutionType": "VISIT",
        "taskExecutionTypeName": "门店拜访",
        "templateIds": [1001]
      }
    ]
  }
}
```

### 5.3 响应结果示例（非 PACKAGE）

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 456,
    "taskType": "TASK",
    "taskCode": "TASK_202604230001",
    "taskName": "终端陈列检查",
    "taskTitle": "终端陈列检查",
    "taskExecutionType": "VISIT",
    "taskExecutionTypeName": "门店拜访",
    "templateIds": [1001],
    "linkedTemplateDefinitionList": [
      {
        "id": 1001,
        "taskType": "TEMPLATE",
        "taskName": "门店陈列模板"
      }
    ]
  }
}
```

### 5.4 回归校验点

- `id` 为 `PACKAGE` 时：`data` 形态应为 `TaskDefinitionPackageUpdateRequestDTO`（含 `tasks[].taskDefId`、`taskRule`、下发扩展字段）。
- `id` 为 `TASK/ACTION` 时：`data` 形态应为 `TaskDefinitionDTO`，且模板关联通过 `linkedTemplateDefinitionList` 返回。
- `id` 不存在时：`data` 为 `null`（由现有服务实现决定），HTTP 返回结构仍为 `Response.success`。

