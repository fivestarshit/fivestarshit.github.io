# OP 部门数据权限同步测试用例

## 功能说明

定时任务 `syncOpPermissionsJob` 将 EHR 营销中心部门树同步至 infra-oauth 数据资源树。

- **最新数据源**：`findDeptTree(marketingDepartmentCode)` — EHR 部门树（以之为准）
- **存量数据源**：`queryDataResource(dataCode)` — infra 已有权限节点
- **根节点**：`marketingOpPermissionId` 为 infra 资源树根，禁止删除

## 同步策略

| 场景 | 行为 |
|------|------|
| EHR 存在、infra 不存在 | 创建数据资源节点 |
| EHR 存在、infra 存在 | 跳过，不更新不删除 |
| infra 存在、EHR 已删除/停用 | 由 `checkOpDepartmentState` 巡检清理 |

**遍历层级**：从营销中心 `findDeptTree` 列表节点起为第 1 级，默认最多同步 **2** 级（`op.config.syncDeptMaxDepth`，未配置或 ≤0 时取 2）；更深层 `subDeptList` 不创建、不递归。

## 测试用例

### TC-01 首次全量同步

**前置条件**：infra 资源树下仅有根节点 `marketingOpPermissionId`，无子部门节点。

**步骤**：执行 `syncOpPermissions()`。

**预期**：
- EHR 营销中心下各级部门在 infra 中创建对应节点
- 根节点 `marketingOpPermissionId` 未被删除或重建
- 日志映射数从 0 增至与 EHR 部门数一致

### TC-02 二次同步幂等（回归）

**前置条件**：TC-01 已执行，infra 与 EHR 结构一致。

**步骤**：再次执行 `syncOpPermissions()`。

**预期**：
- 不触发 `deleteOpPermissions`、`updateOpPermissions`、`createAndMapDept`
- 日志输出「已存在, 跳过」
- infra 节点总数不变

### TC-03 部门名称变更

**前置条件**：EHR 某部门 `deptName` 已修改，结构未变。

**步骤**：执行 `syncOpPermissions()`。

**预期**：
- 同步任务不更新名称（已存在节点跳过）
- infra 中 `aliasName` 保持原值

### TC-04 新增子部门

**前置条件**：EHR 在某已有部门下新增子部门。

**步骤**：执行 `syncOpPermissions()`。

**预期**：
- 仅新增子部门节点创建
- 父部门及已有兄弟节点跳过，不被删除或更新

### TC-05 根节点保护

**前置条件**：infra 根节点 `dataValueCode = marketingOpPermissionId`。

**步骤**：巡检任务 `checkOpDepartmentState()` 触发删除逻辑。

**预期**：
- 日志输出「根节点禁止删除」
- 根节点仍存在

## 配置示例

```json
{
  "op.config.marketingDepartmentCode": "OP_MARKETING", // 营销中心部门编码
  "op.config.marketingOpPermissionId": "100001", // infra 资源树根 dataValueCode，不可删除
  "op.config.dataCode": "OP_DEPT", // 数据维度编码
  "op.config.appCode": "sls", // 应用编码
  "op.config.syncDeptMaxDepth": 2, // 部门树同步遍历层级上限（默认 2）
  "op.config.serviceCode": "sls-sales" // 服务编码
}
```
