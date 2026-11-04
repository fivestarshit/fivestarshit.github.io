# 巡店记录 Kafka（v2_tour_patrol_record）+ pure_sku 补写测试规格

## 变更说明
- **2026-08-31**：对接 `topic-tourease`（完整 topic=`${spring.profiles.active}-topic-tourease`，如 `online-topic-tourease`），仅处理 key=`v2_tour_patrol_record`；接收后先将 `tourPhotos` 展平（`photoType` 合并进原 `skuDetail` 项，去掉嵌套），再按 `tourPhotos[*].code` 调商品中心 `POST /commodity/sku/snapshot/list`，取 `epuList` 中 `epuType=pure_sku` 的 `epuCode` 写回，再走统一 `TaskDistributionKafkaHandler`。
- **2026-09-01**：巡店记下发 JSON **最外层**增加 `skuNumer`（识别总数），值为展平后 `tourPhotos[*].code` **去重**后的数量；无 `tourPhotos` 或无可识别 `code` 时为 `0`。
- **2026-09-14**：消费入口与 pure_sku 补写完成日志不再打印消息 value / enriched JSON；完整报文只在 `handleTaskDistribution` 打一次。

## 1. 消费入口
- Topic：`${spring.profiles.active}-topic-tourease`
- Key：必须为 `v2_tour_patrol_record`（其它 key 跳过）
- 消费者：`SalesTaskConsumer#handleTourPatrolRecordMessage`

## 2. 本地后处理
- 服务：`TourPatrolRecordPureSkuEnrichService#enrichTourPhotosWithPureSkuEpuCode`

### 2.1 tourPhotos 展平
- 入站（Kafka 原结构）：

```json
{
  "tourPhotos": [
    {
      "photoType": 12,
      "skuDetail": [
        {
          "code": "K1AWXR00141011209",
          "name": "外星人-电解质水0糖版-白桃 PET600ml*1 (26年乐享)",
          "num": 1,
          "series": "外星人-电解质水0糖版"
        }
      ]
    }
  ]
}
```

- 展平后（下发结构）：

```json
{
  "skuNumer": 1,
  "tourPhotos": [
    {
      "photoType": 12,
      "code": "K1AWXR00141011209",
      "name": "外星人-电解质水0糖版-白桃 PET600ml*1 (26年乐享)",
      "num": 1,
      "series": "外星人-电解质水0糖版",
      "epuCode": "SKUxxx"
    }
  ]
}
```

- 规则：每个 `skuDetail` 项复制为一条 tourPhotos 元素，并写入外层 `photoType`；去掉 `skuDetail` 嵌套。一条 photo 含多个 skuDetail 时展开为多条。
- 根级 `skuNumer`：对展平后 `tourPhotos` 中非空 `code` 去重计数（同一 `code` 出现多次只计 1）；空数组 / 无 `code` / 无 `tourPhotos` 时为 `0`。

### 2.2 pure_sku 补写
- Feign：`CommodityFeignService#listSkuSnapshot` → `/commodity/sku/snapshot/list`
- 请求示例：

```json
{
  "page": 1,
  "pageSize": 20,
  "skuCodes": ["K1AWXR00141011209"]
}
```

- 匹配规则：展平后 `code` = 快照 `skuCode` → `epuList` 中首个 `epuType=pure_sku` 的 `epuCode`
- 商品接口失败：打 error 日志，**仍用已展平（可能无 epuCode）的 JSON 继续下发**

## 3. 继续往下执行
- 调用：`TaskDistributionKafkaHandler#handleTaskDistribution("v2_tour_patrol_record", enrichedJson)`
- 任务定义需配置 `task_execution_event_code = v2_tour_patrol_record`，字段映射可使用 `skuNumer` / `tourPhotos[*].code` / `tourPhotos[*].epuCode` / `tourPhotos[*].photoType`

## 4. 用例

### 4.1 展平 + 正常补写
- 前置：消息含嵌套 `tourPhotos[0].photoType=12` + `skuDetail[0].code=K1AWXR00141011209`；商品快照返回 pure_sku epuCode
- 预期：下发 JSON 中 `tourPhotos` 为一层数组，元素含 `photoType`、`code`、`epuCode`，无 `skuDetail`；根级 `skuNumer=1`

### 4.2 一条 photo 多个 skuDetail
- 前置：`skuDetail` 长度 2，两条 `code` 不同
- 预期：`tourPhotos` 长度 2，两条均带同一 `photoType`；根级 `skuNumer=2`

### 4.3 无 tourPhotos / 无 code
- 预期：不调商品接口；有嵌套则仍展平；根级 `skuNumer=0`

### 4.4 非目标 key
- 前置：key=`other_key`
- 预期：跳过，不调商品接口、不下发

### 4.5 商品接口异常
- 预期：日志 error；仍调用 `handleTaskDistribution`（已展平，无 epuCode，仍带 `skuNumer`）

### 4.6 skuNumer 去重
- 前置：展平后 `tourPhotos` 含 3 条，其中 2 条 `code` 相同、1 条不同
- 预期：根级 `skuNumer=2`（按 `code` 去重，不是数组长度）
