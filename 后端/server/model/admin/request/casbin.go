package request

// CasbinInfo Casbin info structure
type CasbinInfo struct {
	Path   string `json:"path"`   // 路径
	Method string `json:"method"` // 方法
}

// CasbinInReceive Casbin structure for input parameters
type CasbinInReceive struct {
	RoleID      uint         `json:"roleId"`      // 权限id
	CasbinInfos []CasbinInfo `json:"casbinInfos"`
}

func DefaultCasbin() []CasbinInfo {
	return []CasbinInfo{
		{Path: "/navigation/routes", Method: "POST"},
		{Path: "/dashboard/panel", Method: "GET"},
		{Path: "/auth-tokens/jsonInBlacklist", Method: "POST"},
		{Path: "/system/captcha-config", Method: "GET"},
		{Path: "/system/captcha-config", Method: "PUT"},
		{Path: "/accounts/password/change", Method: "POST"},
		{Path: "/accounts/role/primary", Method: "POST"},
		{Path: "/accounts/profile", Method: "GET"},
		{Path: "/accounts/profile", Method: "PUT"},
		{Path: "/attachments/upload", Method: "POST"},
		{Path: "/attachments/getFileList", Method: "POST"},
		{Path: "/attachments/deleteFile", Method: "POST"},
		{Path: "/attachments/editFileName", Method: "POST"},
		{Path: "/attachments/importURL", Method: "POST"},
		{Path: "/attachment-categories/getCategoryList", Method: "GET"},
		{Path: "/attachment-categories/addCategory", Method: "POST"},
		{Path: "/attachment-categories/deleteCategory", Method: "POST"},
	}
}
