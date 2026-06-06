# 字段筛选操作符测试规格

## 1. 查询全部未删除操作符

- 接口：`POST /sales/task/fieldFilter/operator/listAll`
- 说明：返回 `is_deleted=0` 的记录，按 `sort_order`、`id` 升序；每条含 `fieldTypes`（适用类型：`STRING` 字符串 / `NUMBER` 数字 / `DATE` 日期 / `BOOLEAN` 布尔 / `OTHER` 其他，可多选）。**`OTHER` 仅允许使用「为空」「不为空」**（仅这两条记录的 `fieldTypes` 含 `OTHER`）。
- **按类型过滤**：请求体可选 `fieldTypes` 数组（如 `["STRING"]`、`["BOOLEAN"]`）；服务端仅保留「库中 `field_types` 与入参存在交集」的操作符（入参多个类型时为 **任一命中即保留**，交集语义）。不传、`fieldTypes` 为空或仅非法值时返回**全部**未删除操作符；合法元素为 `STRING`、`NUMBER`、`DATE`、`BOOLEAN`、`OTHER`（忽略大小写，归一为全大写）。

### 1.1 请求示例

不传或空对象（返回全部）：

```json
{}
```

仅查询字符串类型可用操作符：

```json
{
  "fieldTypes": ["STRING"]
}
```

仅查询「其他」类型（应只返回为空、不为空）：

```json
{
  "fieldTypes": ["OTHER"]
}
```

仅查询布尔类型可用操作符：

```json
{
  "fieldTypes": ["BOOLEAN"]
}
```

### 1.2 响应示例

```json
{
  "code": 0,
  "message": "success",
  "data": [
    {
      "id": 1,
      "operatorName": "等于",
      "operatorCode": "=",
      "fieldTypes": ["STRING", "NUMBER", "DATE"],
      "sortOrder": 10,
      "createdAt": "2026-04-30 15:00:00",
      "updatedAt": "2026-04-30 15:00:00"
    }
  ]
}
```

### 1.3 字段说明（data 数组元素）

- `id`：主键
- `operatorName`：操作符中文名称（界面展示，与库 `operator_name` 一致，如「大于等于」）
- `operatorCode`：操作符本身或语义码（与库 `operator_code` 一致、全局唯一，如 `>=`、`=`、`BETWEEN`、`IS_NULL`）
- `fieldTypes`：适用字段类型列表；前端可按当前字段类型过滤，仅展示 `fieldTypes` 包含该类型的项
- `sortOrder`：展示排序
- `createdAt` / `updatedAt`：创建、修改时间

### 1.4 回归

- 逻辑删除后不应出现在列表中
- `operator_code` 唯一；`field_types` 为合法 JSON 数组
- 请求 `fieldTypes: ["BOOLEAN"]`（或 `boolean`）时，仅返回库中 `field_types` 含 `BOOLEAN` 的操作符
