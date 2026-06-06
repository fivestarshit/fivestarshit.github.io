# conditionDetailList 与 mappedResults 条件匹配（field_filter_operator 操作符码）

## 适用场景

- 接口 `POST /sales/task/template/fieldMap/testTaskDistributionByDynamicGroup` 中，请求体 **`code`**（Groovy）与 **`conditionDetailList`**（或 `conditionRepos` 映射后的条件明细）配合 **`mappedResults`** 做完成/条件判定。
- **`conditionDetailList[].operator`** 取值与表 **`field_filter_operator.operator_code`** 一致（见 `doc/sql/update_tables.sql` 596–611 行）：
  - `=`、`!=`、`>`、`>=`、`<`、`<=`
  - `BETWEEN`、`NOT_BETWEEN`
  - `IS_NULL`、`IS_NOT_NULL`
  - `IS_ANY_OR`、`IS_NOT_ALL_AND`
  - `CONTAINS`、`NOT_CONTAINS`
  - `BEFORE`、`AFTER`
- **`defaultValue`** 为集合，元素形如 `{ "value": "1" }`；多值时语义见下表。

## defaultValue 与多值语义

| operator | defaultValue 示例 | 语义 |
|----------|-------------------|------|
| `=` / `!=` / 比较符 | 1 个元素 | 与单值比较 |
| `IS_ANY_OR` | `[{value:1},{value:2}]` | 实际值 **等于任一** 期望值（或关系） |
| `IS_NOT_ALL_AND` | 多个元素 | 实际值 **不等于每一个** 期望值（且关系） |
| `CONTAINS` | 多个元素 | 实际字符串 **包含任一** 模式（或关系；支持 `%`/`_` 或子串包含） |
| `NOT_CONTAINS` | 多个元素 | 实际字符串 **不包含每一个** 模式（且关系） |
| `BETWEEN` / `NOT_BETWEEN` | **至少 2 个**元素 | 取前两个为下界、上界（闭区间 `[low, high]`） |
| `IS_NULL` / `IS_NOT_NULL` | 可忽略 | 判空 / 非空 |

## index 分组

与原版一致：若 `mappedResults` 含非空 **`index`**，按 index 分组，要求 **存在某一 index 分组** 使该组下（及对无 index 行的回退）**全部条件**同时成立。

## 代码片段（可直接作为 `code` 入参）

```groovy
def toStr = { v -> v == null ? null : String.valueOf(v).trim() }
def isBlank = { v ->
  def s = toStr(v)
  return s == null || s.length() == 0
}
def toBig = { v ->
  def s = toStr(v)
  if (s == null || s.length() == 0) return null
  try { return new BigDecimal(s) } catch (ignored) { return null }
}
def pickExpected = { dv ->
  if (dv instanceof Map) return dv.get('value')
  if (dv instanceof List) {
    if (dv.isEmpty()) return null
    if (dv.size() == 1) {
      def first = dv[0]
      return first instanceof Map ? first.get('value') : first
    }
    return null
  }
  return dv
}
def expectedList = { dv ->
  if (dv instanceof List) {
    return dv.collect { one -> one instanceof Map ? toStr(one.get('value')) : toStr(one) }
             .findAll { it != null }
  }
  def one = pickExpected(dv)
  return one == null ? [] : [toStr(one)]
}
def likeMatches = { a, p ->
  if (a == null || p == null) return false
  def regex = new StringBuilder('(?s)^')
  for (int i = 0; i < p.length(); i++) {
    def ch = p.charAt(i)
    if (ch == (char)'%') { regex.append('.*') }
    else if (ch == (char)'_') { regex.append('.') }
    else { regex.append(java.util.regex.Pattern.quote(String.valueOf(ch))) }
  }
  regex.append('$')
  return (a ==~ regex.toString())
}
def normLikePat = { patStr ->
  def pat = patStr
  if (pat != null && pat.length() > 0 && !pat.contains('%') && !pat.contains('_')) {
    pat = '%' + pat + '%'
  }
  return pat
}
def containsPat = { actual, patStr ->
  if (isBlank(actual) || isBlank(patStr)) return false
  def pat = normLikePat(patStr)
  if (pat.contains('%') || pat.contains('_')) {
    return likeMatches(actual, pat)
  }
  return actual.contains(patStr)
}
def compareValue = { a, b ->
  def ba = toBig(a)
  def bb = toBig(b)
  if (ba != null && bb != null) return ba.compareTo(bb)
  def sa = toStr(a)
  def sb = toStr(b)
  if (sa == null || sb == null) return null
  return sa <=> sb
}
def betweenInclusive = { actual, low, high ->
  def c1 = compareValue(actual, low)
  def c2 = compareValue(actual, high)
  if (c1 == null || c2 == null) return false
  return c1 >= 0 && c2 <= 0
}
def normOp = { op ->
  def s = toStr(op)
  if (s == null) return null
  if (s.equalsIgnoreCase('EQ')) return '='
  if (s.equalsIgnoreCase('NE')) return '!='
  if (s.equalsIgnoreCase('GT')) return '>'
  if (s.equalsIgnoreCase('GTE') || s.equalsIgnoreCase('GE')) return '>='
  if (s.equalsIgnoreCase('LT')) return '<'
  if (s.equalsIgnoreCase('LTE') || s.equalsIgnoreCase('LE')) return '<='
  if (s.equalsIgnoreCase('LIKE')) return 'CONTAINS'
  return s
}
def matchActual = { cond, actual ->
  def op = normOp(cond?.operator)
  def dv = cond?.defaultValue
  def es = expectedList(dv)
  if (op == 'IS_NULL') return isBlank(actual)
  if (op == 'IS_NOT_NULL') return !isBlank(actual)
  if (op == 'IS_ANY_OR') {
    if (es.isEmpty()) return false
    return es.any { e -> actual == e }
  }
  if (op == 'IS_NOT_ALL_AND') {
    if (es.isEmpty()) return true
    return es.every { e -> actual != e }
  }
  if (op == 'CONTAINS') {
    if (isBlank(actual) || es.isEmpty()) return false
    return es.any { pat -> containsPat(actual, pat) }
  }
  if (op == 'NOT_CONTAINS') {
    if (isBlank(actual)) return true
    if (es.isEmpty()) return true
    return es.every { pat -> !containsPat(actual, pat) }
  }
  if (op == 'BETWEEN') {
    if (es.size() < 2) return false
    return betweenInclusive(actual, es[0], es[1])
  }
  if (op == 'NOT_BETWEEN') {
    if (es.size() < 2) return false
    return !betweenInclusive(actual, es[0], es[1])
  }
  def expected = es.isEmpty() ? toStr(pickExpected(dv)) : es[0]
  if (op == '=') {
    if (es.size() > 1) return es.contains(actual)
    return actual == expected
  }
  if (op == '!=') {
    if (es.size() > 1) return !es.contains(actual)
    return actual != expected
  }
  def cmp = compareValue(actual, expected)
  if (cmp == null) return false
  if (op == '>') return cmp > 0
  if (op == '>=') return cmp >= 0
  if (op == '<') return cmp < 0
  if (op == '<=') return cmp <= 0
  if (op == 'BEFORE') return cmp < 0
  if (op == 'AFTER') return cmp > 0
  return false
}
def evalOne = { cond, rows ->
  def fieldCode = toStr(cond?.fieldCode)
  def op = normOp(cond?.operator)
  if (!fieldCode || !op) return false
  def hits = (rows ?: []).findAll { r -> toStr(r?.mappedCol) == fieldCode }
  if (!hits) return false
  if (op == 'IS_NULL') {
    return hits.any { h -> isBlank(h?.mappedColVal) }
  }
  if (op == 'IS_NOT_NULL') {
    return hits.any { h -> !isBlank(h?.mappedColVal) }
  }
  return hits.any { h -> matchActual(cond, toStr(h?.mappedColVal)) }
}
def conds = (conditionDetailList ?: [])
if (!conds) return true
def rows = (mappedResults ?: [])
if (!rows) return false
def grouped = rows.groupBy { it?.index }
def nullRows = grouped[null] ?: []
def indexedKeys = grouped.keySet().findAll { it != null }
if (!indexedKeys) {
  return conds.every { c -> evalOne(c, rows) }
}
return indexedKeys.any { idx ->
  def idxRows = grouped[idx] ?: []
  conds.every { c ->
    def f = toStr(c?.fieldCode)
    def hasIndexed = idxRows.any { r -> toStr(r?.mappedCol) == f }
    def scope = hasIndexed ? idxRows : nullRows
    evalOne(c, scope)
  }
}
```

## 测试示例（testTaskDistributionByDynamicGroup）

```json
{
  "code": "<上述 Groovy 片段>",
  "conditionDetailList": [
    {
      "fieldCode": "quantity",
      "operator": ">=",
      "defaultValue": [{ "value": "10" }]
    },
    {
      "fieldCode": "status",
      "operator": "IS_ANY_OR",
      "defaultValue": [{ "value": "1" }, { "value": "2" }]
    }
  ],
  "mappedResults": [
    { "mappedCol": "quantity", "mappedColVal": "12", "index": 0 },
    { "mappedCol": "status", "mappedColVal": "2", "index": 0 }
  ]
}
```

预期：`groovyResult` 为 `true`。
