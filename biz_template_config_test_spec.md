# 业务模板配置测试说明（biz_template_config）

本文档描述与 `BizTemplateConfigController`、`BizTemplateConfigServiceImpl` 相关的接口测试要点；请求 JSON 中注释仅作说明，实际请求需为合法 JSON（去掉 `//` 行或改用文档字段表）。

---

## 1. 更新业务模板并批量 upsert fieldDetails

**接口：** `POST /sales/task/biz/template/config/update`

**说明：** `templateCode` 创建后不可改；示例中 `TPL_XXX` 须与库中该模板实际编码一致，或请求中省略 `templateCode` / 传 `null`。

**前置：** 库中已存在 `biz_template_config.id = 10001`，且存在属于该模板的字段映射 id `501`（可选，用于验证「保留并更新」）。

**期望：** HTTP 200，`code` 成功；主表字段按请求更新；`fieldDetails` 非 null 时：`501` 被更新；`id` 为 null 的项插入新行；原属 `10001` 但未出现在本请求 `fieldDetails` 中的其它映射**仍存在**（不被删除）；并满足 `mappedCol`（trim 后）不重复；**仅当 `isSearchPrimaryKey=true` 时**同一模板内 `objectCode`（trim 后）不可重复；`fieldDetails[].dataTypeDefinition` 非空时仅允许 **NUMBER、STRING、BOOLEAN、DATE**（忽略大小写），可传 `null` 或省略表示不限制该字段定义。

**请求示例：**

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

**字段含义（节选）：**

| 字段 | 含义 |
|------|------|
| `id` | 业务模板主键，必填 |
| `fieldDetails` | 非 null 时逐项 upsert；`id` 为 null 表示新增映射 |
| `fieldDetails[].id` | 有则按 id 更新且须属于当前模板；无则 insert |
| `fieldDetails[].templateId` | 可与模板 id 不一致，服务端强制为当前模板 id |
| `fieldDetails[].dataTypeDefinition` | 可空；非空时须为 NUMBER / STRING / BOOLEAN / DATE（忽略大小写） |

---

## 2. 更新业务模板且不同步 fieldDetails（回归）

**接口：** `POST /sales/task/biz/template/config/update`

**请求示例：** `fieldDetails` 为 `null` 或从 JSON 中省略。

**期望：** 仅主表变更；`biz_template_field_map` 行数与内容不变。

---

## 3. 回归：`fieldDetails` 传空数组不删除已有映射

**接口：** `POST /sales/task/biz/template/config/update`

**请求示例：** 与 **§2** 相同主表字段，且 `"fieldDetails": []`。

**期望：** HTTP 200；`biz_template_field_map` 中该模板下已有行**数量与内容不变**（空数组表示「无 upsert 项」，非清空）。若需删除单条映射，请调用字段映射删除接口。

---

## 4. 负例：fieldDetails 中 id 重复

**期望：** `BizException`，文案包含 `fieldDetails 中存在重复的 id`。

---

## 5. 负例：fieldDetails 引用其它模板的映射 id

**期望：** `BizException`，文案包含 `字段映射不属于当前模板`。

---

## 6. 负例：更新时修改 templateCode

**接口：** `POST /sales/task/biz/template/config/update`

**请求：** 与库中 `id=10001` 的 `template_code` 不同的非空 `templateCode`（例如库为 `TPL_ABC`，请求传 `TPL_OTHER`）。

**期望：** `BizException`，文案为 `模板编码创建后不可修改`；库中 `template_code` 不变。

---

## 7. 负例：fieldDetails 中 mappedCol 重复

**接口：** `POST /sales/task/biz/template/config/update`

**请求：** `fieldDetails` 中两条（或以上）记录的 `mappedCol` 去除首尾空格后相同（例如 `orderId` 与 ` orderId `）。

**期望：** `BizException`，文案包含 `fieldDetails 中 mappedCol 重复`。

---

## 8. 负例：fieldDetails 中 isSearchPrimaryKey=true 时 objectCode 重复

**接口：** `POST /sales/task/biz/template/config/update`

**请求：** `fieldDetails` 中存在**两条及以上**记录均为 `isSearchPrimaryKey=true`，且 `objectCode`（trim 后）相同。

**期望：** `BizException`，文案包含 `fieldDetails 中 isSearchPrimaryKey=true 时 objectCode 重复`。

---

## 9. 正例：多条相同 objectCode 且均为 isSearchPrimaryKey=false

**接口：** `POST /sales/task/biz/template/config/update` 或 `create`

**请求：** `fieldDetails` 中多条 `objectCode` 相同且 `isSearchPrimaryKey=false`（或未传视为 false）。

**期望：** 校验通过（不因 objectCode 重复报错）。

---

## 10. 负例：fieldDetails 中 dataTypeDefinition 非法

**接口：** `POST /sales/task/biz/template/config/update` 或 `create`

**请求：** `fieldDetails` 中某条 `dataTypeDefinition` 为非空且不为 NUMBER、STRING、BOOLEAN、DATE 之一（如 `TEXT`、`INTEGER`）。

**期望：** `BizException`，文案包含 `fieldDetails 中 dataTypeDefinition 仅允许 NUMBER、STRING、BOOLEAN、DATE`。

---

## 11. 按模板 ID 从示例 JSON 提取字段映射

**接口（二选一，语义与入参 JSON 一致）：**

- **历史路径（名称不变）：** `POST /sales/task/biz/template/field/testJsonFieldMapperByTemplateId`，请求体类型 **`JsonFieldMapperByTemplateIdRequest`**
- **推荐前端路径：** `POST /sales/task/biz/template/field/extractMappedFieldsByTemplateId`，请求体类型 **`ExtractMappedFieldsByTemplateIdRequest`**

二者 Body 均为 `{"templateId": <biz_template_config.id>}`。

**说明：** 与 **`/extractMappedFields`** / **`/testJsonFieldMapper`** 同源映射引擎；映射源固定为 **`biz_template_config.groovy_execute_param_sample_json`**（须可解析为 JSON）；字段映射取 **`biz_template_field_map.template_id = templateId`** 的全量行，按 **`sort_order` 升序** 组装映射定义（不依赖 id 批量查询顺序）。

**前置：** 存在 `biz_template_config.id = templateId`；该行 **`groovy_execute_param_sample_json`** 非空且为合法 JSON；至少一条 **`biz_template_field_map`** 已绑定同一 `template_id`。

**期望：** HTTP 200，`data` 为 **`List<IndexAggregatedMappedFieldRow>`**（`JsonFieldMapperUtils`）：按非 null 的 `index` 升序各行，每行 `index` + `mappedFields`；**原 `index=null` 的公共字段不单独成行**，而是**复制到每一行**的 `mappedFields` 前部，其后为该下标专有字段。若结果**仅有**公共字段（无数组展开），则仅一行且 `index` 为 null。元素字段仍含 `mappedCol`、`mappedColVal`、`logicalName`、`dataType`、`dataTypeDefinition` 等。

**负例：** `templateId` 为空；模板不存在；示例 JSON 为空或解析失败；该模板下无字段映射 —— 均 `BizException`，文案分别含 `templateId 不能为空`、`biz_template_config 不存在`、`groovy_execute_param_sample_json 为空/解析失败`、`该模板下无字段映射`。

**请求示例（合法 JSON 需去掉注释行）：**

```json
{
  "//templateId": "业务模板主键，等于 biz_template_config.id，且与 biz_template_field_map.template_id 一致；服务端据此查模板示例 JSON 与本模板下全部字段映射",
  "templateId": 10001
}
```

---

## 12. 按自定义 JSON + 字段映射 id 列表提取

**接口（二选一，语义与入参 JSON 一致）：**

- **历史路径：** `POST /sales/task/biz/template/field/testJsonFieldMapper`，请求体 **`JsonFieldMapperTestRequest`**
- **推荐前端路径：** `POST /sales/task/biz/template/field/extractMappedFields`，请求体 **`ExtractMappedFieldsRequest`**

二者 Body 均为 `jsonSource` + `ids`（`biz_template_field_map.id` 列表）。

**期望：** HTTP 200，`data` 为 **`List<IndexAggregatedMappedFieldRow>`**（按 `index` 聚合，结构同 §11）。

---

## 13. DELAY：`datasourceId` 须为 DynamicHttpEndpoint；`fieldDetails` 可为空数组

**接口：** `POST /sales/task/biz/template/config/create` 或 `update`

**规则：**

- **`syncStrategy=DELAY`**（忽略大小写）时：**`datasourceId` 必填**，且须为库表 **`dynamic_http_endpoint.id`**（存在主键行）；不存在则 `BizException`，文案含 **`datasourceId 须为已存在的 DynamicHttpEndpoint.id`** 或 **`datasourceId 不能为空`**。
- **`update`**：若请求体未传 `syncStrategy` 或 `datasourceId`，则与库中已有行**合并**后再判断是否为 DELAY 及 datasource 是否满足（与 `BizTemplateConfigServiceImpl` 一致）。
- **`fieldDetails: []`**（空数组）：**允许**；不产生任何字段映射 upsert（与 **`fieldDetails` 为 null** 跳过同步不同）。

**负例：** `syncStrategy=DELAY` 且 `datasourceId` 为不存在的 id、或 `datasourceId` 为空（且库中合并后仍为空）。
