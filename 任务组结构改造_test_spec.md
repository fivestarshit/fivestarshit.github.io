# 任务组结构改造测试规格（1.4）

> **变更说明（2026-08-03 · TGR-001）**  
> 销售任务系统 1.4 引入独立「任务组」实体，打破「任务包 = 任务组」的错误口径；下发对象群、下发节奏、去重窗口、完成标准等配置下沉至任务（TASK）层 `task_rule`；存量数据通过迁移 Job 回填。本文档为结构变更总览、字段落库口径、迁移与回归用例入口。
>
> **变更说明（2026-08-04 · TGR-028）**  
> 前端「任务规则配置」信息架构：左栏「下发标准」= PACKAGE；右栏「完成标准」= 子 TASK；菜单「任务规则管理」= package-rules（后端 PACKAGE）。`createPackage`/`updatePackage` 的 **`taskGroupId` 必填**；包规则 `task_rule.task_group_id` 与包一致。完成标准三选一含「基于对象群」（`completionStandardType=OBJECT_GROUP` + 完成群 + IN/NOT_IN）。旧独立 task-rules 菜单下线。

---

## 一、现状 vs 目标态

### 1.1 现状（1.3 及以前）

```
任务包 PACKAGE（task_definition, task_type=PACKAGE）
  ├─ task_package_distribution_ext（1:1）：下发对象群、下发类型码
  ├─ task_rule（包规则）：distributionType/config、is_repeat、deadline*、completionJudgment*
  └─ 子任务 TASK[]（parent_id=包.id）
       └─ task_rule（子任务规则）：执行类型、模板、条件、completionScript；同包共享包层对象群
```

- 无独立 `task_group` 表；统计/筛选常把 `task_package_id` 当作「组」维度使用。
- 完成标准 UI 用 `has_action` 布尔区分「基于标准模板 / 自定义标准」，无法表达「基于对象群」。
- 去重键：`is_repeat=false` → `task_def_id + target_entity_code`；`is_repeat=true` → 再加 `start_time/end_time`。

### 1.2 目标态（1.4）

```
任务组 task_group（新建；可 0 包；本身不下发）
  └─ 任务包 PACKAGE[]（task_definition.task_group_id，可空）
       └─ 子任务 TASK[]（各自独立 task_rule）
            ├─ 下发对象群 distribution_object_group_*
            ├─ 下发节奏 distributionType/config/timeConfig
            ├─ 去重 repeat_window_type + is_repeat（兼容）
            ├─ 截止 deadline* / 判断截止 task_judgment_deadline*
            └─ 完成标准 completion_standard_type（TEMPLATE/CUSTOM/OBJECT_GROUP）
                 └─ OBJECT_GROUP 时：completion_object_group_* + membership_operator（IN/NOT_IN）
```

- **禁止**将 `PACKAGE` 语义重命名为任务组；`task_group_id` ≠ `task_package_id`。
- 明细 `task_distribution_detail.task_package_id` 仍指向任务包；**不冗余** `task_group_id`（任务组可改绑，按包 JOIN 取当前组）。

---

## 二、字段落库位置

| 层级 | 表 | 新增/变更字段 | 说明 |
|------|-----|--------------|------|
| 任务组 | `task_group` | `group_name`, `group_code`(RWZ), `remark`, `strategy_tags`, `status`, 审计字段 | 独立 CRUD（TGR-004） |
| 任务包 | `task_definition` | `task_group_id`（可空） | 创建/编辑包时关联已有组 |
| 任务规则 | `task_rule` | `task_group_id`（可空，与所属包一致） | 包规则 + 子任务规则均维护 |
| 任务规则 | `task_rule` | `completion_standard_type` | TEMPLATE / CUSTOM / OBJECT_GROUP，替代 `has_action` 主口径 |
| 任务规则 | `task_rule` | `completion_object_group_id/name`, `membership_operator` | 仅 OBJECT_GROUP 时必填 |
| 任务规则 | `task_rule` | `repeat_window_type` | **MONTH（默认）/ DAYS / GLOBAL**；历史 NONE/LEGACY→GLOBAL |
| 任务规则 | `task_rule` | `task_judgment_deadline_type/config` 扩展 | 新增 `AFTER_TASK_DEADLINE`（任务截止后 N 天 HH:mm，TGR-010 解析） |
| 聚合（非落库） | — | 关联任务包 id 列表、关联规则数 | 列表/详情 SQL 聚合，见 §2.1 |

### 2.1 关联任务包 id / 关联规则数（查询聚合口径）

- **关联任务包 id 列表**：`SELECT id FROM task_definition WHERE task_type='PACKAGE' AND task_group_id=? AND is_deleted=0`
- **关联规则数（linkedRuleCount）**：组下关联包的子任务条数（**仅 `task_type=TASK`，不含包级 PACKAGE**）  
  ```sql
  SELECT COUNT(child.id)
  FROM task_definition child
  JOIN task_definition pkg ON pkg.id = child.parent_id AND pkg.is_deleted = 0
  WHERE child.task_type = 'TASK'
    AND child.is_deleted = 0
    AND pkg.task_type = 'PACKAGE'
    AND pkg.task_group_id = ?
    AND pkg.is_deleted = 0
  ```

### 2.2 has_action 兼容策略

| 存量 has_action | 迁移后 completion_standard_type | 读接口 |
|-----------------|--------------------------------|--------|
| 1 (true) | TEMPLATE | 短期可双写：DTO 同时返回 `hasAction` 与 `completionStandardType` |
| 0 (false) | CUSTOM | 写接口以 `completionStandardType` 为准 |
| null | CUSTOM | `has_action` 列保留只读，不再扩展语义 |

- **SQL 刷数（TGR-028）**：`dpc/sql/update_tables.sql` 追加按 `has_action` 对齐 `completion_standard_type`（TEMPLATE/CUSTOM）；已是 `OBJECT_GROUP` 不覆盖。

### 2.3 repeat_window_type（仅 3 值，默认单月）

| repeat_window_type | 前端文案 | 内存判重键 | is_repeat 兼容 |
|--------------------|---------|-----------|----------------|
| **MONTH**（默认） | 单月去重 | taskDefId+target+自然月 `yyyy-MM` | 空/`is_repeat=0`→MONTH |
| DAYS | 单日去重 | +自然日 `yyyy-MM-dd` | — |
| GLOBAL | 全局去重 | taskDefId+target（终身） | `is_repeat=1` 或历史 NONE/LEGACY→GLOBAL |

读写兼容：历史库值 `NONE`/`LEGACY` 解析为 `GLOBAL`；刷数见 `dpc/sql/update_tables.sql`。

**TGR-011 下发**：按子 TASK `task_rule.distribution_object_group_id` 各自 `doLatest`；空则回退包层 `task_package_distribution_ext`；同群多 TASK 只拉一次分群；明细 `task_package_id` 仍指向任务包。

---

## 三、编码规则

| 实体 | 前缀 | 示例 | 生成工具 |
|------|------|------|---------|
| 任务组 | RWZ | RWZ260803087d8eyxx | `CodeGenerateUtils.PREFIX_TASK_CODE_TASK_GROUP` |
| 任务包 | B | B260422087d8ey | 既有 |
| 子任务 | R | R260422087d8ey | 既有 |

规则：`前缀 + yyMMdd + 8位小写字母数字`，当日随机段查库去重。

---

## 四、历史迁移（TGR-003）

### 4.1 迁移步骤（幂等）

1. **建组并关联包**：对每个 `task_type=PACKAGE AND task_group_id IS NULL` 的存量包，插入 `task_group`（名称=包名，编码 RWZ），回写 `task_definition.task_group_id`。**默认 1 包 1 组**。
2. **回写 task_rule.task_group_id**：包规则 + 该包下所有子 TASK 规则，与包上 `task_group_id` 一致。
3. **配置下沉到子 TASK 规则**（仅当子规则对应字段为空时回填，保证可重跑）：
   - 从 `task_package_distribution_ext` → 子 `task_rule.distribution_object_group_id/name`
   - 从包 `task_rule` → 子 `task_rule`：`distribution_type/config/time_config`、`is_repeat`、`repeat_window_type`、`deadline_*`、`task_judgment_deadline_*`、`completion_judgment_*`、`auto_close_on_deadline`、`sync_complete_task`
4. **completion_standard_type 回填**：`has_action=1→TEMPLATE`，`has_action=0或null→CUSTOM`（仅 `completion_standard_type IS NULL` 时）。

**不**在 `task_distribution_detail` 写入 `task_group_id`：组与包关联可变，明细通过 `task_package_id → task_definition.task_group_id` 解析当前组。

### 4.2 触发方式

- XXL-JOB：`migrateTaskGroupStructure`（`TaskGroupMigrationJob`）
- 可重复执行；日志输出各步骤处理条数。

### 4.3 抽检 SQL

```sql
-- 应无 PACKAGE 缺 task_group_id（迁移完成后）
SELECT COUNT(*) FROM task_definition
WHERE task_type = 'PACKAGE' AND is_deleted = 0 AND task_group_id IS NULL;

-- 包规则 task_group_id 应与包一致
SELECT pkg.id, pkg.task_group_id, tr.task_group_id
FROM task_definition pkg
JOIN task_rule tr ON tr.id = pkg.rule_id
WHERE pkg.task_type = 'PACKAGE' AND pkg.is_deleted = 0
  AND (pkg.task_group_id IS NULL OR tr.task_group_id <> pkg.task_group_id);

-- 子 TASK 下发对象群应已从 ext 回填（抽样）
SELECT child.id, tr.distribution_object_group_id, ext.distribution_object_group_id
FROM task_definition child
JOIN task_definition pkg ON pkg.id = child.parent_id
JOIN task_rule tr ON tr.id = child.rule_id
LEFT JOIN task_package_distribution_ext ext ON ext.task_package_def_id = pkg.id AND ext.is_deleted = 0
WHERE child.task_type = 'TASK' AND child.is_deleted = 0
  AND ext.distribution_object_group_id IS NOT NULL
  AND (tr.distribution_object_group_id IS NULL OR tr.distribution_object_group_id = '');
```

---

## 五、对 Job / 明细 / 快照的影响矩阵

| 模块 | 1.4 前读什么 | 1.4 后读什么 | 改造任务 |
|------|-------------|-------------|---------|
| 分群下发 Job | 包 ext + 包 rule.is_repeat | **仅包层** `task_package_distribution_ext` 一次 doLatest；子 TASK 不绑定下发群；去重仅读包 rule.repeat_window_type | TGR-011（口径修订：包层下发） |
| 完成判定（对象群） | 包 rule.distribution_object_group | TASK rule.completion_object_group + membership_operator | TGR-009 |
| 去重 | 包 rule.is_repeat | **仅任务包** rule.repeat_window_type：MONTH/DAYS/GLOBAL（默认 MONTH）；不读子 TASK | TGR-008（已落地，口径修订：包层去重） |
| 判断截止 | task_judgment_deadline RELATIVE/ABSOLUTE | + AFTER_TASK_DEADLINE | TGR-010 |
| 快照写侧 | task_package_id 维度 | + task_group_id 维度 | TGR-017 |
| 明细列表筛选 | task_package_id | 按 taskGroupId 时 JOIN 包.task_group_id | TGR-014 |

**TGR-008/011**：下发对象群与去重窗口均只读**任务包**（ext + 包 `repeat_window_type`）；完成群判定仍属 TGR-009（子 TASK）。

---

## 六、API 与 spec 同步说明（TGR-001~003）

| 类型 | 入口 | 文档 |
|------|------|------|
| 迁移 Job | XXL `migrateTaskGroupStructure` | `doc/任务组_test_spec.md` §一 |
| 读侧变更 | `POST /sales/task/rule/detail|list` → TaskRuleDTO 新字段 | `doc/condition_action_task_rule_test_spec.md` |
| 读侧变更 | `POST /sales/task/definition/detail|list` → taskGroupId、taskRuleList 新字段 | `doc/task_definition_test_spec.md` |
| 明细无组 id | `POST /sales/task/distribution/detail/*` | `doc/task_distribution_detail_test_spec.md` |
| 待新增 | `POST /sales/task/group/*` CRUD | `doc/任务组_test_spec.md` §二（TGR-004） |
| 写路径 | createPackage/updatePackage/createTask + taskGroupId | `doc/task_definition_test_spec.md`（TGR-007 / TGR-028 必填） |
| 前端 | 任务规则配置（下发标准/完成标准） | Comm-Divisor-Service `task-package-rules/createOrEdit`（TGR-028） |

---

## 七、API 兼容策略（后续任务）

| API | 变更 |
|-----|------|
| `createTaskGroup` / `updateTaskGroup` / `listTaskGroup` | 新增（TGR-004） |
| `createPackage` / `updatePackage` | **必填** `taskGroupId`（TGR-028；原 TGR-007 可选已加严） |
| `createTask` / `updateTask` | 任务层独立配置（TGR-007） |
| `definition/list` + taskType=PACKAGE | **不可**当作任务组列表；前端对外称「任务规则管理」 |

---

## 八、回归用例（结构 / 迁移）

### TGR-MIG-01：迁移 Job 首次执行

- **前置**：存量 PACKAGE 无 `task_group_id`；已执行 TGR-002 DDL。
- **操作**：触发 XXL-JOB `migrateTaskGroupStructure`。
- **预期**：
  - 每个 PACKAGE 对应 1 条 `task_group`；
  - `task_definition.task_group_id`、`task_rule.task_group_id` 已回写；
  - 子 TASK 规则已从 ext/包规则回填下发与截止字段；
  - `completion_standard_type` 已按 has_action 映射；
  - 响应/日志含 `groupsCreated`、`rulesUpdated`、`childRulesBackfilled` 等计数 > 0。

### TGR-MIG-02：迁移 Job 幂等重跑

- **前置**：TGR-MIG-01 已成功。
- **操作**：再次触发 `migrateTaskGroupStructure`。
- **预期**：`groupsCreated=0`；无重复 task_group；数据与首次一致。

### TGR-DDL-01：task_group 表结构

- **验证**：`group_code` 唯一索引；`group_name` 非空；审计字段存在。

### TGR-DDL-02：task_rule 新字段

- **验证**：`completion_standard_type`、`membership_operator`、`repeat_window_type`、`task_group_id` 列存在；注释与 §二 一致。

### TGR-DDL-03：completion_standard_type 枚举

- **入参示例**（createTask 阶段，TGR-007 落地后）：
  ```json
  {
    "taskPackageId": 100,
    "taskName": "巡店任务",
    "taskRule": {
      "completionStandardType": "OBJECT_GROUP",
      "completionObjectGroupId": "G2001",
      "completionObjectGroupName": "完成判定门店群",
      "membershipOperator": "NOT_IN"
    }
  }
  ```
- **预期**：`OBJECT_GROUP` 时三者必填；其他类型可空。

### TGR-028-01：createPackage 关联任务组必填

- **操作**：`POST /sales/task/definition/createPackage` 不传 `taskGroupId` 或传 `null`。
- **预期**：校验失败（`taskGroupId 不能为空`）；传有效 id 时 PACKAGE 与包规则 `task_rule.task_group_id` 一致。

### TGR-028-02：完成标准基于对象群可保存回显

- **操作**：createPackage/`updatePackage` 子任务 `tasks[].taskRule.completionStandardType=OBJECT_GROUP`，带完成群 + `membershipOperator`。
- **预期**：落库成功；detail 回显三选一为基于对象群及成员关系/完成群；与下发对象群字段分离。

---

## 九、关联文档

- 任务组 CRUD / 迁移 Job：`doc/任务组_test_spec.md`
- 任务包/任务定义读写字段：`doc/task_definition_test_spec.md`
- 任务规则 DTO 字段：`doc/condition_action_task_rule_test_spec.md`
- 下发明细（无 task_group_id）：`doc/task_distribution_detail_test_spec.md`
- 条件动作规则判断截止扩展：`doc/condition_action_task_rule_test_spec.md`（TGR-010）
