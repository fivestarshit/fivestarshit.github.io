# 试用数据配置测试说明（trial_data_config）

本文档与 `TrialDataConfigController`、`TrialDataConfigServiceImpl` 一致；覆盖分页列表、新增、更新、**按 id 详情**、**逻辑删除**；请求 JSON 中 `//` 注释仅作文档说明，实际调用需为合法 JSON（去掉注释或改用下方字段表）。

---

## 1. 分页列表 `POST /sales/task/trial/data/config/list`

- **说明**：按主键 **id 倒序**分页查询 **`trial_data_config`**（`is_deleted=0` 由 MyBatis-Plus 逻辑删除自动过滤）。**`page`、`pageSize` 均可省略**：省略时 **`page=1`**、**`pageSize=100`**（与通用分页默认 20 区分）。
- **成功 `data`**：`PageResult<TrialDataConfigDTO>`，含 **`records`**、**`total`**、**`page`**、**`pageSize`**、**`totalPage`**。

### 1.1 请求 JSON 示例

```json
{
  "page": 1,
  "//page": "当前页码，可选，默认 1",
  "pageSize": 100,
  "//pageSize": "每页条数，可选，默认 100；传小于 1 时按 100 处理"
}
```

### 1.2 字段说明（列表请求体）

| 字段 | 类型 | 说明 |
|------|------|------|
| `page` | 整数 | 当前页，默认 1 |
| `pageSize` | 整数 | 每页条数，**默认 100** |

### 1.3 响应 `data` 结构示例

```json
{
  "records": [
    {
      "id": 1,
      "//id": "主键",
      "configCode": "EVENT_20260511_a1b2c3",
      "//configCode": "创建时 CodeGenerateUtils.generateCode(EVENT_)：EVENT_yyyyMMdd_6位十六进制；只读",
      "configName": "示例同步配置",
      "//configName": "配置名称",
      "taskExecutionEventCode": "ORDER_SYNC",
      "//taskExecutionEventCode": "执行类型监听的事件编码",
      "remark": "试用说明",
      "//remark": "备注",
      "createdAt": "2026-05-11 10:00:00",
      "updatedAt": "2026-05-11 10:00:00",
      "createdBy": null,
      "updatedBy": null
    }
  ],
  "total": 1,
  "page": 1,
  "pageSize": 100,
  "totalPage": 1
}
```

### 1.4 用例

| 编号 | 场景 | 步骤 | 预期 |
|------|------|------|------|
| TDC-LIST-01 | 默认分页 | `POST .../list`，Body 为空 `{}` 或省略 Body | `page=1`，`pageSize=100`，`records` 为当前页数据 |
| TDC-LIST-02 | 指定条数 | Body `{"page":1,"pageSize":20}` | `pageSize=20`，总页数等与总数一致 |

---

## 2. 新增 `POST /sales/task/trial/data/config/create`

- **成功 `data`**：新建行主键 **`Long` id**（**`configCode`** 不在请求体中传入；创建成功后可通过 **详情/列表** 查看，由 **`CodeGenerateUtils.generateCode("EVENT_")`** 生成，形如 **`EVENT_yyyyMMdd_xxxxxx`**，在未删除记录中唯一（冲突时服务端重试生成）。
- **规则**：**`configName`** 必填（Bean Validation + 服务端 trim 后非空）；**`taskExecutionEventCode`**、**`remark`** 可空，仅空白则落库 **null**。

### 2.1 请求 JSON 示例

```json
{
  "configName": "示例同步配置",
  "//configName": "配置名称，必填",
  "taskExecutionEventCode": "ORDER_SYNC",
  "//taskExecutionEventCode": "执行类型监听的事件编码，可选",
  "remark": "试用说明",
  "//remark": "备注，可选"
}
```

### 2.2 用例

| 编号 | 场景 | 预期 |
|------|------|------|
| TDC-CRT-01 | 合法创建 | HTTP 200，`data` 为新 id；再调详情可见 `configCode` 符合 `EVENT_yyyyMMdd_xxxxxx`（与 `CodeGenerateUtils` 一致） |
| TDC-CRT-02 | `configName` 为空 | 校验失败或服务端 `BizException`，`configName 不能为空` |

---

## 3. 更新 `POST /sales/task/trial/data/config/update`

- **成功 `data`**：多为 `null`（`Response.success()`）。
- **规则**：**`id`** 必填且须存在；**`configName`** 必填（trim 后非空）；**`configCode` 不可修改**（请求体中不应再传；即使历史客户端误传也会被忽略，仍以库中原值为准）；**`taskExecutionEventCode`**、**`remark`** 可空，仅空白则落库 **null**。

### 3.1 请求 JSON 示例

```json
{
  "id": 1,
  "//id": "主键 trial_data_config.id，必填",
  "configName": "示例同步配置-改",
  "//configName": "配置名称，必填",
  "taskExecutionEventCode": "ORDER_SYNC",
  "//taskExecutionEventCode": "监听事件编码，可选",
  "remark": "更新备注",
  "//remark": "备注，可选"
}
```

### 3.2 用例

| 编号 | 场景 | 预期 |
|------|------|------|
| TDC-UPD-01 | 合法更新 | HTTP 200；`configCode` 与更新前一致 |
| TDC-UPD-02 | `id` 不存在 | `BizException`，`试用数据配置不存在` |
| TDC-UPD-03 | 仅改名称/备注/事件编码 | HTTP 200，`configCode` 不变 |

---

## 4. 详情 `POST /sales/task/trial/data/config/detail`

- **说明**：按主键 **id** 查询单条 **`trial_data_config`**；逻辑删除行由 MyBatis-Plus 过滤，等同不存在。
- **成功 `data`**：`TrialDataConfigDTO`（字段与列表 `records` 中单条一致）。
- **异常**：`id` 为空、或记录不存在 → `BizException`（`id 不能为空` / `试用数据配置不存在, id=...`）。

### 4.1 请求 JSON 示例

```json
{
  "id": 1,
  "//id": "主键 trial_data_config.id，必填"
}
```

### 4.2 用例

| 编号 | 场景 | 预期 |
|------|------|------|
| TDC-DTL-01 | 合法 id | HTTP 200，`data` 为对应 DTO |
| TDC-DTL-02 | `id` 不存在或已删除 | `BizException`，文案含 `试用数据配置不存在` |
| TDC-DTL-03 | `id` 为空或 Body 缺 id | `BizException`，`id 不能为空` |

---

## 5. 删除 `POST /sales/task/trial/data/config/delete`

- **说明**：按主键 **id** 对 **`trial_data_config`** 做**逻辑删除**（`is_deleted=1`，由 MyBatis-Plus `@TableLogic` 处理）；删除后列表/详情均查不到该记录。
- **成功 `data`**：多为 `null`（`Response.success()`）。
- **异常**：`id` 为空、或记录不存在/已删除 → `BizException`（`id 不能为空` / `试用数据配置不存在, id=...`）。

### 5.1 请求 JSON 示例

```json
{
  "id": 1,
  "//id": "主键 trial_data_config.id，必填"
}
```

### 5.2 用例

| 编号 | 场景 | 预期 |
|------|------|------|
| TDC-DEL-01 | 合法 id | HTTP 200；再调详情/列表不可见 |
| TDC-DEL-02 | `id` 不存在或已删除 | `BizException`，文案含 `试用数据配置不存在` |
| TDC-DEL-03 | `id` 为空 | `BizException`，`id 不能为空` |

---

## 6. 表结构（DDL）

见 **`doc/sql/update_tables.sql`** / **`dpc/sql/update_tables.sql`** 中 **`trial_data_config`** 建表语句；部署后需执行该段 DDL 方可查询到数据。
