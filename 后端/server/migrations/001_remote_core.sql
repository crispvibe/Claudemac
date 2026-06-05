CREATE TABLE IF NOT EXISTS `remote_users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `created_at` datetime(3) DEFAULT NULL COMMENT '创建时间',
  `updated_at` datetime(3) DEFAULT NULL COMMENT '更新时间',
  `deleted_at` datetime(3) DEFAULT NULL COMMENT '软删除时间',
  `phone` varchar(32) NOT NULL COMMENT '手机号，远程账号唯一登录标识',
  `password_hash` varchar(191) NOT NULL COMMENT 'bcrypt 密码哈希',
  `status` varchar(32) NOT NULL DEFAULT 'active' COMMENT '账号状态：active/disabled',
  `last_login_at` datetime(3) DEFAULT NULL COMMENT '最近登录时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_remote_users_phone` (`phone`),
  KEY `idx_remote_users_deleted_at` (`deleted_at`),
  KEY `idx_remote_users_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程 App 用户账号表';

CREATE TABLE IF NOT EXISTS `remote_user_tokens` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `created_at` datetime(3) DEFAULT NULL COMMENT '创建时间',
  `updated_at` datetime(3) DEFAULT NULL COMMENT '更新时间',
  `deleted_at` datetime(3) DEFAULT NULL COMMENT '软删除时间',
  `user_id` bigint unsigned NOT NULL COMMENT '远程用户ID',
  `token_hash` varchar(191) NOT NULL COMMENT '刷新令牌哈希',
  `token_type` varchar(32) NOT NULL DEFAULT 'refresh' COMMENT '令牌类型：refresh',
  `expires_at` datetime(3) NOT NULL COMMENT '过期时间',
  `revoked_at` datetime(3) DEFAULT NULL COMMENT '撤销时间',
  `last_used_at` datetime(3) DEFAULT NULL COMMENT '最近使用时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_remote_user_tokens_hash` (`token_hash`),
  KEY `idx_remote_user_tokens_user_id` (`user_id`),
  KEY `idx_remote_user_tokens_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程用户刷新令牌表';

CREATE TABLE IF NOT EXISTS `remote_devices` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `created_at` datetime(3) DEFAULT NULL COMMENT '创建时间',
  `updated_at` datetime(3) DEFAULT NULL COMMENT '更新时间',
  `deleted_at` datetime(3) DEFAULT NULL COMMENT '软删除时间',
  `user_id` bigint unsigned NOT NULL COMMENT '所属远程用户ID',
  `device_uid` varchar(64) NOT NULL COMMENT '客户端生成的稳定设备标识',
  `device_type` varchar(32) NOT NULL COMMENT '设备类型：desktop/ios',
  `platform` varchar(32) NOT NULL COMMENT '平台：macos/windows/ios',
  `device_name` varchar(191) NOT NULL COMMENT '设备展示名称',
  `device_public_key` text COMMENT '设备公钥，用于后续端到端握手',
  `device_code_hash` varchar(191) DEFAULT NULL COMMENT '固定设备码哈希，仅桌面设备使用',
  `device_code_hint` varchar(16) DEFAULT NULL COMMENT '设备码脱敏提示',
  `approval_policy` varchar(32) NOT NULL DEFAULT 'always_ask' COMMENT '跨账号确认策略：always_ask/allow_anyone',
  `remote_enabled` tinyint(1) NOT NULL DEFAULT 1 COMMENT '远程连接总开关',
  `status` varchar(32) NOT NULL DEFAULT 'active' COMMENT '设备状态：active/disabled',
  `app_version` varchar(64) DEFAULT NULL COMMENT '客户端版本',
  `last_seen_at` datetime(3) DEFAULT NULL COMMENT '最近在线时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_remote_devices_device_uid` (`device_uid`),
  KEY `idx_remote_devices_user_id` (`user_id`),
  KEY `idx_remote_devices_code_hash` (`device_code_hash`),
  KEY `idx_remote_devices_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程设备表';

CREATE TABLE IF NOT EXISTS `remote_device_code_attempts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `created_at` datetime(3) DEFAULT NULL COMMENT '创建时间',
  `updated_at` datetime(3) DEFAULT NULL COMMENT '更新时间',
  `deleted_at` datetime(3) DEFAULT NULL COMMENT '软删除时间',
  `target_device_id` bigint unsigned DEFAULT NULL COMMENT '解析命中的目标设备ID',
  `from_user_id` bigint unsigned DEFAULT NULL COMMENT '发起解析的远程用户ID',
  `from_device_id` bigint unsigned DEFAULT NULL COMMENT '发起解析的设备ID',
  `code_hash_prefix` varchar(16) NOT NULL COMMENT '设备码哈希前缀，用于审计不反推出明文',
  `status` varchar(32) NOT NULL COMMENT '解析结果：success/failed/rate_limited',
  `failure_reason` varchar(191) DEFAULT NULL COMMENT '失败原因',
  `ip_hash` varchar(64) DEFAULT NULL COMMENT '请求 IP 哈希',
  PRIMARY KEY (`id`),
  KEY `idx_remote_device_code_attempts_target` (`target_device_id`),
  KEY `idx_remote_device_code_attempts_from_user` (`from_user_id`),
  KEY `idx_remote_device_code_attempts_created_at` (`created_at`),
  KEY `idx_remote_device_code_attempts_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程设备码解析尝试表';

CREATE TABLE IF NOT EXISTS `remote_device_grants` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `created_at` datetime(3) DEFAULT NULL COMMENT '创建时间',
  `updated_at` datetime(3) DEFAULT NULL COMMENT '更新时间',
  `deleted_at` datetime(3) DEFAULT NULL COMMENT '软删除时间',
  `owner_user_id` bigint unsigned NOT NULL COMMENT '目标设备所属用户ID',
  `target_device_id` bigint unsigned NOT NULL COMMENT '被连接的目标设备ID',
  `grantee_user_id` bigint unsigned NOT NULL COMMENT '被授权用户ID',
  `grantee_device_id` bigint unsigned DEFAULT NULL COMMENT '被授权设备ID',
  `scope` varchar(32) NOT NULL DEFAULT 'chat_only' COMMENT '授权范围：chat_only',
  `grant_type` varchar(32) NOT NULL COMMENT '授权类型：same_account/device_code',
  `remembered` tinyint(1) NOT NULL DEFAULT 0 COMMENT '是否记住授权',
  `status` varchar(32) NOT NULL DEFAULT 'active' COMMENT '授权状态：active/revoked/expired',
  `expires_at` datetime(3) DEFAULT NULL COMMENT '授权过期时间',
  `last_used_at` datetime(3) DEFAULT NULL COMMENT '最近使用时间',
  PRIMARY KEY (`id`),
  KEY `idx_remote_device_grants_target` (`target_device_id`),
  KEY `idx_remote_device_grants_grantee` (`grantee_user_id`,`grantee_device_id`),
  KEY `idx_remote_device_grants_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程设备授权关系表';

CREATE TABLE IF NOT EXISTS `remote_connection_attempts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `created_at` datetime(3) DEFAULT NULL COMMENT '创建时间',
  `updated_at` datetime(3) DEFAULT NULL COMMENT '更新时间',
  `deleted_at` datetime(3) DEFAULT NULL COMMENT '软删除时间',
  `from_user_id` bigint unsigned NOT NULL COMMENT '发起连接用户ID',
  `from_device_id` bigint unsigned DEFAULT NULL COMMENT '发起连接设备ID',
  `to_user_id` bigint unsigned NOT NULL COMMENT '目标设备所属用户ID',
  `to_device_id` bigint unsigned NOT NULL COMMENT '目标设备ID',
  `grant_id` bigint unsigned DEFAULT NULL COMMENT '关联授权ID',
  `status` varchar(32) NOT NULL COMMENT '连接状态：pending/accepted/rejected/canceled/expired',
  `reason` varchar(191) DEFAULT NULL COMMENT '状态原因',
  `completed_at` datetime(3) DEFAULT NULL COMMENT '完成时间',
  PRIMARY KEY (`id`),
  KEY `idx_remote_connection_attempts_from_user` (`from_user_id`),
  KEY `idx_remote_connection_attempts_to_device` (`to_device_id`),
  KEY `idx_remote_connection_attempts_status` (`status`),
  KEY `idx_remote_connection_attempts_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程连接请求状态表';

CREATE TABLE IF NOT EXISTS `remote_legal_documents` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `created_at` datetime(3) DEFAULT NULL COMMENT '创建时间',
  `updated_at` datetime(3) DEFAULT NULL COMMENT '更新时间',
  `deleted_at` datetime(3) DEFAULT NULL COMMENT '软删除时间',
  `type` varchar(64) NOT NULL COMMENT '协议类型：privacy_policy/user_agreement/subscription_agreement',
  `platform` varchar(32) NOT NULL DEFAULT 'all' COMMENT '适用平台：all/ios/macos/windows',
  `version` varchar(64) NOT NULL COMMENT '协议版本',
  `title` varchar(191) NOT NULL COMMENT '协议标题',
  `content_format` varchar(32) NOT NULL DEFAULT 'markdown' COMMENT '内容格式：markdown/html',
  `content` mediumtext NOT NULL COMMENT '协议正文',
  `published` tinyint(1) NOT NULL DEFAULT 0 COMMENT '是否发布',
  `effective_at` datetime(3) DEFAULT NULL COMMENT '生效时间',
  PRIMARY KEY (`id`),
  KEY `idx_remote_legal_documents_lookup` (`type`,`platform`,`published`),
  KEY `idx_remote_legal_documents_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程统一协议文档表';

CREATE TABLE IF NOT EXISTS `remote_legal_consents` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `created_at` datetime(3) DEFAULT NULL COMMENT '创建时间',
  `updated_at` datetime(3) DEFAULT NULL COMMENT '更新时间',
  `deleted_at` datetime(3) DEFAULT NULL COMMENT '软删除时间',
  `user_id` bigint unsigned NOT NULL COMMENT '远程用户ID',
  `document_id` bigint unsigned NOT NULL COMMENT '协议文档ID',
  `document_type` varchar(64) NOT NULL COMMENT '协议类型快照',
  `document_version` varchar(64) NOT NULL COMMENT '协议版本快照',
  `platform` varchar(32) NOT NULL COMMENT '同意来源平台',
  `device_id` bigint unsigned DEFAULT NULL COMMENT '同意来源设备ID',
  `consented_at` datetime(3) NOT NULL COMMENT '同意时间',
  PRIMARY KEY (`id`),
  KEY `idx_remote_legal_consents_user` (`user_id`),
  KEY `idx_remote_legal_consents_document` (`document_id`),
  KEY `idx_remote_legal_consents_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程协议同意记录表';

CREATE TABLE IF NOT EXISTS `remote_subscriptions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `created_at` datetime(3) DEFAULT NULL COMMENT '创建时间',
  `updated_at` datetime(3) DEFAULT NULL COMMENT '更新时间',
  `deleted_at` datetime(3) DEFAULT NULL COMMENT '软删除时间',
  `user_id` bigint unsigned NOT NULL COMMENT '远程用户ID',
  `plan_code` varchar(64) NOT NULL DEFAULT 'free' COMMENT '订阅套餐编码',
  `status` varchar(32) NOT NULL DEFAULT 'free' COMMENT '订阅状态：free/trial/active/expired/canceled',
  `started_at` datetime(3) DEFAULT NULL COMMENT '开始时间',
  `expires_at` datetime(3) DEFAULT NULL COMMENT '过期时间',
  `provider` varchar(64) DEFAULT NULL COMMENT '支付渠道',
  `provider_order_id` varchar(191) DEFAULT NULL COMMENT '渠道订单ID',
  PRIMARY KEY (`id`),
  KEY `idx_remote_subscriptions_user` (`user_id`),
  KEY `idx_remote_subscriptions_status` (`status`),
  KEY `idx_remote_subscriptions_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程订阅权益表';

CREATE TABLE IF NOT EXISTS `remote_entitlement_usages` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `created_at` datetime(3) DEFAULT NULL COMMENT '创建时间',
  `updated_at` datetime(3) DEFAULT NULL COMMENT '更新时间',
  `deleted_at` datetime(3) DEFAULT NULL COMMENT '软删除时间',
  `user_id` bigint unsigned NOT NULL COMMENT '远程用户ID',
  `connection_id` bigint unsigned NOT NULL COMMENT '连接请求ID',
  `usage_date` varchar(10) NOT NULL COMMENT '权益用量日期，YYYY-MM-DD',
  `mode` varchar(32) NOT NULL COMMENT '用量模式：cross_network',
  `started_at` datetime(3) NOT NULL COMMENT '计费开始时间',
  `ended_at` datetime(3) DEFAULT NULL COMMENT '计费结束时间',
  `billed_seconds` int NOT NULL DEFAULT 0 COMMENT '计费秒数',
  `status` varchar(32) NOT NULL COMMENT '用量状态：reserved/settled',
  PRIMARY KEY (`id`),
  KEY `idx_remote_entitlement_usage_day` (`user_id`,`usage_date`,`mode`),
  KEY `idx_remote_entitlement_usages_connection_id` (`connection_id`),
  KEY `idx_remote_entitlement_usages_status` (`status`),
  KEY `idx_remote_entitlement_usages_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程权益用量预留表';

CREATE TABLE IF NOT EXISTS `remote_audit_logs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `created_at` datetime(3) DEFAULT NULL COMMENT '创建时间',
  `updated_at` datetime(3) DEFAULT NULL COMMENT '更新时间',
  `deleted_at` datetime(3) DEFAULT NULL COMMENT '软删除时间',
  `user_id` bigint unsigned DEFAULT NULL COMMENT '远程用户ID',
  `device_id` bigint unsigned DEFAULT NULL COMMENT '远程设备ID',
  `action` varchar(64) NOT NULL COMMENT '审计动作',
  `status` varchar(32) NOT NULL COMMENT '动作结果：success/failed',
  `message` varchar(191) DEFAULT NULL COMMENT '脱敏说明',
  `ip_hash` varchar(64) DEFAULT NULL COMMENT '请求 IP 哈希',
  `user_agent` varchar(191) DEFAULT NULL COMMENT '请求 User-Agent',
  PRIMARY KEY (`id`),
  KEY `idx_remote_audit_logs_user` (`user_id`),
  KEY `idx_remote_audit_logs_device` (`device_id`),
  KEY `idx_remote_audit_logs_action` (`action`),
  KEY `idx_remote_audit_logs_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程业务审计日志表';
