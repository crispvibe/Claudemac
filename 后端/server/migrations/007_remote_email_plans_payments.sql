ALTER TABLE `remote_users`
  MODIFY COLUMN `phone` varchar(32) NOT NULL COMMENT '手机号，历史登录标识，邮箱账号使用内部占位值',
  ADD COLUMN `email` varchar(191) DEFAULT NULL COMMENT '邮箱，远程账号主要登录标识' AFTER `phone`,
  ADD UNIQUE KEY `idx_remote_users_email` (`email`);

ALTER TABLE `remote_auth_codes`
  MODIFY COLUMN `phone` varchar(32) DEFAULT NULL COMMENT '手机号，历史验证码账号标识',
  ADD COLUMN `email` varchar(191) DEFAULT NULL COMMENT '邮箱，验证码所属账号标识' AFTER `phone`,
  ADD KEY `idx_remote_auth_codes_email_purpose` (`email`,`purpose`);

CREATE TABLE IF NOT EXISTS `remote_subscription_plans` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `created_at` datetime(3) DEFAULT NULL COMMENT '创建时间',
  `updated_at` datetime(3) DEFAULT NULL COMMENT '更新时间',
  `deleted_at` datetime(3) DEFAULT NULL COMMENT '软删除时间',
  `code` varchar(64) NOT NULL COMMENT '套餐编码',
  `name` varchar(191) NOT NULL COMMENT '套餐名称',
  `description` varchar(500) DEFAULT NULL COMMENT '套餐说明',
  `duration_months` int NOT NULL COMMENT '套餐时长，单位月，仅允许 6 或 12',
  `price_fen` bigint NOT NULL DEFAULT 0 COMMENT '套餐价格，单位分',
  `currency` varchar(16) NOT NULL DEFAULT 'CNY' COMMENT '币种',
  `status` varchar(32) NOT NULL DEFAULT 'active' COMMENT '套餐状态：active/disabled',
  `sort` int NOT NULL DEFAULT 0 COMMENT '排序值，越小越靠前',
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_remote_subscription_plans_code` (`code`),
  KEY `idx_remote_subscription_plans_status` (`status`),
  KEY `idx_remote_subscription_plans_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程订阅套餐配置表';

CREATE TABLE IF NOT EXISTS `remote_subscription_orders` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `created_at` datetime(3) DEFAULT NULL COMMENT '创建时间',
  `updated_at` datetime(3) DEFAULT NULL COMMENT '更新时间',
  `deleted_at` datetime(3) DEFAULT NULL COMMENT '软删除时间',
  `user_id` bigint unsigned NOT NULL COMMENT '远程用户ID',
  `plan_id` bigint unsigned NOT NULL COMMENT '套餐ID',
  `plan_code` varchar(64) NOT NULL COMMENT '套餐编码快照',
  `plan_name` varchar(191) NOT NULL COMMENT '套餐名称快照',
  `duration_months` int NOT NULL COMMENT '购买时长，单位月',
  `amount_fen` bigint NOT NULL COMMENT '订单金额，单位分',
  `currency` varchar(16) NOT NULL DEFAULT 'CNY' COMMENT '币种',
  `status` varchar(32) NOT NULL DEFAULT 'pending' COMMENT '订单状态：pending/paid/closed/failed',
  `out_trade_no` varchar(64) NOT NULL COMMENT '商户订单号',
  `pay_order_no` varchar(64) DEFAULT NULL COMMENT '支付平台订单号',
  `channel_code` varchar(32) DEFAULT NULL COMMENT '支付方式',
  `trade_type` varchar(32) DEFAULT NULL COMMENT '支付场景',
  `invoke_params` json DEFAULT NULL COMMENT '支付唤起参数',
  `pay_url` varchar(1000) DEFAULT NULL COMMENT '收银台或跳转地址',
  `paid_at` datetime(3) DEFAULT NULL COMMENT '支付完成时间',
  `subscription_id` bigint unsigned DEFAULT NULL COMMENT '开通后的订阅ID',
  `raw_response` json DEFAULT NULL COMMENT '支付平台下单响应摘要',
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_remote_subscription_orders_out_trade_no` (`out_trade_no`),
  KEY `idx_remote_subscription_orders_user` (`user_id`),
  KEY `idx_remote_subscription_orders_plan` (`plan_id`),
  KEY `idx_remote_subscription_orders_plan_code` (`plan_code`),
  KEY `idx_remote_subscription_orders_status` (`status`),
  KEY `idx_remote_subscription_orders_pay_order_no` (`pay_order_no`),
  KEY `idx_remote_subscription_orders_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程订阅支付订单表';

CREATE TABLE IF NOT EXISTS `remote_payment_notify_events` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `created_at` datetime(3) DEFAULT NULL COMMENT '创建时间',
  `updated_at` datetime(3) DEFAULT NULL COMMENT '更新时间',
  `deleted_at` datetime(3) DEFAULT NULL COMMENT '软删除时间',
  `event_id` varchar(128) NOT NULL COMMENT '支付平台事件ID，用于幂等',
  `event_kind` varchar(64) NOT NULL COMMENT '支付平台事件类型',
  `out_trade_no` varchar(64) DEFAULT NULL COMMENT '商户订单号',
  `pay_order_no` varchar(64) DEFAULT NULL COMMENT '支付平台订单号',
  `status` varchar(32) NOT NULL COMMENT '处理状态：processed/ignored/failed',
  `payload` json DEFAULT NULL COMMENT '脱敏通知内容',
  `processed_at` datetime(3) DEFAULT NULL COMMENT '处理时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_remote_payment_notify_events_event_id` (`event_id`),
  KEY `idx_remote_payment_notify_events_event_kind` (`event_kind`),
  KEY `idx_remote_payment_notify_events_out_trade_no` (`out_trade_no`),
  KEY `idx_remote_payment_notify_events_pay_order_no` (`pay_order_no`),
  KEY `idx_remote_payment_notify_events_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程支付通知幂等表';
