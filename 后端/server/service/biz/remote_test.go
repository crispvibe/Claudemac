package biz

import (
	"bufio"
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/glebarez/sqlite"
	"github.com/stretchr/testify/require"
	"gorm.io/gorm"
	"heyu/server/global"
	modelBiz "heyu/server/model/biz"
	bizReq "heyu/server/model/biz/request"
	bizRes "heyu/server/model/biz/response"
)

func setupRemoteServiceTest(t *testing.T) {
	t.Helper()
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	require.NoError(t, err)
	require.NoError(t, db.AutoMigrate(
		&modelBiz.RemoteUser{},
		&modelBiz.RemoteAuthCode{},
		&modelBiz.RemoteUserToken{},
		&modelBiz.RemoteDevice{},
		&modelBiz.RemoteDeviceCodeAttempt{},
		&modelBiz.RemoteDeviceGrant{},
		&modelBiz.RemoteConnectionAttempt{},
		&modelBiz.RemoteLegalDocument{},
		&modelBiz.RemoteLegalConsent{},
		&modelBiz.RemoteSubscription{},
		&modelBiz.RemoteSubscriptionPlan{},
		&modelBiz.RemoteSubscriptionOrder{},
		&modelBiz.RemotePaymentNotifyEvent{},
		&modelBiz.RemoteAccountDeletionRecord{},
		&modelBiz.RemoteEntitlementUsage{},
		&modelBiz.RemoteAuditLog{},
	))
	global.AppDB = db
	global.AppConfig.Remote.TrialMinutesPerDay = 10
	global.AppConfig.Remote.StunURLs = []string{"stun:8.156.64.76:3478"}
	global.AppConfig.Remote.TurnURLs = nil
	global.AppConfig.Remote.TurnSecret = ""
	global.AppConfig.Remote.TurnRealm = ""
	global.AppConfig.Remote.TurnCredentialTTL = 600
}

func captureRemoteAuthCodeEmails(t *testing.T) map[string]string {
	t.Helper()
	sent := map[string]string{}
	previous := remoteSendAuthCodeEmail
	remoteSendAuthCodeEmail = func(to, purpose, code string, _ time.Time) error {
		sent[strings.ToLower(to)+":"+purpose] = code
		return nil
	}
	t.Cleanup(func() {
		remoteSendAuthCodeEmail = previous
	})
	return sent
}

func registerRemoteTestUser(t *testing.T, svc *RemoteService, email, password string) bizRes.RemoteAuthResponse {
	t.Helper()
	sent := captureRemoteAuthCodeEmails(t)
	_, err := svc.RequestRegisterCode(bizReq.RemoteVerificationCodeRequest{Email: email})
	require.NoError(t, err)
	code := sent[strings.ToLower(email)+":"+remoteAuthPurposeRegister]
	require.NotEmpty(t, code)
	session, err := svc.Register(bizReq.RemoteAuthRequest{Email: email, Password: password, VerificationCode: code})
	require.NoError(t, err)
	return session
}

func TestConnectRequiresFromDeviceID(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}
	target := modelBiz.RemoteDevice{UserID: 2, DeviceUID: "mac-1", DeviceType: remoteDeviceTypeDesktop, Platform: "macos", DeviceName: "Mac", DevicePublicKey: "pk", ApprovalPolicy: remoteApprovalAlwaysAsk, RemoteEnabled: true, Status: remoteStatusActive}
	require.NoError(t, global.AppDB.Create(&target).Error)

	_, err := svc.Connect(1, target.ID, bizReq.RemoteConnectRequest{}, "192.168.1.50")
	require.Error(t, err)
	require.True(t, strings.Contains(err.Error(), "发起设备"))

	var count int64
	require.NoError(t, global.AppDB.Model(&modelBiz.RemoteConnectionAttempt{}).Count(&count).Error)
	require.Equal(t, int64(0), count)
}

func TestDecideConnectionAcceptedSameNetworkStillUsesRemoteTransport(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}
	now := time.Now()
	expires := now.Add(10 * time.Minute)
	fromDevice := modelBiz.RemoteDevice{UserID: 1, DeviceUID: "ios-1", DeviceType: "ios", Platform: "ios", DeviceName: "iPhone", DevicePublicKey: "pk", RemoteEnabled: true, Status: remoteStatusActive}
	target := modelBiz.RemoteDevice{UserID: 2, DeviceUID: "mac-1", DeviceType: remoteDeviceTypeDesktop, Platform: "macos", DeviceName: "Mac", DevicePublicKey: "pk", ApprovalPolicy: remoteApprovalAlwaysAsk, RemoteEnabled: true, Status: remoteStatusActive, LanIP: "192.168.1.20", LanPort: 18765, LanToken: "token-1", LanTokenExpiresAt: &expires, LanEndpointLastSeenAt: &now, LanPublisherIPHash: hashString("192.168.1.2")}
	require.NoError(t, global.AppDB.Create(&fromDevice).Error)
	require.NoError(t, global.AppDB.Create(&target).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteSubscription{UserID: 1, PlanCode: remoteSubscriptionTrial, Status: remoteSubscriptionTrial}).Error)
	conn := modelBiz.RemoteConnectionAttempt{FromUserID: 1, FromDeviceID: &fromDevice.ID, ToUserID: 2, ToDeviceID: target.ID, Status: remoteConnectionPending, Reason: "waiting_for_approval"}
	require.NoError(t, global.AppDB.Create(&conn).Error)
	SharedRemoteSignalingService.connections.Store(target.ID, &remoteSignalingConn{userID: target.UserID, deviceID: target.ID, closed: make(chan struct{})})
	t.Cleanup(func() { SharedRemoteSignalingService.connections.Delete(target.ID) })

	res, err := svc.DecideConnection(2, conn.ID, true, bizReq.RemoteConnectionDecisionRequest{}, "192.168.1.2")
	require.NoError(t, err)
	require.Equal(t, remoteConnectionAccepted, res.Status)
	require.Equal(t, remoteTunnelTransport, res.Transport)
	require.Equal(t, remoteReasonRemoteRequired, res.Reason)
	require.Nil(t, res.Endpoint)
	require.Empty(t, res.TransientToken)
}

func TestDecideConnectionAcrossDifferentClientIPUsesTunnelWithoutEntitlement(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}
	now := time.Now()
	expires := now.Add(10 * time.Minute)
	fromDevice := modelBiz.RemoteDevice{UserID: 1, DeviceUID: "ios-1", DeviceType: "ios", Platform: "ios", DeviceName: "iPhone", DevicePublicKey: "pk", RemoteEnabled: true, Status: remoteStatusActive}
	target := modelBiz.RemoteDevice{UserID: 1, DeviceUID: "mac-1", DeviceType: remoteDeviceTypeDesktop, Platform: "macos", DeviceName: "Mac", DevicePublicKey: "pk", ApprovalPolicy: remoteApprovalAlwaysAsk, RemoteEnabled: true, Status: remoteStatusActive, LanIP: "192.168.1.20", LanPort: 18765, LanToken: "token-1", LanTokenExpiresAt: &expires, LanEndpointLastSeenAt: &now, LanPublisherIPHash: hashString("198.51.100.10")}
	require.NoError(t, global.AppDB.Create(&fromDevice).Error)
	require.NoError(t, global.AppDB.Create(&target).Error)
	SharedRemoteSignalingService.connections.Store(target.ID, &remoteSignalingConn{userID: target.UserID, deviceID: target.ID, closed: make(chan struct{})})
	t.Cleanup(func() { SharedRemoteSignalingService.connections.Delete(target.ID) })

	res, err := svc.Connect(1, target.ID, bizReq.RemoteConnectRequest{FromDeviceID: fromDevice.ID}, "203.0.113.10")
	require.NoError(t, err)
	require.Equal(t, remoteConnectionAccepted, res.Status)
	require.Equal(t, remoteTunnelTransport, res.Transport)
	require.Equal(t, remoteReasonRemoteRequired, res.Reason)
	require.Nil(t, res.Endpoint)
	require.Empty(t, res.TransientToken)
}

func TestDecideConnectionAcceptedTunnelDoesNotReserveTrialUsage(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}
	fromDevice := modelBiz.RemoteDevice{UserID: 1, DeviceUID: "ios-1", DeviceType: "ios", Platform: "ios", DeviceName: "iPhone", DevicePublicKey: "pk", RemoteEnabled: true, Status: remoteStatusActive}
	target := modelBiz.RemoteDevice{UserID: 2, DeviceUID: "mac-1", DeviceType: remoteDeviceTypeDesktop, Platform: "macos", DeviceName: "Mac", DevicePublicKey: "pk", ApprovalPolicy: remoteApprovalAlwaysAsk, RemoteEnabled: true, Status: remoteStatusActive}
	require.NoError(t, global.AppDB.Create(&fromDevice).Error)
	require.NoError(t, global.AppDB.Create(&target).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteSubscription{UserID: 1, PlanCode: remoteSubscriptionTrial, Status: remoteSubscriptionTrial}).Error)
	conn := modelBiz.RemoteConnectionAttempt{FromUserID: 1, FromDeviceID: &fromDevice.ID, ToUserID: 2, ToDeviceID: target.ID, Status: remoteConnectionPending, Reason: "waiting_for_approval"}
	require.NoError(t, global.AppDB.Create(&conn).Error)
	SharedRemoteSignalingService.connections.Store(target.ID, &remoteSignalingConn{userID: target.UserID, deviceID: target.ID, closed: make(chan struct{})})
	t.Cleanup(func() { SharedRemoteSignalingService.connections.Delete(target.ID) })

	res, err := svc.DecideConnection(2, conn.ID, true, bizReq.RemoteConnectionDecisionRequest{}, "203.0.113.10")
	require.NoError(t, err)
	require.Equal(t, remoteConnectionAccepted, res.Status)
	require.Equal(t, remoteReasonRemoteRequired, res.Reason)
	require.Equal(t, remoteTunnelTransport, res.Transport)
	require.Nil(t, res.Endpoint)

	var usageCount int64
	require.NoError(t, global.AppDB.Model(&modelBiz.RemoteEntitlementUsage{}).Where("connection_id = ?", conn.ID).Count(&usageCount).Error)
	require.Equal(t, int64(0), usageCount)
}

func TestDecideConnectionAcceptedTunnelIgnoresExhaustedTrial(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}
	fromDevice := modelBiz.RemoteDevice{UserID: 1, DeviceUID: "ios-1", DeviceType: "ios", Platform: "ios", DeviceName: "iPhone", DevicePublicKey: "pk", RemoteEnabled: true, Status: remoteStatusActive}
	target := modelBiz.RemoteDevice{UserID: 2, DeviceUID: "mac-1", DeviceType: remoteDeviceTypeDesktop, Platform: "macos", DeviceName: "Mac", DevicePublicKey: "pk", ApprovalPolicy: remoteApprovalAlwaysAsk, RemoteEnabled: true, Status: remoteStatusActive}
	require.NoError(t, global.AppDB.Create(&fromDevice).Error)
	require.NoError(t, global.AppDB.Create(&target).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteSubscription{UserID: 1, PlanCode: remoteSubscriptionTrial, Status: remoteSubscriptionTrial}).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteEntitlementUsage{UserID: 1, UsageDate: time.Now().Format("2006-01-02"), Mode: remoteUsageModeCrossNetwork, StartedAt: time.Now(), BilledSeconds: configuredTrialSecondsPerDay(), Status: remoteUsageStatusReserved}).Error)
	conn := modelBiz.RemoteConnectionAttempt{FromUserID: 1, FromDeviceID: &fromDevice.ID, ToUserID: 2, ToDeviceID: target.ID, Status: remoteConnectionPending, Reason: "waiting_for_approval"}
	require.NoError(t, global.AppDB.Create(&conn).Error)
	SharedRemoteSignalingService.connections.Store(target.ID, &remoteSignalingConn{userID: target.UserID, deviceID: target.ID, closed: make(chan struct{})})
	t.Cleanup(func() { SharedRemoteSignalingService.connections.Delete(target.ID) })

	res, err := svc.DecideConnection(2, conn.ID, true, bizReq.RemoteConnectionDecisionRequest{}, "203.0.113.10")
	require.NoError(t, err)
	require.Equal(t, remoteConnectionAccepted, res.Status)
	require.Equal(t, remoteReasonRemoteRequired, res.Reason)
	require.Equal(t, remoteTunnelTransport, res.Transport)
}

func TestDecideConnectionAcceptedCrossNetworkRejectsOfflineTarget(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}
	fromDevice := modelBiz.RemoteDevice{UserID: 1, DeviceUID: "ios-1", DeviceType: "ios", Platform: "ios", DeviceName: "iPhone", DevicePublicKey: "pk", RemoteEnabled: true, Status: remoteStatusActive}
	target := modelBiz.RemoteDevice{UserID: 2, DeviceUID: "mac-1", DeviceType: remoteDeviceTypeDesktop, Platform: "macos", DeviceName: "Mac", DevicePublicKey: "pk", ApprovalPolicy: remoteApprovalAlwaysAsk, RemoteEnabled: true, Status: remoteStatusActive}
	require.NoError(t, global.AppDB.Create(&fromDevice).Error)
	require.NoError(t, global.AppDB.Create(&target).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteSubscription{UserID: 1, PlanCode: remoteSubscriptionTrial, Status: remoteSubscriptionTrial}).Error)
	conn := modelBiz.RemoteConnectionAttempt{FromUserID: 1, FromDeviceID: &fromDevice.ID, ToUserID: 2, ToDeviceID: target.ID, Status: remoteConnectionPending, Reason: "waiting_for_approval"}
	require.NoError(t, global.AppDB.Create(&conn).Error)

	res, err := svc.DecideConnection(2, conn.ID, true, bizReq.RemoteConnectionDecisionRequest{}, "203.0.113.10")
	require.NoError(t, err)
	require.Equal(t, remoteConnectionRejected, res.Status)
	require.Equal(t, remoteReasonDeviceOffline, res.Reason)
	require.Empty(t, res.Transport)
	require.Nil(t, res.Endpoint)

	var usageCount int64
	require.NoError(t, global.AppDB.Model(&modelBiz.RemoteEntitlementUsage{}).Where("connection_id = ?", conn.ID).Count(&usageCount).Error)
	require.Equal(t, int64(0), usageCount)
}

func TestReportConnectionMetricsIgnoresTURNTransport(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}
	conn := modelBiz.RemoteConnectionAttempt{FromUserID: 1, ToUserID: 2, ToDeviceID: 10, Status: remoteConnectionAccepted, Reason: remoteReasonRemoteRequired, Transport: remoteTunnelTransport}
	require.NoError(t, global.AppDB.Create(&conn).Error)

	res, err := svc.ReportConnectionMetrics(1, conn.ID, bizReq.RemoteConnectionMetricsRequest{Transport: "turn"})
	require.NoError(t, err)
	require.Equal(t, remoteTunnelTransport, res.Transport)

	var stored modelBiz.RemoteConnectionAttempt
	require.NoError(t, global.AppDB.First(&stored, conn.ID).Error)
	require.Equal(t, remoteTunnelTransport, stored.Transport)
}

func TestEmailRegisterAndLogin(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}

	registered := registerRemoteTestUser(t, svc, "USER@example.com", "secret123")
	require.Equal(t, "user@example.com", registered.User.Email)
	require.Empty(t, registered.User.Phone)

	var stored modelBiz.RemoteUser
	require.NoError(t, global.AppDB.First(&stored, registered.User.ID).Error)
	require.Equal(t, "user@example.com", stored.Email)
	require.True(t, strings.HasPrefix(stored.Phone, "email:"))

	loggedIn, err := svc.Login(bizReq.RemoteAuthRequest{Email: "user@example.com", Password: "secret123"}, "127.0.0.1", "test")
	require.NoError(t, err)
	require.Equal(t, registered.User.ID, loggedIn.User.ID)
}

func TestRegisterRequiresEmailVerificationCode(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}

	_, err := svc.Register(bizReq.RemoteAuthRequest{Email: "new@example.com", Password: "secret123"})
	require.Error(t, err)
	require.Contains(t, err.Error(), "验证码")
}

func TestPasswordResetUsesEmailedVerificationCode(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}
	registered := registerRemoteTestUser(t, svc, "reset@example.com", "oldpass123")
	sent := captureRemoteAuthCodeEmails(t)

	_, err := svc.RequestPasswordResetCode(bizReq.RemoteVerificationCodeRequest{Email: "reset@example.com"})
	require.NoError(t, err)
	code := sent["reset@example.com:"+remoteAuthPurposePassword]
	require.NotEmpty(t, code)

	_, err = svc.ResetPassword(bizReq.RemotePasswordResetRequest{Email: "reset@example.com", Password: "newpass123", VerificationCode: code})
	require.NoError(t, err)

	_, err = svc.Login(bizReq.RemoteAuthRequest{Email: "reset@example.com", Password: "oldpass123"}, "127.0.0.1", "test")
	require.Error(t, err)
	loggedIn, err := svc.Login(bizReq.RemoteAuthRequest{Email: "reset@example.com", Password: "newpass123"}, "127.0.0.1", "test")
	require.NoError(t, err)
	require.Equal(t, registered.User.ID, loggedIn.User.ID)
}

func TestPhoneOnlyIdentityIsRejected(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}

	_, err := svc.Register(bizReq.RemoteAuthRequest{Phone: "13800138000", Password: "secret123"})
	require.Error(t, err)
	require.Contains(t, err.Error(), "邮箱")

	_, err = svc.Login(bizReq.RemoteAuthRequest{Phone: "13800138000", Password: "secret123"}, "127.0.0.1", "test")
	require.Error(t, err)
	require.Contains(t, err.Error(), "邮箱")
}

func TestDeleteAccountRemovesUserDataAndKeepsSnapshot(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}

	session := registerRemoteTestUser(t, svc, "delete@example.com", "secret123")
	userID := session.User.ID
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteDevice{UserID: userID, DeviceUID: "ios-1", DeviceType: "ios", Platform: "ios", DeviceName: "iPhone", DevicePublicKey: "pk", Status: remoteStatusActive}).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteSubscription{UserID: userID, PlanCode: "year", Status: remoteSubscriptionActive}).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteSubscriptionOrder{UserID: userID, PlanCode: "year", PlanName: "年度套餐", DurationMonths: 12, AmountFen: 19900, Currency: "CNY", Status: remoteOrderStatusPaid, OutTradeNo: "R202605190001"}).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteEntitlementUsage{UserID: userID, UsageDate: "2026-05-19", Mode: "cross_network", StartedAt: time.Now(), Status: "settled"}).Error)

	res, err := svc.DeleteAccount(userID, bizReq.RemoteAccountDeletionRequest{
		ConfirmAccount:     remoteDeleteConfirmAccount,
		ConfirmDestroy:     remoteDeleteConfirmDestroy,
		ConfirmWaiveRights: remoteDeleteConfirmWaive,
		Reason:             "不再使用",
	}, "127.0.0.1", "test")
	require.NoError(t, err)
	require.NotZero(t, res.RecordID)

	var userCount int64
	require.NoError(t, global.AppDB.Model(&modelBiz.RemoteUser{}).Where("id = ?", userID).Count(&userCount).Error)
	require.Equal(t, int64(0), userCount)
	require.NoError(t, global.AppDB.Model(&modelBiz.RemoteSubscriptionOrder{}).Where("user_id = ?", userID).Count(&userCount).Error)
	require.Equal(t, int64(0), userCount)

	var record modelBiz.RemoteAccountDeletionRecord
	require.NoError(t, global.AppDB.First(&record, res.RecordID).Error)
	require.Equal(t, userID, record.UserID)
	require.Equal(t, "d***e@example.com", record.EmailMasked)
	require.EqualValues(t, 1, record.OrderSnapshot["count"])
	require.EqualValues(t, 1, record.SubscriptionSnapshot["count"])
}

func TestSignalingWebSocketAllowsNativeClientWithoutOrigin(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}

	session := registerRemoteTestUser(t, svc, "user@example.com", "secret123")
	device := modelBiz.RemoteDevice{
		UserID:          session.User.ID,
		DeviceUID:       "mac-1",
		DeviceType:      remoteDeviceTypeDesktop,
		Platform:        "macos",
		DeviceName:      "Mac",
		DevicePublicKey: "pk",
		RemoteEnabled:   true,
		Status:          remoteStatusActive,
	}
	require.NoError(t, global.AppDB.Create(&device).Error)

	signaling := &RemoteSignalingService{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		signaling.HandleWebSocket(w, r, r.URL.Query().Get("token"))
	}))
	defer server.Close()

	hostPort := strings.TrimPrefix(server.URL, "http://")
	conn, err := net.Dial("tcp", hostPort)
	require.NoError(t, err)
	defer conn.Close()

	request := fmt.Sprintf(
		"GET /remote/signaling/ws?token=%s HTTP/1.1\r\nHost: %s\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n",
		session.AccessToken,
		hostPort,
	)
	_, err = conn.Write([]byte(request))
	require.NoError(t, err)

	status, err := bufio.NewReader(conn).ReadString('\n')
	require.NoError(t, err)
	require.Contains(t, status, "101")
}

func TestHeyupaySignature(t *testing.T) {
	body := []byte(`{"echo":"hello"}`)
	signature := heyupaySignature("POST", "/openapi/v1/ping", "", "1712345678", "nonce-123456", body, "secret")
	require.Equal(t, signature, heyupaySignature("POST", "/openapi/v1/ping", "", "1712345678", "nonce-123456", body, "secret"))
	require.True(t, verifyHeyupaySignature("POST", "/openapi/v1/ping", "", "1712345678", "nonce-123456", body, "secret", signature))
	require.False(t, verifyHeyupaySignature("POST", "/openapi/v1/ping", "", "1712345678", "nonce-123456", []byte(`{}`), "secret", signature))
}

func TestGetICEServersWithoutTURNConfigReturnsOnlySTUN(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}
	conn := modelBiz.RemoteConnectionAttempt{FromUserID: 1, ToUserID: 2, ToDeviceID: 10, Status: remoteConnectionAccepted, Reason: remoteReasonRemoteRequired, Transport: remoteTunnelTransport}
	require.NoError(t, global.AppDB.Create(&conn).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteSubscription{UserID: 1, PlanCode: "year", Status: remoteSubscriptionActive}).Error)

	res, err := svc.GetICEServers(1, conn.ID)
	require.NoError(t, err)
	require.Len(t, res.ICEServers, 1)
	require.Equal(t, []string{"stun:8.156.64.76:3478"}, res.ICEServers[0].URLs)
	require.Empty(t, res.ICEServers[0].Username)
	require.Empty(t, res.ICEServers[0].Credential)
	requireOnlySTUNURLs(t, res)
}

func TestGetICEServersWithTURNConfigReturnsSTUNAndTURNCredentials(t *testing.T) {
	setupRemoteServiceTest(t)
	global.AppConfig.Remote.TurnURLs = []string{"turn:turn.acode.test:3478?transport=udp"}
	global.AppConfig.Remote.TurnSecret = "turn-secret"
	global.AppConfig.Remote.TurnRealm = "acode.test"
	svc := &RemoteService{}
	conn := modelBiz.RemoteConnectionAttempt{FromUserID: 1, ToUserID: 2, ToDeviceID: 10, Status: remoteConnectionAccepted, Reason: remoteReasonRemoteRequired, Transport: remoteTunnelTransport}
	require.NoError(t, global.AppDB.Create(&conn).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteSubscription{UserID: 1, PlanCode: "year", Status: remoteSubscriptionActive}).Error)

	res, err := svc.GetICEServers(1, conn.ID)
	require.NoError(t, err)
	require.Len(t, res.ICEServers, 2)
	require.Equal(t, []string{"stun:8.156.64.76:3478"}, res.ICEServers[0].URLs)
	require.Empty(t, res.ICEServers[0].Username)
	require.Empty(t, res.ICEServers[0].Credential)
	require.Empty(t, res.ICEServers[0].Realm)
	require.Equal(t, []string{"turn:turn.acode.test:3478?transport=udp"}, res.ICEServers[1].URLs)
	requireTURNCredentials(t, res.ICEServers[1], "turn-secret", "acode.test", 600)
}

func TestGetICEServersTrialWithTURNConfigReturnsRelayCredentials(t *testing.T) {
	setupRemoteServiceTest(t)
	global.AppConfig.Remote.TrialMinutesPerDay = 10
	global.AppConfig.Remote.TurnURLs = []string{"turn:turn.acode.test:3478?transport=udp"}
	global.AppConfig.Remote.TurnSecret = "turn-secret"
	svc := &RemoteService{}
	conn := modelBiz.RemoteConnectionAttempt{FromUserID: 1, ToUserID: 2, ToDeviceID: 10, Status: remoteConnectionAccepted, Reason: remoteReasonRemoteRequired, Transport: remoteTunnelTransport}
	require.NoError(t, global.AppDB.Create(&conn).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteSubscription{UserID: 1, PlanCode: "trial", Status: remoteSubscriptionTrial}).Error)

	res, err := svc.GetICEServers(1, conn.ID)
	require.NoError(t, err)
	require.Len(t, res.ICEServers, 2)
	require.Equal(t, []string{"stun:8.156.64.76:3478"}, res.ICEServers[0].URLs)
	require.Equal(t, []string{"turn:turn.acode.test:3478?transport=udp"}, res.ICEServers[1].URLs)
	requireTURNCredentials(t, res.ICEServers[1], "turn-secret", "", 600)
}

func TestGetICEServersRejectsNonParticipant(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}
	conn := modelBiz.RemoteConnectionAttempt{FromUserID: 1, ToUserID: 2, ToDeviceID: 10, Status: remoteConnectionAccepted, Reason: remoteReasonRemoteRequired, Transport: remoteTunnelTransport}
	require.NoError(t, global.AppDB.Create(&conn).Error)

	_, err := svc.GetICEServers(3, conn.ID)
	require.Error(t, err)
	require.Contains(t, err.Error(), "连接不存在或未授权")
}

func TestGetICEServersRejectsMissingConnection(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}

	_, err := svc.GetICEServers(1, 999)
	require.Error(t, err)
	require.Contains(t, err.Error(), "连接不存在或未授权")
}

func TestGetICEServersRejectsNonAcceptedConnection(t *testing.T) {
	setupRemoteServiceTest(t)
	svc := &RemoteService{}
	for _, status := range []string{remoteConnectionPending, remoteConnectionRejected} {
		t.Run(status, func(t *testing.T) {
			conn := modelBiz.RemoteConnectionAttempt{FromUserID: 1, ToUserID: 2, ToDeviceID: 10, Status: status, Reason: "not_accepted", Transport: remoteTunnelTransport}
			require.NoError(t, global.AppDB.Create(&conn).Error)

			_, err := svc.GetICEServers(1, conn.ID)
			require.Error(t, err)
			require.Contains(t, err.Error(), "连接不存在或未授权")
		})
	}
}

func requireOnlySTUNURLs(t *testing.T, res bizRes.RemoteICEServerResponse) {
	t.Helper()
	for _, server := range res.ICEServers {
		for _, rawURL := range server.URLs {
			url := strings.ToLower(strings.TrimSpace(rawURL))
			require.False(t, strings.HasPrefix(url, "turn:"))
			require.False(t, strings.HasPrefix(url, "turns:"))
		}
	}
}

func TestGetICEServersTURNOnlyConfigIssuesRelayCredentials(t *testing.T) {
	setupRemoteServiceTest(t)
	global.AppConfig.Remote.StunURLs = nil
	global.AppConfig.Remote.TurnURLs = []string{"turn:turn.acode.test:3478?transport=udp"}
	global.AppConfig.Remote.TurnSecret = "turn-secret"
	global.AppConfig.Remote.TurnRealm = "acode.test"
	svc := &RemoteService{}
	conn := modelBiz.RemoteConnectionAttempt{FromUserID: 1, ToUserID: 2, ToDeviceID: 10, Status: remoteConnectionAccepted, Reason: remoteReasonRemoteRequired, Transport: remoteTunnelTransport}
	require.NoError(t, global.AppDB.Create(&conn).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteSubscription{UserID: 1, PlanCode: "year", Status: remoteSubscriptionActive}).Error)

	res, err := svc.GetICEServers(1, conn.ID)
	require.NoError(t, err)
	require.Len(t, res.ICEServers, 1)
	require.Equal(t, []string{"turn:turn.acode.test:3478?transport=udp"}, res.ICEServers[0].URLs)
	requireTURNCredentials(t, res.ICEServers[0], "turn-secret", "acode.test", 600)
}

func requireTURNCredentials(t *testing.T, server bizRes.RemoteICEServer, secret, realm string, ttlSeconds int) {
	t.Helper()
	require.NotEmpty(t, server.Username)
	require.NotEmpty(t, server.Credential)
	require.Equal(t, realm, server.Realm)

	parts := strings.Split(server.Username, ":")
	require.Len(t, parts, 3)
	expiresAt, err := strconv.ParseInt(parts[0], 10, 64)
	require.NoError(t, err)
	now := time.Now().Unix()
	require.Greater(t, expiresAt, now)
	require.LessOrEqual(t, expiresAt, now+int64(ttlSeconds)+5)

	mac := hmac.New(sha1.New, []byte(secret))
	_, _ = mac.Write([]byte(server.Username))
	require.Equal(t, base64.StdEncoding.EncodeToString(mac.Sum(nil)), server.Credential)
}
