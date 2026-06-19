package response

// EmailConfigResponse 后台「邮件发送配置」回显。出于安全，授权码不回显明文，
// 仅用 SecretSet 标记是否已配置。
type EmailConfigResponse struct {
	Host        string `json:"host"`
	Port        int    `json:"port"`
	From        string `json:"from"`
	Nickname    string `json:"nickname"`
	IsSSL       bool   `json:"isSSL"`
	IsLoginAuth bool   `json:"isLoginAuth"`
	SecretSet   bool   `json:"secretSet"`
	Configured  bool   `json:"configured"`
}
