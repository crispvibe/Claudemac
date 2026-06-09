package admin

import (
	"strconv"
	"strings"

	"go.uber.org/zap"
	"heyu/server/global"
	"heyu/server/model/admin"
	systemReq "heyu/server/model/admin/request"
	"heyu/server/utils"
)

var bootstrapPublicRoutes = []systemReq.CasbinInfo{
	{Path: "/auth/login", Method: "POST"},
	{Path: "/auth/captcha", Method: "GET"},
	{Path: "/health", Method: "GET"},
	{Path: "/uploads/file/*filepath", Method: "GET"},
	{Path: "/uploads/file/*filepath", Method: "HEAD"},
}

func BootstrapSystemMetadata() {
	ensureDefaultRolePolicies()
	ensureRegisteredSystemAPIs()
	ensureRemoteAdminMenus()
	ensureRemoteAdminAPIs()
	ensureAdminRoleFullCoverage()
}

func ensureDefaultRolePolicies() {
	var roles []admin.Role
	if err := global.AppDB.Select("role_id").Find(&roles).Error; err != nil {
		global.AppLog.Error("补齐默认权限失败", zap.Error(err))
		return
	}
	defaults := systemReq.DefaultCasbin()
	enforcer := utils.GetCasbin()
	for _, role := range roles {
		roleKey := strconv.Itoa(int(role.RoleID))
		existingPolicies, _ := enforcer.GetFilteredPolicy(0, roleKey)
		existingMap := make(map[string]struct{}, len(existingPolicies))
		for _, policy := range existingPolicies {
			if len(policy) < 3 {
				continue
			}
			existingMap[policy[1]+"|"+policy[2]] = struct{}{}
		}
		newRules := make([][]string, 0)
		for _, item := range defaults {
			key := item.Path + "|" + item.Method
			if _, ok := existingMap[key]; ok {
				continue
			}
			newRules = append(newRules, []string{roleKey, item.Path, item.Method})
		}
		if len(newRules) == 0 {
			continue
		}
		if _, err := enforcer.AddPolicies(newRules); err != nil {
			global.AppLog.Error("补齐默认权限失败", zap.Error(err), zap.Uint("roleId", role.RoleID))
		}
	}
}

func ensureRegisteredSystemAPIs() {
	if len(global.AppRouters) == 0 {
		return
	}
	var apis []admin.APICatalogEntry
	if err := global.AppDB.Select("path", "method").Find(&apis).Error; err != nil {
		global.AppLog.Error("补齐系统API失败", zap.Error(err))
		return
	}
	existingMap := make(map[string]struct{}, len(apis))
	for _, api := range apis {
		existingMap[api.Path+"|"+api.Method] = struct{}{}
	}
	newApis := make([]admin.APICatalogEntry, 0)
	for _, route := range global.AppRouters {
		// 存入业务表的 path 不应包含运行时随机后台 slug，否则 slug 每次变化都会让 DB 对不上
		path := stripAdminSlug(route.Path)
		key := path + "|" + route.Method
		if _, ok := existingMap[key]; ok {
			continue
		}
		group := "system"
		parts := strings.Split(strings.TrimPrefix(path, "/"), "/")
		if len(parts) > 0 && parts[0] != "" {
			group = parts[0]
		}
		newApis = append(newApis, admin.APICatalogEntry{
			Path:        path,
			Method:      route.Method,
			ApiGroup:    group,
			Description: "",
		})
	}
	if len(newApis) == 0 {
		return
	}
	if err := global.AppDB.Create(&newApis).Error; err != nil {
		global.AppLog.Error("补齐系统API失败", zap.Error(err))
	}
}

func ensureRemoteAdminMenus() {
	adminRoleID, ok := resolveBootstrapAdminRoleID()
	if !ok {
		return
	}
	parentComponent := admin.BuildComponentIdentifierFromLegacyPath("view/routerHolder.vue")
	pageComponent := admin.BuildComponentIdentifierFromLegacyPath("view/console/remote/index.vue")
	parent := admin.NavigationEntry{Path: "remote", Name: "remoteAdmin", Component: parentComponent, Sort: 6, Meta: admin.Meta{Title: "远程管理", Icon: "connection"}}
	if err := global.AppDB.Where("name = ?", parent.Name).FirstOrCreate(&parent).Error; err != nil {
		global.AppLog.Error("补齐远程管理菜单失败", zap.Error(err))
		return
	}
	if err := global.AppDB.Model(&admin.NavigationEntry{}).Where("id = ?", parent.ID).Updates(map[string]any{"parent_id": 0, "path": "remote", "component": parentComponent, "sort": 6, "title": "远程管理", "icon": "connection", "hidden": false}).Error; err != nil {
		global.AppLog.Error("更新远程管理菜单失败", zap.Error(err))
	}
	childMenus := []admin.NavigationEntry{
		{ParentId: parent.ID, Path: "users", Name: "remoteUsers", Component: pageComponent, Sort: 1, Meta: admin.Meta{Title: "用户列表", Icon: "user"}},
		{ParentId: parent.ID, Path: "devices", Name: "remoteDevices", Component: pageComponent, Sort: 2, Meta: admin.Meta{Title: "设备管理", Icon: "monitor"}},
		{ParentId: parent.ID, Path: "connections", Name: "remoteConnections", Component: pageComponent, Sort: 3, Meta: admin.Meta{Title: "连接日志", Icon: "connection"}},
		{ParentId: parent.ID, Path: "code-attempts", Name: "remoteCodeAttempts", Component: pageComponent, Sort: 4, Meta: admin.Meta{Title: "设备码日志", Icon: "key"}},
		{ParentId: parent.ID, Path: "account-deletions", Name: "remoteAccountDeletions", Component: pageComponent, Sort: 5, Meta: admin.Meta{Title: "注销记录", Icon: "delete"}},
		{ParentId: parent.ID, Path: "legal-documents", Name: "remoteLegalDocuments", Component: pageComponent, Sort: 6, Meta: admin.Meta{Title: "协议文档", Icon: "document"}},
		{ParentId: parent.ID, Path: "app-footer", Name: "remoteAppFooter", Component: pageComponent, Sort: 7, Meta: admin.Meta{Title: "页脚配置", Icon: "tickets"}},
		{ParentId: parent.ID, Path: "app-updates", Name: "remoteAppUpdates", Component: pageComponent, Sort: 8, Meta: admin.Meta{Title: "在线更新", Icon: "upload"}},
		{ParentId: parent.ID, Path: "legal-consents", Name: "remoteLegalConsents", Component: pageComponent, Sort: 9, Meta: admin.Meta{Title: "协议同意记录", Icon: "finished"}},
	}
	bindMenuIDs := []uint{parent.ID}
	for _, item := range childMenus {
		child := item
		if err := global.AppDB.Where("name = ?", child.Name).FirstOrCreate(&child).Error; err != nil {
			global.AppLog.Error("补齐远程管理子菜单失败", zap.Error(err), zap.String("name", item.Name))
			continue
		}
		if err := global.AppDB.Model(&admin.NavigationEntry{}).Where("id = ?", child.ID).Updates(map[string]any{
			"parent_id": parent.ID,
			"path":      item.Path,
			"name":      item.Name,
			"component": pageComponent,
			"sort":      item.Sort,
			"title":     item.Meta.Title,
			"icon":      item.Meta.Icon,
			"hidden":    false,
		}).Error; err != nil {
			global.AppLog.Error("更新远程管理子菜单失败", zap.Error(err), zap.String("name", item.Name))
			continue
		}
		bindMenuIDs = append(bindMenuIDs, child.ID)
	}
	if err := global.AppDB.Model(&admin.NavigationEntry{}).Where("name = ?", "remoteLegal").Updates(map[string]any{"hidden": true}).Error; err != nil {
		global.AppLog.Error("隐藏远程管理废弃子菜单失败", zap.Error(err))
	}
	if err := global.AppDB.Model(&admin.NavigationEntry{}).Where("name IN ?", []string{"remotePlans", "remoteSubscriptions", "remoteSubscriptionOrders"}).Updates(map[string]any{"hidden": true}).Error; err != nil {
		global.AppLog.Error("隐藏远程管理历史权益菜单失败", zap.Error(err))
	}
	for _, menuID := range bindMenuIDs {
		binding := admin.RoleNavigationBinding{MenuId: menuID, RoleID: adminRoleID}
		if err := global.AppDB.Where("navigation_entry_id = ? AND role_id = ?", menuID, adminRoleID).FirstOrCreate(&binding).Error; err != nil {
			global.AppLog.Error("绑定远程管理菜单失败", zap.Error(err), zap.Uint("menuId", menuID), zap.Uint("roleId", adminRoleID))
		}
	}
}

func ensureRemoteAdminAPIs() {
	items := []admin.APICatalogEntry{
		{Path: "/remote-admin/users/list", Method: "POST", ApiGroup: "remote-admin", Description: "远程用户列表"},
		{Path: "/remote-admin/users/save", Method: "POST", ApiGroup: "remote-admin", Description: "保存远程用户"},
		{Path: "/remote-admin/users/status", Method: "POST", ApiGroup: "remote-admin", Description: "更新远程用户状态"},
		{Path: "/remote-admin/users/kick", Method: "POST", ApiGroup: "remote-admin", Description: "踢下线远程用户"},
		{Path: "/remote-admin/users/ban", Method: "POST", ApiGroup: "remote-admin", Description: "禁用远程用户"},
		{Path: "/remote-admin/users/delete", Method: "POST", ApiGroup: "remote-admin", Description: "删除远程用户"},
		{Path: "/remote-admin/devices/list", Method: "POST", ApiGroup: "remote-admin", Description: "远程设备列表"},
		{Path: "/remote-admin/devices/update", Method: "POST", ApiGroup: "remote-admin", Description: "更新远程设备"},
		{Path: "/remote-admin/devices/kick", Method: "POST", ApiGroup: "remote-admin", Description: "踢下线远程设备"},
		{Path: "/remote-admin/devices/delete", Method: "POST", ApiGroup: "remote-admin", Description: "删除远程设备"},
		{Path: "/remote-admin/connections/list", Method: "POST", ApiGroup: "remote-admin", Description: "远程连接记录"},
		{Path: "/remote-admin/connections/delete", Method: "POST", ApiGroup: "remote-admin", Description: "删除远程连接记录"},
		{Path: "/remote-admin/code-attempts/list", Method: "POST", ApiGroup: "remote-admin", Description: "远程设备码日志"},
		{Path: "/remote-admin/code-attempts/delete", Method: "POST", ApiGroup: "remote-admin", Description: "删除远程设备码日志"},
		{Path: "/remote-admin/legal-documents/list", Method: "POST", ApiGroup: "remote-admin", Description: "远程协议列表"},
		{Path: "/remote-admin/legal-documents/save", Method: "POST", ApiGroup: "remote-admin", Description: "保存远程协议"},
		{Path: "/remote-admin/legal-documents/delete", Method: "POST", ApiGroup: "remote-admin", Description: "删除远程协议"},
		{Path: "/remote-admin/app-footer/get", Method: "POST", ApiGroup: "remote-admin", Description: "获取远程 App 页脚配置"},
		{Path: "/remote-admin/app-footer/save", Method: "POST", ApiGroup: "remote-admin", Description: "保存远程 App 页脚配置"},
		{Path: "/remote-admin/app-updates/list", Method: "POST", ApiGroup: "remote-admin", Description: "远程 App 在线更新列表"},
		{Path: "/remote-admin/app-updates/save", Method: "POST", ApiGroup: "remote-admin", Description: "保存远程 App 在线更新"},
		{Path: "/remote-admin/app-updates/delete", Method: "POST", ApiGroup: "remote-admin", Description: "删除远程 App 在线更新"},
		{Path: "/remote-admin/legal-consents/list", Method: "POST", ApiGroup: "remote-admin", Description: "远程协议同意记录"},
		{Path: "/remote-admin/legal-consents/delete", Method: "POST", ApiGroup: "remote-admin", Description: "删除远程协议同意记录"},
		{Path: "/remote-admin/account-deletions/list", Method: "POST", ApiGroup: "remote-admin", Description: "远程账号注销记录"},
	}
	for _, item := range items {
		api := item
		if err := global.AppDB.Where("path = ? AND method = ?", item.Path, item.Method).FirstOrCreate(&api).Error; err != nil {
			global.AppLog.Error("补齐远程管理API失败", zap.Error(err), zap.String("path", item.Path))
			continue
		}
		_ = global.AppDB.Model(&admin.APICatalogEntry{}).Where("id = ?", api.ID).Updates(map[string]any{"description": item.Description, "api_group": item.ApiGroup}).Error
	}
}

func ensureAdminRoleFullCoverage() {
	if len(global.AppRouters) == 0 {
		return
	}

	adminRoleID, ok := resolveBootstrapAdminRoleID()
	if !ok {
		return
	}

	var roleCount int64
	if err := global.AppDB.Model(&admin.Role{}).Where("role_id = ?", adminRoleID).Count(&roleCount).Error; err != nil {
		global.AppLog.Error("补齐管理员权限失败", zap.Error(err), zap.Uint("roleId", adminRoleID))
		return
	}
	if roleCount == 0 {
		return
	}

	var ignoredApis []admin.IgnoredAPIEntry
	if err := global.AppDB.Select("path", "method").Find(&ignoredApis).Error; err != nil {
		global.AppLog.Error("读取忽略鉴权API失败", zap.Error(err))
		return
	}

	ignoredAPIMap := make(map[string]struct{}, len(ignoredApis))
	for _, item := range ignoredApis {
		ignoredAPIMap[item.Path+"|"+item.Method] = struct{}{}
	}
	for _, item := range bootstrapPublicRoutes {
		ignoredAPIMap[item.Path+"|"+item.Method] = struct{}{}
	}

	enforcer := utils.GetCasbin()
	roleKey := strconv.Itoa(int(adminRoleID))
	existingPolicies, err := enforcer.GetFilteredPolicy(0, roleKey)
	if err != nil {
		global.AppLog.Error("读取管理员既有权限失败", zap.Error(err), zap.Uint("roleId", adminRoleID))
		return
	}

	existingPolicyMap := make(map[string]struct{}, len(existingPolicies))
	for _, policy := range existingPolicies {
		if len(policy) < 3 {
			continue
		}
		existingPolicyMap[policy[1]+"|"+policy[2]] = struct{}{}
	}

	newRules := make([][]string, 0)
	for _, route := range global.AppRouters {
		if route.Path == "" || route.Method == "" {
			continue
		}
		// Casbin enforce 侧已按 RouterPrefix 做剥离，这里写入策略也必须是去掉 slug 的纯业务路径
		path := stripAdminSlug(route.Path)
		key := path + "|" + route.Method
		if _, ok := ignoredAPIMap[key]; ok {
			continue
		}
		if _, ok := existingPolicyMap[key]; ok {
			continue
		}
		newRules = append(newRules, []string{roleKey, path, route.Method})
	}

	if len(newRules) == 0 {
		return
	}

	if _, err = enforcer.AddPolicies(newRules); err != nil {
		global.AppLog.Error("补齐管理员权限失败", zap.Error(err), zap.Uint("roleId", adminRoleID), zap.Int("policyCount", len(newRules)))
		return
	}

	global.AppLog.Info("补齐管理员权限成功", zap.Uint("roleId", adminRoleID), zap.Int("policyCount", len(newRules)))
}

func resolveBootstrapAdminRoleID() (uint, bool) {
	var adminUser admin.Account
	if err := global.AppDB.Select("primary_role_id").Where("username = ?", "admin").First(&adminUser).Error; err == nil && adminUser.PrimaryRoleID != 0 {
		return adminUser.PrimaryRoleID, true
	}

	var adminRole admin.Role
	if err := global.AppDB.Select("role_id").Where("role_name = ?", "管理员").First(&adminRole).Error; err == nil && adminRole.RoleID != 0 {
		return adminRole.RoleID, true
	}

	return 0, false
}

func inferSystemAPIGroup(path string) string {
	parts := strings.Split(strings.TrimPrefix(path, "/"), "/")
	if len(parts) > 0 && parts[0] != "" {
		return parts[0]
	}
	return "system"
}

// stripAdminSlug 去掉 path 中的 system.router-prefix 前缀。
// 存入业务表（api_catalog）与 casbin_rule 的 path 都使用纯业务路径，
// 这样后台入口 slug 变化不会影响已入库的接口元数据与权限策略。
func stripAdminSlug(path string) string {
	prefix := strings.TrimSpace(global.AppConfig.System.RouterPrefix)
	if prefix == "" || prefix == "/" {
		return path
	}
	trimmed := strings.TrimPrefix(path, prefix)
	if trimmed == path {
		return path
	}
	if trimmed == "" {
		return "/"
	}
	if !strings.HasPrefix(trimmed, "/") {
		trimmed = "/" + trimmed
	}
	return trimmed
}
