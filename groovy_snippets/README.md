# 常用 Groovy 代码片段

本目录存放任务/模板联调中可复用的 **Groovy 片段**（如 `completion_script`、DynamicHttp 后处理、条件脚本等），按场景分文件记录，便于检索与复制。

| 文件 | 场景简述 |
|------|----------|
| [group_data_list_values_threshold.md](./group_data_list_values_threshold.md) | 从 `data.groupDataList` 取首组 `values` 二维表，按第二列数值阈值判断是否满足完成条件 |
| [condition_detail_mapped_results_match.md](./condition_detail_mapped_results_match.md) | 将 `conditionDetailList` 与 `mappedResults` 做字段级匹配（含按 `index` 分组、多运算符与多值） |
