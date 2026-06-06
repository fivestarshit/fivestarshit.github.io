# Kafka 测试推送接口测试规格

## 功能模块：Kafka 测试推送

### 一、说明
- 接口：`POST /sales/task/kafka/test/push`
- 用途：开发/联调时向**任意指定**的 topic 发送一条消息（`payload` 为 **JSON 对象/数组**，服务端序列化为字符串写入 Kafka value），可选 key；实现参考 `sls-bss-tour-middle` 的 `PushDataServiceImpl#pushData`（本服务无飞书告警，仅委托 `KafkaProducer`）。
- 前置：需配置 `spring.kafka.bootstrap-servers`，否则该 Controller 与 `KafkaTestPushService` 不加载。

### 二、请求 JSON 示例

```json
{
  "topic": "online-sfa_tour_device_photos",
  "//topic": "Kafka topic 全名；若按环境带 profile 前缀，请自行拼好（如 online-、dev-）",
  "key": "tour_device_photos",
  "//key": "可选；不传或空字符串表示消息无 key",
  "payload": {
    "userMasterId": "132872",
    "shopCode": "WD43017242"
  },
  "//payload": "消息体，传 JSON 对象（或数组）；服务端 Fastjson 序列化后作为 Kafka value"
}
```

无 key 示例：

```json
{
  "topic": "online-sfa_tour_device_photos",
  "payload": {
    "test": true
  }
}
```

### 三、响应示例

```json
{
  "code": 0,
  "message": "success",
  "data": null
}
```

### 四、失败与回归
- `topic` 为空、`payload` 为 null：业务异常或校验失败
- Kafka 集群不可用：由 `KafkaProducer` 异步回调打 error 日志
