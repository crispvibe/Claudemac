package admin

import "heyu/server/service"

type APIPack struct {
	JwtApi
	BaseApi
	CasbinApi
	APICatalogApi
	RoleApi
	NavigationApi
	OperationRecordApi
	RoleButtonBindingApi
	LoginLogApi
	FileUploadAndDownloadApi
	AttachmentCategoryApi
	NotificationApi
	RemoteAdminApi
}

var (
	captchaConfigService         = service.Services.Admin.CaptchaConfigService
	apiService                   = service.Services.Admin.ApiService
	jwtService                   = service.Services.Admin.JwtService
	menuService                  = service.Services.Admin.MenuService
	userService                  = service.Services.Admin.UserService
	casbinService                = service.Services.Admin.CasbinService
	baseMenuService              = service.Services.Admin.BaseMenuService
	roleService                  = service.Services.Admin.RoleService
	roleButtonBindingService     = service.Services.Admin.RoleButtonBindingService
	operationRecordService       = service.Services.Admin.OperationRecordService
	loginLogService              = service.Services.Admin.LoginLogService
	fileUploadAndDownloadService = service.Services.Admin.FileUploadAndDownloadService
	attachmentCategoryService    = service.Services.Admin.AttachmentCategoryService
	notificationService          = service.Services.Admin.NotificationService
	remoteAdminService           = service.Services.Admin.RemoteAdminService
)
