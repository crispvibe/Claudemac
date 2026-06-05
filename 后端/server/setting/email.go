package setting

type Email struct {
	To          string `mapstructure:"to" json:"to" yaml:"to"`                               // 收件人，多个地址以英文逗号分隔
	From        string `mapstructure:"from" json:"from" yaml:"from"`                         // 发件人邮箱地址
	Host        string `mapstructure:"host" json:"host" yaml:"host"`                         // 邮件服务器地址
	Secret      string `mapstructure:"secret" json:"secret" yaml:"secret"`                   // 邮件服务密钥或授权码
	Nickname    string `mapstructure:"nickname" json:"nickname" yaml:"nickname"`             // 昵称
	Port        int    `mapstructure:"port" json:"port" yaml:"port"`                         // 端口号
	IsSSL       bool   `mapstructure:"is-ssl" json:"is-ssl" yaml:"is-ssl"`                   // 是否SSL
	IsLoginAuth bool   `mapstructure:"is-loginauth" json:"is-loginauth" yaml:"is-loginauth"` // 是否LoginAuth   是否使用LoginAuth认证方式（适用于IBM、微软邮箱服务器等）
}
