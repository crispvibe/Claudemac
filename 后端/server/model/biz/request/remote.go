package request

type RemoteAuthRequest struct {
	Phone            string `json:"phone"`
	Email            string `json:"email"`
	Password         string `json:"password"`
	VerificationCode string `json:"verificationCode,omitempty"`
}

type RemoteVerificationCodeRequest struct {
	Phone string `json:"phone"`
	Email string `json:"email"`
}

type RemotePasswordResetRequest struct {
	Phone            string `json:"phone"`
	Email            string `json:"email"`
	Password         string `json:"password"`
	VerificationCode string `json:"verificationCode"`
}

type RemoteChangePasswordRequest struct {
	CurrentPassword string `json:"currentPassword"`
	NewPassword     string `json:"newPassword"`
}

type RemoteAccountDeletionRequest struct {
	ConfirmAccount     string `json:"confirmAccount"`
	ConfirmDestroy     string `json:"confirmDestroy"`
	ConfirmWaiveRights string `json:"confirmWaiveRights"`
	Reason             string `json:"reason"`
}

type RemoteRefreshRequest struct {
	RefreshToken string `json:"refreshToken"`
}

type RemoteAppUpdateCheckRequest struct {
	Platform    string `json:"platform" form:"platform"`
	Channel     string `json:"channel" form:"channel"`
	Version     string `json:"version" form:"version"`
	BuildNumber string `json:"buildNumber" form:"buildNumber"`
	PackageArch string `json:"packageArch" form:"packageArch"`
}

type RemoteDeviceRegisterRequest struct {
	DeviceUID       string `json:"deviceUid"`
	DeviceType      string `json:"deviceType"`
	Platform        string `json:"platform"`
	DeviceName      string `json:"deviceName"`
	DevicePublicKey string `json:"devicePublicKey"`
	AppVersion      string `json:"appVersion"`
}

type RemoteDeviceUpdateRequest struct {
	DeviceName     string `json:"deviceName"`
	ApprovalPolicy string `json:"approvalPolicy"`
	RemoteEnabled  *bool  `json:"remoteEnabled"`
	Status         string `json:"status"`
	AppVersion     string `json:"appVersion"`
}

type RemoteDeviceCodeResolveRequest struct {
	DeviceCode   string `json:"deviceCode"`
	FromDeviceID uint   `json:"fromDeviceId"`
}

type RemoteConnectRequest struct {
	FromDeviceID uint `json:"fromDeviceId"`
}

type RemoteLanTokenRequest struct {
	IP             string `json:"ip"`
	Port           int    `json:"port"`
	TransientToken string `json:"transientToken"`
	ExpiresAt      int64  `json:"expiresAt"`
}

type RemoteConnectionDecisionRequest struct {
	Remember bool   `json:"remember"`
	Reason   string `json:"reason"`
}

type RemoteConnectionMetricsRequest struct {
	Transport            string `json:"transport"`
	FirstPacketLatencyMS *int   `json:"firstPacketLatencyMs"`
	Stage                string `json:"stage"`
	Path                 string `json:"path"`
	NetworkType          string `json:"networkType"`
	AppVersion           string `json:"appVersion"`
	RequestID            string `json:"requestId"`
}

type RemoteLegalConsentRequest struct {
	DocumentID uint   `json:"documentId"`
	Platform   string `json:"platform"`
	DeviceID   uint   `json:"deviceId"`
}

type RemoteSubscriptionOrderCreateRequest struct {
	PlanCode    string `json:"planCode"`
	ChannelCode string `json:"channelCode"`
	TradeType   string `json:"tradeType"`
	ReturnURL   string `json:"returnUrl"`
}
