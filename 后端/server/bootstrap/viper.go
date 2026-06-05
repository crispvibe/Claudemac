package bootstrap

import (
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/fsnotify/fsnotify"
	"github.com/gin-gonic/gin"
	"github.com/spf13/viper"
	"heyu/server/bootstrap/internal"
	"heyu/server/global"
)

const defaultJWTSigningKey = "replace-with-a-32-byte-random-secret-before-release"

func validateConfig() error {
	if strings.EqualFold(global.AppConfig.System.Env, "local") {
		return nil
	}
	if strings.TrimSpace(global.AppConfig.JWT.SigningKey) == defaultJWTSigningKey {
		return fmt.Errorf("jwt.signing-key 仍为默认弱值，请在非 local 环境中替换")
	}
	if err := validateRemoteTURNConfig(); err != nil {
		return err
	}
	return nil
}

func validateRemoteTURNConfig() error {
	turnSecret := strings.TrimSpace(global.AppConfig.Remote.TurnSecret)
	hasTURNURL := false
	for _, rawURL := range global.AppConfig.Remote.TurnURLs {
		trimmed := strings.ToLower(strings.TrimSpace(rawURL))
		if strings.HasPrefix(trimmed, "turn:") || strings.HasPrefix(trimmed, "turns:") {
			hasTURNURL = true
			break
		}
	}
	if hasTURNURL && turnSecret == "" {
		return fmt.Errorf("remote.turn-secret 为空，非 local 环境中 remote.turn-urls 已配置时必须设置 TURN REST 密钥，可用 ACODE_REMOTE_TURN_SECRET 注入")
	}
	if turnSecret != "" && !hasTURNURL {
		return fmt.Errorf("remote.turn-secret 已配置但 remote.turn-urls 为空，非 local 环境无法下发 TURN 中继")
	}
	return nil
}

func bindConfigEnv(v *viper.Viper) error {
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_", "-", "_"))
	v.AutomaticEnv()
	bindings := map[string][]string{
		"remote.turn-secret": {"ACODE_REMOTE_TURN_SECRET", "REMOTE_TURN_SECRET"},
	}
	for key, envs := range bindings {
		args := append([]string{key}, envs...)
		if err := v.BindEnv(args...); err != nil {
			return err
		}
	}
	return nil
}

// Viper 配置
func Viper() *viper.Viper {
	config := getConfigPath()

	v := viper.New()
	v.SetConfigFile(config)
	v.SetConfigType("yaml")
	if err := bindConfigEnv(v); err != nil {
		panic(fmt.Errorf("fatal error bind config env: %w", err))
	}
	err := v.ReadInConfig()
	if err != nil {
		panic(fmt.Errorf("fatal error config file: %w", err))
	}
	v.WatchConfig()

	v.OnConfigChange(func(e fsnotify.Event) {
		fmt.Println("config file changed:", e.Name)
		if err = v.Unmarshal(&global.AppConfig); err != nil {
			fmt.Println(err)
			return
		}
		if err = validateConfig(); err != nil {
			fmt.Println(err)
		}
	})
	if err = v.Unmarshal(&global.AppConfig); err != nil {
		panic(fmt.Errorf("fatal error unmarshal config: %w", err))
	}
	if err = validateConfig(); err != nil {
		panic(fmt.Errorf("fatal error validate config: %w", err))
	}
	return v
}

// getConfigPath 获取配置文件路径, 优先级: 命令行 > 环境变量 > 默认值
func getConfigPath() (config string) {
	// `-c` flag parse
	flag.StringVar(&config, "c", "", "choose config file.")
	flag.Parse()
	if config != "" { // 命令行参数不为空 将值赋值于config
		fmt.Printf("您正在使用命令行的 '-c' 参数传递的值, config 的路径为 %s\n", config)
		return
	}
	if env := os.Getenv(internal.ConfigEnv); env != "" { // 判断环境变量 AppConfig
		config = env
		fmt.Printf("您正在使用 %s 环境变量, config 的路径为 %s\n", internal.ConfigEnv, config)
		return
	}

	switch gin.Mode() { // 根据 gin 模式文件名
	case gin.DebugMode:
		config = internal.ConfigDebugFile
	case gin.ReleaseMode:
		config = internal.ConfigReleaseFile
	case gin.TestMode:
		config = internal.ConfigTestFile
	}
	fmt.Printf("您正在使用 gin 的 %s 模式运行, config 的路径为 %s\n", gin.Mode(), config)

	_, err := os.Stat(config)
	if err != nil || os.IsNotExist(err) {
		config = internal.ConfigDefaultFile
		fmt.Printf("配置文件路径不存在, 使用默认配置文件路径: %s\n", config)
	}

	return
}
