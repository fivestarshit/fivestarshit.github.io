# 设备 binlog Kafka 消费测试规格

> **变更说明（2026-09-14）**：消费入口 info 日志不再打印消息 value；完整报文只在 `TaskDistributionKafkaHandler#handleTaskDistribution` 打一次。

## 功能模块：Kafka 消费设备 binlog topic

### 一、说明

应用支持 **2 套 Kafka 连接**（互不干扰）：

| 用途 | 配置项 | 消费者 |
|------|--------|--------|
| 任务下发 / 巡店照片 | `spring.kafka.bootstrap-servers` | `SalesTaskConsumer`（默认容器工厂） |
| 设备 binlog | `spring.kafka.bootstrap-servers-device` | `DeviceBinLogConsumer` → `DeviceBinLogMessageHandler` → `TaskDistributionKafkaHandler` |

集群地址与 topic **按环境在 MSE 中分别配置**（测试/线上各配各的，代码侧统一使用 `bootstrap-servers-device`）。

### 二、MSE 配置示例

**测试环境：**

```yaml
spring:
  kafka:
    bootstrap-servers: alikafka-pre-cn-tl32ngezy009-1-vpc.alikafka.aliyuncs.com:9092,...
    bootstrap-servers-device: 172.17.30.102:9092
    consumer:
      group-id: sls-sales-task
      enable-auto-commit: true
      auto-commit-interval: 100
    topics:
      device-bin-log: gos-spacex-device-bin-log-dev
```

**线上环境：**

```yaml
spring:
  kafka:
    bootstrap-servers: alikafka-pre-cn-tl32ngezy009-1-vpc.alikafka.aliyuncs.com:9092,...
    bootstrap-servers-device: alikafka-pre-cn-zvp2th4zb00k-1-vpc.alikafka.aliyuncs.com:9092,alikafka-pre-cn-zvp2th4zb00k-2-vpc.alikafka.aliyuncs.com:9092,alikafka-pre-cn-zvp2th4zb00k-3-vpc.alikafka.aliyuncs.com:9092
    consumer:
      group-id: sls-sales-task
      enable-auto-commit: true
      auto-commit-interval: 100
    topics:
      device-bin-log: gos-spacex-device-bin-log-online
```

### 三、回归要点

- 配置 `bootstrap-servers-device` 与 `topics.device-bin-log` 后启动，日志应出现消费者订阅对应 topic。
- 未配置 `bootstrap-servers-device` 时，`DeviceKafkaConfig` / `DeviceBinLogConsumer` 不加载，不影响 `SalesTaskConsumer`。
- 消息体非空时与 shop-ease 一致：经 `TaskDistributionKafkaHandler#handleTaskDistribution` 走模板映射、实例匹配、条件计算。
- 消费入口 info 日志只打 topic/partition/offset/key，不打 value；value 以 `handleTaskDistribution` 的「处理任务下发消息」为准。
- 消息处理异常时仅打错误日志，不阻塞 offset 提交。

### 四、消息示例

消费端将业务 key 设为当前订阅的 **topic 名称**（不使用 Kafka `record.key()`），再传入 `TaskDistributionKafkaHandler#handleTaskDistribution` 做模板映射。

Kafka value 为 binlog JSON 字符串（具体结构以 spacex 侧为准），示例：

```json
{
  "database": "spacex",
  "table": "device",
  "type": "UPDATE",
  "data": {}
}
```
