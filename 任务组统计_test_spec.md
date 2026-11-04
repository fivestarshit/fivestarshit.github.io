# 任务组统计测试规格（TGR-017 / TGR-019 / TGR-020）

> **变更说明（2026-08-10）**  
> 快照主维度新增**任务组**（`task_stats_snapshot_group_perf`）；现有 `package_perf` / 非末级 `org_perf` **保留不推倒**。  
> 末级部门组织表现改为按**网点负责人**汇总；反馈原因按 `feedback_reason_content` 优先分桶。  
>
> **变更说明（2026-08-11）**  
> 快照版本指针：各快照表含 `build_id`；读侧（含 `group_perf` / `owner_perf` / `package_perf`）按 `task_stats_snapshot_build_pointer` 当前版本过滤，与任务包统计主规格一致。  
>
> **变更说明（2026-08-11）**  
> `group_perf` / `groupPerformance` 增加 **关联规则数 `linkedRuleCount`**：组下关联 PACKAGE 的子 TASK 条数（与任务组列表口径一致）；写侧落库，读侧合并取 max；须 DDL 并重跑快照。

---

## 一、TGR-017：任务组维度快照

### 1.1 DDL / 表

| 项 | 说明 |
|----|------|
| 冗余列 | `task_stats_snapshot_summary` / `trend_daily` / `feedback_reason` / `org_perf` / `package_perf` 增加 `task_group_id BIGINT NOT NULL DEFAULT 0`（及索引）；**不改原 UNIQUE KEY** |
| 新表 | `task_stats_snapshot_group_perf`：对齐 package_perf，维度含 `parent_department_code` + `owning_department_code` + `object_code` + `task_execution_type` + **`task_group_id`/`task_group_name`** + **`linked_rule_count`** |
| 写侧解析 | 明细不冗余组 id；Job 经 `task_package_id → PACKAGE.task_group_id → task_group`；无组时 `task_group_id=0`、`task_group_name=未关联任务组` |
| 包维保留 | `task_stats_snapshot_package_perf` 与 `/packagePerformance`、`/taskPackageOptions` 继续可用 |

### 1.2 接口：任务组表现

- **接口**：`POST /sales/task/statistics/groupPerformance`
- **请求示例**：
  ```json
  {
    "page": 1,
    "//page": "页码，默认 1",
    "pageSize": 20,
    "//pageSize": "每页条数，默认 20",
    "deptCode": "D001",
    "//deptCode": "架构树选中部门；未传时默认营销中心",
    "taskMonth": "2026-08",
    "//taskMonth": "任务截止月份 yyyy-MM",
    "objectCode": "STORE",
    "//objectCode": "任务对象编码，可选",
    "taskExecutionType": "VISIT",
    "//taskExecutionType": "任务执行类型，可选",
    "taskGroupId": 1001,
    "//taskGroupId": "任务组ID（来自 task_group，≠ 任务包ID）；可选筛选",
    "taskPackageId": null,
    "//taskPackageId": "包维筛选字段保留；组维接口不依赖它"
  }
  ```
- **成功响应**：
  ```json
  {
    "code": 0,
    "//code": "0=成功",
    "message": "success",
    "//message": "提示信息",
    "data": {
      "records": [
        {
          "taskGroupId": 1001,
          "//taskGroupId": "任务组ID",
          "taskGroupName": "Q3华东策略组",
          "//taskGroupName": "任务组名称；0 时为「未关联任务组」",
          "linkedRuleCount": 3,
          "//linkedRuleCount": "关联规则数：组下关联包的子TASK数（仅task_type=TASK）",
          "totalCount": 100,
          "//totalCount": "总任务数（合并后）",
          "completedCount": 80,
          "//completedCount": "已完成数",
          "completionRate": 0.8,
          "//completionRate": "完成率=completed/total",
          "timelinessRate": 0.75,
          "//timelinessRate": "反馈率=分子/分母",
          "topFeedbackReason": "客户不在",
          "//topFeedbackReason": "主要反馈原因（content 优先分桶）"
        }
      ],
      "total": 5,
      "//total": "总条数",
      "page": 1,
      "//page": "当前页",
      "pageSize": 20,
      "//pageSize": "每页条数",
      "totalPage": 1,
      "//totalPage": "总页数"
    }
  }
  ```

### 1.3 接口：任务组下拉

- **接口**：`POST /sales/task/statistics/taskGroupOptions`
- **说明**：从 `group_perf` 去重；**禁止**用 PACKAGE list 冒充任务组。
- **请求示例**：
  ```json
  {
    "deptCode": "D001",
    "//deptCode": "部门编码",
    "taskMonth": "2026-08",
    "//taskMonth": "任务截止月份",
    "keyword": "华东",
    "//keyword": "按任务组名称模糊过滤，可选"
  }
  ```

### 1.4 overview 聚合

- **接口**：`POST /sales/task/statistics/overview`
- **预期**：响应新增 `groupPerformance` 列表；**保留** `packagePerformance`。
- **筛选**：公共请求可带 `taskGroupId`，快照读侧 `applyDimensionFilters` / package&group 过滤器按 `task_group_id` 过滤。

### 1.5 用例

| 用例 | 操作 | 预期 |
|------|------|------|
| TGR-017-01 | 刷新快照后查 `group_perf` | 同组多包、多 object_code 分行；`task_group_id` 正确 |
| TGR-017-02 | overview 带 `taskGroupId` | cards/trend/feedback/org/group 按组过滤；包维接口仍可用 |
| TGR-017-03 | 无组 PACKAGE 明细 | 归 `taskGroupId=0` /「未关联任务组」 |
| TGR-017-04 | taskGroupOptions | 返回组 id/名称，不为包 id |
| TGR-017-05 | 非末级 orgPerformance + `taskGroupId` | `org_perf.task_group_id` 已写入（含 upsert 中段落盘）；筛组后有下级部门行；历史 0 需回填或 refreshSnapshot |

---

## 二、TGR-019：末级按负责人汇总

### 2.1 触发条件

- 与现逻辑一致：`applyDeptScope` + 必有 `deptCode`
- **仅当** `isLeafDepartment(deptCode)`（`deptLevel=6`）走负责人汇总
- **非末级**：仍读 `org_perf` 按直属下级部门汇总（不改）

### 2.2 口径（读侧优先快照）

1. **主路径**：读 `task_stats_snapshot_owner_perf`，条件 `owning_department_code = deptCode`（末级无下级，不用 parent=deptCode）  
2. 按 `user_master_id`（无则 `owner_id`）合并多维度行，重算完成率/反馈率  
3. 返回：`orgCode=userMasterId`，`orgName=ownerName`，`orgType=OWNER`；`UNASSIGNED` 为未分配  
4. **降级**：快照无行时才走实时扫明细 + `mapByAccountNos` / `mapByIds`（首刷前兼容）  
5. Job 写侧已在刷快照时查 DTS 并落 `user_master_id`/`owner_name`，读接口不再查码  
6. 分页排序：`completedCount` 降序（同现）

### 2.3 DDL

- 新表 `task_stats_snapshot_owner_perf`（Job 写；**读侧末级主查本表**）

### 2.4 接口：组织表现（末级）

- **接口**：`POST /sales/task/statistics/orgPerformance`
- **请求示例**（末级部门）：
  ```json
  {
    "page": 1,
    "//page": "页码",
    "pageSize": 20,
    "//pageSize": "每页条数",
    "deptCode": "LEAF_DEPT_001",
    "//deptCode": "末级部门编码（deptLevel=6）",
    "taskMonth": "2026-08",
    "//taskMonth": "任务截止月份",
    "objectCode": "STORE",
    "//objectCode": "建议 STORE；负责人链路基于门店 account",
    "taskGroupId": 1001,
    "//taskGroupId": "可选，按组过滤明细"
  }
  ```
- **成功响应（行结构）**：
  ```json
  {
    "code": 0,
    "//code": "0=成功",
    "message": "success",
    "//message": "提示",
    "data": {
      "records": [
        {
          "orgType": "OWNER",
          "//orgType": "负责人类型；非末级仍为 DEPT",
          "orgCode": "UM123456",
          "//orgCode": "人员主数据ID user_master_id__c；未分配为 UNASSIGNED",
          "orgName": "张三",
          "//orgName": "full_name；未分配为「未分配负责人」",
          "totalCount": 30,
          "//totalCount": "总任务数",
          "completedCount": 24,
          "//completedCount": "已完成数",
          "completionRate": 0.8,
          "//completionRate": "完成率",
          "timelinessRate": 0.7,
          "//timelinessRate": "反馈率"
        }
      ],
      "total": 12,
      "//total": "总条数",
      "page": 1,
      "//page": "当前页",
      "pageSize": 20,
      "//pageSize": "每页条数",
      "totalPage": 1,
      "//totalPage": "总页数"
    }
  }
  ```

### 2.5 用例

| 用例 | 操作 | 预期 |
|------|------|------|
| TGR-019-01 | 末级 + 已有 owner_perf | 读快照；行 orgType=OWNER；orgCode=userMasterId；不查 DTS |
| TGR-019-02 | 多维度同 userMasterId | 指标加总后重算完成率/反馈率 |
| TGR-019-03 | 快照中 UNASSIGNED | 归「未分配负责人」 |
| TGR-019-04 | 末级但快照为空 | 降级实时路径 |
| TGR-019-05 | 非末级 | 仍读 org_perf 下级部门，行为不变 |
| TGR-019-06 | 非末级 + `taskGroupId`（回归） | 依赖 org_perf 冗余 `task_group_id`；upsertAccumulate 必须写该列，否则组织表现为空 |

---

## 三、TGR-020：反馈按 content 分桶

### 3.1 Job 口径

- 适用：`accumulateFeedbackReason`、package/group TOP 原因  
- 桶键：优先 `feedback_reason_content.trim()` → 否则 `feedback_reason.trim()`  
- 仅 `isFeedbackRequiredDetail`（TASK 且 feedback_enabled）且 **已有原因文本** 计入；content/reason 皆空 **不统计**（与改前口径一致）  
- 快照列仍写 `feedback_reason` 字段（存桶键文本），**不改列名**

### 3.2 用例

| 用例 | 明细 | 预期桶键 |
|------|------|----------|
| TGR-020-01 | content=「临时有事」、reason=「其他」 | 临时有事 |
| TGR-020-02 | content 空、reason=「客户不在」 | 客户不在 |
| TGR-020-03 | content/reason 皆空（需反馈） | 不计入原因分布 |
| TGR-020-04 | 非需反馈明细 | 不计入原因分布 |

### 3.3 读侧校验

- **接口**：`POST /sales/task/statistics/feedbackReasonDistribution`
- 刷新快照后，原因文案应为 content 优先桶键；可与 group/package 的 `topFeedbackReason` 对照。

---

## 四、回归注意

- 不改任务包/任务规则「启用」以外状态逻辑  
- 不删除 `package_perf`  
- 列表类接口分页包装：`records/total/page/pageSize/totalPage`  
- DDL 累计文件：`dpc/sql/update_tables.sql`（日期 2026-08-10 · TGR-017/019/020）
