-- ============================================================
-- 任务对象选项表（/objectOptions 数据来源）
-- ============================================================

CREATE TABLE `task_object_option` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `object_name` VARCHAR(128) NOT NULL COMMENT '对象名称（展示）',
  `object_code` VARCHAR(64) NOT NULL COMMENT '对象编码',
  `group_mapping_code` VARCHAR(64) DEFAULT NULL COMMENT '分组映射编码，用于分组映射转换',
  `sort_order` INT NOT NULL DEFAULT 0 COMMENT '排序，越小越靠前',
  `status` TINYINT NOT NULL DEFAULT 1 COMMENT '状态: 1-启用, 0-停用',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否, 1-是',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_object_code` (`object_code`),
  KEY `idx_status_sort` (`status`, `sort_order`),
  KEY `idx_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='任务对象选项字典';

INSERT IGNORE INTO `task_object_option`
  (`object_name`, `object_code`, `sort_order`, `status`, `is_deleted`)
VALUES
  ('门店', 'STORE', 1, 1, 0),
  ('经销商', 'DEALER', 2, 1, 0),
  ('人员', 'PERSON', 3, 1, 0),
  ('商品', 'PRODUCT', 4, 1, 0);
