package response


type CaptchaResponse struct {
	CaptchaId     string `json:"captchaId"`
	PicPath       string `json:"picPath"`
	CaptchaLength int    `json:"captchaLength"`
	OpenCaptcha   bool   `json:"openCaptcha"`
}

type CaptchaConfigResponse struct {
	OpenCaptcha        int    `json:"openCaptcha"`
	OpenCaptchaTimeOut int    `json:"openCaptchaTimeOut"`
	Enabled            bool   `json:"enabled"`
	Mode               string `json:"mode"`
}
