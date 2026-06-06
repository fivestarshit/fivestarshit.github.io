-- 数据源连接配置表
CREATE TABLE `datasource_connection` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `name` VARCHAR(64) NOT NULL COMMENT '连接名称',
  `db_type` VARCHAR(20) NOT NULL COMMENT '数据库类型: MYSQL, ORACLE, PG, SQLSERVER, MONGODB',
  `host` VARCHAR(128) NOT NULL COMMENT '主机地址',
  `port` INT NOT NULL COMMENT '端口',
  `database_name` VARCHAR(64) NOT NULL COMMENT '库名',
  `username` VARCHAR(64) DEFAULT NULL COMMENT '账号，MongoDB无认证可空',
  `password` VARCHAR(256) DEFAULT NULL COMMENT '加密后的密码',
  `auth_source` VARCHAR(64) DEFAULT NULL COMMENT '认证库(MongoDB专有)，如 admin',
  `extra_params` JSON DEFAULT NULL COMMENT '扩展参数',
  `enabled` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否开启: 1-开启(自动创建连接池并连接数据库), 0-关闭',
  `connection_status` TINYINT NOT NULL DEFAULT 0 COMMENT '连接状态: 0-未检测, 1-成功, 2-失败',
  `last_connection_time` DATETIME DEFAULT NULL COMMENT '最后连接检测时间',
  `last_test_time` DATETIME DEFAULT NULL COMMENT '最后测试时间',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否, 1-是',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='数据源连接配置表（含MYSQL/MongoDB等）';

-- 已存在环境：扩展 datasource_connection 支持 MongoDB（按需执行）
-- ALTER TABLE `datasource_connection` ADD COLUMN `auth_source` VARCHAR(64) DEFAULT NULL COMMENT '认证库(MongoDB专有)，如 admin' AFTER `password`;
-- ALTER TABLE `datasource_connection` MODIFY COLUMN `username` VARCHAR(64) DEFAULT NULL COMMENT '账号，MongoDB无认证可空';
-- ALTER TABLE `datasource_connection` MODIFY COLUMN `password` VARCHAR(256) DEFAULT NULL COMMENT '加密后的密码';
-- 数据迁移：将 datasource_connection_mongo 数据迁入 datasource_connection 后，再删除 mongo 表
-- INSERT INTO datasource_connection (name, db_type, host, port, database_name, username, password, auth_source, extra_params, enabled, connection_status, is_deleted)
-- SELECT name, 'MONGODB', host, port, database_name, username, password, IFNULL(auth_source,'admin'), extra_params, enabled, connection_status, is_deleted FROM datasource_connection_mongo;
-- DROP TABLE IF EXISTS datasource_connection_mongo;

-- 业务模板配置主表
CREATE TABLE `biz_template_config` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `template_code` VARCHAR(64) NOT NULL COMMENT '业务唯一编码',
  `template_name` VARCHAR(128) NOT NULL COMMENT '模板名称',
  `icon_url` VARCHAR(256) DEFAULT NULL COMMENT '图标URL',
  `description` TEXT DEFAULT NULL COMMENT '描述',
  `datasource_id` BIGINT NOT NULL COMMENT '关联数据源ID',
  `data_source` VARCHAR(256) DEFAULT NULL COMMENT '数据来源：用于展示该业务模板对应的数据源说明',
  `dynamic_http_group_id` BIGINT DEFAULT NULL COMMENT '关联动态HTTP聚合配置ID(dynamic_http_endpoint_group.id)',
  `physical_table` VARCHAR(128) NOT NULL COMMENT '物理表名',
  `database_name` VARCHAR(128) DEFAULT NULL COMMENT '数据库的database',
  `task_execution_event_code` VARCHAR(128) DEFAULT NULL COMMENT '执行类型监听的事件编码',
  `groovy_execute_param_sample_json` JSON DEFAULT NULL COMMENT 'GroovyShell 执行参数示例 JSON（用于 /sales/task/groovy/execute）',
  `sync_strategy` VARCHAR(20) NOT NULL DEFAULT 'REAL_TIME' COMMENT '同步策略 DELAY  REAL_TIME',
  `sample_limit` INT DEFAULT 100 COMMENT '预览限制条数',
  `version` INT NOT NULL DEFAULT 1 COMMENT '版本号',
  `is_active` BOOLEAN NOT NULL DEFAULT TRUE COMMENT '是否生效',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否, 1-是',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_template_code` (`template_code`),
  KEY `idx_datasource_id` (`datasource_id`),
  KEY `idx_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='业务模板配置主表';

-- 业务模板字段映射表
CREATE TABLE `biz_template_field_map` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `template_id` BIGINT DEFAULT NULL COMMENT '关联模板ID，可为空，后续再关联模板',
  `template_task_id` BIGINT DEFAULT NULL COMMENT '关联模板任务ID(task_definition.id, task_type=TEMPLATE)',
  `object_code` VARCHAR(64) DEFAULT NULL COMMENT '对象类型编码（如 STORE/DEALER，与 task_object_option.object_code 一致）',
  `data_source` VARCHAR(256) DEFAULT NULL COMMENT '数据来源：用于展示该映射字段对应的数据源说明',
  `physical_col` VARCHAR(128) NOT NULL COMMENT '物理字段名',
  `mapped_col` VARCHAR(128) DEFAULT NULL COMMENT '映射后的自定义字段名',
  `mapped_col_val` VARCHAR(128) DEFAULT NULL COMMENT '映射后的自定义字段名',
  `logical_name` VARCHAR(128) NOT NULL COMMENT '业务展示名',
  `data_type` VARCHAR(50) NOT NULL COMMENT '逻辑数据类型',
  `length` INT DEFAULT NULL COMMENT '长度',
  `precision` INT DEFAULT NULL COMMENT '精度',
  `extract_rule` VARCHAR(128) DEFAULT NULL COMMENT '获取规则：当 data_type 为 JSON/数组时，描述如何从 JSON 中提取值映射到 mapped_col，如 items[*].baseUnitQuantity 或文字描述',
  `is_calculable` BOOLEAN NOT NULL DEFAULT FALSE COMMENT '是否可计算',
  `is_searchable` BOOLEAN NOT NULL DEFAULT FALSE COMMENT '是否可搜索',
  `is_search_primary_key` BOOLEAN NOT NULL DEFAULT FALSE COMMENT '是否搜索主键：用于标识检索时的主键映射字段',
  `is_visible` BOOLEAN NOT NULL DEFAULT TRUE COMMENT '是否可见',
  `sort_order` INT NOT NULL DEFAULT 0 COMMENT '显示顺序',
  `default_value` VARCHAR(256) DEFAULT NULL COMMENT '默认值',
  `enum_values` JSON DEFAULT NULL COMMENT '枚举值',
  `is_sensitive` BOOLEAN NOT NULL DEFAULT FALSE COMMENT '是否敏感',
  `mask_rule` VARCHAR(50) DEFAULT 'NONE' COMMENT '脱敏规则',
  `remark` VARCHAR(256) DEFAULT NULL COMMENT '备注',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否, 1-是',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_template_id` (`template_id`),
  KEY `idx_template_task_id` (`template_task_id`),
  KEY `idx_object_code` (`object_code`),
  KEY `idx_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='业务模板字段映射表';

-- 已存在环境执行：删除 status、新增 is_deleted（按需执行）
-- 已存在环境执行：新增连接状态（按需执行）
-- ALTER TABLE `datasource_connection` ADD COLUMN `connection_status` TINYINT NOT NULL DEFAULT 0 COMMENT '连接状态: 0-未检测, 1-成功, 2-失败' AFTER `enabled`, ADD COLUMN `last_connection_time` DATETIME DEFAULT NULL COMMENT '最后连接检测时间' AFTER `connection_status`;
-- ALTER TABLE `datasource_connection_mongo` ADD COLUMN `connection_status` TINYINT NOT NULL DEFAULT 0 COMMENT '连接状态: 0-未检测, 1-成功, 2-失败' AFTER `enabled`, ADD COLUMN `last_connection_time` DATETIME DEFAULT NULL COMMENT '最后连接检测时间' AFTER `connection_status`;
-- ALTER TABLE `datasource_connection` DROP COLUMN `status`, ADD COLUMN `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否, 1-是' AFTER `last_test_time`, ADD KEY `idx_is_deleted` (`is_deleted`);
-- ALTER TABLE `datasource_connection_mongo` DROP COLUMN `status`, ADD COLUMN `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否, 1-是' AFTER `last_test_time`, ADD KEY `idx_is_deleted` (`is_deleted`);
-- ALTER TABLE `biz_template_config` ADD COLUMN `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否, 1-是' AFTER `is_active`, ADD KEY `idx_is_deleted` (`is_deleted`);
-- ALTER TABLE `biz_template_config` ADD COLUMN `task_execution_event_code` VARCHAR(128) DEFAULT NULL COMMENT '执行类型监听的事件编码' AFTER `database_name`;
-- ALTER TABLE `biz_template_field_map` ADD COLUMN `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否, 1-是' AFTER `remark`, ADD COLUMN `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`, ADD KEY `idx_is_deleted` (`is_deleted`);
-- 已存在环境执行：template_id 改为可空（按需执行）
-- ALTER TABLE `biz_template_field_map` MODIFY COLUMN `template_id` BIGINT DEFAULT NULL COMMENT '关联模板ID，可为空，后续再关联模板';
-- 已存在环境执行：新增 template_task_id（按需执行）
-- ALTER TABLE `biz_template_field_map` ADD COLUMN `template_task_id` BIGINT DEFAULT NULL COMMENT '关联模板任务ID(task_definition.id, task_type=TEMPLATE)' AFTER `template_id`, ADD KEY `idx_template_task_id` (`template_task_id`);

