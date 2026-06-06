-- ============================================================
-- 4.2 新增核心表结构设计（TRD 4.2 章节）
-- 条件库、动作库、任务规则、任务实例及执行日志
-- ============================================================

-- 4.2.1 条件库表（condition_repo）
CREATE TABLE `condition_repo` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `condition_code` VARCHAR(64) NOT NULL COMMENT '条件唯一编码',
  `condition_name` VARCHAR(128) NOT NULL COMMENT '条件名称',
  `object_type` VARCHAR(32) NOT NULL COMMENT '对象类型: STORE(店), DEALER(经销商), PERSON(人), PRODUCT(商品), OTHER(其他)',
  `template_id` BIGINT DEFAULT NULL COMMENT '关联业务模板ID 关联biz_template_config',
  `field_code` VARCHAR(128) DEFAULT NULL COMMENT '关联字段编码(mapped_col)',
  `operator` VARCHAR(20) DEFAULT NULL COMMENT '比较运算符: EQ, NE, GT, GE, LT, LE, IN, NOT_IN, LIKE, BETWEEN',
  `operator_name` VARCHAR(64) DEFAULT NULL COMMENT '比较运算符中文名称（界面展示，如「大于等于」）',
  `data_type_definition` VARCHAR(32) DEFAULT NULL COMMENT '数据类型定义：NUMBER/STRING/BOOLEAN/DATE 等，与 biz_template_field_map.data_type_definition 语义一致',
  `default_value` JSON DEFAULT NULL COMMENT '默认比较值(JSON格式)',
  `description` TEXT DEFAULT NULL COMMENT '条件描述',
  `status` TINYINT NOT NULL DEFAULT 1 COMMENT '状态: 1-启用, 0-停用',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否, 1-是',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_condition_code` (`condition_code`),
  KEY `idx_template_id` (`template_id`),
  KEY `idx_object_type` (`object_type`),
  KEY `idx_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='条件库（条件因子定义）';

-- 4.2.2 统一任务定义表（task_definition）- 合并原 SalesTask 与 ActionRepo
-- 任务与动作统一为任务模型，通过 parent_id 关联子任务（原动作）
CREATE TABLE `task_definition` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `task_code` VARCHAR(64) NOT NULL COMMENT '任务唯一编码',
  `task_name` VARCHAR(128) NOT NULL COMMENT '任务名称（原 SalesTask.title / ActionRepo.action_name）',
  `task_type` VARCHAR(32) NOT NULL COMMENT '任务类型: TEMPLATE(任务模板),PACKAGE(任务包), TASK(普通任务), ACTION(子任务-原动作)',
  `parent_id` BIGINT DEFAULT NULL COMMENT '父任务ID：NULL=顶层任务/任务包；非空=子任务(原动作)',
  `task_source` VARCHAR(64) DEFAULT NULL COMMENT '任务来源（如 agreement 等）',
  `related_id` VARCHAR(64) DEFAULT NULL COMMENT '关联业务ID（活动协议ID等）',
  `related_name` VARCHAR(128) DEFAULT NULL COMMENT '关联业务名称',
  `object_id` VARCHAR(64) DEFAULT NULL COMMENT '对象ID（门店/客户等）',
  `object_name` VARCHAR(128) DEFAULT NULL COMMENT '对象名称',
  `object_code` VARCHAR(64) DEFAULT NULL COMMENT '对象编码: STORE(店), DEALER(经销商), PERSON(人), PRODUCT(商品), OTHER(其他)（与 task_object_option.object_code 一致）',
  `object_owner` VARCHAR(64) DEFAULT NULL COMMENT '对象负责人',
  `start_time` DATETIME DEFAULT NULL COMMENT '任务开始时间',
  `end_time` DATETIME DEFAULT NULL COMMENT '任务截止时间',
  `task_month` DATE DEFAULT NULL COMMENT '任务月份',
  `finish_time` DATETIME DEFAULT NULL COMMENT '任务完成时间',
  `finish_related_id` VARCHAR(64) DEFAULT NULL COMMENT '完成关联业务ID',
  `finish_visit_id` VARCHAR(64) DEFAULT NULL COMMENT '完成关联外勤拜访ID',
  `variables` JSON DEFAULT NULL COMMENT '参数/变量定义(JSON Schema或自定义结构)',
  `completion_logic` TEXT DEFAULT NULL COMMENT '完成逻辑脚本(Groovy/SQL等)',
  `completion_script` TEXT DEFAULT NULL COMMENT '完成标准代码脚本(Groovy等)，任务定义维度（与 task_rule.completion_script 区分）',
  `condition_ids` JSON DEFAULT NULL COMMENT '关联条件库ID列表(JSON数组)，如[1,2,3]，task_definition 可关联多个 condition_repo',
  `task_title` VARCHAR(255) DEFAULT NULL COMMENT '任务标题(H5展示用)',
  `task_description` TEXT DEFAULT NULL COMMENT '任务说明(H5展示用)',
  `distribution_task_count` BIGINT DEFAULT NULL COMMENT '下发的普通任务总数量',
  `task_execution_type` VARCHAR(32) DEFAULT NULL COMMENT '任务执行类型编码',
  `task_execution_type_name` VARCHAR(128) DEFAULT NULL COMMENT '任务执行类型中文值',
  `task_execution_event_code` VARCHAR(64) DEFAULT NULL COMMENT '执行类型监听的事件编码',
  `status` TINYINT NOT NULL DEFAULT 1 COMMENT '配置状态: 1-启用, 0-停用',
  `task_status` VARCHAR(32) DEFAULT 'NOT_STARTED' COMMENT '运行状态: NOT_STARTED(未开始), IN_PROGRESS(进行中), COMPLETED(已完成), CLOSED(已关闭), EXPIRED(已过期)',
  `template_ids` JSON DEFAULT NULL COMMENT '模板关联ID列表，关联 task_type=TEMPLATE 的任务定义，可关联多个，如 [1,2,3]',
  `system_ids` JSON DEFAULT NULL COMMENT '关联系统ID列表(JSON数组，关联 task_system_option.id)，可关联多个，如 [1,2]',
  `distributed_at` DATETIME DEFAULT NULL COMMENT '下发具体时间',
  `rule_id` BIGINT DEFAULT NULL COMMENT '关联 task_rule.id（创建任务定义时写入）',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否, 1-是',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_task_code` (`task_code`),
  KEY `idx_parent_id` (`parent_id`),
  KEY `idx_task_type` (`task_type`),
  KEY `idx_rule_id` (`rule_id`),
  KEY `idx_task_status` (`task_status`),
  KEY `idx_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='统一任务定义表（含任务与动作）';

-- 4.2.2.0 任务模板定义表（task_template_definition）：与 task_definition 同结构，仅 task_type=TEMPLATE 数据落此表；template_ids 在本表为 data_template_ids
CREATE TABLE `task_template_definition` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `task_code` VARCHAR(64) NOT NULL COMMENT '任务唯一编码',
  `task_name` VARCHAR(128) NOT NULL COMMENT '任务名称',
  `task_type` VARCHAR(32) NOT NULL DEFAULT 'TEMPLATE' COMMENT '恒为 TEMPLATE',
  `template_type` VARCHAR(32) NOT NULL DEFAULT 'COMMON' COMMENT '模板类型:TEMPORARY=临时模板,COMMON=常用模板',
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
  `completion_time_config` JSON DEFAULT NULL COMMENT '完成周期时间配置(JSON)：a/b/c/d 结构，仅模板侧存储回显',
  `condition_ids` JSON DEFAULT NULL COMMENT '关联条件库ID列表',
  `task_title` VARCHAR(255) DEFAULT NULL COMMENT '任务标题',
  `task_description` TEXT DEFAULT NULL COMMENT '任务说明',
  `distribution_task_count` BIGINT DEFAULT NULL COMMENT '下发的普通任务总数量',
  `task_execution_type` VARCHAR(32) DEFAULT NULL COMMENT '任务执行类型编码',
  `task_execution_type_name` VARCHAR(128) DEFAULT NULL COMMENT '任务执行类型中文值',
  `task_execution_event_code` VARCHAR(64) DEFAULT NULL COMMENT '执行类型监听的事件编码',
  `status` TINYINT NOT NULL DEFAULT 1 COMMENT '配置状态: 1-启用, 0-停用（模板不维护运行态，无 task_status 列）',
  `data_template_ids` JSON DEFAULT NULL COMMENT '数据模板关联ID列表(原 template_ids)',
  `system_ids` JSON DEFAULT NULL COMMENT '关联系统ID列表',
  `template_field_ids` JSON DEFAULT NULL COMMENT '关联 biz_template_field_map.id 列表',
  `distributed_at` DATETIME DEFAULT NULL COMMENT '下发具体时间',
  `rule_id` BIGINT DEFAULT NULL COMMENT '关联 task_rule.id（模板默认不落规则时为 NULL）',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_task_code` (`task_code`),
  KEY `idx_parent_id` (`parent_id`),
  KEY `idx_template_type` (`template_type`),
  KEY `idx_rule_id` (`rule_id`),
  KEY `idx_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='任务模板定义（自 task_definition 拆出）';

-- 4.2.2.1 已有 task_definition 表时，可执行以下迁移（新增 distributed_at、system_ids）
-- 删除 object_type（以 object_code 为准）：先回填再删列
-- UPDATE `task_definition` SET `object_code` = `object_type` WHERE (`object_code` IS NULL OR TRIM(`object_code`) = '') AND `object_type` IS NOT NULL;
-- ALTER TABLE `task_definition` DROP COLUMN `object_type`;
-- ALTER TABLE `task_definition` ADD COLUMN `distributed_at` DATETIME DEFAULT NULL COMMENT '下发具体时间' AFTER `template_ids`;
-- ALTER TABLE `task_definition` ADD COLUMN `system_ids` JSON DEFAULT NULL COMMENT '关联系统ID列表(JSON数组，关联 task_system_option.id)' AFTER `template_ids`;
-- ALTER TABLE `task_definition` ADD COLUMN `completion_script` TEXT DEFAULT NULL COMMENT '完成标准代码脚本(Groovy等)，任务定义维度' AFTER `completion_logic`;

-- 4.2.3 任务规则表（task_rule）
CREATE TABLE `task_rule` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `rule_code` VARCHAR(64) NOT NULL COMMENT '规则唯一编码',
  `rule_name` VARCHAR(128) NOT NULL COMMENT '规则名称',
  `description` TEXT DEFAULT NULL COMMENT '规则描述/备注',
  `target_object_type` VARCHAR(32) NOT NULL DEFAULT 'STORE' COMMENT '下发对象类型: STORE, DEALER, PERSON',
  `condition_mode` VARCHAR(20) NOT NULL COMMENT '条件模式: FACTOR, SCRIPT',
  `target_conditions` JSON DEFAULT NULL COMMENT '因子条件组(JSON格式)',
  `target_condition_script` TEXT DEFAULT NULL COMMENT '代码条件脚本(Groovy)',
  `distribution_type` VARCHAR(20) NOT NULL COMMENT '下发时间: CRON(cron表达式), FIXED(固定时间), IMMEDIATE(直接下发)',
  `distribution_config` JSON DEFAULT NULL COMMENT '下发配置: CRON={"cron":"0 30 2 */1 * ?"}, FIXED={"dateTime":"..."}, IMMEDIATE=null',
  `trigger_type` VARCHAR(32) DEFAULT NULL COMMENT '触发时间: CRON,FIXED,IMMEDIATE_ON_DATA_CHANGE(数据变更后立即触发)',
  `trigger_config` JSON DEFAULT NULL COMMENT '触发配置: CRON={"cron":"..."}, FIXED={"dateTime":"..."}, IMMEDIATE_ON_DATA_CHANGE=null',
  `task_title` VARCHAR(255) DEFAULT NULL COMMENT '任务标题(H5展示用)',
  `task_description` TEXT DEFAULT NULL COMMENT '任务说明(H5展示用)',
  `deadline_type` VARCHAR(20) DEFAULT NULL COMMENT '截止时间: RELATIVE(相对-下发后第N天HH:mm), ABSOLUTE(绝对-固定日期)',
  `deadline_config` JSON DEFAULT NULL COMMENT '截止配置: RELATIVE={"days":10,"time":"22:30"}, ABSOLUTE={"date":"2024-03-15","time":"22:30"}',
  `completion_type` VARCHAR(20) NOT NULL COMMENT '完成标准类型: ACTION_BASED, SCRIPT_BASED',
  `completion_conditions` JSON DEFAULT NULL COMMENT '完成条件(JSON格式)',
  `completion_script` TEXT DEFAULT NULL COMMENT '完成标准代码脚本(Groovy)',
  `action_execution_mode` VARCHAR(20) DEFAULT 'ALL' COMMENT '多动作执行模式: ALL-全部执行, ANY-任一执行',
  `has_action` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否包含操作(模板动作)；createPackage子TASK与tasks[].hasAction一致；任务包规则为0',
  `distributed_at` DATETIME DEFAULT NULL COMMENT '下发具体时间',
  `status` TINYINT NOT NULL DEFAULT 1 COMMENT '状态: 1-启用, 0-停用',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否, 1-是',
  `created_by` VARCHAR(64) DEFAULT NULL COMMENT '创建人',
  `updated_by` VARCHAR(64) DEFAULT NULL COMMENT '最后修改人',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_rule_code` (`rule_code`),
  KEY `idx_status` (`status`),
  KEY `idx_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='任务规则配置表';

-- 4.2.3.1 已有 task_rule 表时，可执行以下迁移（新增 distributed_at）
-- ALTER TABLE `task_rule` ADD COLUMN `distributed_at` DATETIME DEFAULT NULL COMMENT '下发具体时间' AFTER `action_execution_mode`;

-- 4.2.4 任务规则-任务关联表（task_rule_action_rel）已废弃；任务定义侧使用 task_definition.rule_id / task_template_definition.rule_id 指向 task_rule.id

-- 4.2.5 任务下发明细表（task_distribution_detail）
-- 任务包触发下发动作后，根据规则筛选符合条件的门店或人员，生成任务明细。由 TaskRule 生成 TaskInstance 且到达触发时间后触发。
-- 任务包下若有多个普通任务(TASK)，则每个(任务包+普通任务+目标实体)对应一条明细，分别关联 task_package_id 和 task_def_id。
CREATE TABLE `task_distribution_detail` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `task_package_id` BIGINT NOT NULL COMMENT '关联任务包ID(task_definition.id, task_type=PACKAGE)',
  `task_def_id` BIGINT DEFAULT NULL COMMENT '关联普通任务ID(task_definition.id, task_type=TASK)，任务包下的子任务',
  `task_instance_id` BIGINT DEFAULT NULL COMMENT '关联任务实例ID（下发来源）',
  `object_code` VARCHAR(64) NOT NULL COMMENT '对象编码: STORE(店), DEALER(经销商), PERSON(人), PRODUCT(商品), OTHER(其他)（与 task_definition.object_code 一致）',
  `object_name` VARCHAR(128) DEFAULT NULL COMMENT '目标对象名称(冗余)',
  `target_entity_type` VARCHAR(32) NOT NULL COMMENT '目标实体类型: STORE, DEALER, PERSON',
  `target_entity_id` VARCHAR(64) DEFAULT NULL COMMENT '目标实体ID(如门店ID、人员ID)，可空待补全',
  `target_entity_name` VARCHAR(128) DEFAULT NULL COMMENT '目标实体名称(冗余)',
  `target_entity_code` VARCHAR(64) DEFAULT NULL COMMENT '目标实体编码(冗余)',
  `target_entity_field_mapped_id` BIGINT DEFAULT NULL COMMENT '关联 biz_template_field_map.id，标识目标实体字段来源于哪个字段映射',
  `executor_id` VARCHAR(64) DEFAULT NULL COMMENT '执行人ID(人员维度时的业代ID)',
  `executor_name` VARCHAR(64) DEFAULT NULL COMMENT '执行人名称(冗余)',
  `dimension_data` JSON DEFAULT NULL COMMENT '维度扩展数据(JSON格式，存储筛选结果中的其他维度字段)',
  `task_title` VARCHAR(255) DEFAULT NULL COMMENT '任务标题(H5展示用)',
  `task_description` TEXT DEFAULT NULL COMMENT '任务说明(H5展示用)',
  `task_execution_type` VARCHAR(32) DEFAULT NULL COMMENT '任务执行类型编码',
  `task_execution_type_name` VARCHAR(128) DEFAULT NULL COMMENT '任务执行类型中文值',
  `task_month` DATE DEFAULT NULL COMMENT '任务月份(冗余，来源于 task_definition.task_month)',
  `start_time` DATETIME DEFAULT NULL COMMENT '任务开始时间',
  `end_time` DATETIME DEFAULT NULL COMMENT '任务截止时间',
  `status` VARCHAR(32) NOT NULL DEFAULT 'IN_PROGRESS' COMMENT '状态: IN_PROGRESS(进行中), COMPLETED(已完成), CLOSED(已关闭), EXPIRED(已过期)',
  `final_end_time` DATETIME DEFAULT NULL COMMENT '最终结束时间(状态完成时的时间，可能是过期时间或关闭时间)',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否, 1-是',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_task_package_id` (`task_package_id`),
  KEY `idx_task_def_id` (`task_def_id`),
  KEY `idx_task_instance_id` (`task_instance_id`),
  KEY `idx_target_entity` (`target_entity_type`, `target_entity_id`),
  KEY `idx_executor` (`executor_id`),
  KEY `idx_status` (`status`),
  KEY `idx_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='任务下发明细表（任务包触发下发后按规则筛选生成，状态:进行中/已完成/已关闭）';

-- 4.2.5.1 已有 task_distribution_detail 表时，可执行以下迁移（新增 target_entity_field_mapped_id / object_code，并删除 object_type）
-- 若尚未包含任务起止时间，可执行：
-- ALTER TABLE `task_distribution_detail` ADD COLUMN `start_time` DATETIME DEFAULT NULL COMMENT '任务开始时间' AFTER `task_month`;
-- ALTER TABLE `task_distribution_detail` ADD COLUMN `end_time` DATETIME DEFAULT NULL COMMENT '任务截止时间' AFTER `start_time`;
-- ALTER TABLE `task_distribution_detail`
--   ADD COLUMN `target_entity_field_mapped_id` BIGINT DEFAULT NULL COMMENT '关联 biz_template_field_map.id' AFTER `target_entity_code`,
--   ADD KEY `idx_target_entity_field_mapped_id` (`target_entity_field_mapped_id`);
-- ALTER TABLE `task_distribution_detail`
--   ADD COLUMN `object_code` VARCHAR(64) DEFAULT NULL COMMENT '对象编码（与 task_definition.object_code 一致）' AFTER `task_instance_id`;
-- UPDATE `task_distribution_detail` SET `object_code` = `object_type` WHERE `object_code` IS NULL OR `object_code` = '';
-- ALTER TABLE `task_distribution_detail` DROP COLUMN `object_type`;

-- 4.2.6 任务实例表（task_instance）
CREATE TABLE `task_instance` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `task_code` VARCHAR(64) NOT NULL COMMENT '任务实例唯一编码',
  `task_title` VARCHAR(255) NOT NULL COMMENT '任务标题(H5展示用)',
  `task_description` TEXT DEFAULT NULL COMMENT '任务说明',
  `task_rule_id` BIGINT DEFAULT NULL COMMENT '来源任务规则ID',
  `target_entity_type` VARCHAR(32) NOT NULL COMMENT '目标实体类型: STORE, DEALER, PERSON',
  `target_entity_id` VARCHAR(64) NOT NULL COMMENT '目标实体ID(如门店ID)',
  `target_entity_name` VARCHAR(128) DEFAULT NULL COMMENT '目标实体名称(冗余，便于查询)',
  `executor_id` VARCHAR(64) DEFAULT NULL COMMENT '执行人ID(如业代ID)',
  `executor_name` VARCHAR(64) DEFAULT NULL COMMENT '执行人名称',
  `status` VARCHAR(32) NOT NULL DEFAULT 'PENDING' COMMENT '状态: PENDING, DISTRIBUTED, IN_PROGRESS, COMPLETED, CLOSED',
  `deadline` DATETIME DEFAULT NULL COMMENT '截止时间',
  `distributed_at` DATETIME DEFAULT NULL COMMENT '下发时间',
  `scheduled_execute_at` DATETIME DEFAULT NULL COMMENT '计划执行时间（由规则 trigger 配置计算）',
  `triggered_by_data_change` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否由数据变更实时触发: 0-否, 1-是',
  `source_data` JSON DEFAULT NULL COMMENT '接收到的源数据(JSON，如 Kafka 消息体)',
  `task_result_data` JSON DEFAULT NULL COMMENT '任务下发解析结果(JSON: TaskDistributionTaskResult)',
  `task_distribution_detail_id` BIGINT DEFAULT NULL COMMENT '关联任务明细ID(task_distribution_detail.id)',
  `started_at` DATETIME DEFAULT NULL COMMENT '开始执行时间',
  `completed_at` DATETIME DEFAULT NULL COMMENT '完成时间',
  `closed_at` DATETIME DEFAULT NULL COMMENT '关闭时间',
  `close_reason` VARCHAR(256) DEFAULT NULL COMMENT '关闭原因',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已删除: 0-否, 1-是',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_task_code` (`task_code`),
  KEY `idx_rule_id` (`task_rule_id`),
  KEY `idx_target_entity` (`target_entity_type`, `target_entity_id`),
  KEY `idx_executor` (`executor_id`),
  KEY `idx_status` (`status`),
  KEY `idx_deadline` (`deadline`),
  KEY `idx_task_distribution_detail_id` (`task_distribution_detail_id`),
  KEY `idx_is_deleted` (`is_deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='任务实例表';

-- 4.2.6.1 已有 task_instance 表时，可执行以下迁移（新增 source_data）
-- ALTER TABLE `task_instance` ADD COLUMN `source_data` JSON DEFAULT NULL COMMENT '接收到的源数据(JSON，如 Kafka 消息体)' AFTER `triggered_by_data_change`;

-- 4.2.6.2 已有 task_instance 表时，可执行以下迁移（新增 task_result_data / task_distribution_detail_id）
-- ALTER TABLE `task_instance`
--   ADD COLUMN `task_result_data` JSON DEFAULT NULL COMMENT '任务下发解析结果(JSON: TaskDistributionTaskResult)' AFTER `source_data`,
--   ADD COLUMN `task_distribution_detail_id` BIGINT DEFAULT NULL COMMENT '关联任务明细ID(task_distribution_detail.id)' AFTER `task_result_data`,
--   ADD KEY `idx_task_distribution_detail_id` (`task_distribution_detail_id`);


-- 4.2.7 任务实例执行日志表（task_instance_execution_log）
CREATE TABLE `task_instance_execution_log` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
  `task_instance_id` BIGINT NOT NULL COMMENT '关联任务实例ID',
  `event_type` VARCHAR(32) NOT NULL COMMENT '事件类型: CREATED, DISTRIBUTED, ACTION_STARTED, ACTION_COMPLETED, TASK_COMPLETED, CLOSED',
  `event_data` JSON DEFAULT NULL COMMENT '事件数据(JSON格式)',
  `operator_id` VARCHAR(64) DEFAULT NULL COMMENT '操作人ID',
  `operator_name` VARCHAR(64) DEFAULT NULL COMMENT '操作人名称',
  `remark` VARCHAR(512) DEFAULT NULL COMMENT '备注',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_task_instance_id` (`task_instance_id`),
  KEY `idx_event_type` (`event_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='任务实例执行日志表';

-- 4.2.8 任务包下发扩展表（task_package_distribution_ext）：与 task_definition 中 task_type=PACKAGE 的任务包 1:1
CREATE TABLE `task_package_distribution_ext` (
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
