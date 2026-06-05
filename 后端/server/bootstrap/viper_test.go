package bootstrap

import (
	"strings"
	"testing"

	"github.com/spf13/viper"
	"heyu/server/global"
	"heyu/server/setting"
)

func TestValidateConfigRequiresTURNSecretWhenTURNURLsConfigured(t *testing.T) {
	oldConfig := global.AppConfig
	t.Cleanup(func() { global.AppConfig = oldConfig })

	global.AppConfig.System.Env = "prod"
	global.AppConfig.JWT.SigningKey = "strong-signing-key"
	global.AppConfig.Remote.TurnURLs = []string{"turn:turn.acode.test:3478?transport=udp"}
	global.AppConfig.Remote.TurnSecret = ""

	err := validateConfig()
	if err == nil || !strings.Contains(err.Error(), "remote.turn-secret") {
		t.Fatalf("expected remote.turn-secret validation error, got %v", err)
	}
}

func TestBindConfigEnvOverridesRemoteTURNSecret(t *testing.T) {
	t.Setenv("ACODE_REMOTE_TURN_SECRET", "env-turn-secret")

	v := viper.New()
	v.SetConfigType("yaml")
	if err := bindConfigEnv(v); err != nil {
		t.Fatalf("bindConfigEnv failed: %v", err)
	}
	if err := v.ReadConfig(strings.NewReader(`
system:
  env: prod
jwt:
  signing-key: strong-signing-key
remote:
  turn-secret: ""
  turn-urls:
    - turn:turn.acode.test:3478?transport=udp
`)); err != nil {
		t.Fatalf("ReadConfig failed: %v", err)
	}

	var cfg setting.Server
	if err := v.Unmarshal(&cfg); err != nil {
		t.Fatalf("Unmarshal failed: %v", err)
	}
	if cfg.Remote.TurnSecret != "env-turn-secret" {
		t.Fatalf("expected env TURN secret, got %q", cfg.Remote.TurnSecret)
	}
}
