# 动态 HTTP 外部接口配置测试规格

## 功能模块：dynamic_http_endpoint

### 一、路由总览

- 控制器：`DynamicHttpEndpointController`
- 路由前缀：`/sales/task/dynamic/endpoint`
- 全部接口：
  - `POST /create`：新增动态 HTTP 配置
  - `POST /update`：更新动态 HTTP 配置
  - `POST /delete`：删除动态 HTTP 配置（逻辑删除）
  - `POST /detail`：配置详情（返回完整 `appSecret`）
  - `POST /list`：分页列表（`appSecret` 脱敏）
  - `POST /invoke`：按配置发起一次 HTTP 调用
  - `POST /ping`：连通性探测（仅使用库中默认 query/body）

### 二、公共响应结构

所有接口统一返回：

```json
{
  "code": 0, // 响应码，0=成功，非0=失败
  "message": "success", // 响应消息
  "data": {} // 业务数据，不同接口结构不同
}
```

### 三、请求/响应参数明细

#### 1）新增配置 `POST /sales/task/dynamic/endpoint/create`

请求示例：

```json
{
  "id": null, // 主键，新增时可不传
  "configCode": null, // 配置编码由后端自动生成（buildTaskCodeByType，前缀 http），前端可不传
  "configName": "SC设备信息", // 配置名称
  "baseUrl": "https://apiavalon.yqslmall.com", // 基础域名（含协议）
  "path": "/v2/arthur/merchant/ads_account_checking_device_info_cm_mi_1d", // 请求路径
  "httpMethod": "POST", // HTTP方法：GET/POST/PUT/DELETE
  "queryParamsJson": "{\"pageNum\":1,\"pageSize\":2000}", // 默认Query(JSON对象字符串)
  "requestBodyJson": "{\"month_key\":\"202401\",\"mini_number\":\"M001\"}", // 默认Body(JSON对象字符串)
  "executeParamScript": "return [month_key: currentMonth]", // 执行参数脚本(Groovy片段)
  "headersJson": "{\"X-App-Key\":\"{{appKey}}\",\"Authorization\":\"Bearer {{appSecret}}\"}", // 默认请求头(JSON字符串)，支持占位符
  "appKey": "yourAppKey", // 应用key，替换{{appKey}}
  "appSecret": "yourAppSecret", // 应用secret，替换{{appSecret}}
  "remark": "SC Arthur动态接口配置", // 备注
  "accessType": 1, // 接入类型（整数，可空）
  "accessTypeName": "API", // 接入类型名称（可空）
  "enabled": 1, // 是否启用：1-启用，0-停用
  "linkStatus": null, // 链接状态，新增时可不传
  "lastCheckAt": null, // 上次检测时间，新增时可不传
  "lastErrorMessage": null, // 最近错误信息，新增时可不传
  "createdBy": null, // 创建人，后端维护
  "updatedBy": null // 最后修改人，后端维护
}
```

响应示例（`data` 为新记录 ID）：

```json
{
  "code": 0,
  "message": "success",
  "data": 123
}
```

#### 2）更新配置 `POST /sales/task/dynamic/endpoint/update`

请求示例（与 create 同结构，`id` 必填）：

```json
{
  "id": 123, // 主键，更新必填
  "configCode": "http_xxx", // 可传但会被忽略；configCode 创建后不可修改
  "configName": "SC设备信息-更新", // 配置名称
  "baseUrl": "https://apiavalon.yqslmall.com", // 基础域名
  "path": "/v2/arthur/merchant/ads_account_checking_device_info_cm_mi_1d", // 请求路径
  "httpMethod": "POST", // HTTP方法
  "queryParamsJson": "{\"pageNum\":1,\"pageSize\":500}", // 默认Query
  "requestBodyJson": "{\"month_key\":\"202402\"}", // 默认Body
  "executeParamScript": "return [month_key: currentMonth]", // 执行参数脚本
  "headersJson": "{\"X-App-Key\":\"{{appKey}}\"}", // 默认请求头
  "appKey": "yourAppKey", // 应用key
  "appSecret": "yourAppSecret", // 应用secret
  "remark": "更新备注", // 备注
  "accessType": 2, // 接入类型（整数，可空）
  "accessTypeName": "MQ", // 接入类型名称（可空）
  "enabled": 1, // 是否启用
  "linkStatus": "UNKNOWN", // 链接状态，可选
  "lastCheckAt": null, // 上次检测时间，可选
  "lastErrorMessage": null, // 最近错误，可选
  "createdBy": null, // 创建人（通常不改）
  "updatedBy": null // 最后修改人（后端维护）
}
```

响应示例：

```json
{
  "code": 0,
  "message": "success",
  "data": null
}
```

#### 3）删除配置 `POST /sales/task/dynamic/endpoint/delete`

请求示例：

```json
{
  "id": 123 // 要删除的配置主键ID
}
```

响应示例：

```json
{
  "code": 0,
  "message": "success",
  "data": null
}
```

#### 4）详情 `POST /sales/task/dynamic/endpoint/detail`

请求示例：

```json
{
  "id": 123 // 配置主键ID
}
```

响应示例（`data` 为 `DynamicHttpEndpointDTO`）：

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 123, // 主键
    "configCode": "sc_arthur_devices", // 配置编码
    "configName": "SC设备信息", // 配置名称
    "baseUrl": "https://apiavalon.yqslmall.com", // 基础域名
    "path": "/v2/arthur/merchant/ads_account_checking_device_info_cm_mi_1d", // 请求路径
    "httpMethod": "POST", // HTTP方法
    "queryParamsJson": "{\"pageNum\":1,\"pageSize\":2000}", // 默认Query(JSON字符串)
    "requestBodyJson": "{\"month_key\":\"202401\"}", // 默认Body(JSON字符串)
    "executeParamScript": "return [month_key: currentMonth]", // 执行参数脚本
    "headersJson": "{\"X-App-Key\":\"{{appKey}}\"}", // 默认请求头(JSON字符串)
    "appKey": "yourAppKey", // 应用key
    "appSecret": "yourAppSecret", // 应用secret（detail返回完整值）
    "remark": "SC Arthur动态接口配置", // 备注
    "accessType": 1, // 接入类型（整数，可空）
    "accessTypeName": "API", // 接入类型名称（可空）
    "enabled": 1, // 是否启用
    "linkStatus": "UP", // 链接状态：UNKNOWN/UP/DOWN
    "lastCheckAt": "2026-04-29 16:30:00", // 上次检测或调用时间
    "lastErrorMessage": null, // 最近错误信息
    "createdBy": "admin", // 创建人
    "updatedBy": "admin" // 最后修改人
  }
}
```

#### 5）分页列表 `POST /sales/task/dynamic/endpoint/list`

请求示例：

```json
{
  "page": 1, // 当前页，默认1
  "pageSize": 20 // 每页条数，默认20
}
```

响应示例（`data` 为 `PageResult<DynamicHttpEndpointDTO>`）：

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "records": [
      {
        "id": 123, // 主键
        "configCode": "sc_arthur_devices", // 配置编码
        "configName": "SC设备信息", // 配置名称
        "baseUrl": "https://apiavalon.yqslmall.com", // 基础域名
        "path": "/v2/arthur/merchant/ads_account_checking_device_info_cm_mi_1d", // 请求路径
        "httpMethod": "POST", // HTTP方法
        "queryParamsJson": "{\"pageNum\":1,\"pageSize\":2000}", // 默认Query
        "requestBodyJson": "{\"month_key\":\"202401\"}", // 默认Body
        "executeParamScript": "return [month_key: currentMonth]", // 执行参数脚本
        "headersJson": "{\"X-App-Key\":\"{{appKey}}\"}", // 默认请求头
        "appKey": "yourAppKey", // 应用key
        "appSecret": "********", // 应用secret（list固定脱敏）
        "remark": "SC Arthur动态接口配置", // 备注
        "accessType": 1, // 接入类型（整数，可空）
        "accessTypeName": "API", // 接入类型名称（可空）
        "enabled": 1, // 是否启用
        "linkStatus": "UP", // 链接状态
        "lastCheckAt": "2026-04-29 16:30:00", // 上次检测时间
        "lastErrorMessage": null, // 最近错误信息
        "createdBy": "admin", // 创建人
        "updatedBy": "admin" // 最后修改人
      }
    ],
    "total": 1, // 总条数
    "page": 1, // 当前页
    "pageSize": 20, // 每页条数
    "totalPage": 1 // 总页数
  }
}
```

#### 6）动态调用 `POST /sales/task/dynamic/endpoint/invoke`

请求示例：

```json
{
  "configId": 123, // 配置主键，与configCode二选一
  "configCode": null, // 配置编码，与configId二选一
  "queryParams": {
    "pageNum": 1, // 运行时Query参数（覆盖同名默认值）
    "pageSize": 2000 // 运行时Query参数
  },
  "requestBody": {
    "month_key": "202402", // 运行时Body参数（覆盖同名默认值）
    "mini_number": "M002" // 运行时Body参数
  },
  "executeVariables": {
    "bizDate": "2026-03-30" // 执行参数脚本运行时变量（可选）
  },
  "runExecuteParamScript": true // 是否执行配置中的 executeParamScript 生成并合并请求参数；false 跳过脚本；未传与 true 等价（保持原行为）
}
```

响应示例（`data` 为 `DynamicHttpInvokeResultDTO`）：

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "success": true, // 是否调用成功（HTTP 2xx 且无客户端异常）
    "httpStatus": 200, // HTTP状态码（失败时可能为0）
    "rawResponse": "{\"code\":0,\"message\":\"ok\"}", // 原始响应文本
    "responseJson": {
      "code": 0, // 解析后的JSON内容（无法解析时为null）
      "message": "ok" // 解析后的JSON内容
    },
    "durationMs": 135, // 耗时毫秒
    "errorMessage": null // 错误信息（失败时有值）
  }
}
```

#### 7）连通性探测 `POST /sales/task/dynamic/endpoint/ping`

请求示例：

```json
{
  "id": 123 // 配置主键ID（仅使用库中默认query/body，不使用运行时覆盖）
}
```

响应示例（`data` 结构同 invoke）：

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "success": true, // 是否探测成功
    "httpStatus": 200, // HTTP状态码
    "rawResponse": "{\"status\":\"ok\"}", // 原始响应文本
    "responseJson": {
      "status": "ok" // 解析后的JSON
    },
    "durationMs": 88, // 耗时毫秒
    "errorMessage": null // 错误信息
  }
}
```

### 四、回归检查点

- `create` 时 `configCode` 由后端自动生成，前缀为 `http`。
- `update` 时即使请求体传入 `configCode`，库中值也保持不变（不可修改）。
- `list` 必须返回分页结构：`records/total/page/pageSize/totalPage`。
- `list` 中 `appSecret` 必须脱敏，`detail` 中应返回完整值。
- `invoke` / `ping` 后应更新 `linkStatus`、`lastCheckAt`、`lastErrorMessage`。
- `invoke` 请求体 `runExecuteParamScript=false` 时不得执行 `executeParamScript`，仅按运行时 query/body 与库中默认合并。
- `enabled=0` 的配置调用 `invoke` 应按业务规则失败并返回错误信息。
