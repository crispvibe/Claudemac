package request

type CaptchaConfigUpdate struct {
	OpenCaptcha        int `json:"openCaptcha"`
	OpenCaptchaTimeOut int `json:"openCaptchaTimeOut"`
}
