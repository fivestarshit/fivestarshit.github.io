-- ============================================================
-- 任务关联系统选项表（/systemOptions 数据来源）
-- ============================================================

CREATE TABLE `task_system_option` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `system_name` VARCHAR(128) NOT NULL COMMENT '系统名称（展示）',
  `system_code` VARCHAR(64) NOT NULL COMMENT '系统编码',
  `sort_order` INT NOT NULL DEFAULT 0 COMMENT '排序，越小越靠前',
  `status` TINYINT NOT NULL DEFAULT 1 COMMENT '状态: 1-启用, 0-停用',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否, 1-是',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_system_code` (`system_code`),
  KEY `idx_status_sort` (`status`, `sort_order`),
  KEY `idx_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='任务系统选项字典';

INSERT IGNORE INTO `task_system_option`
  (`system_name`, `system_code`, `sort_order`, `status`, `is_deleted`)
VALUES
  ('销售任务中心', 'SLS_SALES_TASK', 1, 1, 0),
  ('主数据平台', 'MDM', 2, 1, 0);
