# 动态HTTP聚合配置测试规格

## 功能模块：dynamic_http_group

### 一、变更说明

1. 新增 `dynamic_http_endpoint_group` 主表，用于定义动态HTTP端点聚合配置（一个聚合可挂多个 endpoint）。
2. 新增 `dynamic_http_endpoint_group_rel` 关联表，用于维护 `group_id` 与 `endpoint_id` 的多对多关系及排序。
3. `biz_template_config` 新增字段 `dynamic_http_group_id`，用于关联一个聚合配置（**仅落库**；业务模板 create/update **不再校验**该 id 是否存在）。
4. 新增接口前缀 `/sales/task/dynamic/endpoint/group`，支持聚合配置的增删改查与分页列表。

### 二、接口列表（前缀 `/sales/task/dynamic/endpoint/group`）

- `POST /create`：新增聚合配置
- `POST /update`：更新聚合配置
- `POST /delete`：删除聚合配置
- `POST /detail`：查询详情（返回 endpointIds）
- `POST /list`：分页查询

### 三、请求 JSON 示例

#### 1. 新增聚合配置 `POST /create`

```json
{
  "groupCode": "group_sc_base",
  "groupName": "SC基础拉数聚合",
  "remark": "组合设备接口+返利接口",
  "enabled": 1,
  "endpointIds": [1, 2, 3]
}
```

字段说明：

- `groupCode`：聚合编码，全局唯一。
- `groupName`：聚合名称。
- `remark`：备注说明。
- `enabled`：是否启用，1 启用 / 0 停用。
- `endpointIds`：关联的 `dynamic_http_endpoint.id` 列表，按数组顺序写入排序号。

#### 2. 更新模板配置关联 `POST /sales/task/biz/template/config/update`

```json
{
  "id": 1001,
  "templateCode": "TPL_20260327_ABC",
  "templateName": "门店陈列模板",
  "datasourceId": 12,
  "physicalTable": "store_display_daily",
  "databaseName": "sales_ods",
  "taskExecutionEventCode": "STORE_DISPLAY_SYNC",
  "dynamicHttpGroupId": 10,
  "syncStrategy": "REAL_TIME",
  "sampleLimit": 20,
  "version": 2,
  "isActive": true
}
```

字段说明：

- `dynamicHttpGroupId`：关联聚合配置主键；为空表示不绑定。
- 其余字段保持模板配置原有语义。

### 四、测试用例

- 用例1：创建聚合配置成功
  - 前置：`dynamic_http_endpoint` 已存在若干有效 `id`。
  - 入参：`groupCode` 不重复，`endpointIds` 都是有效ID。
  - 预期：返回新 `id`，`group_rel` 生成对应关联行。

- 用例2：`groupCode` 重复创建失败
  - 前置：已有同名 `groupCode`。
  - 入参：重复 `groupCode`。
  - 预期：接口报错 `groupCode 已存在`。

- 用例3（已变更）：业务模板 **`dynamicHttpGroupId`** 不再做存在性校验；若需验证聚合配置本身，请直接调 **`/sales/task/dynamic/endpoint/group`** 的 create/update/detail。
  - 说明：历史上曾约定模板 update 对 `dynamicHttpGroupId` 做「库中存在」校验，现已移除；传入任意数值仅写入 **`biz_template_config.dynamic_http_group_id`**，不保证引用有效。

- 用例4：删除聚合配置
  - 前置：存在某聚合及关联行。
  - 入参：该聚合 `id`。
  - 预期：主表逻辑删除，关联表同 `group_id` 行逻辑删除。
