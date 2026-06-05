package setting

type Remote struct {
	TrialMinutesPerDay int      `mapstructure:"trial-minutes-per-day" json:"trial-minutes-per-day" yaml:"trial-minutes-per-day"`
	TurnCredentialTTL  int      `mapstructure:"turn-credential-ttl" json:"turn-credential-ttl" yaml:"turn-credential-ttl"`
	TurnRealm          string   `mapstructure:"turn-realm" json:"turn-realm" yaml:"turn-realm"`
	TurnSecret         string   `mapstructure:"turn-secret" json:"turn-secret" yaml:"turn-secret"`
	StunURLs           []string `mapstructure:"stun-urls" json:"stun-urls" yaml:"stun-urls"`
	TurnURLs           []string `mapstructure:"turn-urls" json:"turn-urls" yaml:"turn-urls"`
	PayGateway         string   `mapstructure:"pay-gateway" json:"pay-gateway" yaml:"pay-gateway"`
	PayAppKey          string   `mapstructure:"pay-app-key" json:"pay-app-key" yaml:"pay-app-key"`
	PayAppSecret       string   `mapstructure:"pay-app-secret" json:"pay-app-secret" yaml:"pay-app-secret"`
	PayNotifyURL       string   `mapstructure:"pay-notify-url" json:"pay-notify-url" yaml:"pay-notify-url"`
	PayReturnURL       string   `mapstructure:"pay-return-url" json:"pay-return-url" yaml:"pay-return-url"`
	PayChannelCode     string   `mapstructure:"pay-channel-code" json:"pay-channel-code" yaml:"pay-channel-code"`
	PayTradeType       string   `mapstructure:"pay-trade-type" json:"pay-trade-type" yaml:"pay-trade-type"`
}
