# 数据分群接口测试用例

## 1. 分页查询分群

- 接口：`GET /dwh/data-labeling/data/crowd/page`
- 调用方式：Feign（`DataCrowdFeignService`）
- 说明：按 `objectCode`、`keyword` 查询分群分页数据。

### 1.1 请求参数示例（Query）

```json
{
  "objectCode": "sales_channel",
  "//objectCode": "分群编码参数（可选）",
  "keyword": "测试",
  "//keyword": "搜索关键字参数（可选）"
}
```

---

## 2. 查询分群最新数据

- 接口：`GET /dwh/data-labeling/data/crowd/data/latest`
- 调用方式：Feign（`DataCrowdFeignService`）
- 说明：按分群 `code` 查询该分群最新对象值列表。

### 2.1 请求参数示例（Query）

```json
{
  "code": "wkiralaw",
  "//code": "分群编码（必填）"
}
```

---

## 3. 业务路由（本服务 API）

- 路由前缀：`/sales/task/data-crowd`
- 说明：由控制器调用 `DataCrowdService`，再转发外部数据分群 Feign 接口。

### 3.1 分页查询分群

- 接口：`POST /sales/task/data-crowd/page`

请求示例：

```json
{
  "objectCode": "sales_channel",
  "//objectCode": "分群对象编码（可选）",
  "keyword": "测试",
  "//keyword": "搜索关键字（可选）"
}
```

### 3.2 查询分群最新数据

- 接口：`POST /sales/task/data-crowd/latest`

请求示例：

```json
{
  "code": "wkiralaw",
  "//code": "分群编码（必填）"
}
```

返回示例（仅透出外部接口的 `data` 节点）：

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "total": 3,
    "list": [
      "YQWD03233175"
    ]
  }
}
```

### 3.3 数据字典：维度分组列表

- 接口：`POST /sales/task/data-dictionary/dimension/list`

#### 3.3.1 响应结构示例（`data` 为分组数组；与网关 `data` 同构）

`data` 中每个元素为**维度分组**；`filedStandardDataList` 为远端 JSON 字段名（拼写为 `filed`）；标准字段项中布尔「是否可空」在 JSON 里为 **`isNull`**（与网关一致）。

```json
{
  "code": 0,
  "message": "success",
  "data": [
    {
      "id": 26,
      "//id": "分组主键",
      "groupName": "一物一码",
      "//groupName": "分组展示名",
      "groupCode": "field_group_26",
      "//groupCode": "分组编码",
      "parentCode": null,
      "//parentCode": "父分组编码",
      "path": null,
      "//path": "层级路径",
      "sort": 1,
      "//sort": "排序号",
      "filedStandardDataList": [
        {
          "id": 202,
          "//id": "标准字段主键",
          "creatorId": 1021775,
          "creatorName": "李鹏",
          "updaterId": 1021775,
          "updaterName": "李鹏",
          "isDeleted": 0,
          "createTime": "2026-01-26T16:03:56",
          "updateTime": "2026-01-26T16:20:51",
          "isActive": false,
          "code": "oioc_marketing_merchant_code",
          "//code": "字段标准编码（维度 code，如用于 /dimension/value 的 dimensionCode）",
          "englishAbbr": "oioc_marketing_merchant_code",
          "englishName": "oioc_marketing_merchant_code",
          "name": "物码营销商户编码",
          "//name": "字段标准名称（中文）",
          "dataType": "STRING",
          "length": null,
          "precisions": null,
          "isNull": false,
          "//isNull": "是否允许为空",
          "defaultValue": null,
          "businessDefinition": null,
          "parentCode": null,
          "quoteCode": "",
          "groupCode": "field_group_26",
          "sort": 2,
          "ownerName": "李鹏",
          "ownerId": 1021775,
          "displayType": "dict",
          "dimensionEnable": true,
          "associatedTableCode": "dim_oioc_marketing_merchant_main_df_1d",
          "associatedDoCode": "oioc_marketing_merchant_code",
          "associatedColumnCode": "oioc_marketing_merchant_code",
          "associatedShowColumnCode": "oioc_marketing_merchant_name",
          "associatedAssistColumnCodes": [],
          "paramConds": {
            "conds": [],
            "relation": "and"
          },
          "//paramConds": "维度查询附加条件，结构随业务变化",
          "dictValueList": []
          ,"//dictValueList": "字典值列表，常为空数组"
        }
      ],
      "children": []
      ,"//children": "子分组列表，结构同当前元素递归"
    }
  ]
}
```

- **字段说明（分组层）**：`id`、`groupName`、`groupCode`、`parentCode`、`path`、`sort`、`children` 见上注释；无子分组时 `children` 多为 `[]`。
- **字段说明（`filedStandardDataList[]`）**：除上表列出的常用字段外，网关还可能返回其它键；本服务 DTO 使用 `@JsonIgnoreProperties(ignoreUnknown = true)` 兼容未声明字段。

### 3.4 数据字典：标准维度值检索

- 接口：`POST /sales/task/data-dictionary/dimension/value`
- 调用方式：`DataDictionaryController` → `DataDictionaryService#listStandardDimensionValues` → `DataCrowdFeignService#doListStandardDimensionValues`
- 说明：成功时 `Response.data` 为网关 `data` 数组（`code`、`name`、`extendsInfo`）。

请求 Body 示例：

```json
{
  "dimensionCode": "visit_route_code",
  "keyword": ""
}
```

- 字段说明：`dimensionCode` 必填，与数据字典标准字段 `code` 一致；`keyword` 可选，可传空串。

返回示例（`data` 为维度值数组）：

```json
{
  "code": 0,
  "message": "success",
  "data": [
    {
      "code": "fx$61ceae2be2d41561fe51bfbf",
      "name": "【周日】上恒",
      "extendsInfo": []
    }
  ]
}
```

### 2.2 返回结果示例

```json
{
  "msg": "success",
  "code": 0,
  "data": {
    "total": 3,
    "list": [
      "YQWD03233175"
    ]
  },
  "requestId": "a27861ec0759b423"
}
```

### 1.2 返回结果示例

```json
{
  "msg": "success",
  "code": 0,
  "data": {
    "total": 3,
    "list": [
      {
        "id": 22,
        "code": "wkiralaw",
        "name": "非26财年冬跃期间维生素双铺网点",
        "objectCode": "sales_channel",
        "objectName": "销售通路",
        "groupId": 22,
        "groupName": "2112",
        "description": "<p>合作非阻断网点-冬跃维生素双铺达成网点</p>",
        "ownerId": 226,
        "ownerName": "苏少华(17207)",
        "creatorId": 0,
        "creatorName": "admin",
        "updaterId": 0,
        "updaterName": "admin",
        "refreshMode": "TIMING",
        "refreshInterval": "0 0 5 * * ?",
        "productMode": "SQL",
        "executorEngine": "HOLOGRES",
        "versions": "V22",
        "uuid": "dco-x7XKU8E3U2uzsDnuQEYtr",
        "guid": "oudc_260402144843598",
        "taskFileId": "503727529",
        "stopRefresh": "2026-06-01T00:00:00",
        "createTime": "2026-04-02T14:48:44",
        "updateTime": "2026-04-03T14:50:49",
        "sort": 0,
        "open": 1,
        "isDeleted": 0,
        "status": 1,
        "syncScheduler": 1,
        "timeConfig": {
          "offset": 0,
          "timeType": "FOREVER",
          "labelDate": "9999",
          "schedulePeriod": null,
          "sit": "rel"
        },
        "mainConfig": {
          "sql": "..."
        }
      }
    ]
  },
  "requestId": "a27861ec0759b423"
}
```

---

## 4. 数据字典：维度分组列表

- 接口：`GET /dwh/data-dictionary/dimension/list`（网关；Feign 同路径 GET）
- 本服务业务路由：`POST /sales/task/data-dictionary/dimension/list`（见 §3.3，与模块内其它接口统一为 POST）
- 调用方式：Feign（`DataCrowdFeignService#listDataDictionaryDimensions` / `doListDataDictionaryDimensions`）
- 说明：网关无 Query 参数；返回全量维度分组及每组下标准字段列表（远端 `data` 为数组；分组内字段列表 JSON 名为 `filedStandardDataList`）。

### 4.1 请求

无请求体、无 Query。

### 4.2 返回结果要点

- `code`：0 成功；`msg`：提示文案；`data`：分组节点列表，节点含 `id`、`groupName`、`groupCode`、`filedStandardDataList`（标准字段数组）、`children`（子分组）等。
- 标准字段对象含 `code`（维度编码）、`name`（中文名）、`dimensionEnable`、`associatedTableCode` 等与网关一致字段；未知扩展字段由 DTO `@JsonIgnoreProperties(ignoreUnknown = true)` 忽略。

### 4.3 网关原始响应 JSON 示例（`GET /dwh/data-dictionary/dimension/list`）

与 **§3.3.1** 中 `data` 数组元素结构相同；最外层为网关统一包装（`msg` 字段名以网关为准，常见为「成功」类文案）。

```json
{
  "code": 0,
  "msg": "成功",
  "data": [
    {
      "id": 26,
      "groupName": "一物一码",
      "groupCode": "field_group_26",
      "parentCode": null,
      "path": null,
      "sort": 1,
      "filedStandardDataList": [
        {
          "id": 202,
          "code": "oioc_marketing_merchant_code",
          "name": "物码营销商户编码",
          "dataType": "STRING",
          "isNull": false,
          "dimensionEnable": true,
          "associatedTableCode": "dim_oioc_marketing_merchant_main_df_1d",
          "associatedColumnCode": "oioc_marketing_merchant_code",
          "associatedShowColumnCode": "oioc_marketing_merchant_name",
          "displayType": "dict",
          "paramConds": {
            "conds": [],
            "relation": "and"
          },
          "dictValueList": []
        }
      ],
      "children": []
    }
  ]
}
```

---

## 5. 指标网格：标准维度值检索

- 接口：`POST /dwh/metric-grid/standard/dimension/value`
- 调用方式：Feign（`DataCrowdFeignService#listStandardDimensionValues` / `doListStandardDimensionValues`）
- 说明：`Content-Type: application/json`；按 `dimensionCode` 拉取可选值列表（`code` + `name`），`keyword` 可为空字符串。

### 5.1 请求 Body 示例

```json
{
  "dimensionCode": "visit_route_code",
  "keyword": ""
}
```

- 字段说明：`dimensionCode` 为数据字典标准字段编码，与列表接口中 `filedStandardDataList[].code` 一致；`keyword` 为关键词过滤，空串表示不按关键词过滤（以网关实际语义为准）。

### 5.2 返回结果示例（结构节选）

```json
{
  "code": 0,
  "msg": "成功",
  "data": [
    {
      "code": "fx$61ceae2be2d41561fe51bfbf",
      "name": "【周日】上恒 转移人：系统 转移人：系统",
      "extendsInfo": []
    }
  ]
}
```

- 字段说明：`data[].code` 为维度值编码；`data[].name` 为展示名；`data[].extendsInfo` 为扩展信息数组（元素结构由远端决定）。

