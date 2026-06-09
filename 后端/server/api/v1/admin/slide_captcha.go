package admin

import (
	"strings"

	"heyu/server/model/shared/response"
	customCaptcha "heyu/server/utils/captcha"

	"github.com/gin-gonic/gin"
)

// SlideCaptchaVerifyRequest 描述滑块校验请求参数。
type SlideCaptchaVerifyRequest struct {
	CaptchaID string `json:"captchaId"`
	X         int    `json:"x"`
}

// SlideCaptchaVerifyResponse 成功后返回的一次性登录 token。
type SlideCaptchaVerifyResponse struct {
	SlideToken string `json:"slideToken"`
}

// GenerateSlideCaptcha 生成一次滑块挑战。
func (b *BaseApi) GenerateSlideCaptcha(c *gin.Context) {
	payload, err := customCaptcha.GenerateSlide()
	if err != nil {
		response.ErrorMessage("生成验证码失败", c)
		return
	}
	response.SuccessPayload(payload, "获取成功", c)
}

// VerifySlideCaptcha 校验滑块结果并签发一次性登录 token。
func (b *BaseApi) VerifySlideCaptcha(c *gin.Context) {
	var req SlideCaptchaVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		failInvalidParams(c)
		return
	}
	if strings.TrimSpace(req.CaptchaID) == "" {
		response.ErrorMessage("验证码参数缺失", c)
		return
	}
	token, err := customCaptcha.VerifySlide(strings.TrimSpace(req.CaptchaID), req.X)
	if err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessPayload(SlideCaptchaVerifyResponse{SlideToken: token}, "验证通过", c)
}
