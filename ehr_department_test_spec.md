# EHR 部门树测试规格

## 1. 部门树 `POST /sales/task/ehr/deptList`

- 说明：转发 EHR 网关 `POST /ehr/api/contact/v1/departments/tree_list`；与 sls-merchant-finance `POST /jxsrebate/op/deptList` 行为一致。
- 默认根部门：`deptCode=573551785`（请求体不传或 `deptCode` 为空时）。

### 1.1 请求示例（默认根）

```json
{}
```

### 1.2 请求示例（指定根部门）

```json
{
  "deptCode": "573551785" // 根部门编码，可选
}
```

### 1.3 响应示例

```json
{
  "code": 0,
  "message": "success",
  "data": {}
}
```

`data` 结构由 EHR 接口返回，本服务原样透传。

### 1.4 用例

- 用例1（正常）：空 body → 使用默认 `deptCode`，返回部门树
- 用例2（正常）：传入合法 `deptCode` → 以该节点为根返回子树
- 用例3（失败）：EHR 网关报错 → 本服务 `BizException`，message 为 EHR 返回信息
