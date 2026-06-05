package response

import (
	"strings"
	"time"

	"heyu/server/model/biz"
)

type RemoteAuthResponse struct {
	AccessToken  string          `json:"accessToken"`
	RefreshToken string          `json:"refreshToken"`
	ExpiresAt    int64           `json:"expiresAt"`
	User         RemoteUserBrief `json:"user"`
}

type RemoteUserBrief struct {
	ID     uint   `json:"id"`
	Phone  string `json:"phone"`
	Email  string `json:"email"`
	Status string `json:"status"`
}

type RemoteDeviceCodeResponse struct {
	DeviceCode string `json:"deviceCode"`
	Hint       string `json:"hint"`
}

type RemoteLanEndpointResponse struct {
	IP         string     `json:"ip"`
	Port       int        `json:"port"`
	LastSeenAt *time.Time `json:"last_seen_at,omitempty"`
}

type RemoteDeviceResponse struct {
	ID             uint                       `json:"id"`
	UserID         uint                       `json:"userId"`
	DeviceUID      string                     `json:"deviceUid"`
	DeviceType     string                     `json:"deviceType"`
	Platform       string                     `json:"platform"`
	DeviceName     string                     `json:"deviceName"`
	DeviceCodeHint string                     `json:"deviceCodeHint,omitempty"`
	ApprovalPolicy string                     `json:"approvalPolicy"`
	RemoteEnabled  bool                       `json:"remoteEnabled"`
	Status         string                     `json:"status"`
	Online         bool                       `json:"online"`
	AppVersion     string                     `json:"appVersion,omitempty"`
	LastSeenAt     *time.Time                 `json:"lastSeenAt,omitempty"`
	LanEndpoint    *RemoteLanEndpointResponse `json:"lan_endpoint,omitempty"`
	TransientToken string                     `json:"transient_token,omitempty"`
}

func RemoteDeviceFromModel(device biz.RemoteDevice, includeLanEndpoint bool, includeTransientToken bool) RemoteDeviceResponse {
	response := RemoteDeviceResponse{
		ID:             device.ID,
		UserID:         device.UserID,
		DeviceUID:      device.DeviceUID,
		DeviceType:     device.DeviceType,
		Platform:       device.Platform,
		DeviceName:     device.DeviceName,
		DeviceCodeHint: device.DeviceCodeHint,
		ApprovalPolicy: device.ApprovalPolicy,
		RemoteEnabled:  device.RemoteEnabled,
		Status:         device.Status,
		AppVersion:     device.AppVersion,
		LastSeenAt:     device.LastSeenAt,
	}
	lanTokenValid := device.LanTokenExpiresAt != nil && device.LanTokenExpiresAt.After(time.Now())
	if includeLanEndpoint && device.LanIP != "" && device.LanPort > 0 && lanTokenValid {
		response.LanEndpoint = &RemoteLanEndpointResponse{IP: device.LanIP, Port: device.LanPort, LastSeenAt: device.LanEndpointLastSeenAt}
		if includeTransientToken && device.LanToken != "" {
			response.TransientToken = device.LanToken
		}
	}
	return response
}

type RemoteVerificationCodeResponse struct {
	VerificationCode string `json:"verificationCode"`
	ExpiresAt        int64  `json:"expiresAt"`
}

type RemoteAccountDeletionResponse struct {
	RecordID  uint      `json:"recordId"`
	DeletedAt time.Time `json:"deletedAt"`
}

type RemoteAppUpdateCheckResponse struct {
	UpdateAvailable   bool       `json:"updateAvailable"`
	LatestVersion     string     `json:"latestVersion"`
	LatestBuildNumber string     `json:"latestBuildNumber"`
	PackageArch       string     `json:"packageArch"`
	MinimumVersion    string     `json:"minimumVersion"`
	ReleaseNotes      string     `json:"releaseNotes"`
	UpdateType        string     `json:"updateType"`
	DownloadURL       string     `json:"downloadUrl"`
	AppStoreURL       string     `json:"appStoreUrl"`
	PackageSHA256     string     `json:"packageSha256"`
	PackageFileSize   int64      `json:"packageFileSize"`
	ForceUpdate       bool       `json:"forceUpdate"`
	ReleasedAt        *time.Time `json:"releasedAt,omitempty"`
}

type RemoteDeviceResolveResponse struct {
	DeviceID        uint   `json:"deviceId"`
	DeviceName      string `json:"deviceName"`
	Platform        string `json:"platform"`
	ApprovalPolicy  string `json:"approvalPolicy"`
	RequiresConfirm bool   `json:"requiresConfirm"`
}

type RemoteConnectionResponse struct {
	ID                   uint                       `json:"id"`
	ConnectionID         uint                       `json:"connectionId"`
	FromUserID           uint                       `json:"fromUserId"`
	FromDeviceID         *uint                      `json:"fromDeviceId"`
	ToUserID             uint                       `json:"toUserId"`
	ToDeviceID           uint                       `json:"toDeviceId"`
	GrantID              *uint                      `json:"grantId"`
	Status               string                     `json:"status"`
	Reason               string                     `json:"reason"`
	CompletedAt          *time.Time                 `json:"completedAt"`
	Transport            string                     `json:"transport,omitempty"`
	FirstPacketLatencyMS *int                       `json:"firstPacketLatencyMs,omitempty"`
	FirstPacketAt        *time.Time                 `json:"firstPacketAt,omitempty"`
	Endpoint             *RemoteLanEndpointResponse `json:"endpoint,omitempty"`
	TransientToken       string                     `json:"transient_token,omitempty"`
}

func RemoteConnectionFromModel(conn biz.RemoteConnectionAttempt) RemoteConnectionResponse {
	return RemoteConnectionResponse{
		ID:                   conn.ID,
		ConnectionID:         conn.ID,
		FromUserID:           conn.FromUserID,
		FromDeviceID:         conn.FromDeviceID,
		ToUserID:             conn.ToUserID,
		ToDeviceID:           conn.ToDeviceID,
		GrantID:              conn.GrantID,
		Status:               conn.Status,
		Reason:               conn.Reason,
		CompletedAt:          conn.CompletedAt,
		Transport:            conn.Transport,
		FirstPacketLatencyMS: conn.FirstPacketLatencyMS,
		FirstPacketAt:        conn.FirstPacketAt,
	}
}

type RemoteSubscriptionResponse struct {
	PlanCode            string     `json:"planCode"`
	Status              string     `json:"status"`
	ExpiresAt           *time.Time `json:"expiresAt"`
	TrialSecondsAllowed int        `json:"trialSecondsAllowed"`
	TrialSecondsUsed    int        `json:"trialSecondsUsed"`
	TrialSecondsLeft    int        `json:"trialSecondsLeft"`
	RenewURL            string     `json:"renewUrl"`
}

type RemoteSubscriptionPlanResponse struct {
	Code           string `json:"code"`
	Name           string `json:"name"`
	Description    string `json:"description"`
	DurationMonths int    `json:"durationMonths"`
	PriceFen       int64  `json:"priceFen"`
	Currency       string `json:"currency"`
}

type RemoteSubscriptionOrderResponse struct {
	ID           uint           `json:"id"`
	OutTradeNo   string         `json:"outTradeNo"`
	PayOrderNo   string         `json:"payOrderNo"`
	Status       string         `json:"status"`
	AmountFen    int64          `json:"amountFen"`
	Currency     string         `json:"currency"`
	PlanCode     string         `json:"planCode"`
	PlanName     string         `json:"planName"`
	InvokeParams map[string]any `json:"invokeParams,omitempty"`
	PayURL       string         `json:"payUrl,omitempty"`
}

type RemoteICEServerResponse struct {
	ICEServers []RemoteICEServer `json:"iceServers"`
}

type RemoteICEServer struct {
	URLs       []string `json:"urls"`
	Username   string   `json:"username,omitempty"`
	Credential string   `json:"credential,omitempty"`
	Realm      string   `json:"realm,omitempty"`
}

func RemoteUserFromModel(user biz.RemoteUser) RemoteUserBrief {
	phone := user.Phone
	if strings.HasPrefix(phone, "email:") {
		phone = ""
	}
	return RemoteUserBrief{ID: user.ID, Phone: phone, Email: user.Email, Status: user.Status}
}
