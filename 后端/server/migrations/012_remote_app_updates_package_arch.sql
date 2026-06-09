SET @column_exists := (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'remote_app_updates'
    AND COLUMN_NAME = 'package_arch'
);

SET @ddl := IF(
  @column_exists = 0,
  'ALTER TABLE `remote_app_updates` ADD COLUMN `package_arch` varchar(32) NOT NULL DEFAULT ''universal'' COMMENT ''安装包架构：universal/arm64/x86_64'' AFTER `build_number`',
  'SELECT 1'
);

PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

UPDATE `remote_app_updates`
SET `package_arch` = 'universal'
WHERE `package_arch` = '';

SET @index_exists := (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'remote_app_updates'
    AND INDEX_NAME = 'idx_remote_app_updates_arch'
);

SET @idx := IF(
  @index_exists = 0,
  'CREATE INDEX `idx_remote_app_updates_arch` ON `remote_app_updates` (`platform`, `channel`, `package_arch`, `published`, `released_at`)',
  'SELECT 1'
);

PREPARE stmt FROM @idx;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
