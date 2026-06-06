-- ============================================================
-- 数据库表结构变更累积脚本（update_tables.sql）
-- 说明：每次修改表结构时，将 ALTER 语句追加至此文件，便于已有环境升级
-- ============================================================

-- ------------------------------------------------------------
-- task_distribution_detail
-- ------------------------------------------------------------
-- 新增 target_entity_field_mapped_id
-- ALTER TABLE `task_distribution_detail`
--   ADD COLUMN `target_entity_field_mapped_id` BIGINT DEFAULT NULL COMMENT '关联 biz_template_field_map.id' AFTER `target_entity_code`,
--   ADD KEY `idx_target_entity_field_mapped_id` (`target_entity_field_mapped_id`);

-- ------------------------------------------------------------
-- task_instance
-- ------------------------------------------------------------
-- 新增 source_data（接收到的源数据 JSON）
ALTER TABLE `task_instance` ADD COLUMN `source_data` JSON DEFAULT NULL COMMENT '接收到的源数据(JSON，如 Kafka 消息体)' AFTER `triggered_by_data_change`;

-- 新增 task_result_data（任务下发解析结果 JSON）
ALTER TABLE `task_instance` ADD COLUMN `task_result_data` JSON DEFAULT NULL COMMENT '任务下发解析结果(JSON: TaskDistributionTaskResult)' AFTER `source_data`;

-- 新增 task_distribution_detail_id（关联任务明细）
ALTER TABLE `task_instance` ADD COLUMN `task_distribution_detail_id` BIGINT DEFAULT NULL COMMENT '关联任务明细ID(task_distribution_detail.id)' AFTER `task_result_data`;

-- 新增索引
ALTER TABLE `task_instance` ADD KEY `idx_task_distribution_detail_id` (`task_distribution_detail_id`);

-- ------------------------------------------------------------
-- task_definition
-- ------------------------------------------------------------
-- 新增 distributed_at（下发具体时间）
ALTER TABLE `task_definition` ADD COLUMN `distributed_at` DATETIME DEFAULT NULL COMMENT '下发具体时间' AFTER `template_ids`;
-- 新增 system_ids（关联系统ID列表）
ALTER TABLE `task_definition` ADD COLUMN `system_ids` JSON DEFAULT NULL COMMENT '关联系统ID列表(JSON数组，关联 task_system_option.id)' AFTER `template_ids`;

-- ------------------------------------------------------------
-- task_rule
-- ------------------------------------------------------------
-- 新增 distributed_at（下发具体时间）
ALTER TABLE `task_rule` ADD COLUMN `distributed_at` DATETIME DEFAULT NULL COMMENT '下发具体时间' AFTER `action_execution_mode`;
-- 新增 is_repeat（是否需要重复下发）
ALTER TABLE `task_rule` ADD COLUMN `is_repeat` TINYINT(1) DEFAULT NULL COMMENT '是否需要重复下发：0-否, 1-是' AFTER `distributed_at`;
-- 下发对象群（与任务包扩展语义对齐，便于规则维度冗余查询）
ALTER TABLE `task_rule` ADD COLUMN `distribution_object_group_id` VARCHAR(128) DEFAULT NULL COMMENT '下发对象群ID' AFTER `is_repeat`;
ALTER TABLE `task_rule` ADD COLUMN `distribution_object_group_name` VARCHAR(256) DEFAULT NULL COMMENT '下发对象群名称' AFTER `distribution_object_group_id`;
-- 任务判断截止时间（类型与结构与 deadline_type / deadline_config 一致）
ALTER TABLE `task_rule` ADD COLUMN `task_judgment_deadline_type` VARCHAR(20) DEFAULT NULL COMMENT '任务判断截止时间类型: RELATIVE/ABSOLUTE，语义与 deadline_type 一致' AFTER `deadline_config`;
ALTER TABLE `task_rule` ADD COLUMN `task_judgment_deadline_config` JSON DEFAULT NULL COMMENT '任务判断截止时间配置(JSON)，结构与 deadline_config 一致' AFTER `task_judgment_deadline_type`;

-- ------------------------------------------------------------
-- task_execution_log -> task_instance_execution_log
-- ------------------------------------------------------------
-- 重命名任务执行日志表
RENAME TABLE `task_execution_log` TO `task_instance_execution_log`;

-- ------------------------------------------------------------
-- biz_template_field_map
-- ------------------------------------------------------------
-- 新增 template_task_id（关联模板任务ID）
ALTER TABLE `biz_template_field_map` ADD COLUMN `template_task_id` BIGINT DEFAULT NULL COMMENT '关联模板任务ID(task_definition.id, task_type=TEMPLATE)' AFTER `template_id`;
ALTER TABLE `biz_template_field_map` ADD KEY `idx_template_task_id` (`template_task_id`);

-- ------------------------------------------------------------
-- biz_template_config
-- ------------------------------------------------------------
-- 新增 task_execution_event_code（执行类型监听的事件编码）
ALTER TABLE `biz_template_config` ADD COLUMN `task_execution_event_code` VARCHAR(128) DEFAULT NULL COMMENT '执行类型监听的事件编码' AFTER `database_name`;

-- 新增 groovy_execute_param_sample_json（GroovyShell 执行参数示例 JSON）
ALTER TABLE `biz_template_config`
  ADD COLUMN `groovy_execute_param_sample_json` JSON DEFAULT NULL
  COMMENT 'GroovyShell 执行参数示例 JSON（用于 /sales/task/groovy/execute）'
  AFTER `task_execution_event_code`;

-- ------------------------------------------------------------
-- task_execution_type_option（任务执行类型选项字典）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `task_execution_type_option` (
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

INSERT IGNORE INTO `task_execution_type_option`
  (`task_execution_type`, `task_execution_type_name`, `sort_order`, `status`, `is_deleted`)
VALUES
  ('a', '销售订单', 1, 1, 0),
  ('b', '巡店记录', 2, 1, 0),
  ('c', '拜访计划', 3, 1, 0);

-- ------------------------------------------------------------
-- task_object_option（任务对象选项字典）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `task_object_option` (
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

-- ------------------------------------------------------------
-- biz_template_field_map
-- ------------------------------------------------------------
-- 新增 object_code、is_search_primary_key
ALTER TABLE `biz_template_field_map` ADD COLUMN `object_code` VARCHAR(64) DEFAULT NULL COMMENT '对象类型编码（如 STORE/DEALER，与 task_object_option.object_code 一致）' AFTER `template_task_id`;
ALTER TABLE `biz_template_field_map` ADD COLUMN `is_search_primary_key` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否搜索主键：用于标识检索时的主键映射字段' AFTER `is_searchable`;
ALTER TABLE `biz_template_field_map` ADD COLUMN `data_type_definition` VARCHAR(64) DEFAULT NULL COMMENT '数据类型定义（业务值逻辑属性类型；与 data_type 区分，data_type 用于取值映射）' AFTER `data_type`;
ALTER TABLE `biz_template_field_map` ADD KEY `idx_object_code` (`object_code`);

-- ------------------------------------------------------------
-- task_system_option（任务系统选项字典）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `task_system_option` (
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

-- ------------------------------------------------------------
-- task_execution_type_option：删除 task_execution_event_code（事件编码由 biz_template_config / task_definition 承载，字典表不再存储）
-- 说明：仅当库中该表仍含此列时执行；若全新库已按上文 CREATE（无该列）建表，执行本句会报错可忽略
-- ------------------------------------------------------------
ALTER TABLE `task_execution_type_option` DROP COLUMN `task_execution_event_code`;

-- ------------------------------------------------------------
-- task_definition：新增 template_field_ids（关联 biz_template_field_map.id 列表，JSON 数组）
-- ------------------------------------------------------------
ALTER TABLE `task_definition` ADD COLUMN `template_field_ids` JSON DEFAULT NULL COMMENT '关联 biz_template_field_map.id 列表(JSON数组)，TEMPLATE 任务定义使用' AFTER `system_ids`;

-- ------------------------------------------------------------
-- task_distribution_detail：新增 object_code（与 object_type 同值）
-- ------------------------------------------------------------
ALTER TABLE `task_distribution_detail` ADD COLUMN `object_code` VARCHAR(64) DEFAULT NULL COMMENT '对象编码，与 object_type 同值' AFTER `object_type`;
UPDATE `task_distribution_detail` SET `object_code` = `object_type` WHERE `object_code` IS NULL OR `object_code` = '';

-- ------------------------------------------------------------
-- task_definition：删除 object_type（以 object_code 为准；请先确保 object_code 已回填）
-- ------------------------------------------------------------
UPDATE `task_definition` SET `object_code` = `object_type` WHERE (`object_code` IS NULL OR TRIM(`object_code`) = '') AND `object_type` IS NOT NULL;
ALTER TABLE `task_definition` DROP COLUMN `object_type`;

-- ------------------------------------------------------------
-- task_distribution_detail：删除 object_type（以 object_code 为准；请先执行上文 object_code 回填）
-- ------------------------------------------------------------
UPDATE `task_distribution_detail` SET `object_code` = `object_type` WHERE (`object_code` IS NULL OR `object_code` = '') AND `object_type` IS NOT NULL;
ALTER TABLE `task_distribution_detail` DROP COLUMN `object_type`;

-- ------------------------------------------------------------
-- task_distribution_detail：任务开始时间、任务截止时间
-- ------------------------------------------------------------
ALTER TABLE `task_distribution_detail` ADD COLUMN `start_time` DATETIME DEFAULT NULL COMMENT '任务开始时间' AFTER `task_month`;
ALTER TABLE `task_distribution_detail` ADD COLUMN `end_time` DATETIME DEFAULT NULL COMMENT '任务截止时间' AFTER `start_time`;

-- ------------------------------------------------------------
-- task_definition：完成脚本（任务定义维度；createPackage 子 TASK 在 tasks[].completionScript 传递，不落 task_rule）
-- ------------------------------------------------------------
ALTER TABLE `task_definition` ADD COLUMN `completion_script` TEXT DEFAULT NULL COMMENT '完成标准代码脚本(Groovy等)，任务定义维度' AFTER `completion_logic`;

-- ------------------------------------------------------------
-- task_template_definition：TEMPLATE 任务定义独立表（字段与 task_definition 一致，template_ids → data_template_ids）
-- 执行顺序：1) 建表 2) 迁移数据 3) 从 task_definition 删除 TEMPLATE 行（若有外键请先处理）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `task_template_definition` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `task_code` VARCHAR(64) NOT NULL COMMENT '任务唯一编码',
  `task_name` VARCHAR(128) NOT NULL COMMENT '任务名称',
  `task_type` VARCHAR(32) NOT NULL DEFAULT 'TEMPLATE' COMMENT '任务类型，恒为 TEMPLATE',
  `parent_id` BIGINT DEFAULT NULL COMMENT '父任务ID',
  `task_source` VARCHAR(64) DEFAULT NULL COMMENT '任务来源',
  `related_id` VARCHAR(64) DEFAULT NULL COMMENT '关联业务ID',
  `related_name` VARCHAR(128) DEFAULT NULL COMMENT '关联业务名称',
  `object_id` VARCHAR(64) DEFAULT NULL COMMENT '对象ID',
  `object_name` VARCHAR(128) DEFAULT NULL COMMENT '对象名称',
  `object_code` VARCHAR(64) DEFAULT NULL COMMENT '对象编码',
  `object_owner` VARCHAR(64) DEFAULT NULL COMMENT '对象负责人',
  `start_time` DATETIME DEFAULT NULL COMMENT '任务开始时间',
  `end_time` DATETIME DEFAULT NULL COMMENT '任务截止时间',
  `task_month` DATE DEFAULT NULL COMMENT '任务月份',
  `finish_time` DATETIME DEFAULT NULL COMMENT '任务完成时间',
  `finish_related_id` VARCHAR(64) DEFAULT NULL COMMENT '完成关联业务ID',
  `finish_visit_id` VARCHAR(64) DEFAULT NULL COMMENT '完成关联外勤拜访ID',
  `variables` JSON DEFAULT NULL COMMENT '参数/变量定义',
  `completion_logic` TEXT DEFAULT NULL COMMENT '完成逻辑脚本',
  `completion_script` TEXT DEFAULT NULL COMMENT '完成标准代码脚本',
  `condition_ids` JSON DEFAULT NULL COMMENT '关联条件库ID列表',
  `task_title` VARCHAR(255) DEFAULT NULL COMMENT '任务标题',
  `task_description` TEXT DEFAULT NULL COMMENT '任务说明',
  `distribution_task_count` BIGINT DEFAULT NULL COMMENT '下发的普通任务总数量',
  `task_execution_type` VARCHAR(32) DEFAULT NULL COMMENT '任务执行类型编码',
  `task_execution_type_name` VARCHAR(128) DEFAULT NULL COMMENT '任务执行类型中文值',
  `task_execution_event_code` VARCHAR(64) DEFAULT NULL COMMENT '执行类型监听的事件编码',
  `status` TINYINT NOT NULL DEFAULT 1 COMMENT '配置状态',
  -- `task_status` VARCHAR(32) DEFAULT 'NOT_STARTED' COMMENT '运行状态', -- 2026-04-07：已从 task_template_definition 删除
  `data_template_ids` JSON DEFAULT NULL COMMENT '数据模板关联ID列表(原 template_ids)，关联 biz_template_config.id 等',
  `system_ids` JSON DEFAULT NULL COMMENT '关联系统ID列表',
  `template_field_ids` JSON DEFAULT NULL COMMENT '关联 biz_template_field_map.id 列表',
  `distributed_at` DATETIME DEFAULT NULL COMMENT '下发具体时间',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_task_code` (`task_code`),
  KEY `idx_parent_id` (`parent_id`),
  -- KEY `idx_task_status` (`task_status`), -- 2026-04-07：已从 task_template_definition 删除
  KEY `idx_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='任务模板定义(task_type=TEMPLATE)，自 task_definition 拆出';

INSERT INTO `task_template_definition` (
  `id`, `task_code`, `task_name`, `task_type`, `parent_id`, `task_source`, `related_id`, `related_name`,
  `object_id`, `object_name`, `object_code`, `object_owner`,
  `start_time`, `end_time`, `task_month`, `finish_time`, `finish_related_id`, `finish_visit_id`,
  `variables`, `completion_logic`, `completion_script`, `condition_ids`, `task_title`, `task_description`,
  `distribution_task_count`, `task_execution_type`, `task_execution_type_name`, `task_execution_event_code`,
  `status`, `data_template_ids`, `system_ids`, `template_field_ids`, `distributed_at`,
  `is_deleted`, `created_at`, `updated_at`
)
SELECT
  `id`, `task_code`, `task_name`, `task_type`, `parent_id`, `task_source`, `related_id`, `related_name`,
  `object_id`, `object_name`, `object_code`, `object_owner`,
  `start_time`, `end_time`, `task_month`, `finish_time`, `finish_related_id`, `finish_visit_id`,
  `variables`, `completion_logic`, `completion_script`, `condition_ids`, `task_title`, `task_description`,
  `distribution_task_count`, `task_execution_type`, `task_execution_type_name`, `task_execution_event_code`,
  `status`, `template_ids` AS `data_template_ids`, `system_ids`, `template_field_ids`, `distributed_at`,
  `is_deleted`, `created_at`, `updated_at`
FROM `task_definition`
WHERE UPPER(`task_type`) = 'TEMPLATE';

DELETE FROM `task_definition` WHERE UPPER(`task_type`) = 'TEMPLATE';

-- 若仍保留 task_rule_action_rel 历史数据，可在 DROP 关联表前执行数据回填（示例）：
-- UPDATE `task_rule` tr INNER JOIN `task_rule_action_rel` rel ON rel.rule_id = tr.id AND rel.is_deleted = 0
--   SET tr.task_definition_id = rel.task_def_id WHERE tr.task_definition_id IS NULL;

-- ------------------------------------------------------------
-- task_template_definition：模板类型（TEMPORARY=临时模板，COMMON=常用模板）
-- ------------------------------------------------------------
ALTER TABLE `task_template_definition` ADD COLUMN `template_type` VARCHAR(32) NOT NULL DEFAULT 'COMMON' COMMENT '模板类型:TEMPORARY=临时模板,COMMON=常用模板' AFTER `task_type`;
ALTER TABLE `task_template_definition` ADD KEY `idx_template_type` (`template_type`);

-- ------------------------------------------------------------
-- task_definition / task_template_definition：rule_id；task_rule 删除 task_definition_id
-- 依赖：曾执行过 task_rule.task_definition_id 的库；若为新库无该列，请跳过 UPDATE/DROP 或按实际调整
-- ------------------------------------------------------------
ALTER TABLE `task_definition` ADD COLUMN `rule_id` BIGINT DEFAULT NULL COMMENT '关联 task_rule.id' AFTER `distributed_at`;
ALTER TABLE `task_definition` ADD KEY `idx_rule_id` (`rule_id`);
ALTER TABLE `task_template_definition` ADD COLUMN `rule_id` BIGINT DEFAULT NULL COMMENT '关联 task_rule.id' AFTER `distributed_at`;
ALTER TABLE `task_template_definition` ADD KEY `idx_rule_id` (`rule_id`);
UPDATE `task_definition` td INNER JOIN `task_rule` tr ON tr.task_definition_id = td.id SET td.rule_id = tr.id WHERE tr.task_definition_id IS NOT NULL;
UPDATE `task_template_definition` ttd INNER JOIN `task_rule` tr ON tr.task_definition_id = ttd.id SET ttd.rule_id = tr.id WHERE tr.task_definition_id IS NOT NULL;
ALTER TABLE `task_rule` DROP INDEX `idx_task_definition_id`;
ALTER TABLE `task_rule` DROP COLUMN `task_definition_id`;

-- ------------------------------------------------------------
-- condition_repo：删除 condition_type
-- ------------------------------------------------------------
ALTER TABLE `condition_repo` DROP COLUMN `condition_type`;

-- ------------------------------------------------------------
-- task_rule：是否包含操作（与 createPackage tasks[].hasAction 对齐）
-- ------------------------------------------------------------
ALTER TABLE `task_rule` ADD COLUMN `has_action` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否包含操作(模板动作)；任务包规则为0，子TASK与tasks[].hasAction一致' AFTER `action_execution_mode`;

-- ------------------------------------------------------------
-- dynamic_http_endpoint：动态 HTTP 外部接口配置（替代编译期 Feign，运行时按配置拉数）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `dynamic_http_endpoint` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `config_code` VARCHAR(64) NOT NULL COMMENT '配置编码，全局唯一',
  `config_name` VARCHAR(128) DEFAULT NULL COMMENT '配置名称',
  `base_url` VARCHAR(512) NOT NULL COMMENT '基础域名(含协议)，如 https://api.example.com',
  `path` VARCHAR(512) NOT NULL COMMENT '路径，如 /v2/hcf/xxx',
  `http_method` VARCHAR(16) NOT NULL DEFAULT 'POST' COMMENT 'HTTP方法 GET/POST/PUT/DELETE',
  `query_params_json` JSON DEFAULT NULL COMMENT '默认URL查询参数(JSON对象)',
  `request_body_json` JSON DEFAULT NULL COMMENT '默认请求体(JSON对象)',
  `execute_param_script` TEXT DEFAULT NULL COMMENT '执行参数脚本（Groovy片段，调用时执行并生成动态参数Map）',
  `headers_json` JSON DEFAULT NULL COMMENT '默认请求头(JSON对象)，值支持占位符 {{appKey}} {{appSecret}}',
  `app_key` VARCHAR(256) DEFAULT NULL COMMENT '应用Key',
  `app_secret` VARCHAR(512) DEFAULT NULL COMMENT '应用Secret',
  `remark` VARCHAR(512) DEFAULT NULL COMMENT '备注',
  `access_type` INT DEFAULT NULL COMMENT '接入类型（整数，可空）',
  `access_type_name` VARCHAR(128) DEFAULT NULL COMMENT '接入类型名称',
  `enabled` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否启用 1-启用 0-停用',
  `link_status` VARCHAR(32) NOT NULL DEFAULT 'UNKNOWN' COMMENT '链接状态 UNKNOWN/UP/DOWN',
  `last_check_at` DATETIME DEFAULT NULL COMMENT '上次连通检测或调用时间',
  `last_error_message` VARCHAR(1024) DEFAULT NULL COMMENT '最近一次错误信息',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除 0-否 1-是',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_dynamic_http_config_code` (`config_code`),
  KEY `idx_dynamic_http_enabled` (`enabled`),
  KEY `idx_dynamic_http_link_status` (`link_status`),
  KEY `idx_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='动态HTTP外部接口配置';

-- 已存在环境执行：新增 execute_param_script（按需执行）
ALTER TABLE `dynamic_http_endpoint`
  ADD COLUMN `execute_param_script` TEXT DEFAULT NULL
  COMMENT '执行参数脚本（Groovy片段，调用时执行并生成动态参数Map）'
  AFTER `request_body_json`;

-- 已存在环境执行：新增接入类型与类型名称（按需执行）
ALTER TABLE `dynamic_http_endpoint`
  ADD COLUMN `access_type` INT DEFAULT NULL COMMENT '接入类型（整数，可空）' AFTER `remark`,
  ADD COLUMN `access_type_name` VARCHAR(128) DEFAULT NULL COMMENT '接入类型名称' AFTER `access_type`;

-- ------------------------------------------------------------
-- dynamic_http_endpoint_group：动态HTTP聚合配置主表（一个聚合可关联多个 endpoint）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `dynamic_http_endpoint_group` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `group_code` VARCHAR(64) NOT NULL COMMENT '聚合编码，全局唯一',
  `group_name` VARCHAR(128) DEFAULT NULL COMMENT '聚合名称',
  `remark` VARCHAR(512) DEFAULT NULL COMMENT '备注',
  `enabled` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否启用 1-启用 0-停用',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除 0-否 1-是',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_dynamic_http_group_code` (`group_code`),
  KEY `idx_dynamic_http_group_enabled` (`enabled`),
  KEY `idx_dynamic_http_group_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='动态HTTP聚合配置主表';

-- ------------------------------------------------------------
-- dynamic_http_endpoint_group_rel：动态HTTP聚合-端点关联表
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `dynamic_http_endpoint_group_rel` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `group_id` BIGINT NOT NULL COMMENT '聚合配置ID dynamic_http_endpoint_group.id',
  `endpoint_id` BIGINT NOT NULL COMMENT '端点配置ID dynamic_http_endpoint.id',
  `sort_order` INT NOT NULL DEFAULT 0 COMMENT '排序号，越小越靠前',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除 0-否 1-是',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_dynamic_http_group_endpoint` (`group_id`, `endpoint_id`),
  KEY `idx_dynamic_http_group_id` (`group_id`),
  KEY `idx_dynamic_http_endpoint_id` (`endpoint_id`),
  KEY `idx_dynamic_http_group_rel_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='动态HTTP聚合端点关联表';

-- ------------------------------------------------------------
-- biz_template_config：关联动态HTTP聚合配置
-- ------------------------------------------------------------
ALTER TABLE `biz_template_config`
  ADD COLUMN `dynamic_http_group_id` BIGINT DEFAULT NULL COMMENT '关联动态HTTP聚合配置ID(dynamic_http_endpoint_group.id)' AFTER `task_execution_event_code`,
  ADD KEY `idx_dynamic_http_group_id` (`dynamic_http_group_id`);

-- ------------------------------------------------------------
-- task_definition：删除 template_field_ids（字段映射仅 task_template_definition.template_field_ids 使用；task_definition 无业务写入）
-- 说明：若库中无该列（例如全新库已按最新 DDL 建表），执行本句会报错可忽略
-- ------------------------------------------------------------
ALTER TABLE `task_definition` DROP COLUMN `template_field_ids`;

-- ------------------------------------------------------------
-- task_package_distribution_ext：任务包下发扩展（createPackage 写入，与 PACKAGE 的 task_definition.id 1:1）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `task_package_distribution_ext` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `task_package_def_id` BIGINT NOT NULL COMMENT '任务包 task_definition.id（task_type=PACKAGE）',
  `distribution_object_group_id` VARCHAR(64) DEFAULT NULL COMMENT '任务包下发对象群ID',
  `distribution_object_group_name` VARCHAR(255) DEFAULT NULL COMMENT '任务包下发对象群名称',
  `distribution_type_code` VARCHAR(64) DEFAULT NULL COMMENT '任务包下发类型编码',
  `distribution_type_name` VARCHAR(128) DEFAULT NULL COMMENT '任务包下发类型名称',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否, 1-是',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_task_package_def_id` (`task_package_def_id`),
  KEY `idx_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='任务包下发扩展（关联 PACKAGE 任务定义）';

-- ------------------------------------------------------------
-- task_distribution_detail：任务包 + 子任务 + 目标实体编码 唯一（分群场景同一子任务对多个 target_entity_code 各一条；不含第三列则无法表达多对象）
-- 执行前请先检查并清理重复数据，否则 ADD UNIQUE 会失败：
-- SELECT task_package_id, task_def_id, target_entity_code, COUNT(*) AS c
-- FROM task_distribution_detail WHERE is_deleted = 0
-- GROUP BY task_package_id, task_def_id, target_entity_code HAVING c > 1;
-- ------------------------------------------------------------
ALTER TABLE `task_distribution_detail` ADD UNIQUE KEY `uk_task_pkg_def_target_code` (`task_package_id`, `task_def_id`, `target_entity_code`);

-- ------------------------------------------------------------
-- task_distribution_detail：target_entity_id 允许为空（分群下发时销客未返回可先落库，后续刷数补全）
-- ------------------------------------------------------------
ALTER TABLE `task_distribution_detail` MODIFY COLUMN `target_entity_id` VARCHAR(64) DEFAULT NULL COMMENT '目标实体ID(如门店ID、人员ID)，可空待补全';

-- ------------------------------------------------------------
-- task_definition：任务包下发明细是否已全部写入（分群/手动同步完成后置 true；默认 false）
-- ------------------------------------------------------------
ALTER TABLE `task_definition`
  ADD COLUMN `distribution_push_completed` TINYINT(1) NOT NULL DEFAULT 0
  COMMENT '下发明细是否已全部写入完成：0-否 1-是（仅 task_type=PACKAGE）'
  AFTER `distributed_at`;
ALTER TABLE `task_definition` ADD KEY `idx_pkg_distribution_push` (`task_type`, `task_status`, `distribution_push_completed`);

-- ------------------------------------------------------------
-- 全库统一审计字段：created_by / updated_by（VARCHAR(64)，与 task_rule 已有列一致）
-- 说明：task_rule 已含该两列，无需执行。其余表若列已存在请勿重复执行。
-- ------------------------------------------------------------

ALTER TABLE `biz_template_config`
  ADD COLUMN `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人' AFTER `is_deleted`,
  ADD COLUMN `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人' AFTER `created_by`;

ALTER TABLE `biz_template_field_map`
  ADD COLUMN `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人' AFTER `is_deleted`,
  ADD COLUMN `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人' AFTER `created_by`;

ALTER TABLE `condition_repo`
  ADD COLUMN `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人' AFTER `is_deleted`,
  ADD COLUMN `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人' AFTER `created_by`;

ALTER TABLE `datasource_connection`
  ADD COLUMN `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人' AFTER `is_deleted`,
  ADD COLUMN `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人' AFTER `created_by`;

ALTER TABLE `dynamic_http_endpoint`
  ADD COLUMN `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人' AFTER `is_deleted`,
  ADD COLUMN `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人' AFTER `created_by`;

ALTER TABLE `dynamic_http_endpoint_group`
  ADD COLUMN `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人' AFTER `is_deleted`,
  ADD COLUMN `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人' AFTER `created_by`;

ALTER TABLE `dynamic_http_endpoint_group_rel`
  ADD COLUMN `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人' AFTER `is_deleted`,
  ADD COLUMN `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人' AFTER `created_by`;

ALTER TABLE `task_definition`
  ADD COLUMN `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人' AFTER `is_deleted`,
  ADD COLUMN `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人' AFTER `created_by`;

ALTER TABLE `task_distribution_detail`
  ADD COLUMN `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人' AFTER `is_deleted`,
  ADD COLUMN `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人' AFTER `created_by`;

ALTER TABLE `task_execution_type_option`
  ADD COLUMN `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人' AFTER `is_deleted`,
  ADD COLUMN `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人' AFTER `created_by`;

ALTER TABLE `task_instance`
  ADD COLUMN `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人' AFTER `is_deleted`,
  ADD COLUMN `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人' AFTER `created_by`;

ALTER TABLE `task_instance_execution_log`
  ADD COLUMN `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人' AFTER `remark`,
  ADD COLUMN `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人' AFTER `created_by`;

ALTER TABLE `task_object_option`
  ADD COLUMN `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人' AFTER `is_deleted`,
  ADD COLUMN `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人' AFTER `created_by`;

ALTER TABLE `task_package_distribution_ext`
  ADD COLUMN `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人' AFTER `is_deleted`,
  ADD COLUMN `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人' AFTER `created_by`;

ALTER TABLE `task_system_option`
  ADD COLUMN `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人' AFTER `is_deleted`,
  ADD COLUMN `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人' AFTER `created_by`;

ALTER TABLE `task_template_definition`
  ADD COLUMN `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人' AFTER `is_deleted`,
  ADD COLUMN `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人' AFTER `created_by`;

-- ------------------------------------------------------------
-- task_distribution_detail：任务包 + 子任务 + 对象编码 + 截止时间 + 开始时间 唯一
-- 说明：与 `uk_task_pkg_def_target_code`（task_package_id, task_def_id, target_entity_code）独立；
-- 若同一子任务、相同 object_code 与起止时间应对多个 target_entity_code 各一条（常见分群），则五元组在多行上重复，本 UNIQUE 无法创建或与业务互斥，执行前务必用下方 SQL 校验。
-- 执行前请先检查并清理重复数据，否则 ADD UNIQUE 会失败：
-- SELECT task_package_id, task_def_id, object_code, end_time, start_time, COUNT(*) AS c
-- FROM task_distribution_detail WHERE is_deleted = 0
-- GROUP BY task_package_id, task_def_id, object_code, end_time, start_time HAVING c > 1;
-- ------------------------------------------------------------
ALTER TABLE `task_distribution_detail` ADD UNIQUE KEY `uk_task_pkg_def_target_end_start` (`task_package_id`, `task_def_id`, `target_entity_code`, `end_time`, `start_time`);

-- ------------------------------------------------------------
-- biz_template_field_map：数据来源（展示用）
-- ------------------------------------------------------------
ALTER TABLE `biz_template_field_map`
  ADD COLUMN `data_source` VARCHAR(256) DEFAULT NULL COMMENT '数据来源：用于展示该映射字段对应的数据源说明' AFTER `object_code`;

-- ------------------------------------------------------------
-- biz_template_config：数据来源（展示用）
-- ------------------------------------------------------------
ALTER TABLE `biz_template_config`
  ADD COLUMN `data_source` VARCHAR(256) DEFAULT NULL COMMENT '数据来源：用于展示该业务模板对应的数据源说明' AFTER `datasource_id`;

-- ------------------------------------------------------------
-- biz_template_config：datasource_id 允许为空
-- ------------------------------------------------------------
ALTER TABLE `biz_template_config`
  MODIFY COLUMN `datasource_id` BIGINT DEFAULT NULL COMMENT '关联数据源ID';

-- ------------------------------------------------------------
-- biz_template_config：physical_table 允许为空
-- ------------------------------------------------------------
ALTER TABLE `biz_template_config`
  MODIFY COLUMN `physical_table` VARCHAR(128) DEFAULT NULL COMMENT '物理表名';

-- ------------------------------------------------------------
-- task_rule：完成判断类型与配置
-- ------------------------------------------------------------
ALTER TABLE `task_rule`
  ADD COLUMN `completion_judgment_type` VARCHAR(20) DEFAULT NULL COMMENT '完成判断类型：CRON/FIXED/IMMEDIATE' AFTER `completion_conditions`,
  ADD COLUMN `completion_judgment_config` JSON DEFAULT NULL COMMENT '完成判断类型配置(JSON)，结构与 distribution_config 一致' AFTER `completion_judgment_type`;

-- ------------------------------------------------------------
-- task_rule：截止自动关闭、同步完成任务
-- ------------------------------------------------------------
ALTER TABLE `task_rule`
  ADD COLUMN `auto_close_on_deadline` TINYINT(1) DEFAULT NULL COMMENT '是否截止自动关闭：0-否，1-是' AFTER `distribution_object_group_name`,
  ADD COLUMN `sync_complete_task` TINYINT(1) DEFAULT NULL COMMENT '是否同步完成任务：0-否，1-是' AFTER `auto_close_on_deadline`;

-- ------------------------------------------------------------
-- field_filter_operator：字段筛选操作符（字符串/数字/日期与操作符一对多）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `field_filter_operator` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `operator_name` VARCHAR(64) NOT NULL COMMENT '操作符中文名称（界面展示，如「大于等于」）',
  `operator_code` VARCHAR(64) NOT NULL COMMENT '操作符本身或语义码（全局唯一，如 >=、=、BETWEEN、IS_NULL）',
  `field_types` JSON NOT NULL COMMENT '适用字段类型 JSON 数组：STRING、NUMBER、DATE、BOOLEAN、OTHER（OTHER 仅允许为空/不为空）',
  `sort_order` INT NOT NULL DEFAULT 0 COMMENT '展示排序，越小越靠前',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否删除：0-否 1-是',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '修改时间',
  `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人',
  `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_field_filter_operator_code` (`operator_code`),
  KEY `idx_field_filter_operator_deleted_sort` (`is_deleted`, `sort_order`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='字段筛选操作符配置';

INSERT IGNORE INTO `field_filter_operator` (`operator_name`, `operator_code`, `field_types`, `sort_order`, `is_deleted`)
VALUES
('等于', '=', JSON_ARRAY('STRING', 'NUMBER', 'DATE', 'BOOLEAN'), 10, 0),
('不等于', '!=', JSON_ARRAY('STRING', 'NUMBER', 'DATE', 'BOOLEAN'), 20, 0),
('大于', '>', JSON_ARRAY('NUMBER', 'DATE'), 30, 0),
('大于等于', '>=', JSON_ARRAY('NUMBER', 'DATE'), 40, 0),
('小于', '<', JSON_ARRAY('NUMBER', 'DATE'), 50, 0),
('小于等于', '<=', JSON_ARRAY('NUMBER', 'DATE'), 60, 0),
('介于', 'BETWEEN', JSON_ARRAY('NUMBER', 'DATE'), 70, 0),
('不介于', 'NOT_BETWEEN', JSON_ARRAY('NUMBER', 'DATE'), 80, 0),
('为空', 'IS_NULL', JSON_ARRAY('STRING', 'NUMBER', 'DATE', 'BOOLEAN', 'OTHER'), 90, 0),
('不为空', 'IS_NOT_NULL', JSON_ARRAY('STRING', 'NUMBER', 'DATE', 'BOOLEAN', 'OTHER'), 100, 0),
('是（多选或关系）', 'IS_ANY_OR', JSON_ARRAY('STRING'), 200, 0),
('不是（多选且关系）', 'IS_NOT_ALL_AND', JSON_ARRAY('STRING'), 210, 0),
('包含（多选或关系）', 'CONTAINS', JSON_ARRAY('STRING'), 220, 0),
('不包含（多选且关系）', 'NOT_CONTAINS', JSON_ARRAY('STRING'), 230, 0),
('早于', 'BEFORE', JSON_ARRAY('DATE'), 300, 0),
('晚于', 'AFTER', JSON_ARRAY('DATE'), 310, 0);

-- 已落库环境：旧编码 FIELD_OP_* 迁移为中文名 + 操作符码（可重复执行，按旧 code 定位）
UPDATE `field_filter_operator` SET `operator_name` = '等于', `operator_code` = '=' WHERE `operator_code` = 'FIELD_OP_EQ' AND `is_deleted` = 0;
UPDATE `field_filter_operator` SET `operator_name` = '不等于', `operator_code` = '!=' WHERE `operator_code` = 'FIELD_OP_NE' AND `is_deleted` = 0;
UPDATE `field_filter_operator` SET `operator_name` = '大于', `operator_code` = '>' WHERE `operator_code` = 'FIELD_OP_GT' AND `is_deleted` = 0;
UPDATE `field_filter_operator` SET `operator_name` = '大于等于', `operator_code` = '>=' WHERE `operator_code` = 'FIELD_OP_GTE' AND `is_deleted` = 0;
UPDATE `field_filter_operator` SET `operator_name` = '小于', `operator_code` = '<' WHERE `operator_code` = 'FIELD_OP_LT' AND `is_deleted` = 0;
UPDATE `field_filter_operator` SET `operator_name` = '小于等于', `operator_code` = '<=' WHERE `operator_code` = 'FIELD_OP_LTE' AND `is_deleted` = 0;
UPDATE `field_filter_operator` SET `operator_name` = '介于', `operator_code` = 'BETWEEN' WHERE `operator_code` = 'FIELD_OP_BETWEEN' AND `is_deleted` = 0;
UPDATE `field_filter_operator` SET `operator_name` = '不介于', `operator_code` = 'NOT_BETWEEN' WHERE `operator_code` = 'FIELD_OP_NOT_BETWEEN' AND `is_deleted` = 0;
UPDATE `field_filter_operator` SET `operator_name` = '为空', `operator_code` = 'IS_NULL' WHERE `operator_code` = 'FIELD_OP_IS_NULL' AND `is_deleted` = 0;
UPDATE `field_filter_operator` SET `operator_name` = '不为空', `operator_code` = 'IS_NOT_NULL' WHERE `operator_code` = 'FIELD_OP_IS_NOT_NULL' AND `is_deleted` = 0;
UPDATE `field_filter_operator` SET `operator_name` = '是（多选或关系）', `operator_code` = 'IS_ANY_OR' WHERE `operator_code` = 'FIELD_OP_IS_ANY_OR' AND `is_deleted` = 0;
UPDATE `field_filter_operator` SET `operator_name` = '不是（多选且关系）', `operator_code` = 'IS_NOT_ALL_AND' WHERE `operator_code` = 'FIELD_OP_IS_NOT_ALL_AND' AND `is_deleted` = 0;
UPDATE `field_filter_operator` SET `operator_name` = '包含（多选或关系）', `operator_code` = 'CONTAINS' WHERE `operator_code` = 'FIELD_OP_CONTAINS_ANY_OR' AND `is_deleted` = 0;
UPDATE `field_filter_operator` SET `operator_name` = '不包含（多选且关系）', `operator_code` = 'NOT_CONTAINS' WHERE `operator_code` = 'FIELD_OP_NOT_CONTAINS_ALL_AND' AND `is_deleted` = 0;
UPDATE `field_filter_operator` SET `operator_name` = '早于', `operator_code` = 'BEFORE' WHERE `operator_code` = 'FIELD_OP_BEFORE' AND `is_deleted` = 0;
UPDATE `field_filter_operator` SET `operator_name` = '晚于', `operator_code` = 'AFTER' WHERE `operator_code` = 'FIELD_OP_AFTER' AND `is_deleted` = 0;

-- 已落库环境：将「其他」类型纳入为空/不为空；并纳入 BOOLEAN（可重复执行）
UPDATE `field_filter_operator`
SET `field_types` = JSON_ARRAY('STRING', 'NUMBER', 'DATE', 'BOOLEAN', 'OTHER')
WHERE `operator_code` IN ('IS_NULL', 'IS_NOT_NULL', 'FIELD_OP_IS_NULL', 'FIELD_OP_IS_NOT_NULL') AND `is_deleted` = 0;

-- field_types：支持 BOOLEAN（等于/不等于；可重复执行）
UPDATE `field_filter_operator`
SET `field_types` = JSON_ARRAY('STRING', 'NUMBER', 'DATE', 'BOOLEAN')
WHERE `operator_code` IN ('=', '!=') AND `is_deleted` = 0;

-- ------------------------------------------------------------
-- task_distribution_detail：归属部门与部门路径
-- ------------------------------------------------------------
ALTER TABLE `task_distribution_detail`
  ADD COLUMN `owning_department_code` VARCHAR(128) DEFAULT NULL COMMENT '归属部门编码（DTS department_obj.dept_code）' AFTER `final_end_time`,
  ADD COLUMN `owning_department_name` VARCHAR(256) DEFAULT NULL COMMENT '归属部门名称（DTS department_obj.name）' AFTER `owning_department_code`,
  ADD COLUMN `department_path_json` JSON DEFAULT NULL COMMENT '部门路径：dept_parent_path 各 id 对应 dept_code 的有序 JSON 数组' AFTER `owning_department_name`;

-- ------------------------------------------------------------
-- 2026-05-08：task_distribution_detail 组合索引 object_code + end_time + target_entity_name（列表/筛选；与 dpc/sql/update_tables.sql 同步）
-- ------------------------------------------------------------
ALTER TABLE `task_distribution_detail`
  ADD KEY `idx_detail_obj_code_end_time_target_name` (`object_code`, `end_time`, `target_entity_name`);

-- ------------------------------------------------------------
-- 2026-05-08：task_distribution_detail 按目标聚合分页（POST .../listGroupByTarget；与 dpc/sql/update_tables.sql 同步）
-- 固定条件：is_deleted=0、status=IN_PROGRESS、object_code 等值、target_entity_code IS NOT NULL；内层 GROUP BY object_code, target_entity_code。
-- ------------------------------------------------------------
ALTER TABLE `task_distribution_detail`
  ADD KEY `idx_detail_list_group_by_target` (`object_code`, `is_deleted`, `status`, `target_entity_code`);

-- ------------------------------------------------------------
-- 2026-05-11：POST .../listGroupByTarget（pageGroupByObjectCodeTargetEntityCode）索引补充说明与覆盖索引（与 dpc/sql/update_tables.sql 同步）
-- ------------------------------------------------------------
-- 【接口与 SQL 形态】
--   Service：TaskDistributionDetailServiceImpl#buildGroupByTargetQueryWrapper + pageListGroupByTargetEntity
--   Mapper：#listMaxIdAndCountByTargetEntityCodes（见本文件后部「listGroupByTarget 语义与 SQL」）；归档：曾用 pageDistinct + countDetails / 全量分组 LIMIT 10
-- 【固定条件（左前缀最优先）】
--   is_deleted = 0；status = 'IN_PROGRESS'；object_code = ?（必传 trim）；object_code IS NOT NULL；target_entity_code IS NOT NULL
-- 【可选条件（影响能否完全走索引）】
--   ① 仅 target_entity_code：等值
--   ② 仅 target_entity_name：target_entity_name 等值（仍要求 target_entity_code IS NOT NULL）
--   ③ 编码+名称均传：(target_entity_code = ? OR target_entity_name = ?) — OR 可能 index_merge 或范围回表
--   ④ task_title： (task_title LIKE '%kw%' OR EXISTS(select 1 from task_definition td where td.id = task_def_id AND td.task_name LIKE '%kw%'))
--      — 前后 % 无法走 task_title 索引；EXISTS 对每行按 task_def_id 查 task_definition 主键，外圈瓶颈仍在明细表扫描
--   ⑤ owning_department_name LIKE '%kw%' — 同上，通配 LIKE 难用列索引
-- 【既有 idx_detail_list_group_by_target 四列】已覆盖 WHERE 等值左前缀，但对「每组 MAX(id) + 按 max_id 排序」叶子仍可能要回表读主键。
-- 【本段覆盖索引】在四列后追加 id，使二级索引叶子即携带分组内 id 顺序信息，利于 COUNT/MAX 与 ORDER BY max_id DESC（是否 Loose Index Scan 依优化器与数据分布而定）。
-- 【运维】若已存在 idx_detail_list_group_by_target_cover，且与 idx_detail_list_group_by_target 并存导致写入放大，
--   可在低峰评估执行：ALTER TABLE task_distribution_detail DROP INDEX idx_detail_list_group_by_target;
--   仅保留含 id 的覆盖索引即可（勿重复执行 DROP/ADD）。
-- ------------------------------------------------------------
ALTER TABLE `task_distribution_detail`
  ADD KEY `idx_detail_list_group_by_target_cover` (`object_code`, `is_deleted`, `status`, `target_entity_code`, `id`);

-- ------------------------------------------------------------
-- 2026-05-11：POST .../list、.../listByPackage 仅传 objectCode 等大表场景（与 dpc/sql/update_tables.sql 同步）
-- ------------------------------------------------------------

ALTER TABLE `task_distribution_detail`
  ADD KEY `idx_detail_object_tar_code_id` (`object_code`,`target_entity_code`);

ALTER TABLE `task_distribution_detail`
  ADD KEY `idx_detail_object_tar_name_id` (`object_code`,`target_entity_name`);

ALTER TABLE `task_distribution_detail`
  ADD KEY `idx_detail_list_object_deleted_id` (`object_code`,`end_time`, `is_deleted`, `id`);
ALTER TABLE `task_distribution_detail`
  ADD KEY `idx_detail_list_pkg_dedup` (`object_code`, `end_time`, `is_deleted`, `target_entity_code`, `id`);

-- ------------------------------------------------------------
-- 2026-05-11（listGroupByTarget 语义与 SQL，无新 DDL；与 dpc/sql/update_tables.sql 同步）：种子 20 条 + listMaxIdAndCountByTargetEntityCodes
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- 2026-05-11：task_instance 目标实体类型、目标实体 ID 允许为空（与 dpc/sql/update_tables.sql 同步）
-- ------------------------------------------------------------
ALTER TABLE `task_instance`
  MODIFY COLUMN `target_entity_type` VARCHAR(32) DEFAULT NULL COMMENT '目标实体类型: STORE, DEALER, PERSON（可空）',
  MODIFY COLUMN `target_entity_id` VARCHAR(64) DEFAULT NULL COMMENT '目标实体ID(如门店ID)（可空）';

-- ------------------------------------------------------------
-- 2026-05-11：condition_repo 增加 data_type_definition（与 dpc/sql/update_tables.sql 同步）
-- ------------------------------------------------------------
ALTER TABLE `condition_repo`
  ADD COLUMN `data_type_definition` VARCHAR(32) DEFAULT NULL COMMENT '数据类型定义：NUMBER/STRING/BOOLEAN/DATE 等，与 biz_template_field_map.data_type_definition 语义一致' AFTER `operator`;

-- ------------------------------------------------------------
-- 2026-05-11：试用数据配置 trial_data_config（与 dpc/sql/update_tables.sql 同步）
-- ------------------------------------------------------------
CREATE TABLE `trial_data_config` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `config_code` VARCHAR(128) NOT NULL COMMENT '配置编码，全局唯一',
  `config_name` VARCHAR(256) NOT NULL COMMENT '配置名称',
  `task_execution_event_code` VARCHAR(128) DEFAULT NULL COMMENT '执行类型监听的事件编码',
  `remark` VARCHAR(512) DEFAULT NULL COMMENT '备注说明',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人',
  `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否 1-是',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_trial_data_config_code` (`config_code`),
  KEY `idx_trial_data_config_event` (`task_execution_event_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='试用数据配置';

-- ------------------------------------------------------------
-- 2026-05-15：task_rule 下发/完成周期时间配置（与 dpc/sql/update_tables.sql 同步）
-- ------------------------------------------------------------
ALTER TABLE `task_rule`
  ADD COLUMN `distribution_time_config` JSON DEFAULT NULL COMMENT '下发周期时间配置(JSON)：a/b/c/d 结构' AFTER `distribution_config`,
  ADD COLUMN `completion_time_config` JSON DEFAULT NULL COMMENT '完成周期时间配置(JSON)：a/b/c/d 结构' AFTER `completion_judgment_config`;

-- ------------------------------------------------------------
-- 2026-06-03：task_template_definition 新增 completion_time_config（与 dpc/sql/update_tables.sql 同步）
-- ------------------------------------------------------------
ALTER TABLE `task_template_definition`
  ADD COLUMN `completion_time_config` JSON DEFAULT NULL COMMENT '完成周期时间配置(JSON)：a/b/c/d 结构，仅模板侧存储回显' AFTER `completion_script`;

-- ------------------------------------------------------------
-- 2026-05-22：Groovy 脚本代码实例 groovy_script_instance（与 dpc/sql/update_tables.sql 同步）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `groovy_script_instance` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `name` VARCHAR(256) NOT NULL COMMENT '实例名称',
  `script_content` TEXT NOT NULL COMMENT 'Groovy 脚本内容',
  `description` VARCHAR(512) DEFAULT NULL COMMENT '描述说明',
  `status` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否启用：0-禁用 1-启用',
  `type` TINYINT NOT NULL DEFAULT 1 COMMENT '脚本类型：1/2/3/4，默认 1',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人',
  `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否 1-是',
  PRIMARY KEY (`id`),
  KEY `idx_groovy_script_instance_status_type` (`status`, `type`),
  KEY `idx_groovy_script_instance_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Groovy 脚本代码实例';

-- groovy_script_instance.type 默认值 1（已建表环境）
ALTER TABLE `groovy_script_instance`
  MODIFY COLUMN `type` TINYINT NOT NULL DEFAULT 1 COMMENT '脚本类型：1/2/3/4，默认 1';

-- ------------------------------------------------------------
-- 2026-06-02：condition_repo 增加 operator_name（与 dpc/sql/update_tables.sql 同步）
-- ------------------------------------------------------------
ALTER TABLE `condition_repo`
  ADD COLUMN `operator_name` VARCHAR(64) DEFAULT NULL COMMENT '比较运算符中文名称（界面展示，如「大于等于」）' AFTER `operator`;
