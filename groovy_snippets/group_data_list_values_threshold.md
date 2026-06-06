# groupDataList / values 二维表数量阈值判定

## 适用场景

- **DELAY 同步**或 **completion_script** 中，源数据经 DynamicHttp 映射后注入变量 **`data`**（或与脚本约定一致的结构）。
- 数据结构为：`data.groupDataList` 为列表；取**第一组**的 **`values`** 为二维行列表。
- 每一行形如 `[ "WD11010068", 8.0 ]`：第 0 列为编码/标识，第 **1 列为数量**（数值）。
- 业务规则：**任意一行**的数量列 **≥ 2.8** 即视为满足条件，脚本返回 **`true`**；结构不合法或无数值满足时返回 **`false`**。

## 说明要点

1. 使用安全导航 `?.` 与 `instanceof List` 校验，避免 NPE 或非预期类型。
2. 仅检查 **`groups[0].values`**，多组场景若需遍历所有组需自行扩展循环。
3. 数量比较要求第 2 列（下标 1）为 **`Number`** 类型且与 `2.8` 比较（Groovy 会按数值比较）。

## 代码片段

```groovy
def groups = data?.groupDataList
if (!(groups instanceof List) || groups.isEmpty()) {
  return false
}

def values = groups[0]?.values
if (!(values instanceof List) || values.isEmpty()) {
  return false
}

// values 每一项形如 ["WD11010068", 8.0]
// 只要存在任意一项数量(第2列) >= 2.8 即返回 true
return values.any { row ->
  row instanceof List &&
    row.size() >= 2 &&
    row[1] instanceof Number &&
    row[1] >= 2.8
}
```
