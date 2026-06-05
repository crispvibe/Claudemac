CREATE TABLE IF NOT EXISTS `remote_auth_codes` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `created_at` datetime(3) DEFAULT NULL COMMENT '创建时间',
  `updated_at` datetime(3) DEFAULT NULL COMMENT '更新时间',
  `deleted_at` datetime(3) DEFAULT NULL COMMENT '软删除时间',
  `phone` varchar(32) NOT NULL COMMENT '手机号，验证码所属账号标识',
  `purpose` varchar(32) NOT NULL COMMENT '验证码用途：register_code/password_reset',
  `code_hash` varchar(191) NOT NULL COMMENT '验证码哈希',
  `expires_at` datetime(3) NOT NULL COMMENT '过期时间',
  `consumed_at` datetime(3) DEFAULT NULL COMMENT '使用时间',
  `revoked_at` datetime(3) DEFAULT NULL COMMENT '撤销时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_remote_auth_codes_hash` (`code_hash`),
  KEY `idx_remote_auth_codes_phone_purpose` (`phone`,`purpose`),
  KEY `idx_remote_auth_codes_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程账号验证码表';
