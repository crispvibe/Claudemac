package admin

type ServicePack struct {
	CaptchaConfigService
	EmailConfigService
	JwtService
	ApiService
	MenuService
	UserService
	CasbinService
	BaseMenuService
	RoleService
	OperationRecordService
	RoleButtonBindingService
	LoginLogService
	FileUploadAndDownloadService
	AttachmentCategoryService
	NotificationService
	RemoteAdminService
}
