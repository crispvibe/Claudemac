package request

// EmailConfigUpdate 后台「邮件发送配置」更新入参。
// Secret 为 QQ/163 等邮箱的 SMTP 授权码（非登录密码）。
type EmailConfigUpdate struct {
	Host        string `json:"host"`
	Port        int    `json:"port"`
	From        string `json:"from"`
	Nickname    string `json:"nickname"`
	Secret      string `json:"secret"`
	IsSSL       bool   `json:"isSSL"`
	IsLoginAuth bool   `json:"isLoginAuth"`
	// SecretChanged 为 false 时表示前端未修改授权码，沿用已保存的值（避免回显明文）。
	SecretChanged bool `json:"secretChanged"`
}

// EmailConfigTest 发送测试邮件入参。
type EmailConfigTest struct {
	To string `json:"to"`
}
