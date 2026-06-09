package biz

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/glebarez/sqlite"
	"github.com/stretchr/testify/require"
	"gorm.io/gorm"
	"heyu/server/global"
	adminReq "heyu/server/model/admin/request"
	modelBiz "heyu/server/model/biz"
	"heyu/server/model/shared"
	sharedReq "heyu/server/model/shared/request"
	adminService "heyu/server/service/admin"
	"heyu/server/utils"
)

func setupRemoteRouterDeletionExperiment(t *testing.T) {
	t.Helper()
	gin.SetMode(gin.TestMode)
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
	global.AppConfig.JWT.SigningKey = "remote-deletion-test-secret"
	global.AppConfig.JWT.Issuer = "remote-deletion-test"
	global.AppConfig.Remote.TrialMinutesPerDay = 10
}

func TestRemoteAccountDeletionAPIExperimentDeletesUserDataAndKeepsAdminSnapshot(t *testing.T) {
	setupRemoteRouterDeletionExperiment(t)

	user := modelBiz.RemoteUser{Email: "delete-api@example.com", Phone: "email:delete-api", PasswordHash: utils.BcryptHash("secret123"), Status: "active"}
	require.NoError(t, global.AppDB.Create(&user).Error)
	userID := user.ID
	accessToken, _, err := utils.CreateRemoteAccessToken(user.ID, user.Phone, user.Email, user.TokenVersion)
	require.NoError(t, err)
	now := time.Now()

	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteAuthCode{
		Email:     "delete-api@example.com",
		Purpose:   "password_reset",
		CodeHash:  "delete-api-code-hash",
		ExpiresAt: now.Add(10 * time.Minute),
	}).Error)
	device := modelBiz.RemoteDevice{
		UserID:          userID,
		DeviceUID:       "ios-delete-api",
		DeviceType:      "ios",
		Platform:        "ios",
		DeviceName:      "iPhone",
		DevicePublicKey: "pk",
		Status:          "active",
		RemoteEnabled:   true,
	}
	require.NoError(t, global.AppDB.Create(&device).Error)
	targetDevice := modelBiz.RemoteDevice{
		UserID:          userID,
		DeviceUID:       "mac-delete-api",
		DeviceType:      "desktop",
		Platform:        "macos",
		DeviceName:      "Mac",
		DevicePublicKey: "pk",
		Status:          "active",
		RemoteEnabled:   true,
	}
	require.NoError(t, global.AppDB.Create(&targetDevice).Error)
	grant := modelBiz.RemoteDeviceGrant{
		OwnerUserID:     userID,
		TargetDeviceID:  targetDevice.ID,
		GranteeUserID:   userID,
		GranteeDeviceID: &device.ID,
		Scope:           "chat_only",
		GrantType:       "same_account",
		Status:          "active",
	}
	require.NoError(t, global.AppDB.Create(&grant).Error)
	conn := modelBiz.RemoteConnectionAttempt{
		FromUserID:   userID,
		FromDeviceID: &device.ID,
		ToUserID:     userID,
		ToDeviceID:   targetDevice.ID,
		GrantID:      &grant.ID,
		Status:       "accepted",
		Transport:    "lan",
	}
	require.NoError(t, global.AppDB.Create(&conn).Error)
	legalDoc := modelBiz.RemoteLegalDocument{
		Type:          "privacy_policy",
		Platform:      "all",
		Version:       "test",
		Title:         "隐私政策",
		ContentFormat: "markdown",
		Content:       "test",
		Published:     true,
	}
	require.NoError(t, global.AppDB.Create(&legalDoc).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteLegalConsent{
		UserID:          userID,
		DocumentID:      legalDoc.ID,
		DocumentType:    legalDoc.Type,
		DocumentVersion: legalDoc.Version,
		Platform:        "ios",
		DeviceID:        &device.ID,
		ConsentedAt:     now,
	}).Error)
	subscription := modelBiz.RemoteSubscription{
		UserID:          userID,
		PlanCode:        "yearly",
		Status:          "active",
		Provider:        "alipay",
		ProviderOrderID: "pay-order-1",
	}
	require.NoError(t, global.AppDB.Create(&subscription).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteSubscriptionOrder{
		UserID:         userID,
		PlanCode:       "yearly",
		PlanName:       "年度套餐",
		DurationMonths: 12,
		AmountFen:      19900,
		Currency:       "CNY",
		Status:         "paid",
		OutTradeNo:     "R202605190099",
		PayOrderNo:     "PAY202605190099",
		ChannelCode:    "alipay",
		PaidAt:         &now,
		SubscriptionID: &subscription.ID,
		RawResponse:    shared.JSONMap{"result": "ok"},
	}).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemotePaymentNotifyEvent{
		EventID:    "evt-delete-api",
		EventKind:  "payment.paid",
		OutTradeNo: "R202605190099",
		PayOrderNo: "PAY202605190099",
		Status:     "processed",
		Payload:    shared.JSONMap{"status": "paid"},
	}).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteEntitlementUsage{
		UserID:        userID,
		ConnectionID:  conn.ID,
		UsageDate:     "2026-05-19",
		Mode:          "cross_network",
		StartedAt:     now,
		BilledSeconds: 60,
		Status:        "settled",
	}).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteDeviceCodeAttempt{
		TargetDeviceID: &targetDevice.ID,
		FromUserID:     &userID,
		FromDeviceID:   &device.ID,
		CodeHashPrefix: "abcdef12",
		Status:         "success",
	}).Error)
	require.NoError(t, global.AppDB.Create(&modelBiz.RemoteAuditLog{
		UserID:       &userID,
		DeviceID:     &device.ID,
		ConnectionID: &conn.ID,
		Action:       "remote.connect",
		Status:       "success",
		Message:      "connected",
	}).Error)

	router := gin.New()
	(&RemoteRouter{}).InitRemoteRouter(router.Group(""))
	payload := map[string]string{
		"confirmAccount":     "我确认注销账号",
		"confirmDestroy":     "确认销毁",
		"confirmWaiveRights": "确认清理远程连接数据",
		"reason":             "完整注销实验",
	}
	body, err := json.Marshal(payload)
	require.NoError(t, err)
	req := httptest.NewRequest(http.MethodPost, "/remote/account/deletion", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Content-Type", "application/json")
	res := httptest.NewRecorder()
	router.ServeHTTP(res, req)

	require.Equal(t, http.StatusOK, res.Code)
	var envelope struct {
		Code int            `json:"code"`
		Msg  string         `json:"msg"`
		Data map[string]any `json:"data"`
	}
	require.NoError(t, json.Unmarshal(res.Body.Bytes(), &envelope))
	require.Equal(t, 0, envelope.Code)
	require.Equal(t, "账号已注销", envelope.Msg)
	require.NotZero(t, envelope.Data["recordId"])

	assertNoRowsForUser := func(model any, query string, args ...any) {
		t.Helper()
		var count int64
		require.NoError(t, global.AppDB.Model(model).Where(query, args...).Count(&count).Error)
		require.Equal(t, int64(0), count, "%T still has user data", model)
	}
	assertNoRowsForUser(&modelBiz.RemoteUser{}, "id = ?", userID)
	assertNoRowsForUser(&modelBiz.RemoteUserToken{}, "user_id = ?", userID)
	assertNoRowsForUser(&modelBiz.RemoteAuthCode{}, "email = ?", "delete-api@example.com")
	assertNoRowsForUser(&modelBiz.RemoteDevice{}, "user_id = ?", userID)
	assertNoRowsForUser(&modelBiz.RemoteDeviceGrant{}, "owner_user_id = ? OR grantee_user_id = ?", userID, userID)
	assertNoRowsForUser(&modelBiz.RemoteConnectionAttempt{}, "from_user_id = ? OR to_user_id = ?", userID, userID)
	assertNoRowsForUser(&modelBiz.RemoteLegalConsent{}, "user_id = ?", userID)
	assertNoRowsForUser(&modelBiz.RemoteSubscription{}, "user_id = ?", userID)
	assertNoRowsForUser(&modelBiz.RemoteSubscriptionOrder{}, "user_id = ?", userID)
	assertNoRowsForUser(&modelBiz.RemotePaymentNotifyEvent{}, "out_trade_no = ?", "R202605190099")
	assertNoRowsForUser(&modelBiz.RemoteEntitlementUsage{}, "user_id = ?", userID)
	assertNoRowsForUser(&modelBiz.RemoteDeviceCodeAttempt{}, "from_user_id = ? OR target_device_id IN ? OR from_device_id IN ?", userID, []uint{device.ID, targetDevice.ID}, []uint{device.ID, targetDevice.ID})
	assertNoRowsForUser(&modelBiz.RemoteAuditLog{}, "user_id = ? OR device_id IN ? OR connection_id = ?", userID, []uint{device.ID, targetDevice.ID}, conn.ID)

	var records []modelBiz.RemoteAccountDeletionRecord
	require.NoError(t, global.AppDB.Find(&records).Error)
	require.Len(t, records, 1)
	record := records[0]
	require.Equal(t, userID, record.UserID)
	require.Equal(t, "d***i@example.com", record.EmailMasked)
	require.Equal(t, "self", record.Operator)
	require.Equal(t, "完整注销实验", record.Reason)
	require.EqualValues(t, 1, record.SubscriptionSnapshot["count"])
	require.EqualValues(t, 1, record.OrderSnapshot["count"])
	require.EqualValues(t, 2, record.DeviceSnapshot["count"])
	require.EqualValues(t, 1, record.UsageSnapshot["count"])

	adminList, total, err := (&adminService.RemoteAdminService{}).ListAccountDeletions(adminReq.RemoteAccountDeletionSearch{
		PageInfo:    sharedReq.PageInfo{Page: 1, PageSize: 10},
		EmailMasked: record.EmailMasked,
		Operator:    "self",
	})
	require.NoError(t, err)
	require.Equal(t, int64(1), total)
	adminRecords, ok := adminList.([]modelBiz.RemoteAccountDeletionRecord)
	require.True(t, ok)
	require.Len(t, adminRecords, 1)
	require.Equal(t, record.ID, adminRecords[0].ID)
}
