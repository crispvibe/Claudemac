package admin

import (
	"strings"
	"testing"

	"github.com/glebarez/sqlite"
	"github.com/stretchr/testify/require"
	"gorm.io/gorm"
	"heyu/server/global"
	adminReq "heyu/server/model/admin/request"
	modelBiz "heyu/server/model/biz"
	bizReq "heyu/server/model/biz/request"
	bizService "heyu/server/service/biz"
	"heyu/server/utils"
)

func setupRemoteAdminServiceTest(t *testing.T) {
	t.Helper()
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	require.NoError(t, err)
	require.NoError(t, db.AutoMigrate(
		&modelBiz.RemoteUser{},
		&modelBiz.RemoteUserToken{},
		&modelBiz.RemoteAuthCode{},
		&modelBiz.RemoteDevice{},
		&modelBiz.RemoteDeviceGrant{},
		&modelBiz.RemoteConnectionAttempt{},
		&modelBiz.RemoteDeviceCodeAttempt{},
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
	global.AppConfig.JWT.SigningKey = "test-signing-key"
}

func TestSaveUserPasswordCanLoginWithNewPassword(t *testing.T) {
	setupRemoteAdminServiceTest(t)

	adminSvc := &RemoteAdminService{}
	remoteSvc := &bizService.RemoteService{}

	user, err := adminSvc.SaveUser(adminReq.RemoteUserSave{
		Email:    "user@example.com",
		Password: "oldpass123",
		Status:   "active",
	})
	require.NoError(t, err)
	require.True(t, strings.HasPrefix(user.PasswordHash, "$2"))
	require.NotEqual(t, "oldpass123", user.PasswordHash)
	require.True(t, utils.BcryptCheck("oldpass123", user.PasswordHash))

	_, err = remoteSvc.Login(bizReq.RemoteAuthRequest{Email: "user@example.com", Password: "oldpass123"}, "127.0.0.1", "test")
	require.NoError(t, err)

	updated, err := adminSvc.SaveUser(adminReq.RemoteUserSave{
		ID:       user.ID,
		Email:    "user@example.com",
		Password: "123456",
		Status:   "active",
	})
	require.NoError(t, err)
	require.True(t, strings.HasPrefix(updated.PasswordHash, "$2"))
	require.NotEqual(t, "123456", updated.PasswordHash)
	require.True(t, utils.BcryptCheck("123456", updated.PasswordHash))

	_, err = remoteSvc.Login(bizReq.RemoteAuthRequest{Email: "user@example.com", Password: "oldpass123"}, "127.0.0.1", "test")
	require.Error(t, err)

	_, err = remoteSvc.Login(bizReq.RemoteAuthRequest{Email: "user@example.com", Password: "123456"}, "127.0.0.1", "test")
	require.NoError(t, err)
}

func TestDeleteUserRemovesRemoteDataAndKeepsAdminDeletionRecord(t *testing.T) {
	setupRemoteAdminServiceTest(t)

	adminSvc := &RemoteAdminService{}
	user, err := adminSvc.SaveUser(adminReq.RemoteUserSave{
		Email:    "delete-user@example.com",
		Password: "oldpass123",
		Status:   "active",
	})
	require.NoError(t, err)
	token := modelBiz.RemoteUserToken{UserID: user.ID, TokenHash: "hash-delete-user", TokenType: "refresh"}
	device := modelBiz.RemoteDevice{UserID: user.ID, DeviceUID: "delete-device-uid", DeviceType: "desktop", Platform: "macos", DeviceName: "Mac", DevicePublicKey: "pub", Status: "active", RemoteEnabled: true}
	subscription := modelBiz.RemoteSubscription{UserID: user.ID, PlanCode: "free", Status: "free"}
	require.NoError(t, global.AppDB.Create(&token).Error)
	require.NoError(t, global.AppDB.Create(&device).Error)
	require.NoError(t, global.AppDB.Create(&subscription).Error)

	require.NoError(t, adminSvc.DeleteUser(adminReq.RemoteAdminIDRequest{ID: user.ID}))

	var userCount int64
	require.NoError(t, global.AppDB.Unscoped().Model(&modelBiz.RemoteUser{}).Where("id = ?", user.ID).Count(&userCount).Error)
	require.Zero(t, userCount)
	var tokenCount int64
	require.NoError(t, global.AppDB.Unscoped().Model(&modelBiz.RemoteUserToken{}).Where("user_id = ?", user.ID).Count(&tokenCount).Error)
	require.Zero(t, tokenCount)
	var deviceCount int64
	require.NoError(t, global.AppDB.Unscoped().Model(&modelBiz.RemoteDevice{}).Where("user_id = ?", user.ID).Count(&deviceCount).Error)
	require.Zero(t, deviceCount)

	var record modelBiz.RemoteAccountDeletionRecord
	require.NoError(t, global.AppDB.Where("user_id = ?", user.ID).First(&record).Error)
	require.Equal(t, "admin", record.Operator)
	require.Equal(t, "后台删除远程用户", record.Reason)
	require.Equal(t, "后台确认删除远程用户", record.ConfirmationSnapshot)
}

func TestDeleteDeviceRemovesRelatedRecords(t *testing.T) {
	setupRemoteAdminServiceTest(t)

	user := modelBiz.RemoteUser{Email: "device-owner@example.com", Phone: "email:device-owner", PasswordHash: "hash", Status: "active"}
	require.NoError(t, global.AppDB.Create(&user).Error)
	device := modelBiz.RemoteDevice{UserID: user.ID, DeviceUID: "device-delete-uid", DeviceType: "desktop", Platform: "macos", DeviceName: "Mac", DevicePublicKey: "pub", Status: "active", RemoteEnabled: true}
	require.NoError(t, global.AppDB.Create(&device).Error)
	fromDeviceID := device.ID
	grant := modelBiz.RemoteDeviceGrant{OwnerUserID: user.ID, TargetDeviceID: device.ID, GranteeUserID: user.ID, GranteeDeviceID: &fromDeviceID, Scope: "chat_only", GrantType: "same_account", Status: "active"}
	connection := modelBiz.RemoteConnectionAttempt{FromUserID: user.ID, FromDeviceID: &fromDeviceID, ToUserID: user.ID, ToDeviceID: device.ID, Status: "accepted"}
	codeAttempt := modelBiz.RemoteDeviceCodeAttempt{TargetDeviceID: &device.ID, FromUserID: &user.ID, FromDeviceID: &fromDeviceID, CodeHashPrefix: "abcdef", Status: "success"}
	require.NoError(t, global.AppDB.Create(&grant).Error)
	require.NoError(t, global.AppDB.Create(&connection).Error)
	require.NoError(t, global.AppDB.Create(&codeAttempt).Error)

	require.NoError(t, (&RemoteAdminService{}).DeleteDevice(adminReq.RemoteAdminIDRequest{ID: device.ID}))

	var deviceCount int64
	require.NoError(t, global.AppDB.Unscoped().Model(&modelBiz.RemoteDevice{}).Where("id = ?", device.ID).Count(&deviceCount).Error)
	require.Zero(t, deviceCount)
	var grantCount int64
	require.NoError(t, global.AppDB.Unscoped().Model(&modelBiz.RemoteDeviceGrant{}).Where("id = ?", grant.ID).Count(&grantCount).Error)
	require.Zero(t, grantCount)
	var connectionCount int64
	require.NoError(t, global.AppDB.Unscoped().Model(&modelBiz.RemoteConnectionAttempt{}).Where("id = ?", connection.ID).Count(&connectionCount).Error)
	require.Zero(t, connectionCount)
	var codeAttemptCount int64
	require.NoError(t, global.AppDB.Unscoped().Model(&modelBiz.RemoteDeviceCodeAttempt{}).Where("id = ?", codeAttempt.ID).Count(&codeAttemptCount).Error)
	require.Zero(t, codeAttemptCount)
}
