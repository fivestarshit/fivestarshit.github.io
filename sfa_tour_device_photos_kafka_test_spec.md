# 巡店照片结果 Kafka 消费测试规格

## 功能模块：Kafka 消费 `*-sfa_tour_device_photos`

### 一、说明
- Topic：`${spring.profiles.active}-sfa_tour_device_photos`（例如 `online-sfa_tour_device_photos`）。
- 消息可无 Kafka key；value 为 JSON 字符串。若 `record.key()` 为空，消费端默认将业务 key 视为 `tour_device_photos`（用于日志与后续扩展）。

### 二、消息体字段整理规则
遍历根节点下 `devicePhotoParameters` 数组**每一项**，将嵌套数据**汇总到 JSON 根对象**（与 `userMasterId`、`devicePhotoParameters` 同级）：

| 原路径（每条 devicePhotoParameters 内） | 汇总到根路径 |
|----------------------------------------|--------------|
| `details.object_device_photo_detail__c`（数组） | 根 `object_device_photo_detail__c`：多张照片时**顺序拼接**为一个数组 |
| `detect_result.sku_detect_result`（数组） | 根 `sku_detect_result`：多条目时**顺序拼接**外层数组元素 |

从各条目中移除已汇总字段；若 `details` / `detect_result` 已无其它键则删除该对象。

实现类：`com.yqsl.sls.common.utils.TourDevicePhotosPayloadUtils`

### 三、请求/消息示例（value 为 JSON）

```json
{
  "userMasterId": "132872",
  "finishTime": 1775011340437,
  "uniqCode": "YQBA21018893SC-600YS_SC-600YS",
  "code": "YQBA21018893SC-600YS",
  "status": "2",
  "shopCode": "WD43017242",
  "shopName": "大嘴猴超市",
  "devicePhotoParameters": [
    {
      "object_data": {},
      "details": {
        "object_device_photo_detail__c": [
          {
            "productname__c": "示例商品",
            "code__c": "K1AXXX",
            "count__c": 1.0,
            "record_type": "default__c"
          }
        ]
      },
      "detect_result": {
        "sku_detect_result": [
          [
            {
              "sku_code": "K1AXXX",
              "sku_name": "示例",
              "score": 0.9,
              "location": {}
            }
          ]
        ]
      }
    }
  ]
}
```

整理后，在**根对象**上增加（示例仅一条 `devicePhotoParameters` 时与原先明细一致）：
- 根 `"object_device_photo_detail__c": [ ... ]`（由所有条目的 `details.object_device_photo_detail__c` 合并）
- 根 `"sku_detect_result": [ ... ]`（由所有条目的 `detect_result.sku_detect_result` 外层元素顺序合并）

各 `devicePhotoParameters[i]` 内删除已汇总的 `details`/`detect_result` 或清空后移除空对象。

### 四、回归要点
- `devicePhotoParameters` 缺失或非数组：不改变根 JSON 其它字段。
- JSON 非法：保持原字符串，不抛异常（由工具类吞掉解析异常并返回原文）。
