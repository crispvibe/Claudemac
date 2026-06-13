package biz

import (
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	bizReq "heyu/server/model/biz/request"
	"heyu/server/model/shared/response"
	"heyu/server/utils"
)

type RemoteApi struct{}

func remoteUserMessage(message string) string {
	switch strings.TrimSpace(strings.ToLower(message)) {
	case "":
		return "操作失败，请稍后重试。"
	case "record not found":
		return "没有找到对应记录，请刷新后重试。"
	case "unauthorized", "token is expired", "invalid token":
		return "登录状态已失效，请重新登录。"
	case "forbidden":
		return "当前账号没有权限执行此操作。"
	case "subscription_expired":
		return "远程连接服务状态不可用，请在电脑端确认后再连接。"
	case "trial_daily_limit_exceeded":
		return "今日远程连接时长已用完，请明天再试或确认电脑端服务状态。"
	case "entitlement_required":
		return "当前账号未开通远程连接权限，请确认电脑端服务状态后再试。"
	case "pay_notify_bad_sign":
		return "支付通知校验失败。"
	case "remote_transport_required":
		return "正在通过远程通道连接这台 Mac，请稍后。"
	case "device_offline":
		return "目标 Mac 当前离线，请打开 Mac 端 AnnaCode 后重试。"
	case "waiting_for_approval":
		return "连接请求已发送，请在 Mac 端允许。"
	case "auto_accepted", "grant_accepted", "approved":
		return "连接已允许。"
	case "rejected", "manual_rejected", "user_rejected":
		return "Mac 端已拒绝本次连接。"
	default:
		if strings.ContainsAny(message, "_") || looksEnglish(message) {
			return "操作失败，请稍后重试。"
		}
		return message
	}
}

func remoteError(c *gin.Context, err error, fallback string) {
	if err == nil {
		response.ErrorMessage(fallback, c)
		return
	}
	msg := remoteUserMessage(err.Error())
	if msg == "操作失败，请稍后重试。" && fallback != "" {
		msg = fallback
	}
	response.ErrorMessage(msg, c)
}

func looksEnglish(message string) bool {
	latinRun := 0
	for _, r := range message {
		switch {
		case r >= 'A' && r <= 'Z', r >= 'a' && r <= 'z':
			latinRun++
			if latinRun >= 3 {
				return true
			}
		default:
			latinRun = 0
		}
	}
	return false
}

func (a *RemoteApi) RequestRegisterCode(c *gin.Context) {
	var req bizReq.RemoteVerificationCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.RequestRegisterCode(req)
	if err != nil {
		remoteError(c, err, "验证码发送失败，请稍后重试。")
		return
	}
	response.SuccessPayload(data, "验证码已发送", c)
}

func (a *RemoteApi) Register(c *gin.Context) {
	var req bizReq.RemoteAuthRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.Register(req)
	if err != nil {
		remoteError(c, err, "注册失败，请检查邮箱和密码后重试。")
		return
	}
	response.SuccessPayload(data, "注册成功", c)
}

func (a *RemoteApi) Login(c *gin.Context) {
	var req bizReq.RemoteAuthRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.Login(req, c.ClientIP(), c.Request.UserAgent())
	if err != nil {
		remoteError(c, err, "登录失败，请检查邮箱和密码。")
		return
	}
	response.SuccessPayload(data, "登录成功", c)
}

func (a *RemoteApi) Refresh(c *gin.Context) {
	var req bizReq.RemoteRefreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.Refresh(req, c.ClientIP(), c.Request.UserAgent())
	if err != nil {
		remoteError(c, err, "登录状态已失效，请重新登录。")
		return
	}
	response.SuccessPayload(data, "刷新成功", c)
}

func (a *RemoteApi) RequestPasswordResetCode(c *gin.Context) {
	var req bizReq.RemoteVerificationCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.RequestPasswordResetCode(req)
	if err != nil {
		remoteError(c, err, "验证码发送失败，请稍后重试。")
		return
	}
	response.SuccessPayload(data, "验证码已发送", c)
}

func (a *RemoteApi) ResetPassword(c *gin.Context) {
	var req bizReq.RemotePasswordResetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.ResetPassword(req)
	if err != nil {
		remoteError(c, err, "密码重置失败，请检查验证码后重试。")
		return
	}
	response.SuccessPayload(data, "重置成功", c)
}

func (a *RemoteApi) ChangePassword(c *gin.Context) {
	var req bizReq.RemoteChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ErrorMessage("参数错误", c)
		return
	}
	if err := remoteService.ChangePassword(utils.GetRemoteUserID(c), req); err != nil {
		remoteError(c, err, "密码修改失败，请检查原密码后重试。")
		return
	}
	response.SuccessMessage("修改成功", c)
}

func (a *RemoteApi) DeleteAccount(c *gin.Context) {
	var req bizReq.RemoteAccountDeletionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.DeleteAccount(utils.GetRemoteUserID(c), req, c.ClientIP(), c.Request.UserAgent())
	if err != nil {
		remoteError(c, err, "账号注销失败，请确认输入内容后重试。")
		return
	}
	response.SuccessPayload(data, "账号已注销", c)
}

func (a *RemoteApi) RegisterDevice(c *gin.Context) {
	var req bizReq.RemoteDeviceRegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.RegisterDevice(utils.GetRemoteUserID(c), req)
	if err != nil {
		remoteError(c, err, "设备注册失败，请稍后重试。")
		return
	}
	response.SuccessPayload(data, "注册成功", c)
}

func (a *RemoteApi) ListDevices(c *gin.Context) {
	data, err := remoteService.ListDeviceResponses(utils.GetRemoteUserID(c))
	if err != nil {
		remoteError(c, err, "设备列表加载失败，请刷新后重试。")
		return
	}
	response.SuccessPayload(data, "获取成功", c)
}

func (a *RemoteApi) GetDevice(c *gin.Context) {
	deviceID, ok := uintParam(c, "deviceId")
	if !ok {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.GetDeviceResponse(utils.GetRemoteUserID(c), deviceID)
	if err != nil {
		remoteError(c, err, "设备信息获取失败，请刷新后重试。")
		return
	}
	response.SuccessPayload(data, "获取成功", c)
}

func (a *RemoteApi) UpdateDevice(c *gin.Context) {
	deviceID, ok := uintParam(c, "deviceId")
	if !ok {
		response.ErrorMessage("参数错误", c)
		return
	}
	var req bizReq.RemoteDeviceUpdateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.UpdateDevice(utils.GetRemoteUserID(c), deviceID, req)
	if err != nil {
		remoteError(c, err, "设备设置保存失败，请稍后重试。")
		return
	}
	response.SuccessPayload(data, "更新成功", c)
}

func (a *RemoteApi) GetDeviceCode(c *gin.Context) {
	deviceID, ok := uintParam(c, "deviceId")
	if !ok {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.GetDeviceCode(utils.GetRemoteUserID(c), deviceID)
	if err != nil {
		remoteError(c, err, "设备码获取失败，请刷新后重试。")
		return
	}
	response.SuccessPayload(data, "获取成功", c)
}

func (a *RemoteApi) ResetDeviceCode(c *gin.Context) {
	deviceID, ok := uintParam(c, "deviceId")
	if !ok {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.ResetDeviceCode(utils.GetRemoteUserID(c), deviceID)
	if err != nil {
		remoteError(c, err, "设备码重置失败，请稍后重试。")
		return
	}
	response.SuccessPayload(data, "重置成功", c)
}

func (a *RemoteApi) ResolveDeviceCode(c *gin.Context) {
	var req bizReq.RemoteDeviceCodeResolveRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.ResolveDeviceCode(utils.GetRemoteUserID(c), req, c.ClientIP())
	if err != nil {
		remoteError(c, err, "设备码无效，请确认 Mac 端显示的设备码。")
		return
	}
	response.SuccessPayload(data, "解析成功", c)
}

func (a *RemoteApi) PublishLanToken(c *gin.Context) {
	deviceID, ok := uintParam(c, "deviceId")
	if !ok {
		response.ErrorMessage("参数错误", c)
		return
	}
	var req bizReq.RemoteLanTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.PublishLanToken(utils.GetRemoteUserID(c), deviceID, c.ClientIP(), req)
	if err != nil {
		remoteError(c, err, "局域网地址发布失败，请稍后重试。")
		return
	}
	response.SuccessPayload(data, "发布成功", c)
}

func (a *RemoteApi) Connect(c *gin.Context) {
	deviceID, ok := uintParam(c, "deviceId")
	if !ok {
		response.ErrorMessage("参数错误", c)
		return
	}
	var req bizReq.RemoteConnectRequest
	_ = c.ShouldBindJSON(&req)
	data, err := remoteService.Connect(utils.GetRemoteUserID(c), deviceID, req, c.ClientIP())
	if err != nil {
		remoteError(c, err, "连接请求失败，请稍后重试。")
		return
	}
	response.SuccessPayload(data, "连接请求已创建", c)
}

func (a *RemoteApi) GetICEServers(c *gin.Context) {
	connectionIDValue := c.Query("connectionId")
	connectionID64, err := strconv.ParseUint(connectionIDValue, 10, 64)
	if err != nil || connectionID64 == 0 {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.GetICEServers(utils.GetRemoteUserID(c), uint(connectionID64))
	if err != nil {
		remoteError(c, err, "远程连接信息获取失败，请稍后重试。")
		return
	}
	response.SuccessPayload(data, "获取成功", c)
}

func (a *RemoteApi) ListConnections(c *gin.Context) {
	data, err := remoteService.ListConnections(utils.GetRemoteUserID(c), c.Query("status"))
	if err != nil {
		remoteError(c, err, "连接记录加载失败，请刷新后重试。")
		return
	}
	response.SuccessPayload(data, "获取成功", c)
}

func (a *RemoteApi) GetConnection(c *gin.Context) {
	connectionID, ok := uintParam(c, "connectionId")
	if !ok {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.GetConnectionResponse(utils.GetRemoteUserID(c), connectionID)
	if err != nil {
		remoteError(c, err, "连接记录获取失败，请刷新后重试。")
		return
	}
	response.SuccessPayload(data, "获取成功", c)
}

func (a *RemoteApi) ReportConnectionMetrics(c *gin.Context) {
	connectionID, ok := uintParam(c, "connectionId")
	if !ok {
		response.ErrorMessage("参数错误", c)
		return
	}
	var req bizReq.RemoteConnectionMetricsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.ReportConnectionMetrics(utils.GetRemoteUserID(c), connectionID, req)
	if err != nil {
		remoteError(c, err, "连接状态上报失败，请稍后重试。")
		return
	}
	response.SuccessPayload(data, "上报成功", c)
}

func (a *RemoteApi) ApproveConnection(c *gin.Context) {
	a.decideConnection(c, true)
}

func (a *RemoteApi) RejectConnection(c *gin.Context) {
	a.decideConnection(c, false)
}

func (a *RemoteApi) GetLegalDocument(c *gin.Context) {
	data, err := remoteService.GetLegalDocument(c.Query("type"), c.DefaultQuery("platform", "all"))
	if err != nil {
		remoteError(c, err, "协议内容加载失败，请稍后重试。")
		return
	}
	response.SuccessPayload(data, "获取成功", c)
}

func (a *RemoteApi) GetAppFooter(c *gin.Context) {
	data, err := remoteService.GetAppFooter(c.DefaultQuery("platform", "ios"))
	if err != nil {
		remoteError(c, err, "页脚信息加载失败，请稍后重试。")
		return
	}
	response.SuccessPayload(data, "获取成功", c)
}

func (a *RemoteApi) CheckAppUpdate(c *gin.Context) {
	req := bizReq.RemoteAppUpdateCheckRequest{
		Platform:    c.Query("platform"),
		Channel:     c.Query("channel"),
		Version:     c.Query("version"),
		BuildNumber: c.Query("buildNumber"),
		PackageArch: c.Query("arch"),
	}
	data, err := remoteService.CheckAppUpdate(req)
	if err != nil {
		remoteError(c, err, "版本信息加载失败，请稍后重试。")
		return
	}
	response.SuccessPayload(data, "获取成功", c)
}

func (a *RemoteApi) ConsentLegal(c *gin.Context) {
	var req bizReq.RemoteLegalConsentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.ConsentLegal(utils.GetRemoteUserID(c), req)
	if err != nil {
		remoteError(c, err, "协议确认失败，请稍后重试。")
		return
	}
	response.SuccessPayload(data, "提交成功", c)
}

func (a *RemoteApi) GetSubscription(c *gin.Context) {
	data, err := remoteService.GetSubscription(utils.GetRemoteUserID(c))
	if err != nil {
		remoteError(c, err, "服务状态获取失败，请稍后重试。")
		return
	}
	response.SuccessPayload(data, "获取成功", c)
}

func (a *RemoteApi) ListSubscriptionPlans(c *gin.Context) {
	data, err := remoteService.ListSubscriptionPlans()
	if err != nil {
		remoteError(c, err, "服务状态列表加载失败，请稍后重试。")
		return
	}
	response.SuccessPayload(data, "获取成功", c)
}

func (a *RemoteApi) CreateSubscriptionOrder(c *gin.Context) {
	var req bizReq.RemoteSubscriptionOrderCreateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.ErrorMessage("参数错误", c)
		return
	}
	data, err := remoteService.CreateSubscriptionOrder(c.Request.Context(), utils.GetRemoteUserID(c), req)
	if err != nil {
		remoteError(c, err, "服务开通流程创建失败，请稍后重试。")
		return
	}
	response.SuccessPayload(data, "请求已创建", c)
}

func (a *RemoteApi) GetSubscriptionOrder(c *gin.Context) {
	data, err := remoteService.GetSubscriptionOrder(utils.GetRemoteUserID(c), c.Param("outTradeNo"))
	if err != nil {
		remoteError(c, err, "服务开通记录获取失败，请刷新后重试。")
		return
	}
	response.SuccessPayload(data, "获取成功", c)
}

func (a *RemoteApi) PaymentNotify(c *gin.Context) {
	body, err := io.ReadAll(io.LimitReader(c.Request.Body, 1<<20))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "msg": "bad body"})
		return
	}
	headers := map[string]string{
		"event_id":   c.GetHeader("X-Heyupay-Event-Id"),
		"event_kind": c.GetHeader("X-Heyupay-Event-Kind"),
		"timestamp":  c.GetHeader("X-Heyupay-Timestamp"),
		"nonce":      c.GetHeader("X-Heyupay-Nonce"),
		"signature":  c.GetHeader("X-Heyupay-Signature"),
	}
	if err := remoteService.HandlePaymentNotify(c.Request.URL.Path, c.Request.URL.Query(), headers, body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "msg": "bad sign"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"code": 0, "msg": "ok"})
}

func (a *RemoteApi) decideConnection(c *gin.Context, accepted bool) {
	connectionID, ok := uintParam(c, "connectionId")
	if !ok {
		response.ErrorMessage("参数错误", c)
		return
	}
	var req bizReq.RemoteConnectionDecisionRequest
	_ = c.ShouldBindJSON(&req)
	data, err := remoteService.DecideConnection(utils.GetRemoteUserID(c), connectionID, accepted, req, c.ClientIP())
	if err != nil {
		remoteError(c, err, "连接处理失败，请刷新后重试。")
		return
	}
	response.SuccessPayload(data, "处理成功", c)
}

func uintParam(c *gin.Context, name string) (uint, bool) {
	value, err := strconv.ParseUint(c.Param(name), 10, 64)
	if err != nil || value == 0 {
		return 0, false
	}
	return uint(value), true
}
