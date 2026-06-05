package admin

import (
	"errors"
	"strings"
	"time"

	"heyu/server/global"
	"heyu/server/model/shared/response"
	systemReq "heyu/server/model/admin/request"
	systemRes "heyu/server/model/admin/response"
	customCaptcha "heyu/server/utils/captcha"
	"github.com/gin-gonic/gin"
)

type BaseApi struct{}

const loginFailedCounterPrefix = "LOGIN_FAIL:"

// Captcha 仅返回当前是否需要验证码的标志位，真正的人机挑战走
// /auth/slide-captcha 滑块链路。保留该端点仅为兼容前端登录页探测，
// 不再生成任何图片验证码，彻底与 base64Captcha 解耦。
func (b *BaseApi) Captcha(c *gin.Context) {
	result := systemRes.CaptchaResponse{
		CaptchaLength: global.AppConfig.Captcha.KeyLong,
		OpenCaptcha:   shouldOpenCaptcha(c.ClientIP()),
	}
	response.SuccessPayload(result, "获取成功", c)
}

func (b *BaseApi) GetCaptchaConfig(c *gin.Context) {
	response.SuccessPayload(captchaConfigService.GetCaptchaConfig(), "获取成功", c)
}

func (b *BaseApi) UpdateCaptchaConfig(c *gin.Context) {
	var req systemReq.CaptchaConfigUpdate
	if err := c.ShouldBindJSON(&req); err != nil {
		failInvalidParams(c)
		return
	}

	result, err := captchaConfigService.UpdateCaptchaConfig(req)
	if err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessPayload(result, "保存成功", c)
}

func shouldOpenCaptcha(ip string) bool {
	threshold := global.AppConfig.Captcha.OpenCaptcha
	if threshold == 0 {
		return true
	}
	if threshold < 0 {
		return false
	}
	return failedLoginAttempts(ip) >= threshold
}

func verifyLoginCaptcha(loginReq systemReq.Login, ip string) error {
	// 由 shouldOpenCaptcha 统一决定当前请求是否需要验证码：
	//   - open-captcha < 0：管理员主动关闭（"仅建议内网使用"），直接放行
	//   - open-captcha == 0：每次都要
	//   - open-captcha > 0：同 IP 失败达到阈值时才要
	if !shouldOpenCaptcha(ip) {
		return nil
	}
	token := strings.TrimSpace(loginReq.SlideToken)
	if token == "" {
		return errors.New("请先完成滑块验证")
	}
	if !customCaptcha.ConsumeSlideToken(token) {
		return errors.New("滑块验证已过期，请重新滑动")
	}
	return nil
}

func loginFailedCounterKey(ip string) string {
	return loginFailedCounterPrefix + ip
}

func failedLoginAttempts(ip string) int {
	key := loginFailedCounterKey(ip)
	value, ok := global.BlackCache.Get(key)
	if !ok {
		return 0
	}
	switch counter := value.(type) {
	case int:
		return counter
	case int64:
		return int(counter)
	case uint:
		return int(counter)
	default:
		return 0
	}
}

func markLoginFailure(ip string) {
	key := loginFailedCounterKey(ip)
	if _, ok := global.BlackCache.Get(key); ok {
		_ = global.BlackCache.Increment(key, 1)
		return
	}
	ttl := time.Duration(global.AppConfig.Captcha.OpenCaptchaTimeOut) * time.Second
	if ttl <= 0 {
		ttl = 15 * time.Minute
	}
	global.BlackCache.Set(key, 1, ttl)
}

func clearLoginFailure(ip string) {
	global.BlackCache.Delete(loginFailedCounterKey(ip))
}
