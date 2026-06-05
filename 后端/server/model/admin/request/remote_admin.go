package request

import (
	"time"

	sharedReq "heyu/server/model/shared/request"
)

type RemoteUserSearch struct {
	sharedReq.PageInfo
	Phone  string `json:"phone" form:"phone"`
	Email  string `json:"email" form:"email"`
	Status string `json:"status" form:"status"`
}

type RemoteSubscriptionPlanSearch struct {
	sharedReq.PageInfo
	Code   string `json:"code" form:"code"`
	Status string `json:"status" form:"status"`
}

type RemoteDeviceSearch struct {
	sharedReq.PageInfo
	UserID     uint   `json:"userId" form:"userId"`
	DeviceName string `json:"deviceName" form:"deviceName"`
	DeviceType string `json:"deviceType" form:"deviceType"`
	Platform   string `json:"platform" form:"platform"`
	Status     string `json:"status" form:"status"`
}

type RemoteConnectionSearch struct {
	sharedReq.PageInfo
	FromUserID uint   `json:"fromUserId" form:"fromUserId"`
	ToUserID   uint   `json:"toUserId" form:"toUserId"`
	ToDeviceID uint   `json:"toDeviceId" form:"toDeviceId"`
	Status     string `json:"status" form:"status"`
	Transport  string `json:"transport" form:"transport"`
}

type RemoteCodeAttemptSearch struct {
	sharedReq.PageInfo
	TargetDeviceID uint   `json:"targetDeviceId" form:"targetDeviceId"`
	FromUserID     uint   `json:"fromUserId" form:"fromUserId"`
	Status         string `json:"status" form:"status"`
}

type RemoteLegalDocumentSearch struct {
	sharedReq.PageInfo
	Type      string `json:"type" form:"type"`
	Platform  string `json:"platform" form:"platform"`
	Published *bool  `json:"published" form:"published"`
}

type RemoteAppUpdateSearch struct {
	sharedReq.PageInfo
	Platform    string `json:"platform" form:"platform"`
	Channel     string `json:"channel" form:"channel"`
	PackageArch string `json:"packageArch" form:"packageArch"`
	Published   *bool  `json:"published" form:"published"`
}

type RemoteLegalConsentSearch struct {
	sharedReq.PageInfo
	UserID       uint   `json:"userId" form:"userId"`
	DocumentID   uint   `json:"documentId" form:"documentId"`
	DocumentType string `json:"documentType" form:"documentType"`
	Platform     string `json:"platform" form:"platform"`
}

type RemoteSubscriptionSearch struct {
	sharedReq.PageInfo
	UserID   uint   `json:"userId" form:"userId"`
	PlanCode string `json:"planCode" form:"planCode"`
	Status   string `json:"status" form:"status"`
}

type RemoteSubscriptionOrderSearch struct {
	sharedReq.PageInfo
	UserID     uint   `json:"userId" form:"userId"`
	Email      string `json:"email" form:"email"`
	PlanCode   string `json:"planCode" form:"planCode"`
	Status     string `json:"status" form:"status"`
	OutTradeNo string `json:"outTradeNo" form:"outTradeNo"`
	PayOrderNo string `json:"payOrderNo" form:"payOrderNo"`
}

type RemoteAccountDeletionSearch struct {
	sharedReq.PageInfo
	UserID      uint   `json:"userId" form:"userId"`
	EmailMasked string `json:"emailMasked" form:"emailMasked"`
	EmailHash   string `json:"emailHash" form:"emailHash"`
	Operator    string `json:"operator" form:"operator"`
}

type RemoteStatusUpdate struct {
	ID     uint   `json:"id"`
	Status string `json:"status"`
}

type RemoteUserSave struct {
	ID       uint   `json:"id"`
	Phone    string `json:"phone"`
	Email    string `json:"email"`
	Password string `json:"password"`
	Status   string `json:"status"`
}

type RemoteAdminIDRequest struct {
	ID uint `json:"id"`
}

type RemoteDeviceUpdate struct {
	ID             uint   `json:"id"`
	DeviceName     string `json:"deviceName"`
	ApprovalPolicy string `json:"approvalPolicy"`
	RemoteEnabled  *bool  `json:"remoteEnabled"`
	Status         string `json:"status"`
}

type RemoteLegalDocumentSave struct {
	ID            uint       `json:"id"`
	Type          string     `json:"type"`
	Platform      string     `json:"platform"`
	Version       string     `json:"version"`
	Title         string     `json:"title"`
	ContentFormat string     `json:"contentFormat"`
	Content       string     `json:"content"`
	Published     bool       `json:"published"`
	EffectiveAt   *time.Time `json:"effectiveAt"`
}

type RemoteAppFooterGet struct {
	Platform string `json:"platform" form:"platform"`
}

type RemoteAppFooterSave struct {
	ID            uint   `json:"id"`
	Platform      string `json:"platform"`
	CompanyName   string `json:"companyName"`
	CopyrightText string `json:"copyrightText"`
	ICPText       string `json:"icpText"`
	RecordText    string `json:"recordText"`
	SupportURL    string `json:"supportUrl"`
	PrivacyURL    string `json:"privacyUrl"`
	Published     bool   `json:"published"`
}

type RemoteAppUpdateSave struct {
	ID              uint       `json:"id"`
	Platform        string     `json:"platform"`
	Channel         string     `json:"channel"`
	Version         string     `json:"version"`
	BuildNumber     string     `json:"buildNumber"`
	PackageArch     string     `json:"packageArch"`
	MinimumVersion  string     `json:"minimumVersion"`
	ReleaseNotes    string     `json:"releaseNotes"`
	UpdateType      string     `json:"updateType"`
	DownloadURL     string     `json:"downloadUrl"`
	AppStoreURL     string     `json:"appStoreUrl"`
	PackageFileID   *uint      `json:"packageFileId"`
	PackageFileName string     `json:"packageFileName"`
	PackageFileSize int64      `json:"packageFileSize"`
	PackageSHA256   string     `json:"packageSha256"`
	ForceUpdate     bool       `json:"forceUpdate"`
	Published       bool       `json:"published"`
	ReleasedAt      *time.Time `json:"releasedAt"`
}

type RemoteSubscriptionSave struct {
	ID              uint       `json:"id"`
	UserID          uint       `json:"userId"`
	PlanCode        string     `json:"planCode"`
	Status          string     `json:"status"`
	StartedAt       *time.Time `json:"startedAt"`
	ExpiresAt       *time.Time `json:"expiresAt"`
	Provider        string     `json:"provider"`
	ProviderOrderID string     `json:"providerOrderId"`
}

type RemoteSubscriptionPlanSave struct {
	ID             uint   `json:"id"`
	Code           string `json:"code"`
	Name           string `json:"name"`
	Description    string `json:"description"`
	DurationMonths int    `json:"durationMonths"`
	PriceFen       int64  `json:"priceFen"`
	Currency       string `json:"currency"`
	Status         string `json:"status"`
	Sort           int    `json:"sort"`
}
