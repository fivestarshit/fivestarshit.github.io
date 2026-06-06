# 认证与 OP 拦截（JwtAuthFilter + OpAuthInterceptor）测试说明

## 行为说明

1. **Filter 层 `JwtAuthFilter`**
   - 白名单：`/sales/task/user/getToken`、`/health` 等。
   - **OP 与 JWT 二选一**：请求头带 **`op-employee-id`** 且为合法数字时：**不校验 JWT**，并写入请求属性 `AUTH_MODE=OP`。
   - 否则：必须带 **`Authorization`** JWT，校验通过后写入请求属性 `AUTH_MODE=JWT`。

2. **Interceptor 层 `OpAuthInterceptor`**（在 `HeaderInterceptor` 之后）
   - 若 **`op-employee-id` 有值**：通过 EHR 查询人员，写入 `HeaderThreadLocal` 的 `opUser`。
   - 若 **无 `op-employee-id`** 且 **`AUTH_MODE=JWT`**（即已在 Filter 通过 JWT）：**不再调用** merchant-system，仅保留网关头信息，`opUser` 为空。
   - 若 **无 `op-employee-id`** 且 **非 JWT 模式**（兜底）：调用 **`sls-merchant-system`** 的 `/rpc/auth/intercept`，将返回的 `RpcAuthHeader` 写回 ThreadLocal。

3. **排除路径（不走 OP 拦截）**
   - `/error/**`、`/health`、`/health/**`、`/sales/task/user/getToken`、`/actuator/**`

---

## 用例 1：外勤 JWT（无 OP）

**说明**：无 `op-employee-id`，需走 JWT；Filter 校验通过后 Interceptor **不再**强制 merchant-system RPC（与 OP 二选一）。

**请求**

```http
POST /sales/task/xxx HTTP/1.1
Authorization: <JWT>
Content-Type: application/json

{}
```

**字段说明**

| 位置 | 字段 | 含义 |
|------|------|------|
| Header | Authorization | 外勤登录颁发的 JWT，必填（本场景） |

**期望**：JWT 合法时 `code=0`；否则 401（Filter）。

---

## 用例 4：B 端经销商链路（无 JWT、无 op-employee-id）

**说明**：正常请求会先被 Filter 以 401 拦截（缺少 JWT 与 OP）。若存在内部转发、测试或未来扩展使请求**未**经 Filter 写入 `AUTH_MODE`，Interceptor 会走 merchant-system 兜底。生产环境以外勤 JWT 或 `op-employee-id` 为主。

---

## 用例 2：OP 网关（有 op-employee-id）

**说明**：带 `op-employee-id` 时 **Filter 不校验 JWT**；Interceptor 从 EHR 加载人员。

**请求**

```http
POST /sales/task/xxx HTTP/1.1
op-employee-id: 12345
Content-Type: application/json

{}
```

**字段说明**

| 位置 | 字段 | 含义 |
|------|------|------|
| Header | op-employee-id | 人事主数据员工 ID，与库存等服务一致；有则视为 OP 链路 |
| Header | op-token 等 | 可选，与 RpcAuthHeader 解析一致 |

**期望**：EHR 能查到人员时业务正常；查不到或异常时 Interceptor 返回 403。

---

## 用例 3：获取 Token（白名单）

**请求**

```http
POST /sales/task/user/getToken HTTP/1.1
Content-Type: application/json

{
  "code": "13261178730"
}
```

**字段说明**

| 字段 | 含义 |
|------|------|
| code | 纷享销客授权码或测试手机号，见 `UserController` 实现 |

**期望**：不经过 JWT 与 OP 业务拦截（白名单）。

---

## 回归说明

- 功能变更：需覆盖「仅 JWT」「仅 OP」「白名单」；JWT 与 OP 互斥满足其一即可进入业务。
- 问题修复：若出现「带 op-employee-id 仍被要求 JWT」，检查 `JwtAuthFilter.hasOpEmployeeIdentity` 与网关是否透传 `op-employee-id`。
