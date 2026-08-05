# 销售任务系统 MVP版 PRD

# 文档概要

## 变更记录

|变更时间|变更人|变更内容|
|---|---|---|
|2026\.03\.04 ～ 2026\.03\.13|@吴企帆|建立文档，评审方案内容|

## 功能范围

|系统/终端|功能模块|简要说明|优先级|成本归类|
|---|---|---|---|---|
|任务系统|新增 \- 条件库\&任务模版|跑通核心功能的基本机制|P0（重要紧急）|销售任务|
|任务系统|新增 \- 任务规则列表||P0（重要紧急）|销售任务|
|任务系统|新增 \- 任务规则配置||P0（重要紧急）|销售任务|
|任务系统|新增 \- 任务详情||P0（重要紧急）|销售任务|

## 版本记录

[新探索](https://k11pnjpvz1.feishu.cn/wiki/BPPrwc3x6irGoAkpGp9cL3YznJf?from=from_copylink)

# 背景目标

## 当前痛点和愿景

|层级|痛点|
|---|---|
|业代|- **巡店动作固定**：所有门店执行动作一致，未区分动作优先级<br>- **经验依赖性强**：新业代因不熟悉门店特征，导致无执行重点，执行效果差<br>- **活动多难执行**：总地各种策略过多，业代很难第一时间知道最应该做哪个执行动作，能够达到管理动作<br>- **动态响应不足**：市场冲击（如新品促销）无法实时推送针对性任务|
|管理层|- **策略落地偏差**：战役专案指令未精准匹配到人，匹配到适用门店（基本是宣贯到主管，主管再传达给业代）<br>- **活动多难推动**：总地各种策略过多，只能选择性的推给业务<br>- **数据反馈滞后**：依赖动作执行后，才有数据，才能分析出执行效果（如差多少达标）|

希望通过销售任务，让销售巡店有重点，让管理有抓手。

形成完整的销售动作管理 （P:制定任务、D:执行任务、C:监控任务、A:复盘任务）

## 竞品调研

**未找到通用接近我司想法的任务系统**

|**系统**|说明|备注|
|---|---|---|
|[🔗 钉钉任务通](https://www.aliwork.com/APP_Y4V9O3E3WNOUD5RUS535/workbench?spm=a2q5o.26736374.0.0.7f0f1bcbo7BJQX)|- 类似飞书的描述性手工创建的任务<br>|![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=YTAyYzE2NTkyODFhMjE2N2U2YWRkYzliZjMxOWEwZjZfYjA4ZTUyOWY4NDJlZjE1OGNkMDQ1Y2QxZDE2NGZkZjhfSUQ6NzYwMTEwNTg4NDI0NDU2MDg0OV8xNzg1ODk4NDYzOjE3ODU5ODQ4NjNfVjM)|
|[🔗 卖教数字系统](https://www.yuque.com/moresales520/moresales/smogxf)|- 仅指定销售额目标的任务系统<br>- 市面大多数的业务任务系统均是目标追踪管理工具<br>|![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=OWNiYjNkZDg2NjZiYjlhZDY4ZWI1MWJjYzk2YjFmNzdfNTczYjkwZjAzMTcwNjljMTEwOTQxMzMzZmEyMjc4M2JfSUQ6NzYwMTEwNjUxNjQxMDQwMzc4NF8xNzg1ODk4NDYzOjE3ODU5ODQ4NjNfVjM)|
|[🔗 医疗巡店任务系统](https://www.yuque.com/zhongkangjubai/ks5geu/uwh2qy)|- 固定的巡店任务系统|![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=MTViOWE0YWJjOWYyOWVlMjJiYTJiNmJiNzc3NzI5YzNfOTY3NDAxMmY0NDA5NGVlZDE0NDZkYjE2NjFhZjE1MWFfSUQ6NzYwMTEwNzgxODcwNzkxMzkyOF8xNzg1ODk4NDYzOjE3ODU5ODQ4NjNfVjM)|

# 方案详情

## 相关系统关系图

## 任务系统功能模块

## 概念说明

|术语|说明|举例|示例|
|---|---|---|---|
|任务包|基于业务考核的整体方案，由很多任务组成|**春耕战役铺货**|<br>|
|任务<br>|有明确的“什么时间、什么人、做什么事、完成标准是什么”<br>同一个任务包里的多个任务之间，可以各自独立，也可以相互依赖；任务不能跨越任务包依赖<br>|**时间**：截止2月底<br>**人**：张三<br>**todo**：在欣欣超市下单10箱白桃气泡水<br>**完成标准**：2月内订单出库到欣欣超市下单10箱白桃气泡水||
|聚合维度|任务根据业务需求，可以根据不同方式进行聚合：如状态、任务包、任务分类|按任务分类聚合：**订单**<br>按任务包聚合：**春耕**||

## 页面框架

## 任务配置核心机制

## 功能详情

|终端|功能点|功能详细说明|交互图|
|---|---|---|---|
|运维端|新增 \- 条件库\&任务模版页<br>|**页面构成**：采用 Tab 切换结构，分为“条件库”和“任务模版”。<br>**条件库**<br>- 对接数据源后，在本系统将数据源，抽象成三种类型：指标、标签、维度，对象上分为：商（经销商）、店（网点）、人、品、其他<br>- 条件库支持增删改查，具体编辑弹窗根据研发技术对接方案为准<br>**任务模版**<br>- 每一个任务模版都要配置完成条件，完成条件会依赖一部分变量，变量需要添加关联数据源<br>- **名称、说明**：必填文本字段<br>- **任务类型**：选项，需要配置一个任务分类，需要支持配置，存储在后端配置<br>- **关联数据源**：可选择表或事件，服务端根据“对象\+数据类型”返给前端可选的数据源<br>- **变量：**添加需要先选择数据源，不同数据源下边可选的字段有所差别<br>    - 每个字段只能被添加一次，展示名默认同字段名<br>- **状态**：启用，停用；停用的任务模版，任务配置页不能搜到停用的任务，已经使用的不影响<br>- **默认完成逻辑**：会被引用到任务规则里，作为任务生效的通用规则。需要支持代码编写判断动作是否完成的条件，除了上边的变量，额外可以引用的变量为“任务开始时间、任务完成时间、任务执行人、任务门店”，需要研发整理标准代码规范文档<br>- **判断时间**：需要配置调度时间，根据数据源的不同，影响是否有数据变更判断这个点<br>    - 数仓数据源：定时判断<br>    - 事件：数据变更判断|![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=NjQ2NjMwNmQ4N2EyOWZhZjkzZTI4MzFmNzg1ODQ3ODJfNWJmMjkzYzM2MThhZjliNzJiYThjNzdmMTU1M2Q3YzJfSUQ6NzYyMTQ5OTkxMzQ5MDY2NDM4NV8xNzg1ODk4NDYyOjE3ODU5ODQ4NjJfVjM)<br>![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=M2IwNTBmNmZjMjJhODEzMjJkNzQ3ZDM4ZWNjYzhmYTdfMWI5NzZhZmRhMWE1MmUzNDA3YTc4ZmZkOGY3MTdiZDhfSUQ6NzYyNjIyNDcwMzIyODY3NzA3MV8xNzg1ODk4NDYzOjE3ODU5ODQ4NjNfVjM)<br>|
|运营端|新增 \- 任务规则列表页|**任务包规则管理**<br>- 任务包需要支持模糊搜索名称和备注<br>- 点击累表关联任务规则，需要支持跳转任务规则管理页，同时筛选到对应的任务包<br>- “下发任务包”和“下发任务数”跳转到对应的任务包明细页和下发任务明细页<br>- **状态：**点击关闭需二次确认，确定后同步关闭所有相关的任务，同时生成的调度也要关闭<br>- **复制**：在新的页签打开，同时保持之前任务包的所有内容<br>**任务规则管理**<br>- 支持模糊搜索任务包名称或精确搜索任务包编码<br>- 支持模糊搜索任务规则名称<br>- 点击列表任务包，点击跳转任务包规则详情页<br>- 点击列表任务数或任务明细，跳转任务明细页|![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=OGQxNzRjN2UyNTY5Mjc5YzUwN2RkOWRhMWNlYTJmNTVfNTBlOTgwYzJlYmY1MTVlMGM2NzIzMDI5NGNmNTE3NDFfSUQ6NzYxNjY0MTEwNjMyMzI3ODgxMV8xNzg1ODk4NDYzOjE3ODU5ODQ4NjNfVjM)<br>![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=OGIwOTNlMmNjM2VjZTU3NTU1NjViMzI4NDE0MzkyZjNfZTFjZjc1OGJjNTJjMjMxZGQ1MDAwYjIxMjJlYjc5MWNfSUQ6NzYxNjY0MTM4NTA2MDIwNzU3OV8xNzg1ODk4NDYzOjE3ODU5ODQ4NjNfVjM)|
|运营端|新增 \- 任务规则配置页|- 整体配置页面，分为左右两边，左边为任务包的生成下发机制，右侧为具体任务和任务的完成条件配置，顶部为整体的操作按钮（本期暂无执行日志）<br>### ⬅️ 左侧 任务包下发<br>- **基本信息**<br>    - **任务包规则名称**：H5详情页展示内容<br>    - **备注**：任务列表备注内容<br>    - **下发人**：当前只有总部下发<br>    - **下发对象**：当前只有门店，后续会增加人和经销商等<br>        - 对象群由数仓提供接口，根据对象返回对象群列表，可跳转对象群编辑<br>    - **下发时间**：<br>        - **手动下发**：当前只有总部下发，点击即可下发<br>        - **定时调度**：配置表达式，定时执行（后续优化成配置）需要配置截止时间<br>        - **其他任务完成下发、数据变更下发**：本期不做<br>    - 已下发，默认不再重复下发<br>        - 例：A网点3月2号命中下发了任务，3月3号命中不再下发任务<br>- **完成条件**<br>    - 判断标准：<br>        - 以任务完成为准：则必需配置每个任务的完成条件<br>            - 当前版本仅支持所有任务完成或任一任务完成<br>        - 整体判断：需要配置完成逻辑，及判断时间（同任务包下发）<br>            - 同时可以定义截止完成同步关闭任务规则<br>            - 同时支持任务包完成，同步完成所有任务<br>### ➡️ 右侧 任务列表<br>- **任务信息**<br>    - 任务标题和说明，用于H5展示<br>    - **截止时间**：相对时间，相对于下发时候后什么时间，以及指定具体年月日时间点<br>- **是否关联标准模版**<br>    - 如果有，弹窗配置选择任务模版<br>        - 根据模版不同，带出不同的变量，变量根据字段类型，对应是输入框还是选项框<br>        - 自动带出完成逻辑的sql和判断时间，此处支持修改配置（后续任务动作调整不影响已生成的任务，除非编辑刷新更新配置；如果规则删除了，则刷新将会清空变量和完成逻辑）<br>    - 如果没有需要蛋醋配置完成标准和判断时间（可以下期再做）|![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=MTM0OWVkNjYzYTQ4ZmFkYzU4OTI5M2MwYjdjYzA4MGZfMGJiOWEyY2QxYmNiYjBhNTM3MWEyZmQzYzY0ZGZjYzZfSUQ6NzYyMTUwMDIwMjc2MzgzMjUxM18xNzg1ODk4NDYzOjE3ODU5ODQ4NjNfVjM)<br>![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=ZDQzNGU4ZWQyZjkyNTk4YjViNWFhMjA1MmQxMWIzNjNfNzM2NWFkMGQ3NDVhZmIzYWVjOWE2Y2JhMDA1YWI5NDhfSUQ6NzYyMTUwMDI2MTI0NDMyNDgyOF8xNzg1ODk4NDYzOjE3ODU5ODQ4NjNfVjM)<br>![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=MTU1NmI5ZjA5MTU4MzRhZTE0YTJjNDZhZTZlOWMzMTVfYzk1NDRjNmM0MDBjZjM4NTVmZGRiNDNhNzA3ZmJkOTNfSUQ6NzYyMTUwMDI5ODk2MDA2MzY3N18xNzg1ODk4NDYzOjE3ODU5ODQ4NjNfVjM)|
|运营端|新增 \- 任务明细|展示规则实际下发对应的任务包明细和任务明细<br>**任务包明细**<br>- 状态：已完成、关闭、进行中<br>**任务明细**<br>- 状态：已完成、关闭、过期、进行中<br><br>本期仅用于展示，后续增加任务的删改操作，和H5预览<br>|![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=NDUxYWU0Nzc2MGY1MjM1NjQxNGYxYTc0MWQ3NGMwZWFfZTQxOWE2ODViY2UyYTZjMWQ2ODllMzI1N2JlOTdlYjNfSUQ6NzYxNjY0NjA5NjQ2NzQ2MzM0OF8xNzg1ODk4NDYzOjE3ODU5ODQ4NjNfVjM)<br>![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=OWNiMDgzYzExZmVjODFiN2QyMjJhNmQwOWEzNTA2OGJfYjFkOGM1YTEwNTgwNWY1MmZiYmU4ZjBjMDAzOTlkMWRfSUQ6NzYxNjY0NjE1Mzg3OTQwNzgwMl8xNzg1ODk4NDYzOjE3ODU5ODQ4NjNfVjM)|
|应用端|联动 \- H5任务详情|- 保持原页面展示即可，数据联动当前文档内容|![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=MWE0NzE5YmY0OGRkYzk3YWI1ODAzYzE0ZDJkYzE4OTNfY2FhZGU2YWExZDkxMTYzOWQzYWU1ZTU5ZDI1YmMwOWZfSUQ6NzYxNjMwMTMxMDcxOTUxMTc2OV8xNzg1ODk4NDYzOjE3ODU5ODQ4NjNfVjM)|

# 原型地址

[https://www.figma.com/design/2ipoyIhwH3zX3G0p8oDFWX/%E9%94%80%E5%94%AE%E4%BB%BB%E5%8A%A1?node-id=5-4&t=YvJHoVbZ7OzVMswk-1]()

# 场景验证

[销售任务场景收集](https://k11pnjpvz1.feishu.cn/wiki/UTI9wtZ3ciduKbkj6ajcWYPln5d?from=from_copylink)

