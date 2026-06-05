package initialize

import (
	"crypto/rand"
	"math/big"
	"os"
	"strings"

	"github.com/google/uuid"
	"go.uber.org/zap"
	"gorm.io/gorm"
	"heyu/server/utils"

	"heyu/server/global"
	"heyu/server/model/admin"
)

func bootstrapLocalBaselineData(db *gorm.DB) {
	if global.AppConfig.System.Env != "local" {
		return
	}

	var menuCount int64
	if err := db.Model(&admin.NavigationEntry{}).Count(&menuCount).Error; err != nil {
		global.AppLog.Error("inspect local baseline menus failed", zap.Error(err))
		return
	}
	if menuCount > 0 {
		return
	}

	adminUUID := uuid.New()
	bootstrapPassword, passwordFromEnv, err := resolveBootstrapAdminPassword()
	if err != nil {
		global.AppLog.Error("generate local baseline admin password failed", zap.Error(err))
		return
	}

	adminRoleID, memberRoleID, testRoleID, err := generateLocalRoleIDs()
	if err != nil {
		global.AppLog.Error("generate local baseline role ids failed", zap.Error(err))
		return
	}

	users := []admin.Account{
		{
			BaseModel:     global.BaseModel{ID: 1},
			UUID:          adminUUID,
			Username:      "admin",
			Password:      utils.BcryptHash(bootstrapPassword),
			NickName:      "Anna",
			PrimaryRoleID: adminRoleID,
			Enable:        1,
		},
	}
	roles := []admin.Role{
		{RoleID: adminRoleID, RoleName: "管理员", ParentId: uintPtr(0), DefaultEntry: "dashboard"},
		{RoleID: memberRoleID, RoleName: "普通用户子角色", ParentId: uintPtr(adminRoleID), DefaultEntry: "dashboard"},
		{RoleID: testRoleID, RoleName: "测试角色", ParentId: uintPtr(0), DefaultEntry: "dashboard"},
	}
	remoteParentComponent := admin.BuildComponentIdentifierFromLegacyPath("view/routerHolder.vue")
	remotePageComponent := admin.BuildComponentIdentifierFromLegacyPath("view/console/remote/index.vue")
	menus := []admin.NavigationEntry{
		{BaseModel: global.BaseModel{ID: 1}, Path: "dashboard", Name: "dashboard", Component: "cmp_d0ec3ba8ed08a523", Sort: 1, Meta: admin.Meta{Title: "仪表盘", Icon: "monitor"}},
		{BaseModel: global.BaseModel{ID: 2}, ParentId: 1, Path: "home", Name: "home", Component: "cmp_9f3cfc435d466f44", Sort: 1, Meta: admin.Meta{Title: "工作台", Icon: "house"}},
		{BaseModel: global.BaseModel{ID: 3}, Path: "system", Name: "systemSettings", Component: "layoutParentView", Sort: 2, Meta: admin.Meta{Title: "系统管理", Icon: "setting"}},
		{BaseModel: global.BaseModel{ID: 6}, ParentId: 3, Path: "roles", Name: "roles", Component: "cmp_15497c338c2a6605", Sort: 1, Meta: admin.Meta{Title: "权限分组", Icon: "avatar"}},
		{BaseModel: global.BaseModel{ID: 7}, ParentId: 3, Path: "navigation", Name: "navigation", Component: "cmp_34c73f707f2e2655", Sort: 2, Meta: admin.Meta{Title: "导航配置", Icon: "tickets", KeepAlive: true}},
		{BaseModel: global.BaseModel{ID: 8}, ParentId: 3, Path: "api-catalog", Name: "apiCatalog", Component: "cmp_3d5aecbc794c2c8c", Sort: 3, Meta: admin.Meta{Title: "接口配置", Icon: "platform", KeepAlive: true}},
		{BaseModel: global.BaseModel{ID: 9}, ParentId: 3, Path: "accounts", Name: "accounts", Component: "cmp_7e1209afc44cc24c", Sort: 4, Meta: admin.Meta{Title: "账号管理", Icon: "coordinate"}},
		{BaseModel: global.BaseModel{ID: 10}, ParentId: 3, Path: "operation-logs", Name: "operationLogs", Component: "cmp_12daf0025c276632", Sort: 5, Meta: admin.Meta{Title: "操作日志", Icon: "pie-chart"}},
		{BaseModel: global.BaseModel{ID: 11}, ParentId: 0, Path: "remote", Name: "remoteAdmin", Component: remoteParentComponent, Sort: 6, Meta: admin.Meta{Title: "远程管理", Icon: "connection"}},
		{BaseModel: global.BaseModel{ID: 12}, ParentId: 11, Path: "users", Name: "remoteUsers", Component: remotePageComponent, Sort: 1, Meta: admin.Meta{Title: "用户列表", Icon: "user"}},
		{BaseModel: global.BaseModel{ID: 13}, ParentId: 11, Path: "devices", Name: "remoteDevices", Component: remotePageComponent, Sort: 2, Meta: admin.Meta{Title: "设备管理", Icon: "monitor"}},
		{BaseModel: global.BaseModel{ID: 14}, ParentId: 11, Path: "connections", Name: "remoteConnections", Component: remotePageComponent, Sort: 3, Meta: admin.Meta{Title: "连接日志", Icon: "connection"}},
		{BaseModel: global.BaseModel{ID: 15}, ParentId: 11, Path: "code-attempts", Name: "remoteCodeAttempts", Component: remotePageComponent, Sort: 4, Meta: admin.Meta{Title: "设备码日志", Icon: "key"}},
		{BaseModel: global.BaseModel{ID: 16}, ParentId: 11, Path: "account-deletions", Name: "remoteAccountDeletions", Component: remotePageComponent, Sort: 5, Meta: admin.Meta{Title: "注销记录", Icon: "delete"}},
		{BaseModel: global.BaseModel{ID: 17}, ParentId: 11, Path: "legal-documents", Name: "remoteLegalDocuments", Component: remotePageComponent, Sort: 6, Meta: admin.Meta{Title: "协议文档", Icon: "document"}},
		{BaseModel: global.BaseModel{ID: 19}, ParentId: 11, Path: "app-footer", Name: "remoteAppFooter", Component: remotePageComponent, Sort: 7, Meta: admin.Meta{Title: "页脚配置", Icon: "tickets"}},
		{BaseModel: global.BaseModel{ID: 20}, ParentId: 11, Path: "app-updates", Name: "remoteAppUpdates", Component: remotePageComponent, Sort: 8, Meta: admin.Meta{Title: "在线更新", Icon: "upload"}},
		{BaseModel: global.BaseModel{ID: 18}, ParentId: 11, Path: "legal-consents", Name: "remoteLegalConsents", Component: remotePageComponent, Sort: 9, Meta: admin.Meta{Title: "协议同意记录", Icon: "finished"}},
	}
	roleMenuBindings := []admin.RoleNavigationBinding{
		{MenuId: 1, RoleID: adminRoleID},
		{MenuId: 3, RoleID: adminRoleID},
		{MenuId: 4, RoleID: adminRoleID},
		{MenuId: 6, RoleID: adminRoleID},
		{MenuId: 7, RoleID: adminRoleID},
		{MenuId: 8, RoleID: adminRoleID},
		{MenuId: 9, RoleID: adminRoleID},
		{MenuId: 10, RoleID: adminRoleID},
		{MenuId: 11, RoleID: adminRoleID},
		{MenuId: 12, RoleID: adminRoleID},
		{MenuId: 13, RoleID: adminRoleID},
		{MenuId: 14, RoleID: adminRoleID},
		{MenuId: 15, RoleID: adminRoleID},
		{MenuId: 16, RoleID: adminRoleID},
		{MenuId: 17, RoleID: adminRoleID},
		{MenuId: 18, RoleID: adminRoleID},
		{MenuId: 19, RoleID: adminRoleID},
		{MenuId: 20, RoleID: adminRoleID},
		{MenuId: 1, RoleID: memberRoleID},
		{MenuId: 3, RoleID: memberRoleID},
		{MenuId: 4, RoleID: memberRoleID},
		{MenuId: 1, RoleID: testRoleID},
		{MenuId: 4, RoleID: testRoleID},
	}
	userRoles := []admin.AccountRole{
		{AccountID: 1, RoleID: adminRoleID},
		{AccountID: 1, RoleID: memberRoleID},
		{AccountID: 1, RoleID: testRoleID},
	}
	roleDataScopes := []admin.RoleDataScope{
		{RoleID: adminRoleID, ScopeRoleID: adminRoleID},
		{RoleID: adminRoleID, ScopeRoleID: memberRoleID},
		{RoleID: adminRoleID, ScopeRoleID: testRoleID},
		{RoleID: testRoleID, ScopeRoleID: memberRoleID},
		{RoleID: testRoleID, ScopeRoleID: testRoleID},
	}
	ignoreApis := []admin.IgnoredAPIEntry{
		{BaseModel: global.BaseModel{ID: 1}, Path: "/uploads/file/*filepath", Method: "GET"},
		{BaseModel: global.BaseModel{ID: 2}, Path: "/health", Method: "GET"},
		{BaseModel: global.BaseModel{ID: 3}, Path: "/uploads/file/*filepath", Method: "HEAD"},
		{BaseModel: global.BaseModel{ID: 4}, Path: "/auth/login", Method: "POST"},
		{BaseModel: global.BaseModel{ID: 5}, Path: "/auth/captcha", Method: "GET"},
	}

	err = db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&roles).Error; err != nil {
			return err
		}
		if err := tx.Create(&users).Error; err != nil {
			return err
		}
		if err := tx.Create(&menus).Error; err != nil {
			return err
		}
		if err := tx.Create(&roleMenuBindings).Error; err != nil {
			return err
		}
		if err := tx.Create(&userRoles).Error; err != nil {
			return err
		}
		if err := tx.Create(&roleDataScopes).Error; err != nil {
			return err
		}
		if err := tx.Create(&ignoreApis).Error; err != nil {
			return err
		}
		return nil
	})
	if err != nil {
		global.AppLog.Error("bootstrap local baseline data failed", zap.Error(err))
		return
	}

	if passwordFromEnv {
		global.AppLog.Info("bootstrap local baseline data success", zap.String("adminUsername", "admin"), zap.String("adminPasswordSource", "env"), zap.Uint("adminRoleId", adminRoleID))
		return
	}

	global.AppLog.Info("bootstrap local baseline data success", zap.String("adminUsername", "admin"), zap.String("generatedAdminPassword", bootstrapPassword), zap.Uint("adminRoleId", adminRoleID))
}

func resolveBootstrapAdminPassword() (string, bool, error) {
	if password := strings.TrimSpace(os.Getenv("HEYU_BOOTSTRAP_PASSWORD")); password != "" {
		return password, true, nil
	}
	if password := strings.TrimSpace(os.Getenv("ADMIN_BOOTSTRAP_PASSWORD")); password != "" {
		return password, true, nil
	}
	password, err := randomBootstrapString(18)
	if err != nil {
		return "", false, err
	}
	return password, false, nil
}

func generateLocalRoleIDs() (uint, uint, uint, error) {
	adminRoleID, err := randomRoleID()
	if err != nil {
		return 0, 0, 0, err
	}
	memberRoleID, err := randomRoleID()
	if err != nil {
		return 0, 0, 0, err
	}
	for memberRoleID == adminRoleID {
		memberRoleID, err = randomRoleID()
		if err != nil {
			return 0, 0, 0, err
		}
	}
	testRoleID, err := randomRoleID()
	if err != nil {
		return 0, 0, 0, err
	}
	for testRoleID == adminRoleID || testRoleID == memberRoleID {
		testRoleID, err = randomRoleID()
		if err != nil {
			return 0, 0, 0, err
		}
	}
	return adminRoleID, memberRoleID, testRoleID, nil
}

func randomRoleID() (uint, error) {
	value, err := rand.Int(rand.Reader, big.NewInt(8000))
	if err != nil {
		return 0, err
	}
	return uint(value.Int64()) + 2000, nil
}

func randomBootstrapString(length int) (string, error) {
	const alphabet = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	buffer := make([]byte, length)
	limit := big.NewInt(int64(len(alphabet)))
	for index := range buffer {
		value, err := rand.Int(rand.Reader, limit)
		if err != nil {
			return "", err
		}
		buffer[index] = alphabet[value.Int64()]
	}
	return string(buffer), nil
}

func uintPtr(value uint) *uint {
	return &value
}
