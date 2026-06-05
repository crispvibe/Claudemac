CREATE TABLE IF NOT EXISTS `remote_account_deletion_records` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `created_at` datetime(3) DEFAULT NULL COMMENT '创建时间',
  `updated_at` datetime(3) DEFAULT NULL COMMENT '更新时间',
  `deleted_at` datetime(3) DEFAULT NULL COMMENT '软删除时间',
  `user_id` bigint unsigned NOT NULL COMMENT '被注销远程用户ID快照',
  `email_hash` varchar(64) DEFAULT NULL COMMENT '邮箱 SHA256，用于脱敏追查',
  `email_masked` varchar(191) DEFAULT NULL COMMENT '脱敏邮箱快照',
  `phone_hash` varchar(64) DEFAULT NULL COMMENT '手机号 SHA256，用于历史账号脱敏追查',
  `phone_masked` varchar(64) DEFAULT NULL COMMENT '脱敏手机号快照',
  `status_snapshot` varchar(32) DEFAULT NULL COMMENT '注销前账号状态',
  `reason` varchar(500) DEFAULT NULL COMMENT '用户填写的注销原因',
  `operator` varchar(32) NOT NULL DEFAULT 'self' COMMENT '注销触发方：self/admin',
  `confirmation_snapshot` varchar(191) DEFAULT NULL COMMENT '注销确认文本快照',
  `subscription_snapshot` json DEFAULT NULL COMMENT '注销前服务权益快照',
  `order_snapshot` json DEFAULT NULL COMMENT '注销前服务开通记录快照',
  `device_snapshot` json DEFAULT NULL COMMENT '注销前设备快照',
  `usage_snapshot` json DEFAULT NULL COMMENT '注销前权益用量快照',
  `deleted_at_snapshot` datetime(3) NOT NULL COMMENT '注销完成时间',
  PRIMARY KEY (`id`),
  KEY `idx_remote_account_deletion_records_user_id` (`user_id`),
  KEY `idx_remote_account_deletion_records_email_hash` (`email_hash`),
  KEY `idx_remote_account_deletion_records_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='远程账号注销记录表';

UPDATE `remote_legal_documents`
SET `published` = 0, `updated_at` = NOW(3)
WHERE `type` IN ('privacy_policy', 'user_agreement')
  AND `platform` IN ('all', 'ios', 'macos')
  AND `published` = 1;

INSERT INTO `remote_legal_documents`
(`created_at`, `updated_at`, `type`, `platform`, `version`, `title`, `content_format`, `content`, `published`, `effective_at`)
VALUES
(NOW(3), NOW(3), 'privacy_policy', 'ios', '2026.05.19-ios-remote', 'AnnaCode iOS 隐私政策', 'markdown',
'# AnnaCode iOS 隐私政策

更新日期：2026-05-19

## 账号与登录
AnnaCode iOS 使用邮箱注册和登录。我们会处理邮箱、密码哈希、登录令牌、刷新令牌、登录时间、协议确认记录和必要的安全审计信息，用于创建账号、保持登录状态、防止未经授权访问和记录用户同意情况。

## 设备与远程连接
为连接你自己的电脑端 AnnaCode，我们会处理 iOS 设备标识、设备名称、设备公钥、App 版本、连接请求记录、连接状态、设备授权记录、局域网 IP 和端口、短期连接凭证、WebRTC/信令协商信息、连接质量指标和必要的脱敏日志。上述信息用于发现设备、建立局域网或远程连接、完成电脑端确认、排查连接问题和保护账号安全。

## 相机、相册、图片和文件
当你主动选择拍照、从相册选择图片或上传文件附件时，AnnaCode iOS 会读取你选择的图片或文件，并发送到你连接的电脑端用于本次对话或任务处理。我们不会在你未主动选择时读取相机、相册或文件内容。

## 保存期限与删除
账号、设备、连接授权和协议确认记录在账号有效期间保存。连接日志、设备码尝试、安全审计和质量指标按排障、安全和合规所需的最小期限保存。你在 iOS 端发起注销后，系统会删除远程账号、登录令牌、设备、连接授权、协议确认和主要服务数据；为处理争议、审计和合规留痕，仅保留脱敏注销记录、邮箱哈希、注销时间、设备和服务权益快照等无法直接登录或继续使用服务的信息。

## 用户权利
你可以查询、更正、删除个人信息，撤回同意，或注销账号。注销成功后账号不可恢复，法律法规另有要求的记录按最小必要原则保留。

## 联系我们
如需行使个人信息权利或提出隐私问题，请通过 App 内反馈入口或官方支持邮箱联系我们。', 1, NOW(3)),
(NOW(3), NOW(3), 'user_agreement', 'ios', '2026.05.19-ios-remote', 'AnnaCode iOS 用户协议', 'markdown',
'# AnnaCode iOS 用户协议

更新日期：2026-05-19

## 服务范围
AnnaCode iOS 是连接你自己电脑端 AnnaCode 的远程伴侣工具。iOS 端用于登录账号、查看和连接已授权电脑、发送对话消息、上传你主动选择的图片或文件附件，并展示电脑端返回的会话内容。

## 账号与设备
你应使用本人可控制的邮箱注册和登录，并妥善保管密码、设备和登录状态。连接他人设备或跨账号连接时，需要遵守电脑端确认和授权流程。

## 远程连接规则
你只能连接自己拥有或已获得授权的电脑。不得绕过电脑端确认，不得利用远程连接访问无权访问的账号、文件、系统、服务或数据，不得攻击、干扰、逆向破坏 AnnaCode 或相关服务。

## 附件与内容
你应确保通过 iOS 上传的图片、文件和输入内容来源合法，并自行确认是否适合发送到电脑端进行处理。涉及敏感、保密或第三方权利内容时，请先取得必要授权。

## 账号注销
你可以在“设置 - 账号与安全 - 注销账号”发起注销。注销前需输入指定确认文本，包括确认注销账号、确认销毁账号数据、确认放弃未使用服务权益。提交成功后系统将注销账号并删除主要用户数据，注销不可撤销。

## 违约处理
如你违反本协议或法律法规，我们可限制、暂停或终止相关服务，并保留必要的安全审计记录。', 1, NOW(3)),
(NOW(3), NOW(3), 'privacy_policy', 'macos', '2026.05.19-macos-remote', 'AnnaCode macOS 隐私政策', 'markdown',
'# AnnaCode macOS 隐私政策

更新日期：2026-05-19

## 账号与设备
AnnaCode macOS 使用邮箱注册和登录。我们会处理邮箱、密码哈希、登录令牌、刷新令牌、设备标识、设备名称、设备公钥、App 版本、协议确认记录和必要的安全审计信息，用于账号安全、设备绑定和远程连接授权。

## 电脑端远程服务
为让 iOS 端连接你自己的电脑，AnnaCode macOS 会处理设备码、连接请求、电脑端确认结果、授权记录、局域网 IP 和端口、短期连接凭证、WebRTC/信令协商信息、连接状态、连接日志和质量指标。上述信息用于设备发现、建立连接、保护电脑端访问边界和排查连接问题。

## 对话、命令和附件
AnnaCode macOS 会在本机处理你发起的对话、命令、会话记录、项目路径、你选择的文件或图片附件，以及 iOS 主动发送到电脑端的附件。AnnaCode 只应访问你授权或主动选择的项目和文件；请勿让应用处理你无权处理或不希望被 AI 工具读取的内容。

## 保存期限与删除
账号、设备、连接授权、协议确认和必要服务状态在账号有效期间保存。连接日志、设备码尝试、安全审计和质量指标按排障、安全和合规所需的最小期限保存。注销后，系统会删除远程账号、登录令牌、设备、连接授权、协议确认和主要服务数据；为处理争议、审计和合规留痕，仅保留脱敏注销记录、邮箱哈希、注销时间、设备和服务权益快照等无法直接登录或继续使用服务的信息。

## 用户权利
你可以查询、更正、删除个人信息，撤回同意，或注销账号。注销成功后账号不可恢复，法律法规另有要求的记录按最小必要原则保留。

## 联系我们
如需行使个人信息权利或提出隐私问题，请通过 App 内反馈入口或官方支持邮箱联系我们。', 1, NOW(3)),
(NOW(3), NOW(3), 'user_agreement', 'macos', '2026.05.19-macos-remote', 'AnnaCode macOS 用户协议', 'markdown',
'# AnnaCode macOS 用户协议

更新日期：2026-05-19

## 服务范围
AnnaCode macOS 是运行在你自己电脑上的 AI CLI 工作台和远程连接主机。它用于管理本机项目、启动本机 AI 命令行会话、处理你主动选择的文件或附件，并在你允许后向 iOS 端提供远程会话能力。

## 账号与设备
你应使用本人可控制的邮箱注册和登录，并妥善保管密码、设备、设备码和登录状态。你应确认每次远程连接请求来自可信设备和可信账号。

## 远程连接规则
你应只向自己或已获授权的人开放电脑端连接。不得共享、转售、滥用账号或设备授权，不得绕过连接确认和安全限制，不得利用 AnnaCode 访问无权访问的系统、账号、文件、服务或数据。

## 本机内容处理
你应确保通过 AnnaCode macOS 处理的项目、命令、文件、图片和附件来源合法，且你有权提交给相关 AI 工具处理。涉及敏感、保密、第三方代码或第三方权利内容时，请自行确认授权和合规边界。

## 账号注销
你可以在“设置 - 账号与安全 - 注销账号”发起注销。注销前需输入指定确认文本，包括确认注销账号、确认销毁账号数据、确认放弃未使用服务权益。提交成功后系统将注销账号并删除主要用户数据，注销不可撤销。

## 违约处理
如你违反本协议或法律法规，我们可限制、暂停或终止相关服务，并保留必要的安全审计记录。', 1, NOW(3));
