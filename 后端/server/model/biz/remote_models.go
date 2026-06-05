package biz

import (
	"time"

	"heyu/server/global"
	"heyu/server/model/shared"
)

type RemoteUser struct {
	global.BaseModel
	Phone        string     `json:"phone" gorm:"uniqueIndex;size:32;comment:手机号，历史登录标识，逐步迁移为邮箱"`
	Email        string     `json:"email" gorm:"uniqueIndex;size:191;comment:邮箱，远程账号主要登录标识"`
	PasswordHash string     `json:"-" gorm:"size:191;comment:bcrypt 密码哈希"`
	Status       string     `json:"status" gorm:"size:32;default:active;comment:账号状态：active/disabled"`
	TokenVersion int        `json:"-" gorm:"default:0;comment:访问令牌版本，递增后使旧 access token 失效"`
	LastLoginAt  *time.Time `json:"lastLoginAt" gorm:"comment:最近登录时间"`
}

func (RemoteUser) TableName() string { return "remote_users" }

type RemoteUserToken struct {
	global.BaseModel
	UserID     uint       `json:"userId" gorm:"index;comment:远程用户ID"`
	TokenHash  string     `json:"-" gorm:"uniqueIndex;size:191;comment:刷新令牌哈希"`
	TokenType  string     `json:"tokenType" gorm:"size:32;default:refresh;comment:令牌类型：refresh"`
	ExpiresAt  time.Time  `json:"expiresAt" gorm:"comment:过期时间"`
	RevokedAt  *time.Time `json:"revokedAt" gorm:"comment:撤销时间"`
	LastUsedAt *time.Time `json:"lastUsedAt" gorm:"comment:最近使用时间"`
}

func (RemoteUserToken) TableName() string { return "remote_user_tokens" }

type RemoteAuthCode struct {
	global.BaseModel
	Phone      string     `json:"phone" gorm:"index:idx_remote_auth_codes_phone_purpose,priority:1;size:32;comment:手机号，历史验证码账号标识"`
	Email      string     `json:"email" gorm:"index:idx_remote_auth_codes_email_purpose,priority:1;size:191;comment:邮箱，验证码所属账号标识"`
	Purpose    string     `json:"purpose" gorm:"index:idx_remote_auth_codes_phone_purpose,priority:2;index:idx_remote_auth_codes_email_purpose,priority:2;size:32;comment:验证码用途：register_code/password_reset"`
	CodeHash   string     `json:"-" gorm:"uniqueIndex;size:191;comment:验证码哈希"`
	ExpiresAt  time.Time  `json:"expiresAt" gorm:"comment:过期时间"`
	ConsumedAt *time.Time `json:"consumedAt" gorm:"comment:使用时间"`
	RevokedAt  *time.Time `json:"revokedAt" gorm:"comment:撤销时间"`
}

func (RemoteAuthCode) TableName() string { return "remote_auth_codes" }

type RemoteDevice struct {
	global.BaseModel
	UserID                uint       `json:"userId" gorm:"index;comment:所属远程用户ID"`
	DeviceUID             string     `json:"deviceUid" gorm:"uniqueIndex;size:64;comment:客户端生成的稳定设备标识"`
	DeviceType            string     `json:"deviceType" gorm:"size:32;comment:设备类型：desktop/ios"`
	Platform              string     `json:"platform" gorm:"size:32;comment:平台：macos/windows/ios"`
	DeviceName            string     `json:"deviceName" gorm:"size:191;comment:设备展示名称"`
	DevicePublicKey       string     `json:"devicePublicKey" gorm:"type:text;comment:设备公钥，用于后续端到端握手"`
	DeviceCodeHash        string     `json:"-" gorm:"index;size:191;comment:固定设备码哈希，仅桌面设备使用"`
	DeviceCodeHint        string     `json:"deviceCodeHint" gorm:"size:16;comment:设备码脱敏提示"`
	ApprovalPolicy        string     `json:"approvalPolicy" gorm:"size:32;default:always_ask;comment:跨账号确认策略：always_ask/allow_anyone"`
	RemoteEnabled         bool       `json:"remoteEnabled" gorm:"default:true;comment:远程连接总开关"`
	Status                string     `json:"status" gorm:"size:32;default:active;comment:设备状态：active/disabled"`
	AppVersion            string     `json:"appVersion" gorm:"size:64;comment:客户端版本"`
	LastSeenAt            *time.Time `json:"lastSeenAt" gorm:"comment:最近在线时间"`
	LanIP                 string     `json:"-" gorm:"size:64;comment:局域网连接 IP，仅设备所属用户可见"`
	LanPort               int        `json:"-" gorm:"comment:局域网连接端口"`
	LanToken              string     `json:"-" gorm:"size:191;comment:局域网短期访问令牌明文，过期后失效"`
	LanTokenExpiresAt     *time.Time `json:"-" gorm:"comment:局域网短期访问令牌过期时间"`
	LanEndpointLastSeenAt *time.Time `json:"-" gorm:"comment:局域网入口最近发布时间"`
	LanPublisherIPHash    string     `json:"-" gorm:"size:64;comment:局域网入口发布方 IP 哈希"`
}

func (RemoteDevice) TableName() string { return "remote_devices" }

type RemoteDeviceCodeAttempt struct {
	global.BaseModel
	TargetDeviceID *uint  `json:"targetDeviceId" gorm:"index;comment:解析命中的目标设备ID"`
	FromUserID     *uint  `json:"fromUserId" gorm:"index;comment:发起解析的远程用户ID"`
	FromDeviceID   *uint  `json:"fromDeviceId" gorm:"comment:发起解析的设备ID"`
	CodeHashPrefix string `json:"codeHashPrefix" gorm:"size:16;comment:设备码哈希前缀，用于审计不反推出明文"`
	Status         string `json:"status" gorm:"size:32;comment:解析结果：success/failed/rate_limited"`
	FailureReason  string `json:"failureReason" gorm:"size:191;comment:失败原因"`
	IPHash         string `json:"ipHash" gorm:"size:64;comment:请求 IP 哈希"`
}

func (RemoteDeviceCodeAttempt) TableName() string { return "remote_device_code_attempts" }

type RemoteDeviceGrant struct {
	global.BaseModel
	OwnerUserID     uint       `json:"ownerUserId" gorm:"index;comment:目标设备所属用户ID"`
	TargetDeviceID  uint       `json:"targetDeviceId" gorm:"index;comment:被连接的目标设备ID"`
	GranteeUserID   uint       `json:"granteeUserId" gorm:"index;comment:被授权用户ID"`
	GranteeDeviceID *uint      `json:"granteeDeviceId" gorm:"comment:被授权设备ID"`
	Scope           string     `json:"scope" gorm:"size:32;default:chat_only;comment:授权范围：chat_only"`
	GrantType       string     `json:"grantType" gorm:"size:32;comment:授权类型：same_account/device_code"`
	Remembered      bool       `json:"remembered" gorm:"default:false;comment:是否记住授权"`
	Status          string     `json:"status" gorm:"size:32;default:active;comment:授权状态：active/revoked/expired"`
	ExpiresAt       *time.Time `json:"expiresAt" gorm:"comment:授权过期时间"`
	LastUsedAt      *time.Time `json:"lastUsedAt" gorm:"comment:最近使用时间"`
}

func (RemoteDeviceGrant) TableName() string { return "remote_device_grants" }

type RemoteConnectionAttempt struct {
	global.BaseModel
	FromUserID           uint       `json:"fromUserId" gorm:"index;comment:发起连接用户ID"`
	FromDeviceID         *uint      `json:"fromDeviceId" gorm:"comment:发起连接设备ID"`
	ToUserID             uint       `json:"toUserId" gorm:"comment:目标设备所属用户ID"`
	ToDeviceID           uint       `json:"toDeviceId" gorm:"index;comment:目标设备ID"`
	GrantID              *uint      `json:"grantId" gorm:"comment:关联授权ID"`
	Status               string     `json:"status" gorm:"index;size:32;comment:连接状态：pending/accepted/rejected/canceled/expired"`
	Reason               string     `json:"reason" gorm:"size:191;comment:状态原因"`
	CompletedAt          *time.Time `json:"completedAt" gorm:"comment:完成时间"`
	Transport            string     `json:"transport" gorm:"index;size:32;comment:实际连接传输：lan/p2p/turn，未建立时为空"`
	FirstPacketLatencyMS *int       `json:"firstPacketLatencyMs" gorm:"comment:首包延迟毫秒，客户端首次成功收包后上报"`
	FirstPacketAt        *time.Time `json:"firstPacketAt" gorm:"index;comment:首包到达时间"`
	NetworkType          string     `json:"networkType" gorm:"size:64;comment:客户端脱敏网络类型，用于连接质量观测"`
	AppVersion           string     `json:"appVersion" gorm:"size:64;comment:客户端版本，用于连接质量观测"`
	RequestID            string     `json:"requestId" gorm:"size:64;comment:客户端请求标识，用于脱敏链路追踪"`
}

func (RemoteConnectionAttempt) TableName() string { return "remote_connection_attempts" }

type RemoteLegalDocument struct {
	global.BaseModel
	Type          string     `json:"type" gorm:"index;size:64;comment:协议类型：privacy_policy/user_agreement/subscription_agreement"`
	Platform      string     `json:"platform" gorm:"index;size:32;default:all;comment:适用平台：all/ios/macos/windows"`
	Version       string     `json:"version" gorm:"size:64;comment:协议版本"`
	Title         string     `json:"title" gorm:"size:191;comment:协议标题"`
	ContentFormat string     `json:"contentFormat" gorm:"size:32;default:markdown;comment:内容格式：markdown/html"`
	Content       string     `json:"content" gorm:"type:mediumtext;comment:协议正文"`
	Published     bool       `json:"published" gorm:"index;default:false;comment:是否发布"`
	EffectiveAt   *time.Time `json:"effectiveAt" gorm:"comment:生效时间"`
}

func (RemoteLegalDocument) TableName() string { return "remote_legal_documents" }

type RemoteLegalConsent struct {
	global.BaseModel
	UserID          uint      `json:"userId" gorm:"index;comment:远程用户ID"`
	DocumentID      uint      `json:"documentId" gorm:"index;comment:协议文档ID"`
	DocumentType    string    `json:"documentType" gorm:"size:64;comment:协议类型快照"`
	DocumentVersion string    `json:"documentVersion" gorm:"size:64;comment:协议版本快照"`
	Platform        string    `json:"platform" gorm:"size:32;comment:同意来源平台"`
	DeviceID        *uint     `json:"deviceId" gorm:"comment:同意来源设备ID"`
	ConsentedAt     time.Time `json:"consentedAt" gorm:"comment:同意时间"`
}

func (RemoteLegalConsent) TableName() string { return "remote_legal_consents" }

type RemoteAppFooterConfig struct {
	global.BaseModel
	Platform      string `json:"platform" gorm:"uniqueIndex;size:32;default:ios;comment:适用平台：ios/macos/windows/all"`
	CompanyName   string `json:"companyName" gorm:"size:191;comment:公司名称"`
	CopyrightText string `json:"copyrightText" gorm:"size:191;comment:版权文案"`
	ICPText       string `json:"icpText" gorm:"size:191;comment:ICP备案文案"`
	RecordText    string `json:"recordText" gorm:"size:191;comment:公安备案或其他备案文案"`
	SupportURL    string `json:"supportUrl" gorm:"size:500;comment:支持URL"`
	PrivacyURL    string `json:"privacyUrl" gorm:"size:500;comment:隐私政策URL"`
	Published     bool   `json:"published" gorm:"index;default:true;comment:是否启用"`
}

func (RemoteAppFooterConfig) TableName() string { return "remote_app_footer_configs" }

type RemoteAppUpdate struct {
	global.BaseModel
	Platform        string     `json:"platform" gorm:"index:idx_remote_app_updates_lookup,priority:1;size:32;comment:适用平台：android/windows/macos/ios/all"`
	Channel         string     `json:"channel" gorm:"index:idx_remote_app_updates_lookup,priority:2;size:32;default:stable;comment:发布通道：stable/beta"`
	Version         string     `json:"version" gorm:"size:64;comment:版本号，例如 1.2.0"`
	BuildNumber     string     `json:"buildNumber" gorm:"size:64;comment:构建号"`
	PackageArch     string     `json:"packageArch" gorm:"index:idx_remote_app_updates_lookup,priority:3;size:32;default:universal;comment:安装包架构：universal/arm64/x86_64"`
	MinimumVersion  string     `json:"minimumVersion" gorm:"size:64;comment:最低可用版本，低于该版本应强制更新"`
	ReleaseNotes    string     `json:"releaseNotes" gorm:"type:text;comment:更新说明"`
	UpdateType      string     `json:"updateType" gorm:"size:32;default:link;comment:更新方式：link/file/app_store"`
	DownloadURL     string     `json:"downloadUrl" gorm:"size:1000;comment:下载链接或 DMG 文件地址"`
	AppStoreURL     string     `json:"appStoreUrl" gorm:"size:1000;comment:iOS App Store 链接"`
	PackageFileID   *uint      `json:"packageFileId" gorm:"comment:关联上传文件ID，可为空"`
	PackageFileName string     `json:"packageFileName" gorm:"size:191;comment:上传文件名"`
	PackageFileSize int64      `json:"packageFileSize" gorm:"comment:上传文件大小"`
	PackageSHA256   string     `json:"packageSha256" gorm:"size:128;comment:安装包 SHA256"`
	ForceUpdate     bool       `json:"forceUpdate" gorm:"default:false;comment:是否强制更新"`
	Published       bool       `json:"published" gorm:"index:idx_remote_app_updates_lookup,priority:4;default:false;comment:是否发布"`
	ReleasedAt      *time.Time `json:"releasedAt" gorm:"index;comment:发布时间"`
}

func (RemoteAppUpdate) TableName() string { return "remote_app_updates" }

type RemoteSubscription struct {
	global.BaseModel
	UserID          uint       `json:"userId" gorm:"index;comment:远程用户ID"`
	PlanCode        string     `json:"planCode" gorm:"size:64;default:free;comment:订阅套餐编码"`
	Status          string     `json:"status" gorm:"index;size:32;default:free;comment:订阅状态：free/trial/active/expired/canceled"`
	StartedAt       *time.Time `json:"startedAt" gorm:"comment:开始时间"`
	ExpiresAt       *time.Time `json:"expiresAt" gorm:"comment:过期时间"`
	Provider        string     `json:"provider" gorm:"size:64;comment:支付渠道"`
	ProviderOrderID string     `json:"providerOrderId" gorm:"size:191;comment:渠道订单ID"`
}

func (RemoteSubscription) TableName() string { return "remote_subscriptions" }

type RemoteSubscriptionPlan struct {
	global.BaseModel
	Code           string `json:"code" gorm:"uniqueIndex;size:64;comment:套餐编码"`
	Name           string `json:"name" gorm:"size:191;comment:套餐名称"`
	Description    string `json:"description" gorm:"size:500;comment:套餐说明"`
	DurationMonths int    `json:"durationMonths" gorm:"comment:套餐时长，单位月，仅允许 6 或 12"`
	PriceFen       int64  `json:"priceFen" gorm:"comment:套餐价格，单位分"`
	Currency       string `json:"currency" gorm:"size:16;default:CNY;comment:币种"`
	Status         string `json:"status" gorm:"index;size:32;default:active;comment:套餐状态：active/disabled"`
	Sort           int    `json:"sort" gorm:"default:0;comment:排序值，越小越靠前"`
}

func (RemoteSubscriptionPlan) TableName() string { return "remote_subscription_plans" }

type RemoteSubscriptionOrder struct {
	global.BaseModel
	UserID         uint           `json:"userId" gorm:"index;comment:远程用户ID"`
	PlanID         uint           `json:"planId" gorm:"index;comment:套餐ID"`
	PlanCode       string         `json:"planCode" gorm:"index;size:64;comment:套餐编码快照"`
	PlanName       string         `json:"planName" gorm:"size:191;comment:套餐名称快照"`
	DurationMonths int            `json:"durationMonths" gorm:"comment:购买时长，单位月"`
	AmountFen      int64          `json:"amountFen" gorm:"comment:订单金额，单位分"`
	Currency       string         `json:"currency" gorm:"size:16;default:CNY;comment:币种"`
	Status         string         `json:"status" gorm:"index;size:32;default:pending;comment:订单状态：pending/paid/closed/failed"`
	OutTradeNo     string         `json:"outTradeNo" gorm:"uniqueIndex;size:64;comment:商户订单号"`
	PayOrderNo     string         `json:"payOrderNo" gorm:"index;size:64;comment:支付平台订单号"`
	ChannelCode    string         `json:"channelCode" gorm:"size:32;comment:支付方式"`
	TradeType      string         `json:"tradeType" gorm:"size:32;comment:支付场景"`
	InvokeParams   shared.JSONMap `json:"invokeParams" gorm:"type:json;comment:支付唤起参数"`
	PayURL         string         `json:"payUrl" gorm:"size:1000;comment:收银台或跳转地址"`
	PaidAt         *time.Time     `json:"paidAt" gorm:"comment:支付完成时间"`
	SubscriptionID *uint          `json:"subscriptionId" gorm:"comment:开通后的订阅ID"`
	RawResponse    shared.JSONMap `json:"rawResponse" gorm:"type:json;comment:支付平台下单响应摘要"`
}

func (RemoteSubscriptionOrder) TableName() string { return "remote_subscription_orders" }

type RemotePaymentNotifyEvent struct {
	global.BaseModel
	EventID     string         `json:"eventId" gorm:"uniqueIndex;size:128;comment:支付平台事件ID，用于幂等"`
	EventKind   string         `json:"eventKind" gorm:"index;size:64;comment:支付平台事件类型"`
	OutTradeNo  string         `json:"outTradeNo" gorm:"index;size:64;comment:商户订单号"`
	PayOrderNo  string         `json:"payOrderNo" gorm:"index;size:64;comment:支付平台订单号"`
	Status      string         `json:"status" gorm:"size:32;comment:处理状态：processed/ignored/failed"`
	Payload     shared.JSONMap `json:"payload" gorm:"type:json;comment:脱敏通知内容"`
	ProcessedAt *time.Time     `json:"processedAt" gorm:"comment:处理时间"`
}

func (RemotePaymentNotifyEvent) TableName() string { return "remote_payment_notify_events" }

type RemoteAccountDeletionRecord struct {
	global.BaseModel
	UserID               uint           `json:"userId" gorm:"index;comment:被注销远程用户ID快照"`
	EmailHash            string         `json:"emailHash" gorm:"index;size:64;comment:邮箱 SHA256，用于脱敏追查"`
	EmailMasked          string         `json:"emailMasked" gorm:"size:191;comment:脱敏邮箱快照"`
	PhoneHash            string         `json:"phoneHash" gorm:"size:64;comment:手机号 SHA256，用于历史账号脱敏追查"`
	PhoneMasked          string         `json:"phoneMasked" gorm:"size:64;comment:脱敏手机号快照"`
	StatusSnapshot       string         `json:"statusSnapshot" gorm:"size:32;comment:注销前账号状态"`
	Reason               string         `json:"reason" gorm:"size:500;comment:用户填写的注销原因"`
	Operator             string         `json:"operator" gorm:"size:32;default:self;comment:注销触发方：self/admin"`
	ConfirmationSnapshot string         `json:"confirmationSnapshot" gorm:"size:191;comment:注销确认文本快照"`
	SubscriptionSnapshot shared.JSONMap `json:"subscriptionSnapshot" gorm:"type:json;comment:注销前订阅权益快照"`
	OrderSnapshot        shared.JSONMap `json:"orderSnapshot" gorm:"type:json;comment:注销前订单快照"`
	DeviceSnapshot       shared.JSONMap `json:"deviceSnapshot" gorm:"type:json;comment:注销前设备快照"`
	UsageSnapshot        shared.JSONMap `json:"usageSnapshot" gorm:"type:json;comment:注销前权益用量快照"`
	DeletedAtSnapshot    time.Time      `json:"deletedAtSnapshot" gorm:"comment:注销完成时间"`
}

func (RemoteAccountDeletionRecord) TableName() string { return "remote_account_deletion_records" }

type RemoteEntitlementUsage struct {
	global.BaseModel
	UserID        uint       `json:"userId" gorm:"index:idx_remote_entitlement_usage_day,priority:1;comment:远程用户ID"`
	ConnectionID  uint       `json:"connectionId" gorm:"index;comment:连接请求ID"`
	UsageDate     string     `json:"usageDate" gorm:"index:idx_remote_entitlement_usage_day,priority:2;size:10;comment:权益用量日期，YYYY-MM-DD"`
	Mode          string     `json:"mode" gorm:"index:idx_remote_entitlement_usage_day,priority:3;size:32;comment:用量模式：cross_network"`
	StartedAt     time.Time  `json:"startedAt" gorm:"comment:计费开始时间"`
	EndedAt       *time.Time `json:"endedAt" gorm:"comment:计费结束时间"`
	BilledSeconds int        `json:"billedSeconds" gorm:"comment:计费秒数"`
	Status        string     `json:"status" gorm:"index;size:32;comment:用量状态：reserved/settled"`
}

func (RemoteEntitlementUsage) TableName() string { return "remote_entitlement_usages" }

type RemoteAuditLog struct {
	global.BaseModel
	UserID       *uint  `json:"userId" gorm:"index;comment:远程用户ID"`
	DeviceID     *uint  `json:"deviceId" gorm:"index;comment:远程设备ID"`
	ConnectionID *uint  `json:"connectionId" gorm:"index;comment:远程连接请求ID，用于关联连接、信令和审计"`
	Action       string `json:"action" gorm:"index;size:64;comment:审计动作"`
	Status       string `json:"status" gorm:"size:32;comment:动作结果：success/failed"`
	Message      string `json:"message" gorm:"size:191;comment:脱敏说明"`
	IPHash       string `json:"ipHash" gorm:"size:64;comment:请求 IP 哈希"`
	UserAgent    string `json:"userAgent" gorm:"size:191;comment:请求 User-Agent"`
}

func (RemoteAuditLog) TableName() string { return "remote_audit_logs" }
