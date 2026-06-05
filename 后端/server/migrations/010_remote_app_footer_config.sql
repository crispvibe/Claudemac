CREATE TABLE IF NOT EXISTS `remote_app_footer_configs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(3) DEFAULT NULL,
  `updated_at` datetime(3) DEFAULT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  `platform` varchar(32) NOT NULL DEFAULT 'ios' COMMENT '适用平台：ios/macos/windows/all',
  `company_name` varchar(191) NOT NULL DEFAULT '' COMMENT '公司名称',
  `copyright_text` varchar(191) NOT NULL DEFAULT '' COMMENT '版权文案',
  `icp_text` varchar(191) NOT NULL DEFAULT '' COMMENT 'ICP备案文案',
  `record_text` varchar(191) NOT NULL DEFAULT '' COMMENT '公安备案或其他备案文案',
  `support_url` varchar(500) NOT NULL DEFAULT '' COMMENT '支持URL',
  `privacy_url` varchar(500) NOT NULL DEFAULT '' COMMENT '隐私政策URL',
  `published` tinyint(1) NOT NULL DEFAULT 1 COMMENT '是否启用',
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_remote_app_footer_configs_platform` (`platform`),
  KEY `idx_remote_app_footer_configs_published` (`published`),
  KEY `idx_remote_app_footer_configs_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程 App 页脚配置表';

INSERT INTO `remote_app_footer_configs`
(`created_at`, `updated_at`, `platform`, `company_name`, `copyright_text`, `icp_text`, `record_text`, `support_url`, `privacy_url`, `published`)
VALUES
(NOW(3), NOW(3), 'ios', '禾屿科技', '© 2026 禾屿科技', 'ICP备案信息待更新', '', 'https://acode.anna.vin/support.html', 'https://acode.anna.vin/privacy-ios.html', 1)
ON DUPLICATE KEY UPDATE
  `company_name` = VALUES(`company_name`),
  `copyright_text` = VALUES(`copyright_text`),
  `updated_at` = NOW(3);
