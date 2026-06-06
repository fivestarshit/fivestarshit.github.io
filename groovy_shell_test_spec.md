# GroovyShell 接口测试规格（execute / executeMap / assembleMap）

## execute：布尔表达式 `POST /sales/task/groovy/execute`

### 一、接口说明
- 接口：`POST /sales/task/groovy/execute`
- 用途：开发/联调时验证 Groovy 表达式片段是否能按预期计算
- 安全约束（服务端默认）：允许分号（`;`），允许传入可计算脚本片段（支持换行/`return`，支持 `any { ... }` 这类闭包写法）。
- 结果类型约束（服务端默认）：你的脚本必须最终返回布尔值（`true/false`），否则会返回业务错误。

### 二、请求 JSON 示例
```json
{
  "code": "a + b * 2 > 5", // 必填：要执行的 Groovy 表达式（必须返回布尔值 true/false）
  "variables": {       // 可选：表达式执行时绑定的变量（会作为脚本变量注入到 Binding）
    "a": 1,            // 变量 a 的值
    "b": 3             // 变量 b 的值
  }
}
```

当你在 `biz_template_config` 中维护了字段 `groovy_execute_param_sample_json`（存储一份示例 JSON）后，
也可以直接通过 `bizTemplateConfigId` 来使用这份示例 JSON 作为脚本参数注入：

```json
{
  "bizTemplateConfigId": 4, // 可选：用于从 biz_template_config.groovy_execute_param_sample_json 解析变量
  "code": "return items != null && items.any { it != null && it.commodityCode == 'YQ03002' && (it.quantity ?: 0) > 1 }", // 必填：要执行的 Groovy 表达式（建议仅表达式，不建议包含语句/多行/导入）
}
```

示例（支持 return，允许换行）：
```json
{
  "code": "return a > b\n", 
  "variables": {
    "a": 2,
    "b": 1
  }
}
```

### 三、响应示例
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "costMillis": 2,              // 执行耗时（毫秒）
    "resultJson": "true",      // 执行结果（JSON 字符串形式）
    "resultType": "java.lang.Boolean", // 执行结果的 Java 类型（必须为布尔值）
    "errorMessage": null        // 失败时的错误信息；成功时为 null
  }
}
```

### 四、失败场景
- `code` 为空或超过长度限制（与全项目 Groovy 脚本统一上限 `GroovyScriptConstants.GROOVY_CODE_MAX_LENGTH`，当前为 6000 字符）：直接返回业务错误
- `code` 包含不被允许的关键字/多行/语句块：直接拒绝执行并返回错误信息
- 表达式语法错误：返回执行失败错误信息

### 五、脚本编译缓存（性能与 Metaspace）
- 服务端对 **相同源码**（`code` 字符串完全一致）只 **编译一次**，结果缓存在进程内（Guava Cache，默认最多约 **2048** 条不同脚本）。
- 消息量很大时，**重复执行同一任务配置里的 `completion_script` 等固定片段**，可显著减少 CPU 与重复生成脚本类的开销。
- **说明**：缓存淘汰后若再次遇到相同脚本会重新编译；**不同脚本种类** 仍会增加 Groovy 解析器 ClassLoader 中的类数量，业务上仍应控制「动态脚本」种类（见运维 Metaspace 监控）。

---

## executeMap：返回 Map `POST /sales/task/groovy/executeMap`

### 一、接口说明
- 接口：`POST /sales/task/groovy/executeMap`
- 用途：传入自定义 Groovy 代码片段，要求最终返回一个 Map；该 Map 可作为后续其它接口的请求参数来源。
- 结果类型约束（服务端默认）：脚本最终返回值必须为 Map。
- 安全约束（服务端默认）：允许分号（`;`），禁止 `import/class/new/...` 等高风险关键字；允许 `any { ... }` 等闭包写法。

### 二、请求 JSON 示例（生成当前月）
```json
{
  "code": "def now = java.time.LocalDate.now(); return [month: now.format(java.time.format.DateTimeFormatter.ofPattern('yyyy-MM'))]"
}
```

说明：服务端会内置注入变量 `currentMonth`（格式 `yyyy-MM`），可直接使用。

### 三、响应示例
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "costMillis": 2,
    "resultMap": {
      "month": "2026-03"
    },
    "errorMessage": null
  }
}
```

### 四、使用 bizTemplateConfigId 注入参数示例
当 `biz_template_config.groovy_execute_param_sample_json` 存了一份示例 JSON（例如 `{ "a": 1 }`）时：
```json
{
  "bizTemplateConfigId": 4,
  "code": "return [month: '2026-03', a: a]"
}
```

### 五、脚本编译缓存
- 与 `execute` 相同：相同 `code` 源码进程内只编译一次（见上文 **execute** 第五节）。

---

## assembleMap/execute：双 Map 组装 `POST /sales/task/groovy/assembleMap/execute`

### 一、接口说明
- 接口：`POST /sales/task/groovy/assembleMap/execute`
- 用途：传入 `a`、`b` 两个 Map，并传入自定义 Groovy 片段；脚本执行完成后，服务端要求最终返回一个 Map，再把该 Map 原样作为 `resultMap` 返回。
- 安全约束（服务端默认）：
  - 允许分号 `;` 与闭包 `{}`（用于 any/find/collect 等），但仍会拦截高风险关键字
  - 禁止 `import/package/class/def/throw/try/catch/finally/while/for/switch/new` 等高风险关键字
  - 禁止 `system/runtime/java./groovy./@grab/println` 等高风险访问

### 二、请求 JSON 示例
```json
{
  "a": {                          // 必填：a Map
    "x": 2
  },
  "b": {                          // 必填：b Map
    "y": 3
  },
  "code": "return ['sum': a.get('x')+100,'sum2':b.get('y')+200]"
}
```

### 三、响应示例
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "costMillis": 2,                    // 执行耗时（毫秒）
    "resultMap": {                      // 组装后的结果 Map（必须由 code 返回）
      "sum2": 203,
      "sum": 102
    },
    "errorMessage": null               // 失败时错误信息；成功时为 null
  }
}
```

### 四、失败场景
- `a` / `b` / `code` 为空：返回业务错误
- `code` 最终返回值不是 Map：返回业务错误（提示「执行结果必须为 Map 对象」）
- 脚本存在语法错误或被安全策略拦截：返回执行失败信息

### 五、脚本编译缓存
- 与 `execute` 相同：相同 `code` 源码进程内只编译一次（见上文 **execute** 第五节）。

