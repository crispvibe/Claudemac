ALTER TABLE `remote_devices`
  ADD COLUMN `lan_ip` varchar(64) DEFAULT NULL COMMENT '局域网连接 IP，仅设备所属用户可见' AFTER `last_seen_at`,
  ADD COLUMN `lan_port` int DEFAULT 0 COMMENT '局域网连接端口' AFTER `lan_ip`,
  ADD COLUMN `lan_token` varchar(191) DEFAULT NULL COMMENT '局域网短期访问令牌明文，过期后失效' AFTER `lan_port`,
  ADD COLUMN `lan_token_expires_at` datetime(3) DEFAULT NULL COMMENT '局域网短期访问令牌过期时间' AFTER `lan_token`,
  ADD COLUMN `lan_endpoint_last_seen_at` datetime(3) DEFAULT NULL COMMENT '局域网入口最近发布时间' AFTER `lan_token_expires_at`,
  ADD COLUMN `lan_publisher_ip_hash` varchar(64) DEFAULT NULL COMMENT '局域网入口发布方 IP 哈希' AFTER `lan_endpoint_last_seen_at`,
  ADD KEY `idx_remote_devices_lan_token_expires_at` (`lan_token_expires_at`);
