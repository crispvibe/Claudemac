package admin

import api "heyu/server/api/v1"

type RouterPack struct {
	ApiRouter
	JwtRouter
	BaseRouter
	CaptchaConfigRouter
	MenuRouter
	UserRouter
	CasbinRouter
	RoleRouter
	OperationRecordRouter
	RoleButtonBindingRouter
	LoginLogRouter
	FileUploadAndDownloadRouter
	AttachmentCategoryRouter
	NotificationRouter
	RemoteAdminRouter
}

var (
	jwtApi                   = api.APIs.Admin.JwtApi
	baseApi                  = api.APIs.Admin.BaseApi
	casbinApi                = api.APIs.Admin.CasbinApi
	roleApi                  = api.APIs.Admin.RoleApi
	apiRouterApi             = api.APIs.Admin.APICatalogApi
	roleButtonBindingApi     = api.APIs.Admin.RoleButtonBindingApi
	navigationApi            = api.APIs.Admin.NavigationApi
	operationRecordApi       = api.APIs.Admin.OperationRecordApi
	loginLogApi              = api.APIs.Admin.LoginLogApi
	fileUploadAndDownloadApi = api.APIs.Admin.FileUploadAndDownloadApi
	attachmentCategoryApi    = api.APIs.Admin.AttachmentCategoryApi
	notificationApiV1        = api.APIs.Admin.NotificationApi
	remoteAdminApi           = api.APIs.Admin.RemoteAdminApi
)

var _ = notificationApiV1
