# 任务组测试规格（1.4）

> **变更说明（2026-08-13）**：删除拒绝文案括号由 `[]` 改为 `【】`。
>
> **变更说明（2026-08-03）**  
> 1.4 新建独立 **`task_group`** 表；任务包通过 **`task_definition.task_group_id`** 关联任务组。本文档覆盖：**历史迁移 Job**（TGR-003，已落地）与 **任务组 CRUD HTTP 接口**（TGR-004，已落地）。

---

## 一、历史数据迁移 Job（TGR-003 · 已落地）

非 HTTP 接口，由 XXL-JOB 调度。

| 项 | 说明 |
|----|------|
| Job 名称 | `migrateTaskGroupStructure` |
| 实现类 | `TaskGroupMigrationJob` |
| Service | `TaskGroupMigrationService#migrateTaskGroupStructure` |
| 幂等 | 可重复执行；已为 PACKAGE 建组则跳过建组步骤 |

### 1.1 执行内容

1. 为 `task_group_id IS NULL` 的存量 **PACKAGE** 各建 1 条 **task_group**（`group_code` 前缀 **RWZ**），回写 **`task_definition.task_group_id`**
2. 回写包规则 + 子 TASK 规则的 **`task_rule.task_group_id`**
3. 从 **ext / 包 rule** 回填子 TASK 规则的下发、节奏、截止等（仅空字段）
4. 回填 **`completion_standard_type`**（`has_action` → TEMPLATE/CUSTOM）

**不在** `task_distribution_detail` 写 `task_group_id`。

### 1.2 日志 / 结果结构

Job 完成后日志 JSON 对应 **`TaskGroupMigrationResultDTO`**：

```json
{
  "groupsCreated": 12,
  "//groupsCreated": "本次新建 task_group 条数",
  "packagesLinked": 12,
  "//packagesLinked": "回写 task_definition.task_group_id 的包数",
  "rulesGroupIdUpdated": 48,
  "//rulesGroupIdUpdated": "回写 task_rule.task_group_id 的规则数（包+子TASK）",
  "childRulesBackfilled": 36,
  "//childRulesBackfilled": "从包层/ext 回填到子 TASK 规则的次数",
  "completionStandardTypeBackfilled": 120,
  "//completionStandardTypeBackfilled": "回填 completion_standard_type 的规则数"
}
```

### 1.3 用例 TGR-JOB-01：首次迁移

- **前置**：已执行 TGR-002 DDL；存在无 `task_group_id` 的 PACKAGE
- **操作**：XXL 控制台触发 **`migrateTaskGroupStructure`**
- **预期**：`groupsCreated > 0`；抽检 SQL 见 **`doc/任务组结构改造_test_spec.md` §4.3**

### 1.4 用例 TGR-JOB-02：幂等重跑

- **操作**：再次触发同一 Job
- **预期**：`groupsCreated=0`；无重复 task_group 记录

---

## 二、任务组 CRUD API（TGR-004 · 已落地）

> Controller：`TaskGroupController`（`/sales/task/group`）；Service：`TaskGroupService` / `TaskGroupServiceImpl`。  
> **禁止**用 `POST /sales/task/definition/list?taskType=PACKAGE` 冒充任务组列表。

### 2.1 创建任务组

- **接口**：`POST /sales/task/group/create`
- **请求示例**：
  ```json
  {
    "groupName": "Q3华东策略组",
    "//groupName": "任务组名称，必填",
    "remark": "三季度华东区域任务策略",
    "//remark": "备注，可选",
    "strategyTags": "华东,Q3",
    "//strategyTags": "策略标签，必填；多个英文逗号分隔"
  }
  ```
- **说明**：可不关联任何任务包；**`groupName`、`strategyTags` 必填**；**`groupCode`** 服务端生成（**RWZ** + yyMMdd + 8 位随机）
- **成功响应**：
  ```json
  {
    "code": 0,
    "message": "success",
    "data": 1001
  }
  ```
  - **`data`**：新建 **`task_group.id`**

### 2.2 更新任务组

- **接口**：`POST /sales/task/group/update`
- **请求示例**：
  ```json
  {
    "id": 1001,
    "groupName": "Q3华东策略组（修订）",
    "remark": "更新备注",
    "strategyTags": "华东,Q3,修订",
    "status": 1
  }
  ```
- **说明**：**不可修改** `groupCode`
- **TGR-012**：当 **`status` 由 1→0（停用）** 时，按 **`PACKAGE.task_group_id=本组`** 查找关联任务包，关闭各包下 **IN_PROGRESS** 下发明细（组 id ≠ 包 id）

### 2.3 任务组详情

- **接口**：`POST /sales/task/group/detail`
- **请求**：`{ "id": 1001 }`
- **响应 `data` 示例**：
  ```json
  {
    "id": 1001,
    "groupName": "Q3华东策略组",
    "groupCode": "RWZ260803087d8eyxx",
    "remark": "三季度华东区域任务策略",
    "strategyTags": "华东,Q3",
    "status": 1,
    "linkedPackageIds": [2001, 2002],
    "//linkedPackageIds": "关联任务包 id 列表（PACKAGE.task_group_id=本组），可空数组",
    "linkedRuleCount": 8,
    "//linkedRuleCount": "组下关联包的子任务数量（仅 task_type=TASK，不含 PACKAGE）",
    "createdBy": "张三",
    "updatedBy": "张三",
    "createdAt": "2026-08-03 10:00:00",
    "updatedAt": "2026-08-03 10:00:00"
  }
  ```

### 2.4 任务组分页列表

- **接口**：`POST /sales/task/group/list`
- **请求示例**：
  ```json
  {
    "page": 1,
    "//page": "当前页，默认 1",
    "pageSize": 20,
    "//pageSize": "每页条数，默认 20",
    "groupName": "华东",
    "//groupName": "任务组名称模糊，可选",
    "groupCode": "RWZ260803",
    "//groupCode": "编码模糊，可选",
    "status": 1
  }
  ```
- **成功响应**：
  ```json
  {
    "code": 0,
    "message": "success",
    "data": {
      "records": [
        {
          "id": 1001,
          "groupName": "Q3华东策略组",
          "groupCode": "RWZ260803087d8eyxx",
          "remark": "三季度华东区域任务策略",
          "strategyTags": "华东,Q3",
          "status": 1,
          "linkedPackageIds": [2001],
          "//linkedPackageIds": "关联任务包 id 列表",
          "linkedRuleCount": 4,
          "//linkedRuleCount": "仅统计关联包下 task_type=TASK 的数量，不含 PACKAGE",
          "createdBy": "张三",
          "updatedBy": "张三"
        }
      ],
      "total": 1,
      "page": 1,
      "pageSize": 20,
      "totalPage": 1
    }
  }
  ```

### 2.5 删除任务组

- **接口**：`POST /sales/task/group/delete`
- **请求示例**：
  ```json
  {
    "id": 1001,
    "//id": "任务组主键 task_group.id，必填"
  }
  ```
- **说明**：逻辑删除；若仍有关联 PACKAGE（`task_definition.task_group_id=本组`），拒绝删除
- **关联拒绝文案**：`当前任务组被【任务规则名称】关联无法删除`  
  （按关联 PACKAGE 查询包规则 + 子 TASK 规则的 **`task_rule.rule_name`**，顿号 `、` 拼接；无规则名时回退任务包名称）
- **成功响应**：
  ```json
  {
    "code": 0,
    "message": "success",
    "data": null
  }
  ```
- **失败响应示例**（有关联任务包/规则）：
  ```json
  {
    "code": 1,
    "message": "当前任务组被【陈列检查、库存盘点】关联无法删除",
    "//message": "括号内为关联包下 task_rule.rule_name；前端 axios 拦截器直接展示该文案"
  }
  ```

### 2.6 用例 TGR-API-01 ~ 05

| 用例 | 操作 | 预期 |
|------|------|------|
| TGR-API-01 | create 传名称+策略标签 | 返回 id；detail 可见 RWZ 编码 |
| TGR-API-02 | create 不传任务包 | `linkedPackageIds=[]`、`linkedRuleCount=0` |
| TGR-API-03 | update 改名称/备注/status/策略标签 | detail 已更新；groupCode 不变 |
| TGR-API-04 | list 分页 | records/total/page/pageSize/totalPage 结构正确 |
| TGR-API-05 | delete 无关联包可删；有关联包拒绝 | 无包：删除成功；有包：`当前任务组被【任务规则名称】关联无法删除`（取包下 rule_name） |
| TGR-API-06 | create/update 缺 groupName 或 strategyTags | 校验失败（`@NotBlank` / BizException） |
| TGR-API-07 | detail/list 的 linkedRuleCount | 仅统计组下关联 PACKAGE 的子任务（`task_type=TASK`）条数；**不含**包级 PACKAGE 自身 |

---

## 三、前端对接（TGR-027 · Comm-Divisor-Service）

| 能力 | 前端路径 / 常量 | 后端接口 |
|------|----------------|----------|
| 列表 | `/sales-task/task-groups`，`TASK_GROUP_LIST` | `POST /sales/task/group/list` |
| 新建/编辑 | `/sales-task/task-groups/create-or-edit`，`TASK_GROUP_CREATE` / `UPDATE` / `DETAIL` | create / update / detail |
| 删除 | 列表操作列，`TASK_GROUP_DELETE`，body `{ id }` | `POST /sales/task/group/delete` |
| 任务明细 | 列表操作列最左「任务明细」→ `/sales-task/task-detail?taskGroupId=` | `POST .../distribution/detail/list` 带 **`taskGroupId`**（按所属包 `task_group_id`） |
| 任务包选组 | 任务包创建/编辑页下拉，`TASK_GROUP_LIST` + `DETAIL` | list / detail；包提交顶层 `taskGroupId` |

---

## 四、关联文档

- 结构总览 / 迁移抽检：`doc/任务组结构改造_test_spec.md`
- 任务包关联任务组 / 独立任务写路径：`doc/task_definition_test_spec.md`（TGR-007 **`taskGroupId`** / **`createTask`**）
- 任务规则新字段：`doc/condition_action_task_rule_test_spec.md`
