# task_template_definition 字段变更记录

## 2026-04-07 删除 `task_status`

- **表**：`task_template_definition`
- **字段**：`task_status`
- **变更**：删除字段
- **原因**：模板定义仅承载配置，不维护运行态；运行态由下发明细/实例等运行时表体现。

对应 SQL 见：`dpc/sql/update_tables.sql`

