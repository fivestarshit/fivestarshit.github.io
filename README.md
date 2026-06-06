# sls-sales-task 文档说明

## 一、项目定位

**sls-sales-task** 是面向外勤销售场景的**销售任务管理系统**，服务「外勤动作中查看销售任务、列出外勤任务清单」等能力。

**业务愿景**：让销售巡店有重点，让管理有抓手——将销售动作拆解为可配置、可下发、可追踪、可复盘的任务体系，形成 **P（制定）→ D（执行）→ C（监控）→ A（复盘）** 的管理闭环。

| 维度 | 说明 |
|------|------|
| 技术栈 | Java 8、Spring Boot、MyBatis-Plus、Nacos、XXL-JOB、Redisson、Kafka、OpenFeign、Groovy |
| 接口风格 | REST + POST 分页（`page` / `pageSize` 默认 1/20），统一 `PageResult` 包装 |
| 文档约定 | 功能测试规格存于 `doc/*_test_spec.md`；表结构变更累计于 `dpc/sql/update_tables.sql` |

---

## 二、核心业务链路（从配置到执行）

从「数据准备」到「一线执行」的完整串列如下：

```
数据模板 → 字段映射 → 任务定义 → 任务规则/条件 → 下发明细 → 任务实例 → 状态流转/完成判定
```

### 步骤 1：配置数据模板（biz_template_config）

- **作用**：定义业务数据来源的结构、事件名称及执行规则，是数仓指标/外部数据进入任务体系的前置层。
- **关键能力**：模板 CRUD、字段明细（fieldDetails）批量 upsert、主键与映射校验。
- **相关接口**：`BizTemplateConfigController`（`/sales/task/biz/template/config/*`）
- **文档**：[biz_template_config_test_spec.md](./biz_template_config_test_spec.md)、[biz_template_config_controller_api_spec.md](./biz_template_config_controller_api_spec.md)

### 步骤 2：配置字段映射（biz_template_field_map）

- **作用**：承接数据模板返回的数据，定义**映射字段规则**；通过 `is_search_primary_key` 标识搜索主键，供任务明细 list/export 等筛选使用。
- **关键能力**：字段与模板关联、objectCode 去重、dataTypeDefinition（NUMBER/STRING/BOOLEAN/DATE）校验。
- **相关接口**：`BizTemplateFieldMapController`
- **文档**：[biz_template_config_test_spec.md](./biz_template_config_test_spec.md)（含 fieldDetails 章节）

### 步骤 3：创建任务定义（task_definition）

任务定义采用**三层结构**：

| taskType | 含义 | 说明 |
|----------|------|------|
| **PACKAGE** | 任务包 | 一次下发活动的容器，可含多个 TASK |
| **TASK** | 普通任务 | 绑定 `biz_template_config`、任务规则，可配置 Groovy 完成脚本 |
| **ACTION** | 动作 | 挂在 TASK 下的细粒度动作项 |
| **TEMPLATE** | 任务模板 | 存于独立表 `task_template_definition`，供快速复用配置 |

- **作用**：圈选下发对象、绑定数据模板与规则，是生成 `task_distribution_detail` 的配置源头。
- **关键能力**：`createPackage` 创建任务包及子任务、list/listStats 分页与统计、TEMPLATE 分支独立查询。
- **相关接口**：`TaskDefinitionController`（`/sales/task/definition/*`）
- **文档**：[task_definition_test_spec.md](./task_definition_test_spec.md)（核心，约 700+ 行）

### 步骤 4：配置规则与条件（task_rule + condition_repo）

- **task_rule（任务规则）**：定义下发类型（CRON/即时等）、完成判断方式、截止时间（含财季末月等特殊规则）。
- **condition_repo（条件库）**：通用条件片段，与模板字段、Groovy 脚本组合，用于前置条件组装。
- **相关接口**：`TaskRuleController`、`ConditionRepoController`
- **文档**：[condition_action_task_rule_test_spec.md](./condition_action_task_rule_test_spec.md)

### 步骤 5：生成任务下发明细（task_distribution_detail）

- **触发时机**：遍历 `task_instance`，到达 `distributed_at` 时，按任务包类型为每个（任务包 + 普通任务 + 目标实体）创建明细行。
- **作用**：一线外勤看到的**可执行任务清单**；关联 `task_package_id`、`task_def_id`、`object_code`、目标实体、归属部门等。
- **关键能力**：明细 list/export、状态统计、分群同步、部门路径补全、XXL-JOB 驱动状态迁移。
- **相关接口**：`TaskDistributionDetailController`
- **文档**：[task_distribution_detail_test_spec.md](./task_distribution_detail_test_spec.md)（约 680+ 行，含多篇 API/Job）

### 步骤 6：任务实例与条件匹配（task_instance）

- **作用**：运行时任务实例；Groovy 条件匹配 Job 扫描 `IN_PROGRESS` 实例，判定是否满足完成条件。
- **关键能力**：实例 CRUD、执行日志（execution_log）、条件匹配定时任务。
- **相关接口**：`TaskInstanceController`、`TaskInstanceExecutionLogController`
- **文档**：[condition_action_task_rule_test_spec.md](./condition_action_task_rule_test_spec.md)、[task_distribution_detail_test_spec.md](./task_distribution_detail_test_spec.md) 第二篇

---

## 三、功能模块一览

### 3.1 模板与数据源

| 模块 | 说明 | 测试文档 |
|------|------|----------|
| **biz_template_config** | 业务数据模板配置 | [biz_template_config_test_spec.md](./biz_template_config_test_spec.md) |
| **biz_template_field_map** | 模板字段映射 | 同上 |
| **datasource_connection** | 数据源连接管理 | [datasource_template_test_spec.md](./datasource_template_test_spec.md) |
| **trial_data_config** | 试用/试跑数据配置 | [trial_data_config_test_spec.md](./trial_data_config_test_spec.md) |

### 3.2 任务定义与模板

| 模块 | 说明 | 测试文档 |
|------|------|----------|
| **task_definition** | 任务包/任务/动作定义 | [task_definition_test_spec.md](./task_definition_test_spec.md) |
| **task_template_definition** | 任务模板（TEMPLATE 类型） | [task_template_test_spec.md](./task_template_test_spec.md) |

### 3.3 规则、条件与筛选

| 模块 | 说明 | 测试文档 |
|------|------|----------|
| **task_rule** | 下发/完成/截止规则 | [condition_action_task_rule_test_spec.md](./condition_action_task_rule_test_spec.md) |
| **condition_repo** | 条件库 | 同上 |
| **field_filter_operator** | 字段筛选操作符枚举 | [field_filter_operator_test_spec.md](./field_filter_operator_test_spec.md) |

### 3.4 下发、实例与 Job

| 模块 | 说明 | 测试文档 |
|------|------|----------|
| **task_distribution_detail** | 下发明细、状态、统计 | [task_distribution_detail_test_spec.md](./task_distribution_detail_test_spec.md) |
| **task_instance** | 任务实例、条件匹配 | [condition_action_task_rule_test_spec.md](./condition_action_task_rule_test_spec.md) |
| **XXL-JOB** | 状态迁移、分群同步、过期、部门补全等 | [task_distribution_detail_test_spec.md](./task_distribution_detail_test_spec.md) |

主要定时任务（节选）：

- `syncReadyPackagesAndTasksToInProgress` — 任务包/TASK 就绪 → 进行中
- `syncPackageTaskStatusCompleted` — 到期/完成状态同步
- `expireInProgressDetailsPastEndTime` — 超 end_time 明细过期
- `syncInProgressPackagesByCrowd` — 按分群同步进行中任务包
- `evaluateConditionMatchForInProgressTaskInstances` — Groovy 条件匹配
- `syncTaskDistributionDetailOwningDepartment` — 明细归属部门补全

### 3.5 Groovy 与动态 HTTP

| 模块 | 说明 | 测试文档 |
|------|------|----------|
| **groovy_script_instance** | Groovy 脚本实例管理 | [groovy_script_instance_test_spec.md](./groovy_script_instance_test_spec.md) |
| **groovy_shell** | 脚本执行/联调测试接口 | [groovy_shell_test_spec.md](./groovy_shell_test_spec.md) |
| **groovy_snippets** | 可复用脚本片段库 | [groovy_snippets/README.md](./groovy_snippets/README.md) |
| **dynamic_http_endpoint** | 动态 HTTP 外部接口配置 | [dynamic_http_endpoint_test_spec.md](./dynamic_http_endpoint_test_spec.md) |
| **dynamic_http_endpoint_group** | HTTP 端点分组 | [dynamic_http_group_test_spec.md](./dynamic_http_group_test_spec.md) |

### 3.6 外部集成

| 模块 | 说明 | 测试文档 |
|------|------|----------|
| **data_crowd** | 数仓分群圈选 | [data_crowd_test_spec.md](./data_crowd_test_spec.md) |
| **ehr_department** | EHR 部门树 | [ehr_department_test_spec.md](./ehr_department_test_spec.md) |
| **auth** | JWT + OP 双链路认证 | [auth_interceptor_test_spec.md](./auth_interceptor_test_spec.md) |
| **kafka** | 消息推送/巡店照片消费 | [kafka_test_push_spec.md](./kafka_test_push_spec.md)、[sfa_tour_device_photos_kafka_test_spec.md](./sfa_tour_device_photos_kafka_test_spec.md) |

---

## 四、PDCA 与系统能力对应

| 阶段 | 业务含义 | 系统模块 |
|------|----------|----------|
| **P · 制定** | 配置模板、任务包、规则，圈选下发对象 | task_definition、task_rule、template、data_crowd |
| **D · 执行** | 明细触达门店/人员，外勤按清单完成 | task_distribution_detail、task_instance、Groovy |
| **C · 监控** | 查看下发/完成进度，Job 驱动状态准确 | listStats、status Job、分群同步 |
| **A · 复盘** | 基于执行明细优化下一轮任务规划 | execution_log、completion_judgment、统计缓存 |

---

## 五、快速创建一条完整任务（操作顺序）

适用于联调或新人上手，按以下顺序配置即可跑通「配置 → 下发 → 执行」：

1. **创建数据模板** `biz_template_config`，并配置 `biz_template_field_map`（含 `is_search_primary_key`）。
2. **（可选）配置条件库** `condition_repo`、**任务规则** `task_rule`（下发时间、完成判定、截止时间）。
3. **创建任务包** `POST .../definition/createPackage`：PACKAGE + 若干 TASK，TASK 绑定模板与规则。
4. **等待/触发下发**：任务实例到达 `distributed_at` 后，Job 或接口触发，生成 `task_distribution_detail`。
5. **外勤执行 & 监控**：明细状态由 Job 与 Groovy 条件匹配驱动流转；管理端通过 list/listStats 查看进度。

详细接口参数、JSON 示例、边界用例见各模块 `*_test_spec.md` 文件。

---

## 六、文档索引

| 类型 | 路径 | 说明 |
|------|------|------|
| 研发提效总结（HTML） | [ai_rd_efficiency_summary.html](./ai_rd_efficiency_summary.html) | AI 协作实践、Rules、优化方向 |
| Markdown 预览页 | [md-viewer.html](./md-viewer.html) | 附录 md 链接经此页 UTF-8 渲染；本地建议 `cd doc && python3 -m http.server 8765` 后访问 |
| 表结构变更 | [../dpc/sql/update_tables.sql](../dpc/sql/update_tables.sql) | DDL 累计追加 |
| 模板表变更记录 | [sql/task_template_definition_change.md](./sql/task_template_definition_change.md) | 字段级变更说明 |
| 全部 test_spec | 本目录 `*_test_spec.md` | 各模块接口用例、Job、回归场景 |

更完整的文档列表与描述见 HTML 总结页 [附录：文档索引](./ai_rd_efficiency_summary.html#appendix)。

---

## 七、维护约定

- 功能变更 → 更新对应 `doc/[模块]_test_spec.md`，在文档顶部追加**变更说明**。
- 新增场景 → 补充用例与 JSON 示例（字段加 `//` 注释说明含义）。
- 问题修复 → 增加**回归用例**描述。
- 表结构变更 → 在 `dpc/sql/update_tables.sql` 追加 SQL，并在 spec 中说明影响。
