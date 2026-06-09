ALTER TABLE `remote_connection_attempts`
  ADD COLUMN `transport` varchar(32) DEFAULT NULL COMMENT '实际连接传输：lan/p2p/turn，未建立时为空' AFTER `completed_at`,
  ADD COLUMN `first_packet_latency_ms` int DEFAULT NULL COMMENT '首包延迟毫秒，客户端首次成功收包后上报' AFTER `transport`,
  ADD COLUMN `first_packet_at` datetime(3) DEFAULT NULL COMMENT '首包到达时间' AFTER `first_packet_latency_ms`,
  ADD COLUMN `network_type` varchar(64) DEFAULT NULL COMMENT '客户端脱敏网络类型，用于连接质量观测' AFTER `first_packet_at`,
  ADD COLUMN `app_version` varchar(64) DEFAULT NULL COMMENT '客户端版本，用于连接质量观测' AFTER `network_type`,
  ADD COLUMN `request_id` varchar(64) DEFAULT NULL COMMENT '客户端请求标识，用于脱敏链路追踪' AFTER `app_version`,
  ADD KEY `idx_remote_connection_attempts_transport` (`transport`),
  ADD KEY `idx_remote_connection_attempts_first_packet_at` (`first_packet_at`);

ALTER TABLE `remote_audit_logs`
  ADD COLUMN `connection_id` bigint unsigned DEFAULT NULL COMMENT '远程连接请求ID，用于关联连接、信令和审计' AFTER `device_id`,
  ADD KEY `idx_remote_audit_logs_connection_id` (`connection_id`);
