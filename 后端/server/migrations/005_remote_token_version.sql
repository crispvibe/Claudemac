ALTER TABLE `remote_users`
  ADD COLUMN `token_version` int NOT NULL DEFAULT 0 COMMENT '访问令牌版本，递增后使旧 access token 失效' AFTER `status`,
  ADD KEY `idx_remote_users_token_version` (`token_version`);
