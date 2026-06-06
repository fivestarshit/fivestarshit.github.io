-- ============================================================
-- 任务执行类型选项表（/executionTypeOptions 数据来源）
-- ============================================================

CREATE TABLE `task_execution_type_option` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `task_execution_type` VARCHAR(64) NOT NULL COMMENT '任务执行类型编码',
  `task_execution_type_name` VARCHAR(128) NOT NULL COMMENT '任务执行类型名称',
  `sort_order` INT NOT NULL DEFAULT 0 COMMENT '排序，越小越靠前',
  `status` TINYINT NOT NULL DEFAULT 1 COMMENT '状态: 1-启用, 0-停用',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否, 1-是',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_task_execution_type` (`task_execution_type`),
  KEY `idx_status_sort` (`status`, `sort_order`),
  KEY `idx_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='任务执行类型选项字典';

-- 初始化数据（与历史硬编码一致，可按业务调整；重复执行请用 INSERT IGNORE 或先判空）
INSERT IGNORE INTO `task_execution_type_option`
  (`task_execution_type`, `task_execution_type_name`, `sort_order`, `status`, `is_deleted`)
VALUES
  ('a', '销售订单', 1, 1, 0),
  ('b', '巡店记录', 2, 1, 0),
  ('c', '拜访计划', 3, 1, 0);
