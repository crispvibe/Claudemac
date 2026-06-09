package initialize

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"strings"

	"heyu/server/global"
	"go.uber.org/zap"
)

// EnsureAdminSlug 保证 system.router-prefix 非空，用作后台入口"随机地址"。
//   - 为空时：生成 16 位 hex slug（形如 /a1b2c3d4e5f6a7b8）并回写到当前加载的配置文件，
//     下次启动沿用；同一实例多次重启保持稳定。
//   - 已设置：仅做归一化（补 '/' 前缀、去重复斜杠、去结尾斜杠）。
//
// 安全意义：所有受保护的业务/鉴权路由统一挂在 RouterPrefix 下。不知道 slug 的扫描器
// 在根域只能命中 /health 这类运维路由，无法探到 /auth/login 等入口。
func EnsureAdminSlug() {
	current := strings.TrimSpace(global.AppConfig.System.RouterPrefix)
	if current != "" {
		normalized := normalizeSlug(current)
		if normalized != current {
			global.AppConfig.System.RouterPrefix = normalized
			persistAdminSlug(normalized)
		}
		logAdminSlug(global.AppConfig.System.RouterPrefix, false)
		return
	}

	slug, err := randomSlug(8)
	if err != nil {
		panic(fmt.Errorf("generate admin slug failed: %w", err))
	}
	slug = "/" + slug
	global.AppConfig.System.RouterPrefix = slug
	persistAdminSlug(slug)
	logAdminSlug(slug, true)
}

func randomSlug(byteLen int) (string, error) {
	b := make([]byte, byteLen)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func normalizeSlug(s string) string {
	s = strings.TrimSpace(s)
	s = strings.TrimRight(s, "/")
	if s == "" {
		return ""
	}
	if !strings.HasPrefix(s, "/") {
		s = "/" + s
	}
	return s
}

func persistAdminSlug(slug string) {
	if global.AppVP == nil {
		return
	}
	global.AppVP.Set("system.router-prefix", slug)
	if err := global.AppVP.WriteConfig(); err != nil {
		msg := fmt.Sprintf("persist admin slug failed: %v", err)
		if global.AppLog != nil {
			global.AppLog.Warn(msg, zap.Error(err))
		} else {
			fmt.Println(msg)
		}
	}
}

func logAdminSlug(slug string, generated bool) {
	banner := fmt.Sprintf("======== 后台入口 prefix = %s ========", slug)
	if generated {
		banner = "[首次启动已生成随机后台入口 slug] " + banner
	}
	if global.AppLog != nil {
		global.AppLog.Info(banner)
	}
	fmt.Println(banner)
}
