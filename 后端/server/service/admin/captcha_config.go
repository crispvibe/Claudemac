package admin

import (
	"fmt"
	"sync"

	"heyu/server/global"
	systemReq "heyu/server/model/admin/request"
	systemRes "heyu/server/model/admin/response"
)

var captchaConfigWriteLock sync.Mutex

type CaptchaConfigService struct{}

func (s *CaptchaConfigService) GetCaptchaConfig() systemRes.CaptchaConfigResponse {
	return buildCaptchaConfigResponse(global.AppConfig.Captcha.OpenCaptcha, global.AppConfig.Captcha.OpenCaptchaTimeOut)
}

func (s *CaptchaConfigService) UpdateCaptchaConfig(input systemReq.CaptchaConfigUpdate) (systemRes.CaptchaConfigResponse, error) {
	if input.OpenCaptcha < -1 {
		return systemRes.CaptchaConfigResponse{}, fmt.Errorf("验证码策略值不能小于 -1")
	}
	if input.OpenCaptchaTimeOut < 0 {
		return systemRes.CaptchaConfigResponse{}, fmt.Errorf("验证码超时时间不能小于 0")
	}

	captchaConfigWriteLock.Lock()
	defer captchaConfigWriteLock.Unlock()

	global.AppVP.Set("captcha.open-captcha", input.OpenCaptcha)
	global.AppVP.Set("captcha.open-captcha-timeout", input.OpenCaptchaTimeOut)
	if err := global.AppVP.WriteConfig(); err != nil {
		return systemRes.CaptchaConfigResponse{}, fmt.Errorf("保存验证码配置失败: %w", err)
	}

	global.AppConfig.Captcha.OpenCaptcha = input.OpenCaptcha
	global.AppConfig.Captcha.OpenCaptchaTimeOut = input.OpenCaptchaTimeOut
	return buildCaptchaConfigResponse(input.OpenCaptcha, input.OpenCaptchaTimeOut), nil
}

func buildCaptchaConfigResponse(openCaptcha, timeout int) systemRes.CaptchaConfigResponse {
	mode := "threshold"
	enabled := true
	switch {
	case openCaptcha < 0:
		mode = "disabled"
		enabled = false
	case openCaptcha == 0:
		mode = "always"
	default:
		mode = "threshold"
	}

	return systemRes.CaptchaConfigResponse{
		OpenCaptcha:        openCaptcha,
		OpenCaptchaTimeOut: timeout,
		Enabled:            enabled,
		Mode:               mode,
	}
}
