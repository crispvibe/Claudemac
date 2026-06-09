package utils

import (
	"net"
	"net/http"
	"strings"
	"time"

	"heyu/server/global"
	"heyu/server/model/admin"
	systemReq "heyu/server/model/admin/request"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

func shouldUseSecureCookie(c *gin.Context) bool {
	if c == nil || c.Request == nil {
		return false
	}
	if c.Request.TLS != nil {
		return true
	}
	forwardedProto := strings.TrimSpace(strings.ToLower(c.GetHeader("X-Forwarded-Proto")))
	forwardedSSL := strings.TrimSpace(strings.ToLower(c.GetHeader("X-Forwarded-Ssl")))
	return forwardedProto == "https" || forwardedSSL == "on"
}

func setTokenCookie(c *gin.Context, value string, maxAge int) {
	host, _, err := net.SplitHostPort(c.Request.Host)
	if err != nil {
		host = c.Request.Host
	}
	secure := shouldUseSecureCookie(c)
	// 后台登录态 cookie 仅作为 Authorization 头兜底，前端主链路用 Bearer token，
	// SameSite=Strict 可彻底阻断跨站场景下的 cookie 携带，降低 CSRF / 越权风险；
	// HttpOnly=true 杜绝 document.cookie 窃取；Secure 随请求实际协议动态决定
	c.SetSameSite(http.SameSiteStrictMode)
	if net.ParseIP(host) != nil {
		c.SetCookie("access_token", value, maxAge, "/", "", secure, true)
	} else {
		c.SetCookie("access_token", value, maxAge, "/", host, secure, true)
	}
}

func extractBearerToken(header string) string {
	header = strings.TrimSpace(header)
	if header == "" {
		return ""
	}
	parts := strings.SplitN(header, " ", 2)
	if len(parts) == 2 && strings.EqualFold(parts[0], "Bearer") {
		return strings.TrimSpace(parts[1])
	}
	return header
}

func ClearToken(c *gin.Context) {
	setTokenCookie(c, "", -1)
}

func SetToken(c *gin.Context, token string, maxAge int) {
	setTokenCookie(c, token, maxAge)
}

func GetToken(c *gin.Context) string {
	token := extractBearerToken(c.Request.Header.Get("Authorization"))
	if token == "" {
		j := NewJWT()
		token, _ = c.Cookie("access_token")
		claims, err := j.ParseToken(token)
		if err != nil {
			global.AppLog.Error("重新写入 cookie token 失败，未能成功解析 token，请检查 Authorization 或 access_token cookie")
			return token
		}
		SetToken(c, token, int(claims.ExpiresAt.Unix()-time.Now().Unix()))
	}
	return token
}

func GetClaims(c *gin.Context) (*systemReq.CustomClaims, error) {
	token := GetToken(c)
	j := NewJWT()
	claims, err := j.ParseToken(token)
	if err != nil {
		global.AppLog.Error("从 Gin Context 获取 JWT 解析信息失败，请检查 Authorization 或 access_token cookie")
	}
	return claims, err
}

// GetUserID 从Gin的Context中获取从jwt解析出来的用户ID
func GetUserID(c *gin.Context) uint {
	if claims, exists := c.Get("claims"); !exists {
		if cl, err := GetClaims(c); err != nil {
			return 0
		} else {
			return cl.BaseClaims.ID
		}
	} else {
		waitUse := claims.(*systemReq.CustomClaims)
		return waitUse.BaseClaims.ID
	}
}

// GetUserUuid 从Gin的Context中获取从jwt解析出来的用户UUID
func GetUserUuid(c *gin.Context) uuid.UUID {
	if claims, exists := c.Get("claims"); !exists {
		if cl, err := GetClaims(c); err != nil {
			return uuid.UUID{}
		} else {
			return cl.UUID
		}
	} else {
		waitUse := claims.(*systemReq.CustomClaims)
		return waitUse.UUID
	}
}

// GetUserRoleID 从Gin的Context中获取从jwt解析出来的用户角色id
func GetUserRoleID(c *gin.Context) uint {
	if claims, exists := c.Get("claims"); !exists {
		if cl, err := GetClaims(c); err != nil {
			return 0
		} else {
			return cl.RoleID
		}
	} else {
		waitUse := claims.(*systemReq.CustomClaims)
		return waitUse.RoleID
	}
}

// GetUserInfo 从Gin的Context中获取从jwt解析出来的用户角色id
func GetUserInfo(c *gin.Context) *systemReq.CustomClaims {
	if claims, exists := c.Get("claims"); !exists {
		if cl, err := GetClaims(c); err != nil {
			return nil
		} else {
			return cl
		}
	} else {
		waitUse := claims.(*systemReq.CustomClaims)
		return waitUse
	}
}

// GetUserName 从Gin的Context中获取从jwt解析出来的用户名
func GetUserName(c *gin.Context) string {
	if claims, exists := c.Get("claims"); !exists {
		if cl, err := GetClaims(c); err != nil {
			return ""
		} else {
			return cl.Username
		}
	} else {
		waitUse := claims.(*systemReq.CustomClaims)
		return waitUse.Username
	}
}

func LoginToken(user admin.Login) (token string, claims systemReq.CustomClaims, err error) {
	j := NewJWT()
	claims = j.CreateClaims(systemReq.BaseClaims{
		UUID:        user.GetUUID(),
		ID:          user.GetUserId(),
		NickName:    user.GetNickname(),
		Username:    user.GetUsername(),
		RoleID:      user.GetRoleID(),
	})
	token, err = j.CreateToken(claims)
	return
}
