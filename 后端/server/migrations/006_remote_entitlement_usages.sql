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
