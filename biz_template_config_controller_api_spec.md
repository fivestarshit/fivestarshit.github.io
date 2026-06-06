# 业务模板配置接口说明（BizTemplateConfigController）

本文档与源码 `BizTemplateConfigController` 一致：**基础路径** `POST /sales/task/biz/template/config`，请求体均为 **JSON**（`Content-Type: application/json`）。

外层包装为 `com.yq.tools.base.Response`，业务数据在 **`data`** 中。成功时常见形态如下（`code` / `message` 以实际依赖为准）：

```json
{
  "code": 0,
  "message": "success",
  "data": null
}
```

---

## 一、公共数据结构（JSON 字段说明）

### 1.1 分页结果 `PageResult<T>`

当接口返回分页列表时，`data` 为该结构：

```json
{
  "records": [],
  "total": 7884,
  "page": 1,
  "pageSize": 20,
  "totalPage": 395
}
```

| JSON 字段 | 类型 | 说明 |
|-----------|------|------|
| `records` | 数组 | 当前页数据 |
| `total` | 数值 | 总条数 |
| `page` | 数值 | 当前页码 |
| `pageSize` | 数值 | 每页条数 |
| `totalPage` | 数值 | 总页数 |

### 1.2 业务模板 `BizTemplateConfigDTO`

用于 **create / update 请求体**，以及 **detail、list 的 records 单项**。  
**注意**：**分页 `/list`** 的每条记录 **不含** `fieldDetails`（为 `null` 或未设置）。**详情 `/detail`** 由服务端填充 `fieldDetails`。  
**create / update**：请求体中 **`fieldDetails` 为 `null` 或未传**时，**不**改动已有字段映射；**传入非 `null` 的数组**时，对数组内每一项按 **`BizTemplateFieldMapService#upsertMapsForTemplate`** 处理（见 2.1 / 2.2）：**有 `id`** 则校验归属当前模板后**按 id 更新**；**无 `id`** 则**新增**；**不会**删除请求中未出现的已有映射；**空数组 `[]`** 不产生任何字段映射变更。单项结构见 1.3；`templateId` 可与模板主键不一致，服务端会**强制覆盖**为当前模板 id。  
此外，create/update 在 upsert 前会对「最终生效字段集」执行校验：`mappedCol`（trim 后）不可重复；**仅当 `isSearchPrimaryKey=true` 时**，`objectCode`（trim 后）在同一模板内不可重复（为 `false` 时不做 objectCode 唯一校验）。需删除映射请走字段映射 **`delete`** 等接口。

| JSON 字段 | 类型 | 说明 |
|-----------|------|------|
| `id` | 数值 | 主键；**update 必填** |
| `templateCode` | 字符串 | 模板编码；**create 时**服务端会执行 `CodeGenerateUtils.generateCode("TPL_")` **覆盖**入参，客户端传入无效；**update 时不可修改**（与库中不一致则拒绝，一致或未传/空则仍以库中值落库） |
| `templateName` | 字符串 | 模板名称 |
| `iconUrl` | 字符串 | 图标 URL，可空 |
| `description` | 字符串 | 描述，可空 |
| `datasourceId` | 数值 | **`syncStrategy=DELAY` 时须为已存在的 `dynamic_http_endpoint.id`**（服务端强校验）；其它策略下历史语义可能为数据源连接 id |
| `dataSource` | 字符串 | 数据来源说明（展示用，对应表 `biz_template_config.data_source`），可空 |
| `physicalTable` | 字符串 | 物理表名或 Mongo 集合名 |
| `databaseName` | 字符串 | 库名/模式名，可空 |
| `taskExecutionEventCode` | 字符串 | 执行类型监听的事件编码，可空 |
| `groovyExecuteParamSampleJson` | 字符串 | Groovy 执行参数示例 JSON 字符串，可空 |
| `dynamicHttpGroupId` | 数值 | `dynamic_http_endpoint_group.id`，可空；**服务端 create/update 不再校验**该 id 是否存在（字段仅落库，后续链路可不使用） |
| `syncStrategy` | 字符串 | 同步策略，如 `REAL_TIME`、`DELAY` |
| `sampleLimit` | 数值 | 预览限制条数，可空 |
| `version` | 数值 | 版本号；create 时若空则服务端默认 `1` |
| `isActive` | 布尔 | 是否生效；create 时若空则默认 `true` |
| `isDeleted` | 数值 | 逻辑删除 0/1；create 时若空则默认 `0` |
| `createdBy` | 字符串 | 创建人 |
| `updatedBy` | 字符串 | 最后修改人 |
| `fieldDetails` | 数组 | 字段映射列表，见 1.3；**list 不返回**；**detail 返回**；**create/update 可选**，规则见上文 |

### 1.3 字段映射 `BizTemplateFieldMapDTO`（`fieldDetails` 元素）

| JSON 字段 | 类型 | 说明 |
|-----------|------|------|
| `id` | 数值 | 主键；经模板 create/update 的 `fieldDetails` 提交时：**有 id → 更新**，**无 id → 新增** |
| `templateId` | 数值 | 关联 `biz_template_config.id` |
| `templateTaskId` | 数值 | 模板任务 ID，可空 |
| `objectCode` | 字符串 | 对象类型编码 |
| `dataSource` | 字符串 | 字段级数据来源说明（展示用） |
| `physicalCol` | 字符串 | 物理字段名 |
| `mappedCol` | 字符串 | 映射业务字段名 |
| `mappedColVal` | 字符串 | 映射值（运行期场景），可空 |
| `logicalName` | 字符串 | 展示名 |
| `dataType` | 字符串 | 逻辑数据类型（映射提取） |
| `dataTypeDefinition` | 字符串 | 业务属性类型定义，可空；**非空时仅允许** `NUMBER`、`STRING`、`BOOLEAN`、`DATE`（忽略大小写） |
| `length` | 数值 | 长度，可空 |
| `precision` | 数值 | 精度，可空 |
| `isCalculable` | 布尔 | 是否可计算 |
| `isSearchable` | 布尔 | 是否可搜索 |
| `isSearchPrimaryKey` | 布尔 | 是否搜索主键 |
| `isVisible` | 布尔 | 是否可见 |
| `sortOrder` | 数值 | 排序 |
| `defaultValue` | 字符串 | 默认值，可空 |
| `enumValues` | 字符串 | 枚举 JSON 字符串，可空 |
| `isSensitive` | 布尔 | 是否敏感 |
| `maskRule` | 字符串 | 脱敏规则 |
| `extractRule` | 字符串 | JSON/数组提取规则，可空 |
| `remark` | 字符串 | 备注，可空 |
| `isDeleted` | 数值 | 是否删除 |
| `createdBy` | 字符串 | 创建人 |
| `updatedBy` | 字符串 | 最后修改人 |

### 1.4 通用 ID 请求 `IdRequest`

```json
{
  "id": 1
}
```

| JSON 字段 | 类型 | 说明 |
|-----------|------|------|
| `id` | 数值 | 业务主键 |

---

## 二、接口明细

### 2.1 新增业务模板

| 项目 | 内容 |
|------|------|
| **路径** | `POST /sales/task/biz/template/config/create` |
| **请求体** | `BizTemplateConfigDTO` |
| **成功 `data`** | 新建记录主键 `Long` |

**请求示例（字段旁注释为含义说明，非合法 JSON 需复制时去掉 `//` 行）：**

```json
{
  "id": null,
  "templateCode": "可忽略", // create 时由服务端生成 TPL_ 前缀编码并覆盖
  "templateName": "订单同步模板",
  "iconUrl": "https://example.com/icon.png",
  "description": "描述",
  "datasourceId": 100,
  "dataSource": "数仓订单库", // 可空：模板级数据来源展示文案
  "physicalTable": "t_order",
  "databaseName": "sales_db",
  "taskExecutionEventCode": "ORDER_SYNC",
  "groovyExecuteParamSampleJson": "{\"k\":1}",
  "dynamicHttpGroupId": null,
  "syncStrategy": "REAL_TIME",
  "sampleLimit": 100,
  "version": null,
  "isActive": null,
  "isDeleted": null,
  "createdBy": null,
  "updatedBy": null,
  "fieldDetails": null
}
```

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": 10001
}
```

**`fieldDetails` 同步（可选）：** 与 **2.2** 相同语义——仅当请求 JSON 中 **`fieldDetails` 为非 null 数组** 时，在插入主表后对**新建模板 id** 执行 **upsert**（有 id 更新、无 id 新增，不删未列出项）；`null` 表示不同步。

**失败场景（`BizException`，外层为非成功响应）：** `syncStrategy=DELAY` 且 **`datasourceId` 为空或不是已存在的 `dynamic_http_endpoint.id`**；生成编码冲突（极少）；`fieldDetails` 内 **id 重复**、引用 **不存在或不属于本模板** 的映射 id；`mappedCol` 重复；多条 **`isSearchPrimaryKey=true`** 且 **`objectCode`（trim）相同**；`fieldDetails` 某项 **`dataTypeDefinition` 非空且不为** `NUMBER` / `STRING` / `BOOLEAN` / `DATE`（忽略大小写）。

**`syncStrategy=DELAY` 与 `fieldDetails`：** 允许传 **`fieldDetails: []`**（空数组），表示本请求不通过 upsert 新增或更新任何字段映射；与 **`fieldDetails` 为 `null`/不传**（跳过字段映射同步）语义不同。

---

### 2.2 更新业务模板

| 项目 | 内容 |
|------|------|
| **路径** | `POST /sales/task/biz/template/config/update` |
| **请求体** | `BizTemplateConfigDTO`（主表字段 + 可选 `fieldDetails`） |
| **成功 `data`** | 多为 `null`（`Response.success()`，无业务体） |
| **说明** | 先 `updateById` 更新主表 `biz_template_config`；若 **`fieldDetails` 非 null**，再对该模板 id 调用 **`upsertMapsForTemplate`**（与 **1.2** 一致：有 id 更新、无 id 新增，不删未列出映射）。`fieldDetails` 为 `null` 或未传时**不**改字段映射。主表字段：请求 JSON **未出现或为 null 的标量**反序列化后多为 `null`，**可能把库中对应列更新为 NULL**，调用方宜**传全量主表字段**或明确可空策略。主表与字段映射在同一事务中提交。 |

#### 2.2.1 请求体字段明细（`BizTemplateConfigDTO`）

| JSON 字段 | 类型 | 更新说明 |
|-----------|------|----------|
| `id` | 数值 | **必填**；`null` 时抛 `BizException`「模板ID不能为空」 |
| `templateCode` | 字符串 | **创建后不可改**：若传非空且 trim 后与库中该模板编码**不一致**，抛「模板编码创建后不可修改」；未传、空或与库中一致时，更新语句中**始终使用库中原有编码** |
| `templateName` | 字符串 | 模板名称 |
| `iconUrl` | 字符串 | 图标 URL |
| `description` | 字符串 | 描述 |
| `datasourceId` | 数值 | **`syncStrategy=DELAY` 时须为已存在的 `dynamic_http_endpoint.id`**；其它策略见 **1.2** |
| `dataSource` | 字符串 | 数据来源展示文案（`biz_template_config.data_source`） |
| `physicalTable` | 字符串 | 物理表名或 Mongo 集合名 |
| `databaseName` | 字符串 | 库名/模式名 |
| `taskExecutionEventCode` | 字符串 | 执行类型监听的事件编码 |
| `groovyExecuteParamSampleJson` | 字符串 | Groovy 示例 JSON 字符串 |
| `dynamicHttpGroupId` | 数值 | `dynamic_http_endpoint_group.id`，可空；**服务端不再校验**存在性，按请求体原样落库 |
| `syncStrategy` | 字符串 | 如 `REAL_TIME`、`DELAY`。**`DELAY`**：**`datasourceId` 非空且为 `dynamic_http_endpoint.id`**（`create`/`update` 均按生效策略校验，`update` 可与库中已有值合并判断）。`fieldDetails` 可为空数组 `[]` |
| `sampleLimit` | 数值 | 预览条数 |
| `version` | 数值 | 版本号 |
| `isActive` | 布尔 | 是否生效 |
| `isDeleted` | 数值 | 逻辑删除 0/1 |
| `createdBy` | 字符串 | 创建人 |
| `updatedBy` | 字符串 | 最后修改人 |
| `fieldDetails` | 数组 | 见 **1.2**：`null`/不传则不同步；非 null 则逐项 upsert（空数组无操作）；并校验 `mappedCol` 唯一；**仅 `isSearchPrimaryKey=true` 时**校验 `objectCode`（trim）不重复；**`dataTypeDefinition` 非空时**须为 NUMBER/STRING/BOOLEAN/DATE；元素见 **1.3** |

#### 2.2.2 请求示例（仅主表；不同步字段映射时 `fieldDetails` 传 `null` 或省略）

```json
{
  "id": 10001,
  "templateCode": "TPL_XXX",
  "templateName": "订单同步模板-改",
  "iconUrl": null,
  "description": "更新描述",
  "datasourceId": 100,
  "dataSource": "数仓订单库-主从",
  "physicalTable": "t_order",
  "databaseName": "sales_db",
  "taskExecutionEventCode": "ORDER_SYNC",
  "groovyExecuteParamSampleJson": "{}",
  "dynamicHttpGroupId": 200,
  "syncStrategy": "DELAY",
  "sampleLimit": 50,
  "version": 2,
  "isActive": true,
  "isDeleted": 0,
  "createdBy": null,
  "updatedBy": "admin",
  "fieldDetails": null
}
```

#### 2.2.3 请求示例（含 `fieldDetails` 批量新增/更新）

以下表示：对 id `501` 的映射做**更新**；对 `id` 为 `null` 的项执行**新增**；模板下其它已有映射行**不受影响**（不会因未出现在本数组中被删除）。

```json
{
  "id": 10001,
  "templateCode": "TPL_XXX",
  "templateName": "订单同步模板-改",
  "iconUrl": null,
  "description": "更新描述",
  "datasourceId": 100,
  "dataSource": "数仓订单库-主从",
  "physicalTable": "t_order",
  "databaseName": "sales_db",
  "taskExecutionEventCode": "ORDER_SYNC",
  "groovyExecuteParamSampleJson": "{}",
  "dynamicHttpGroupId": 200,
  "syncStrategy": "DELAY",
  "sampleLimit": 50,
  "version": 2,
  "isActive": true,
  "isDeleted": 0,
  "createdBy": null,
  "updatedBy": "admin",
  "fieldDetails": [
    {
      "id": 501,
      "templateId": 10001,
      "templateTaskId": null,
      "objectCode": "STORE",
      "dataSource": "主库",
      "physicalCol": "order_id",
      "mappedCol": "orderId",
      "mappedColVal": null,
      "logicalName": "订单ID",
      "dataType": "BIGINT",
      "dataTypeDefinition": null,
      "length": 20,
      "precision": null,
      "isCalculable": false,
      "isSearchable": true,
      "isSearchPrimaryKey": true,
      "isVisible": true,
      "sortOrder": 1,
      "defaultValue": null,
      "enumValues": null,
      "isSensitive": false,
      "maskRule": "NONE",
      "extractRule": null,
      "remark": null,
      "isDeleted": 0,
      "createdBy": null,
      "updatedBy": "admin"
    },
    {
      "id": null,
      "templateId": null,
      "templateTaskId": null,
      "objectCode": "STORE",
      "dataSource": "主库",
      "physicalCol": "store_name",
      "mappedCol": "storeName",
      "mappedColVal": null,
      "logicalName": "门店名称",
      "dataType": "VARCHAR",
      "dataTypeDefinition": null,
      "length": 128,
      "precision": null,
      "isCalculable": false,
      "isSearchable": true,
      "isSearchPrimaryKey": false,
      "isVisible": true,
      "sortOrder": 2,
      "defaultValue": null,
      "enumValues": null,
      "isSensitive": false,
      "maskRule": "NONE",
      "extractRule": null,
      "remark": null,
      "isDeleted": 0,
      "createdBy": null,
      "updatedBy": "admin"
    }
  ]
}
```

#### 2.2.4 响应示例

**成功（HTTP 200，`code` 以网关为准）：**

```json
{
  "code": 0,
  "message": "success",
  "data": null
}
```

**失败（业务异常示例，`data` 多为 null 或网关约定结构）：**

| 场景 | 典型提示（`BizException` message） |
|------|-----------------------------------|
| `id` 为空 | `模板ID不能为空` |
| `id` 对应记录不存在 | `模板不存在` |
| `templateCode` 与库中不一致 | `模板编码创建后不可修改` |
| `syncStrategy=DELAY` 且 `datasourceId` 无效 | `datasourceId 不能为空` / `datasourceId 须为已存在的 DynamicHttpEndpoint.id` |
| `fieldDetails` 中同一 `id` 出现多次 | `fieldDetails 中存在重复的 id` |
| `fieldDetails` 中 `id` 在库中不存在 | `字段映射不存在，id=…` |
| `fieldDetails` 中 `id` 归属其它模板 | `字段映射不属于当前模板，id=…` |
| `fieldDetails` 中 `mappedCol`（trim 后）重复 | `fieldDetails 中 mappedCol 重复: xxx` |
| `fieldDetails` 中多条 `isSearchPrimaryKey=true` 且 `objectCode` 相同 | `fieldDetails 中 isSearchPrimaryKey=true 时 objectCode 重复: xxx` |
| `fieldDetails` 中 `dataTypeDefinition` 非空且非法 | `fieldDetails 中 dataTypeDefinition 仅允许 NUMBER、STRING、BOOLEAN、DATE，当前值: …` |

更新成功后如需核对字段映射，可再调 **`POST /sales/task/biz/template/config/detail`**（`IdRequest`）拉取含 `fieldDetails` 的完整 DTO。

---

### 2.3 删除业务模板

| 项目 | 内容 |
|------|------|
| **路径** | `POST /sales/task/biz/template/config/delete` |
| **请求体** | `IdRequest` |
| **说明** | `id` 为 `null` 时服务层不执行删除、不抛错 |

**请求示例：**

```json
{
  "id": 10001
}
```

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": null
}
```

---

### 2.4 查询业务模板详情

| 项目 | 内容 |
|------|------|
| **路径** | `POST /sales/task/biz/template/config/detail` |
| **请求体** | `IdRequest` |
| **成功 `data`** | `BizTemplateConfigDTO`，含 **`fieldDetails`**（列表，无映射时为空数组） |
| **说明** | `id` 为空或记录不存在时，`data` 可能为 **`null`** |

**请求示例：**

```json
{
  "id": 10001
}
```

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 10001,
    "templateCode": "TPL_ABC123",
    "templateName": "订单同步模板",
    "iconUrl": null,
    "description": "描述",
    "datasourceId": 100,
    "dataSource": "数仓订单库",
    "physicalTable": "t_order",
    "databaseName": "sales_db",
    "taskExecutionEventCode": "ORDER_SYNC",
    "groovyExecuteParamSampleJson": "{}",
    "dynamicHttpGroupId": null,
    "syncStrategy": "REAL_TIME",
    "sampleLimit": 100,
    "version": 1,
    "isActive": true,
    "isDeleted": 0,
    "createdBy": "system",
    "updatedBy": "admin",
    "fieldDetails": [
      {
        "id": 1,
        "templateId": 10001,
        "templateTaskId": null,
        "objectCode": "STORE",
        "dataSource": "主库字段",
        "physicalCol": "order_id",
        "mappedCol": "orderId",
        "mappedColVal": null,
        "logicalName": "订单ID",
        "dataType": "BIGINT",
        "dataTypeDefinition": null,
        "length": 20,
        "precision": null,
        "isCalculable": false,
        "isSearchable": true,
        "isSearchPrimaryKey": true,
        "isVisible": true,
        "sortOrder": 1,
        "defaultValue": null,
        "enumValues": null,
        "isSensitive": false,
        "maskRule": "NONE",
        "extractRule": null,
        "remark": null,
        "isDeleted": 0,
        "createdBy": null,
        "updatedBy": null
      }
    ]
  }
}
```

---

### 2.5 分页查询业务模板列表

| 项目 | 内容 |
|------|------|
| **路径** | `POST /sales/task/biz/template/config/list` |
| **请求体** | `BizTemplateConfigPageRequest`（继承分页：`page`、`pageSize`；**`syncStrategy` 必填** `@NotBlank`） |
| **成功 `data`** | `PageResult<BizTemplateConfigDTO>`，`records` **无** `fieldDetails` |

**请求示例：**

```json
{
  "page": 1,
  "pageSize": 20,
  "syncStrategy": "REAL_TIME",
  "templateCode": "TPL",
  "templateName": "订单",
  "physicalTable": "order",
  "objectCode": "STORE"
}
```

| JSON 字段 | 类型 | 说明 |
|-----------|------|------|
| `page` | 数值 | 当前页，默认 1 |
| `pageSize` | 数值 | 每页条数，默认 20 |
| `syncStrategy` | 字符串 | **必填**，与库 `sync_strategy` 精确匹配（trim 后） |
| `templateCode` | 字符串 | 可选，模板编码模糊 |
| `templateName` | 字符串 | 可选，模板名称模糊 |
| `physicalTable` | 字符串 | 可选，物理表名模糊 |
| `objectCode` | 字符串 | 可选；仅返回在 `biz_template_field_map` 中存在该 `object_code` 且已绑定 `template_id` 的模板；无匹配则空分页 |

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "records": [
      {
        "id": 10001,
        "templateCode": "TPL_ABC123",
        "templateName": "订单同步模板",
        "iconUrl": null,
        "description": "描述",
        "datasourceId": 100,
        "dataSource": "数仓订单库",
        "physicalTable": "t_order",
        "databaseName": "sales_db",
        "taskExecutionEventCode": "ORDER_SYNC",
        "groovyExecuteParamSampleJson": "{}",
        "dynamicHttpGroupId": null,
        "syncStrategy": "REAL_TIME",
        "sampleLimit": 100,
        "version": 1,
        "isActive": true,
        "isDeleted": 0,
        "createdBy": "system",
        "updatedBy": "admin",
        "fieldDetails": null
      }
    ],
    "total": 1,
    "page": 1,
    "pageSize": 20,
    "totalPage": 1
  }
}
```

---

### 2.6 按模板查询映射后的表数据

| 项目 | 内容 |
|------|------|
| **路径** | `POST /sales/task/biz/template/config/data/query` |
| **请求体** | `QueryMappedDataRequest` |
| **成功 `data`** | `PageResult<Map<String, Object>>`：每行 JSON 的 **key** 优先 `mappedCol`，否则 `logicalName`，再否则 `physicalCol` |

**请求示例：**

```json
{
  "templateId": 10001,
  "page": 1,
  "pageSize": 20
}
```

| JSON 字段 | 类型 | 说明 |
|-----------|------|------|
| `templateId` | 数值 | **必填**；为 null 时返回空分页 |
| `page` | 数值 | 当前页，默认 1 |
| `pageSize` | 数值 | 每页条数，默认 20（内部 `getPageSizeValue`） |

**响应示例：**

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "records": [
      {
        "orderId": 9001,
        "storeName": "测试门店"
      }
    ],
    "total": 7884,
    "page": 1,
    "pageSize": 20,
    "totalPage": 395
  }
}
```

**行为摘要：** 模板不存在、未生效、未配表名、无可见字段映射、数据源不可用等情况下，可能返回 **`records` 为空、`total` 为 0** 的分页（仍可能 HTTP 200 + 业务 `code` 成功）；MySQL 等与 MongoDB 分支由数据源类型决定。

---

## 三、路由与 Swagger 对照

| 路径 | 说明 |
|------|------|
| `/sales/task/biz/template/config/create` | 新增业务模板 |
| `/sales/task/biz/template/config/update` | 更新业务模板 |
| `/sales/task/biz/template/config/delete` | 删除业务模板 |
| `/sales/task/biz/template/config/detail` | 查询详情（含 `fieldDetails`） |
| `/sales/task/biz/template/config/list` | 分页列表（`syncStrategy` 必填） |
| `/sales/task/biz/template/config/data/query` | 按模板查映射表数据 |

文档与 `BizTemplateConfigController` 当前代码同步维护。
