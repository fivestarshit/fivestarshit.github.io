# conditionDetailList 与 mappedResults 条件匹配（含 index 分组）

## 适用场景

- 任务完成或条件评估脚本中，已注入 **`conditionDetailList`**（条件库明细列表，含 `fieldCode`、`operator`、`defaultValue` 等）与 **`mappedResults`**（字段映射结果行，含 `mappedCol`、`mappedColVal`，可选 **`index`**）。
- 需对「条件列表」与「映射结果行」做 **EQ / NE / LIKE / GT / GTE / LT / LTE** 及 **OR（多期望值包含）** 等运算；支持 **`defaultValue`** 为单值、列表或 `{ value: ... }` 结构。
- 当 **`mappedResults` 中存在非空 `index`** 时：按 `index` **分组**，要求 **存在某一索引分组**，使得该分组下（及对无索引行的回退逻辑）**全部条件**同时成立；若无 `index` 字段或全部为空，则退化为**扁平列表**上对每个条件 `evalOne` 全部满足。

## 说明要点

1. **`toStr` / `toBig`**：字符串规范化与数值解析，避免类型不一致导致误判。
2. **`pickExpected` / `expectedList`**：从 `defaultValue` 中取出期望值或期望值列表（兼容 Map 包裹的 `value`）。
3. **`likeMatches`**：将 SQL 风格 **`%` / `_`** 转为正则，实现 LIKE 语义（`(?s)^...$` 单行/多行按模式匹配）。
4. **`evalOne(cond, rows)`**：在指定 `rows` 子集上按 `fieldCode` 筛行，再按运算符比较；**OR** 表示多值中任一命中即可。
5. **多值 `defaultValue`（List 且 size>1）**：与 EQ/NE/LIKE/数值比较时按「多期望值」语义处理（见脚本内分支）。
6. **`groupBy { it?.index }`**：有索引时，`indexedKeys.any { ... }` 表示「至少一组 index 下全部条件成立」；每条条件在「当前 index 行有该 field」时用 `idxRows`，否则用 `null` index 的 `nullRows` 参与判定。

## 代码片段

```groovy
def toStr = { v -> v == null ? null : String.valueOf(v).trim() }
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
def evalOne = { cond, rows ->
    def fieldCode = toStr(cond?.fieldCode)
    def op = toStr(cond?.operator)
    if (!fieldCode || !op) return false
    def hits = (rows ?: []).findAll { r -> toStr(r?.mappedCol) == fieldCode }
    if (!hits) return false
    if (op.equalsIgnoreCase('OR')) {
        def es = expectedList(cond?.defaultValue)
        return hits.any { h -> es.contains(toStr(h?.mappedColVal)) }
    }
    def actual = toStr(hits[0]?.mappedColVal)
    def dv = cond?.defaultValue
    def isMulti = dv instanceof List && dv.size() > 1
    if (isMulti) {
        def es = expectedList(dv)
        if (op.equalsIgnoreCase('EQ')) return es.contains(actual)
        if (op.equalsIgnoreCase('NE')) return !es.contains(actual)
        if (op.equalsIgnoreCase('LIKE')) {
            return es.any { patStr ->
                def pat = patStr
                if (pat != null && pat.length() > 0 && !pat.contains('%') && !pat.contains('_')) {
                    pat = '%' + pat + '%'
                }
                return likeMatches(actual, pat)
            }
        }
        def a = toBig(actual)
        if (a == null) return false
        if (op.equalsIgnoreCase('GT')) return es.any { e -> def eb = toBig(e); eb != null && a > eb }
        if (op.equalsIgnoreCase('GTE') || op.equalsIgnoreCase('GE')) return es.any { e -> def eb = toBig(e); eb != null && a >= eb }
        if (op.equalsIgnoreCase('LT')) return es.any { e -> def eb = toBig(e); eb != null && a < eb }
        if (op.equalsIgnoreCase('LTE') || op.equalsIgnoreCase('LE')) return es.any { e -> def eb = toBig(e); eb != null && a <= eb }
        return false
    }
    def expected = toStr(pickExpected(dv))
    if (op.equalsIgnoreCase('EQ')) return actual == expected
    if (op.equalsIgnoreCase('NE')) return actual != expected
    if (op.equalsIgnoreCase('LIKE')) {
        def pat = expected
        if (pat != null && pat.length() > 0 && !pat.contains('%') && !pat.contains('_')) {
            pat = '%' + pat + '%'
        }
        return likeMatches(actual, pat)
    }
    def a = toBig(actual)
    def e = toBig(expected)
    if (a == null || e == null) return false
    if (op.equalsIgnoreCase('GT')) return a > e
    if (op.equalsIgnoreCase('GTE') || op.equalsIgnoreCase('GE')) return a >= e
    if (op.equalsIgnoreCase('LT')) return a < e
    if (op.equalsIgnoreCase('LTE') || op.equalsIgnoreCase('LE')) return a <= e
    return false
}
def conds = (conditionDetailList ?: [])
if (!conds) return true
def rows = (mappedResults ?: [])
if (!rows) return false
def grouped = rows.groupBy { it?.index }
def indexedKeys = grouped.keySet().findAll { it != null }
if (!indexedKeys) {
    return conds.every { c -> evalOne(c, rows) }
}
return indexedKeys.any { idx ->
    def idxRows = grouped[idx] ?: []
    def nullRows = grouped[null] ?: []
    conds.every { c ->
        def f = toStr(c?.fieldCode)
        def hasIndexed = idxRows.any { r -> toStr(r?.mappedCol) == f }
        evalOne(c, hasIndexed ? idxRows : nullRows)
    }
}
```

针对商品名称特殊like处理, 商品名字里OR+LIKE 逻辑 
```groovy 
def toStr = { v -> v == null ? null : String.valueOf(v).trim() }
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
def sameCond = { a, b ->
  if (a == null || b == null) return false
  try { if (a.is(b)) return true } catch (ignored) {}
  def ca = toStr(a?.conditionCode)
  def cb = toStr(b?.conditionCode)
  if (ca && ca.length() > 0 && ca == cb) return true
  def ia = a?.id
  def ib = b?.id
  return ia != null && ia == ib
}
def matchActual = { cond, actual ->
  def op = toStr(cond?.operator)
  def dv = cond?.defaultValue
  def isMulti = dv instanceof List && dv.size() > 1
  if (isMulti) {
    def es = expectedList(dv)
    if (op.equalsIgnoreCase('EQ')) return es.contains(actual)
    if (op.equalsIgnoreCase('NE')) return !es.contains(actual)
    if (op.equalsIgnoreCase('LIKE')) {
      return es.any { patStr ->
        return likeMatches(actual, normLikePat(patStr))
      }
    }
    def a = toBig(actual)
    if (a == null) return false
    if (op.equalsIgnoreCase('GT')) return es.any { e -> def eb = toBig(e); eb != null && a > eb }
    if (op.equalsIgnoreCase('GTE') || op.equalsIgnoreCase('GE')) return es.any { e -> def eb = toBig(e); eb != null && a >= eb }
    if (op.equalsIgnoreCase('LT')) return es.any { e -> def eb = toBig(e); eb != null && a < eb }
    if (op.equalsIgnoreCase('LTE') || op.equalsIgnoreCase('LE')) return es.any { e -> def eb = toBig(e); eb != null && a <= eb }
    return false
  }
  def expected = toStr(pickExpected(dv))
  if (op.equalsIgnoreCase('EQ')) return actual == expected
  if (op.equalsIgnoreCase('NE')) return actual != expected
  if (op.equalsIgnoreCase('LIKE')) {
    return likeMatches(actual, normLikePat(expected))
  }
  def a = toBig(actual)
  def e = toBig(expected)
  if (a == null || e == null) return false
  if (op.equalsIgnoreCase('GT')) return a > e
  if (op.equalsIgnoreCase('GTE') || op.equalsIgnoreCase('GE')) return a >= e
  if (op.equalsIgnoreCase('LT')) return a < e
  if (op.equalsIgnoreCase('LTE') || op.equalsIgnoreCase('LE')) return a <= e
  return false
}
def evalOne
evalOne = { cond, rows, ctx ->
  def fieldCode = toStr(cond?.fieldCode)
  def op = toStr(cond?.operator)
  if (!fieldCode || !op) return false
  def cn = toStr(cond?.conditionName)
  def nameOrListIndexed = ctx != null && op.equalsIgnoreCase('OR') && '商品名字'.equals(cn) && (cond?.defaultValue instanceof List)
  def hitSrc = nameOrListIndexed ? (ctx.allRows ?: rows) : rows
  def hits = (hitSrc ?: []).findAll { r -> toStr(r?.mappedCol) == fieldCode }
  if (!hits) return false
  if (op.equalsIgnoreCase('OR')) {
    def es = expectedList(cond?.defaultValue)
    if ('商品名字'.equals(cn) && (cond?.defaultValue instanceof List)) {
      if (ctx != null) {
        def grouped = ctx.grouped
        def allConds = ctx.allConds
        def nr = ctx.nullRows ?: []
        def pickScope = { oc, idx ->
          def idxRows = idx != null ? (grouped[idx] ?: []) : nr
          def hasIndexed = idxRows.any { r -> toStr(r?.mappedCol) == toStr(oc?.fieldCode) }
          return hasIndexed ? idxRows : nr
        }
        return es.every { patStr ->
          def pat = normLikePat(patStr)
          hits.any { h ->
            def actual = toStr(h?.mappedColVal)
            if (!likeMatches(actual, pat)) return false
            def hi = h?.index
            return allConds.every { oc ->
              if (sameCond(oc, cond)) return true
              return evalOne(oc, pickScope(oc, hi), null)
            }
          }
        }
      }
      return es.every { patStr ->
        def pat = normLikePat(patStr)
        hits.any { h -> likeMatches(toStr(h?.mappedColVal), pat) }
      }
    }
    return hits.any { h -> es.contains(toStr(h?.mappedColVal)) }
  }
  hits.any { h -> matchActual(cond, toStr(h?.mappedColVal)) }
}
def conds = (conditionDetailList ?: [])
if (!conds) return true
def rows = (mappedResults ?: [])
if (!rows) return false
def grouped = rows.groupBy { it?.index }
def nullRows = grouped[null] ?: []
def indexedKeys = grouped.keySet().findAll { it != null }
if (!indexedKeys) {
  return conds.every { c -> evalOne(c, rows, null) }
}
return indexedKeys.any { idx ->
  def idxRows = grouped[idx] ?: []
  conds.every { c ->
    def f = toStr(c?.fieldCode)
    def hasIndexed = idxRows.any { r -> toStr(r?.mappedCol) == f }
    def scope = hasIndexed ? idxRows : nullRows
    evalOne(c, scope, [grouped: grouped, nullRows: nullRows, allConds: conds, allRows: rows])
  }
}
```