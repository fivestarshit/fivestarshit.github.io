# 数据源与业务模板配置测试规格

## 功能模块：数据源与业务模板配置

### 一、数据源连接配置（datasource_connection）

- **用例1：新增数据源连接成功**
  - 接口：`POST /datasource/connection/create`
  - 请求 Body 示例（JSON）：
    ```json
    {
      "name": "MySQL生产库",
      "dbType": "MYSQL",
      "host": "192.168.1.100",
      "port": 3306,
      "databaseName": "biz_db",
      "username": "app_user",
      "password": "encrypted_password",
      "extraParams": "{\"useSSL\":false}",
      "enabled": true
    }
    ```
    - 说明：`id`、`lastTestTime` 可不传；`enabled` 不传时默认 true。
    - **dbType 必填**，且必须为以下之一：`MYSQL`、`ORACLE`、`PG`、`POSTGRESQL`、`SQLSERVER`、`MONGODB`。
  - 预期结果：
    - 返回 `Response.success`，data 为新建记录的自增 `id`
    - 表 `datasource_connection` 中存在对应记录，字段与入参一致

- **用例1a：新增数据源连接 - dbType 非法（校验失败）**
  - 接口：`POST /datasource/connection/create`
  - 请求 Body 示例（JSON）：
    ```json
    {
      "name": "测试库",
      "dbType": "INVALID_TYPE",
      "host": "192.168.1.100",
      "port": 3306,
      "databaseName": "biz_db",
      "username": "app_user",
      "password": "encrypted_password",
      "enabled": true
    }
    ```
  - 预期结果：
    - 返回错误，提示：`dbType必须为以下之一: MYSQL, ORACLE, PG, POSTGRESQL, SQLSERVER, MONGODB`

- **用例1b：新增数据源连接 - dbType 为空（校验失败）**
  - 接口：`POST /datasource/connection/create`
  - 请求 Body 示例（JSON）：
    ```json
    {
      "name": "测试库",
      "dbType": "",
      "host": "192.168.1.100",
      "port": 3306,
      "databaseName": "biz_db",
      "username": "app_user",
      "password": "encrypted_password",
      "enabled": true
    }
    ```
  - 预期结果：
    - 返回错误，提示：`dbType不能为空`

- **用例2：更新数据源连接成功**
  - 接口：`POST /datasource/connection/update`
  - 请求 Body 示例（JSON）：
    ```json
    {
      "id": 1,
      "name": "MySQL生产库-新",
      "dbType": "MYSQL",
      "host": "192.168.1.101",
      "port": 3306,
      "databaseName": "biz_db",
      "username": "app_user",
      "password": "encrypted_password",
      "extraParams": null,
      "enabled": true
    }
    ```
  - 预期结果：
    - 返回 `Response.success`
    - 数据库中该 `id` 记录字段被正确更新

- **用例2a：更新数据源连接 - dbType 非法（校验失败）**
  - 接口：`POST /datasource/connection/update`
  - 请求 Body 示例（JSON）：
    ```json
    {
      "id": 1,
      "name": "测试库",
      "dbType": "UNKNOWN",
      "host": "192.168.1.100",
      "port": 3306,
      "databaseName": "biz_db",
      "username": "app_user",
      "password": "encrypted_password",
      "enabled": true
    }
    ```
  - 预期结果：
    - 返回错误，提示：`dbType必须为以下之一: MYSQL, ORACLE, PG, POSTGRESQL, SQLSERVER, MONGODB`

- **用例3：删除数据源连接（逻辑删除）**
  - 接口：`POST /datasource/connection/delete?id={id}`
  - 请求：无 Body，Query 参数示例：`?id=1`
  - 预期结果：
    - 返回 `Response.success`
    - 表中对应记录 `is_deleted` 置为 1（逻辑删除）

- **用例4：查询数据源连接详情**
  - 接口：`POST /datasource/connection/detail`
  - 请求 Body 示例（JSON）：
    ```json
    { "id": 1 }
    ```
  - 预期结果：
    - 返回 `Response.success`，data 为 `DatasourceConnectionDTO`
    - 各字段与数据库记录一致

- **用例5：查询数据源连接列表**
  - 接口：`POST /datasource/connection/list`
  - 请求：无 Body，无 Query 参数
  - 预期结果：
    - 返回 `Response.success`，data 为 `List<DatasourceConnectionDTO>`
    - 仅包含未逻辑删除（is_deleted=0）的记录

### 二、业务模板配置（biz_template_config）

- **用例6：新增业务模板成功**
  - 接口：`POST /biz/template/config/create`
  - 请求 Body 示例（JSON）：
    ```json
    {
      "templateCode": "TPL_ORDER",
      "templateName": "订单模板",
      "iconUrl": "https://example.com/icon.png",
      "description": "订单业务数据模板",
      "datasourceId": 1,
      "dataSource": "数仓订单库", // 可空：数据来源说明，对应 biz_template_config.data_source
      "physicalTable": "t_order",
      "databaseName": "public",
      "syncStrategy": "REAL_TIME",
      "sampleLimit": 100,
      "version": 1,
      "isActive": true
    }
    ```
    - 说明：`id` 不传；`version`、`isActive` 不传时默认 1、true。
  - 预期结果：
    - 返回 `Response.success`，data 为新建模板 `id`
    - 表中记录 `version` 默认为 1，`is_active` 默认为 true

- **用例7：更新业务模板成功**
  - 接口：`POST /biz/template/config/update`
  - 请求 Body 示例（JSON）：
    ```json
    {
      "id": 1,
      "templateCode": "TPL_ORDER",
      "templateName": "订单模板-更新",
      "iconUrl": "https://example.com/icon2.png",
      "description": "订单业务数据模板（更新）",
      "datasourceId": 1,
      "dataSource": "数仓订单库-主从", // 可空：数据来源说明
      "physicalTable": "t_order",
      "databaseName": "public",
      "syncStrategy": "REAL_TIME",
      "sampleLimit": 200,
      "version": 2,
      "isActive": true
    }
    ```
  - 预期结果：
    - 返回 `Response.success`
    - 对应记录被正确更新

- **用例8：删除业务模板**
  - 接口：`POST /biz/template/config/delete?id={id}`
  - 请求：无 Body，Query 参数示例：`?id=1`
  - 预期结果：
    - 返回 `Response.success`
    - 表中对应记录被物理删除

- **用例9：查询业务模板详情（含字段明细）**
  - 接口：`POST /biz/template/config/detail`
  - 请求 Body 示例（JSON）：
    ```json
    { "id": 1 }
    ```
  - 预期结果：
    - 返回 `Response.success`，data 为 `BizTemplateConfigDTO`
    - `fieldDetails` 包含该模板下所有字段映射明细（按 `sortOrder` 升序）；无字段时为空列表

- **用例10：查询业务模板列表（分页）**
  - 接口：`POST /sales/task/biz/template/config/list`
  - 请求 Body（必填 `syncStrategy`，与库字段精确匹配；分页默认 `page=1`、`pageSize=20`）示例：
    ```json
    {
      "page": 1, // 当前页码
      "pageSize": 20, // 每页条数
      "syncStrategy": "REAL_TIME", // 同步策略，必填，精确匹配 biz_template_config.sync_strategy
      "templateCode": null, // 可选，模板编码模糊
      "templateName": null, // 可选，模板名称模糊
      "physicalTable": null, // 可选，物理表名模糊
      "objectCode": null // 可选；传入时仅返回 biz_template_field_map 中存在该 object_code 且 template_id 指向本表的模板；若库中无任何该 objectCode 的字段映射，则 records 为空且 total=0
    }
    ```
  - 预期结果：
    - 返回 `Response.success`，data 为 `PageResult`（含 `records`、`total`、`page`、`pageSize`、`totalPage`）
    - 仅返回 `sync_strategy` 与入参一致的模板；缺 `syncStrategy` 或 Body 非法时校验失败
    - 传 `objectCode` 时与 `syncStrategy`、模糊条件同时生效；无匹配字段映射时整体空分页

### 三、业务模板字段映射（biz_template_field_map）

- **用例11：新增字段映射成功**
  - 接口：`POST /biz/template/field/create`
  - 请求 Body 示例（JSON）：
    ```json
    {
      "templateId": 1,
      "objectCode": "STORE", // 可空：对象类型编码，与 task_object_option.object_code 一致
      "dataSource": "主库订单表", // 可空：数据来源说明，对应 biz_template_field_map.data_source
      "physicalCol": "order_id",
      "mappedCol": "orderId",
      "logicalName": "订单ID",
      "dataType": "BIGINT",
      "length": 20,
      "precision": null,
      "isCalculable": false,
      "isSearchable": true,
      "isSearchPrimaryKey": true, // 是否搜索主键
      "isVisible": true,
      "sortOrder": 1,
      "defaultValue": null,
      "enumValues": null,
      "isSensitive": false,
      "maskRule": "NONE",
      "remark": "主键"
    }
    ```
    - 说明：`templateId` 可为空，先创建字段映射，后续通过 update 关联到模板。
  - 预期结果：
    - 返回 `Response.success`，data 为新建字段映射 `id`
    - 表中存在对应记录

- **用例12：更新字段映射成功**
  - 接口：`POST /biz/template/field/update`
  - 请求 Body 示例（JSON）：
    ```json
    {
      "id": 1,
      "templateId": 1,
      "objectCode": "STORE",
      "dataSource": "主库订单表", // 可空：数据来源说明
      "physicalCol": "order_id",
      "mappedCol": "orderId",
      "logicalName": "订单编号",
      "dataType": "BIGINT",
      "length": 20,
      "precision": null,
      "isCalculable": false,
      "isSearchable": true,
      "isSearchPrimaryKey": true,
      "isVisible": true,
      "sortOrder": 2,
      "defaultValue": null,
      "enumValues": null,
      "isSensitive": false,
      "maskRule": "NONE",
      "remark": "主键-已更新"
    }
    ```
  - 预期结果：
    - 返回 `Response.success`
    - 对应记录被正确更新

- **用例13：删除字段映射**
  - 接口：`POST /biz/template/field/delete?id={id}`
  - 请求：无 Body，Query 参数示例：`?id=1`
  - 预期结果：
    - 返回 `Response.success`
    - 表中对应记录被物理删除

- **用例14：查询字段映射详情**
  - 接口：`POST /biz/template/field/detail`
  - 请求 Body 示例（JSON）：
    ```json
    { "id": 1 }
    ```
  - 预期结果：
    - 返回 `Response.success`，data 为 `BizTemplateFieldMapDTO`

- **用例15：按模板ID分页查询字段列表**
  - 接口：`POST /sales/task/biz/template/field/listByTemplateId`
  - 请求 Body 示例（JSON，字段含义）：
    ```json
    {
      "page": 1, // 当前页，默认 1
      "pageSize": 20, // 每页条数，默认 20
      "templateId": 1, // 可空：业务模板 ID；null 表示只查 template_id 为空的映射
      "fieldNameKeyword": "数量" // 可空：非空时仅对 logical_name（展示名）模糊匹配
    }
    ```
  - 预期结果：
    - 返回 `Response.success`，`data` 为分页结构（`records`、`total`、`page`、`pageSize`、`totalPage`），`records` 为 `BizTemplateFieldMapDTO` 列表
    - 传 `templateId` 时记录 `templateId` 与入参一致；`templateId` 为 null 时仅 `template_id` 为空的记录
    - 传 `fieldNameKeyword` 时仅保留 `logical_name` 含关键字的记录

- **任务下发 processTaskDistribution 字段映射（回归）**
  - 从条件 `condition_repo` 反查 `template_id`（业务模板 ID），再按 **`biz_template_field_map.template_id`** 调用 **`listByTemplateId`** 得到字段映射列表；**不再**按 `template_task_id` 联合查询，**不再**按 objectCode + 搜索主键做合并覆盖。

### 四、按模板关联查询映射表数据

- **用例16：按模板ID分页查询映射后的表数据**
  - 接口：`POST /biz/template/data/query`
  - 说明：根据业务模板配置绑定数据源（datasource_id）+ 表名（physical_table）+ 字段映射（biz_template_field_map），查询动态数据源中该表的数据，返回 key 为映射字段名（mapped_col/logical_name）的分页列表。
  - 请求 Body 示例（JSON）：
    ```json
    {
      "templateId": 1,
      "page": 1,
      "pageSize": 20
    }
    ```
  - 预期结果：
    - 返回 `Response.success`，data 为分页结构：
      ```json
      {
        "records": [...],
        "total": 7884,
        "page": 1,
        "pageSize": 20,
        "totalPage": 395
      }
      ```
    - records 中每条 Map 的 key 为映射后的字段名，value 为列值
    - 仅包含模板中 is_visible=true 的字段；数据源未开启或连接失败时返回空分页（records 空、total 0）
