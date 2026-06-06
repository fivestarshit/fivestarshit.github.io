# Groovy 脚本代码实例测试规格

## 1. 概述

- 表名：`groovy_script_instance`
- 用途：存储预置 Groovy 脚本片段，配置任务/模板时可直接选用
- 接口前缀：`POST /sales/task/groovy/script/instance/*`

## 2. 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| name | VARCHAR(256) | 实例名称 |
| script_content | TEXT | Groovy 代码内容 |
| description | VARCHAR(512) | 描述，可空 |
| status | TINYINT | 0-禁用，1-启用 |
| type | TINYINT | 脚本分类：1/2/3/4，**默认 1** |

## 3. 创建 `POST /sales/task/groovy/script/instance/create`

### 请求示例

```json
{
  "name": "条件匹配示例", // 必填：实例名称
  "scriptContent": "return items != null && items.size() > 0", // 必填：Groovy 脚本，长度不超过 6000
  "description": "判断 items 非空", // 可选：描述
  "status": 1 // 可选：0-禁用 1-启用，默认 1
  // type 可选：1/2/3/4，不传默认 1
}
```

### 响应示例

```json
{
  "code": 0,
  "message": "success",
  "data": 1001 // 新建记录主键 id
}
```

### 用例

- 用例1（正常）：上述入参 → 创建成功，返回 id，`type` 默认为 1，`createdBy`/`updatedBy` 为当前 OP 登录人姓名
- 用例1b（正常）：不传 `type` → 创建成功，`type=1`
- 用例2（失败）：`name` 为空 → 业务错误
- 用例3（失败）：`scriptContent` 为空 → 业务错误
- 用例4（失败）：`type=5` → 业务错误「type 须为 1/2/3/4」
- 用例5（失败）：`scriptContent` 超过 6000 字符 → 业务错误

## 4. 更新 `POST /sales/task/groovy/script/instance/update`

### 请求示例

```json
{
  "id": 1001, // 必填：主键
  "name": "条件匹配示例（修订）", // 必填
  "scriptContent": "return items != null", // 必填
  "description": "修订描述", // 可选
  "status": 0, // 必填：0-禁用 1-启用
  "type": 2 // 必填：1/2/3/4
}
```

### 用例

- 用例6（正常）：id 存在 → 更新成功，`updatedBy` 更新为当前操作人，`createdBy` 不变
- 用例7（失败）：id 不存在 → 业务错误

## 5. 详情 `POST /sales/task/groovy/script/instance/detail`

### 请求示例

```json
{
  "id": 1001 // 必填：主键
}
```

### 响应示例

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 1001,
    "name": "条件匹配示例",
    "scriptContent": "return items != null && items.size() > 0",
    "description": "判断 items 非空",
    "status": 1,
    "type": 1,
    "createdAt": "2026-05-22T10:00:00",
    "updatedAt": "2026-05-22T10:00:00",
    "createdBy": null,
    "updatedBy": null
  }
}
```

## 6. 分页列表 `POST /sales/task/groovy/script/instance/list`

### 请求示例

```json
{
  "page": 1, // 当前页，默认 1
  "pageSize": 20, // 每页条数，默认 20
  "name": "条件", // 可选：名称模糊匹配
  "status": 1, // 可选：0/1
  "type": 1 // 可选：1/2/3/4
}
```

### 响应示例

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

## 7. 已启用列表（选用） `POST /sales/task/groovy/script/instance/listEnabled`

### 请求示例

```json
{
  "type": 1 // 可选：仅返回指定类型的已启用实例；不传则返回全部类型
}
```

### 响应示例

```json
{
  "code": 0,
  "message": "success",
  "data": [
    {
      "id": 1001,
      "name": "条件匹配示例",
      "scriptContent": "return items != null && items.size() > 0",
      "description": "判断 items 非空",
      "status": 1,
      "type": 1
    }
  ]
}
```

### 用例

- 用例8（回归）：仅 `status=1` 的记录出现在 listEnabled；`status=0` 不出现
- 用例9（回归）：传 `type=2` 时仅返回 type=2 且启用的记录

## 8. 删除 `POST /sales/task/groovy/script/instance/delete`

### 请求示例

```json
{
  "id": 1001 // 必填：主键，逻辑删除
}
```

### 用例

- 用例10（正常）：id 存在 → 逻辑删除成功，detail/list 不可见
