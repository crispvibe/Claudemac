package biz

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"mime"
	"net"
	"net/mail"
	"net/smtp"
	"strconv"
	"strings"
	"time"

	"gorm.io/gorm"
	"heyu/server/global"
	modelBiz "heyu/server/model/biz"
	bizReq "heyu/server/model/biz/request"
	bizRes "heyu/server/model/biz/response"
	"heyu/server/model/shared"
	"heyu/server/utils"
)

type RemoteService struct{}

const (
	remoteStatusActive         = "active"
	remoteDeviceTypeDesktop    = "desktop"
	remoteApprovalAlwaysAsk    = "always_ask"
	remoteApprovalAllowAnyone  = "allow_anyone"
	remoteConnectionPending    = "pending"
	remoteConnectionAccepted   = "accepted"
	remoteConnectionRejected   = "rejected"
	remoteAuthPurposeRegister  = "register_code"
	remoteAuthPurposeLogin     = "login_code"
	remoteAuthPurposePassword  = "password_reset"
	remoteAuthCodeValidity     = 10 * time.Minute
	remoteAuthCodeDigits       = 6
	remoteRegisterTrialDuration = 24 * time.Hour
	remoteLanTransport         = "lan"
	remoteP2PTransport         = "p2p"
	remoteTunnelTransport      = "tunnel"
	remoteReasonRemoteRequired = "remote_transport_required"
	remoteReasonDeviceOffline  = "device_offline"
	remoteLanTokenMaxValidity  = 15 * time.Minute
	remoteDeleteConfirmAccount = "我确认注销账号"
	remoteDeleteConfirmDestroy = "确认销毁"
	remoteDeleteConfirmWaive   = "不要这些权益"
	remoteDeleteConfirmCleanup = "确认清理远程连接数据"
)

var remoteSendAuthCodeEmail = sendRemoteAuthCodeEmail

// remoteRegisterEmailDomains 限定注册仅支持 QQ / 163 邮箱，避免一次性邮箱薅免费试用。
var remoteRegisterEmailDomains = map[string]struct{}{
	"qq.com":  {},
	"163.com": {},
}

// assertRegisterableEmail 校验邮箱是否允许注册：仅限 QQ/163 主域名，且不接受带 "+" 的别名地址。
func assertRegisterableEmail(email string) error {
	at := strings.LastIndex(email, "@")
	if at <= 0 || at >= len(email)-1 {
		return errors.New("请输入正确的邮箱地址。")
	}
	local := email[:at]
	domain := email[at+1:]
	if _, ok := remoteRegisterEmailDomains[domain]; !ok {
		return errors.New("仅支持 QQ 邮箱（@qq.com）或 163 邮箱（@163.com）注册。")
	}
	if strings.Contains(local, "+") {
		return errors.New("不支持别名邮箱，请使用真实的 QQ 或 163 邮箱注册。")
	}
	return nil
}

// RequestRegisterCode 发送注册邮箱验证码。仅允许 QQ/163 邮箱、且未注册过的邮箱，
// 以此结合验证码防止恶意批量注册薅免费试用。
func (s *RemoteService) RequestRegisterCode(req bizReq.RemoteVerificationCodeRequest) (bizRes.RemoteVerificationCodeResponse, error) {
	identity, isEmail, err := normalizeRemoteIdentity(req.Email, req.Phone)
	if err != nil {
		return bizRes.RemoteVerificationCodeResponse{}, err
	}
	if err := assertRegisterableEmail(identity); err != nil {
		return bizRes.RemoteVerificationCodeResponse{}, err
	}
	var existing modelBiz.RemoteUser
	if err := remoteUserIdentityQuery(identity, isEmail).First(&existing).Error; err == nil {
		return bizRes.RemoteVerificationCodeResponse{}, errors.New("这个邮箱已经注册，请直接登录。")
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		return bizRes.RemoteVerificationCodeResponse{}, err
	}
	return s.issueAuthCode(identity, isEmail, remoteAuthPurposeRegister)
}

func (s *RemoteService) Register(req bizReq.RemoteAuthRequest) (bizRes.RemoteAuthResponse, error) {
	identity, isEmail, err := normalizeRemoteIdentity(req.Email, req.Phone)
	if err != nil {
		return bizRes.RemoteAuthResponse{}, err
	}
	if err := assertRegisterableEmail(identity); err != nil {
		return bizRes.RemoteAuthResponse{}, err
	}
	code := strings.TrimSpace(req.VerificationCode)
	if code == "" {
		return bizRes.RemoteAuthResponse{}, errors.New("请填写邮箱和验证码。")
	}
	var existing modelBiz.RemoteUser
	if err := remoteUserIdentityQuery(identity, isEmail).First(&existing).Error; err == nil {
		return bizRes.RemoteAuthResponse{}, errors.New("这个邮箱已经注册，请直接登录。")
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		return bizRes.RemoteAuthResponse{}, err
	}
	// 账号体系改为「邮箱 + 验证码」登录，不再使用密码，PasswordHash 字段保留但置空（已弃用）。
	user := modelBiz.RemoteUser{Status: remoteStatusActive}
	if isEmail {
		user.Email = identity
		user.Phone = remoteEmailPhonePlaceholder(identity)
	} else {
		user.Phone = identity
	}
	if err := global.AppDB.Transaction(func(tx *gorm.DB) error {
		if err := s.consumeAuthCodeWithDB(tx, identity, isEmail, remoteAuthPurposeRegister, code); err != nil {
			return err
		}
		if err := tx.Create(&user).Error; err != nil {
			return err
		}
		// 免费注册即赠送 1 天免费试用权益。
		return grantRegistrationTrial(tx, user.ID)
	}); err != nil {
		return bizRes.RemoteAuthResponse{}, err
	}
	return s.issueTokens(user)
}

// RequestLoginCode 向已注册邮箱发送登录验证码。
func (s *RemoteService) RequestLoginCode(req bizReq.RemoteVerificationCodeRequest) (bizRes.RemoteVerificationCodeResponse, error) {
	identity, isEmail, err := normalizeRemoteIdentity(req.Email, req.Phone)
	if err != nil {
		return bizRes.RemoteVerificationCodeResponse{}, err
	}
	var user modelBiz.RemoteUser
	if err := remoteUserIdentityQuery(identity, isEmail).First(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return bizRes.RemoteVerificationCodeResponse{}, errors.New("这个邮箱还没有注册，请先注册。")
		}
		return bizRes.RemoteVerificationCodeResponse{}, err
	}
	if user.Status != remoteStatusActive {
		return bizRes.RemoteVerificationCodeResponse{}, errors.New("账号已禁用，请联系管理员。")
	}
	return s.issueAuthCode(identity, isEmail, remoteAuthPurposeLogin)
}

// Login 改为「邮箱 + 验证码」登录，不再校验密码。
func (s *RemoteService) Login(req bizReq.RemoteAuthRequest, clientIP, userAgent string) (bizRes.RemoteAuthResponse, error) {
	identity, isEmail, err := normalizeRemoteIdentity(req.Email, req.Phone)
	if err != nil {
		return bizRes.RemoteAuthResponse{}, err
	}
	code := strings.TrimSpace(req.VerificationCode)
	if code == "" {
		return bizRes.RemoteAuthResponse{}, errors.New("请填写邮箱和验证码。")
	}
	var user modelBiz.RemoteUser
	if err := remoteUserIdentityQuery(identity, isEmail).First(&user).Error; err != nil {
		RecordRemoteAudit(nil, nil, nil, "remote.login", "failed", "user not found", clientIP, userAgent)
		return bizRes.RemoteAuthResponse{}, errors.New("这个邮箱还没有注册，请先注册。")
	}
	if user.Status != remoteStatusActive {
		RecordRemoteAudit(&user.ID, nil, nil, "remote.login", "failed", "user disabled", clientIP, userAgent)
		return bizRes.RemoteAuthResponse{}, errors.New("账号已禁用，请联系管理员。")
	}
	if err := s.consumeAuthCode(identity, isEmail, remoteAuthPurposeLogin, code); err != nil {
		RecordRemoteAudit(&user.ID, nil, nil, "remote.login", "failed", "invalid code", clientIP, userAgent)
		return bizRes.RemoteAuthResponse{}, err
	}
	now := time.Now()
	global.AppDB.Model(&user).Update("last_login_at", now)
	user.LastLoginAt = &now
	response, err := s.issueTokens(user)
	if err != nil {
		RecordRemoteAudit(&user.ID, nil, nil, "remote.login", "failed", "issue tokens failed", clientIP, userAgent)
		return bizRes.RemoteAuthResponse{}, err
	}
	RecordRemoteAudit(&user.ID, nil, nil, "remote.login", "success", "login succeeded", clientIP, userAgent)
	return response, nil
}

func (s *RemoteService) Refresh(req bizReq.RemoteRefreshRequest, clientIP, userAgent string) (bizRes.RemoteAuthResponse, error) {
	hash := hashString(req.RefreshToken)
	var token modelBiz.RemoteUserToken
	if err := global.AppDB.Where("token_hash = ? AND token_type = ?", hash, "refresh").First(&token).Error; err != nil {
		RecordRemoteAudit(nil, nil, nil, "remote.refresh", "failed", "refresh token not found", clientIP, userAgent)
		return bizRes.RemoteAuthResponse{}, errors.New("刷新令牌无效")
	}
	if token.RevokedAt != nil || time.Now().After(token.ExpiresAt) {
		RecordRemoteAudit(&token.UserID, nil, nil, "remote.refresh", "failed", "refresh token expired or revoked", clientIP, userAgent)
		return bizRes.RemoteAuthResponse{}, errors.New("刷新令牌已失效")
	}
	var user modelBiz.RemoteUser
	if err := global.AppDB.First(&user, token.UserID).Error; err != nil {
		RecordRemoteAudit(&token.UserID, nil, nil, "remote.refresh", "failed", "user not found", clientIP, userAgent)
		return bizRes.RemoteAuthResponse{}, err
	}
	if user.Status != remoteStatusActive {
		RecordRemoteAudit(&user.ID, nil, nil, "remote.refresh", "failed", "user disabled", clientIP, userAgent)
		return bizRes.RemoteAuthResponse{}, errors.New("账号已禁用")
	}
	now := time.Now()
	global.AppDB.Model(&token).Updates(map[string]any{"last_used_at": now, "revoked_at": now})
	response, err := s.issueTokens(user)
	if err != nil {
		RecordRemoteAudit(&user.ID, nil, nil, "remote.refresh", "failed", "issue tokens failed", clientIP, userAgent)
		return bizRes.RemoteAuthResponse{}, err
	}
	RecordRemoteAudit(&user.ID, nil, nil, "remote.refresh", "success", "refresh succeeded", clientIP, userAgent)
	return response, nil
}

func (s *RemoteService) DeleteAccount(userID uint, req bizReq.RemoteAccountDeletionRequest, clientIP, userAgent string) (bizRes.RemoteAccountDeletionResponse, error) {
	if strings.TrimSpace(req.ConfirmAccount) != remoteDeleteConfirmAccount ||
		strings.TrimSpace(req.ConfirmDestroy) != remoteDeleteConfirmDestroy ||
		!isValidRemoteDeletionFinalConfirm(req.ConfirmWaiveRights) {
		return bizRes.RemoteAccountDeletionResponse{}, errors.New("请按提示完整输入注销确认内容。")
	}

	var user modelBiz.RemoteUser
	if err := global.AppDB.First(&user, userID).Error; err != nil {
		return bizRes.RemoteAccountDeletionResponse{}, err
	}

	deletedAt := time.Now()
	record, err := s.buildDeletionRecord(user, req, deletedAt)
	if err != nil {
		return bizRes.RemoteAccountDeletionResponse{}, err
	}

	err = global.AppDB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&record).Error; err != nil {
			return err
		}
		if err := DeleteRemoteAccountData(tx, user); err != nil {
			return err
		}
		if err := tx.Unscoped().Delete(&user).Error; err != nil {
			return err
		}
		return nil
	})
	if err != nil {
		RecordRemoteAudit(&userID, nil, nil, "remote.account_delete", "failed", "account deletion failed", clientIP, userAgent)
		return bizRes.RemoteAccountDeletionResponse{}, err
	}

	SharedRemoteSignalingService.KickUser(userID)
	return bizRes.RemoteAccountDeletionResponse{RecordID: record.ID, DeletedAt: deletedAt}, nil
}

func (s *RemoteService) RegisterDevice(userID uint, req bizReq.RemoteDeviceRegisterRequest) (modelBiz.RemoteDevice, error) {
	deviceUID := strings.TrimSpace(req.DeviceUID)
	deviceName := strings.TrimSpace(req.DeviceName)
	deviceType := strings.TrimSpace(req.DeviceType)
	platform := strings.TrimSpace(req.Platform)
	devicePublicKey := strings.TrimSpace(req.DevicePublicKey)
	if deviceUID == "" || deviceName == "" || deviceType == "" || platform == "" || devicePublicKey == "" {
		return modelBiz.RemoteDevice{}, errors.New("设备信息不完整")
	}
	now := time.Now()
	var device modelBiz.RemoteDevice
	if err := global.AppDB.Where("device_uid = ?", deviceUID).First(&device).Error; err == nil {
		if device.UserID != userID {
			return modelBiz.RemoteDevice{}, errors.New("设备已绑定其他账号")
		}
		updates := map[string]any{
			"device_type":       deviceType,
			"platform":          platform,
			"device_name":       deviceName,
			"device_public_key": devicePublicKey,
			"app_version":       strings.TrimSpace(req.AppVersion),
			"last_seen_at":      now,
			"updated_at":        now,
		}
		if err := global.AppDB.Model(&device).Updates(updates).Error; err != nil {
			return modelBiz.RemoteDevice{}, err
		}
		return s.GetDevice(userID, device.ID)
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		return modelBiz.RemoteDevice{}, err
	}
	device = modelBiz.RemoteDevice{
		UserID:          userID,
		DeviceUID:       deviceUID,
		DeviceType:      deviceType,
		Platform:        platform,
		DeviceName:      deviceName,
		DevicePublicKey: devicePublicKey,
		ApprovalPolicy:  remoteApprovalAlwaysAsk,
		RemoteEnabled:   true,
		Status:          remoteStatusActive,
		AppVersion:      strings.TrimSpace(req.AppVersion),
		LastSeenAt:      &now,
	}
	err := global.AppDB.Create(&device).Error
	return device, err
}

func (s *RemoteService) ListDevices(userID uint) ([]modelBiz.RemoteDevice, error) {
	var devices []modelBiz.RemoteDevice
	err := global.AppDB.Where("user_id = ?", userID).Order("updated_at desc").Find(&devices).Error
	return devices, err
}

func (s *RemoteService) ListDeviceResponses(userID uint) ([]bizRes.RemoteDeviceResponse, error) {
	devices, err := s.ListDevices(userID)
	if err != nil {
		return nil, err
	}
	responses := make([]bizRes.RemoteDeviceResponse, 0, len(devices))
	for _, device := range devices {
		response := bizRes.RemoteDeviceFromModel(device, true, true)
		response.Online = SharedRemoteSignalingService.IsDeviceOnline(device.ID)
		responses = append(responses, response)
	}
	return responses, nil
}

func (s *RemoteService) GetDevice(userID, deviceID uint) (modelBiz.RemoteDevice, error) {
	var device modelBiz.RemoteDevice
	err := global.AppDB.Where("id = ? AND user_id = ?", deviceID, userID).First(&device).Error
	return device, err
}

func (s *RemoteService) GetDeviceResponse(userID, deviceID uint) (bizRes.RemoteDeviceResponse, error) {
	device, err := s.GetDevice(userID, deviceID)
	if err != nil {
		return bizRes.RemoteDeviceResponse{}, err
	}
	response := bizRes.RemoteDeviceFromModel(device, true, true)
	response.Online = SharedRemoteSignalingService.IsDeviceOnline(device.ID)
	return response, nil
}

func (s *RemoteService) UpdateDevice(userID, deviceID uint, req bizReq.RemoteDeviceUpdateRequest) (modelBiz.RemoteDevice, error) {
	device, err := s.GetDevice(userID, deviceID)
	if err != nil {
		return modelBiz.RemoteDevice{}, err
	}
	updates := map[string]any{}
	if strings.TrimSpace(req.DeviceName) != "" {
		updates["device_name"] = strings.TrimSpace(req.DeviceName)
	}
	if req.ApprovalPolicy == remoteApprovalAlwaysAsk || req.ApprovalPolicy == remoteApprovalAllowAnyone {
		updates["approval_policy"] = req.ApprovalPolicy
	}
	if req.RemoteEnabled != nil {
		updates["remote_enabled"] = *req.RemoteEnabled
	}
	if req.Status == remoteStatusActive || req.Status == "disabled" {
		updates["status"] = req.Status
	}
	if strings.TrimSpace(req.AppVersion) != "" {
		updates["app_version"] = strings.TrimSpace(req.AppVersion)
	}
	if len(updates) > 0 {
		if err := global.AppDB.Model(&device).Updates(updates).Error; err != nil {
			return modelBiz.RemoteDevice{}, err
		}
	}
	return s.GetDevice(userID, deviceID)
}

func (s *RemoteService) ResetDeviceCode(userID, deviceID uint) (bizRes.RemoteDeviceCodeResponse, error) {
	device, err := s.GetDevice(userID, deviceID)
	if err != nil {
		return bizRes.RemoteDeviceCodeResponse{}, err
	}
	if device.DeviceType != remoteDeviceTypeDesktop {
		return bizRes.RemoteDeviceCodeResponse{}, errors.New("只有桌面设备支持设备码")
	}
	code, err := randomCode(10)
	if err != nil {
		return bizRes.RemoteDeviceCodeResponse{}, err
	}
	hint := code[len(code)-4:]
	if err := global.AppDB.Model(&device).Updates(map[string]any{"device_code_hash": hashString(code), "device_code_hint": hint}).Error; err != nil {
		return bizRes.RemoteDeviceCodeResponse{}, err
	}
	return bizRes.RemoteDeviceCodeResponse{DeviceCode: code, Hint: hint}, nil
}

func (s *RemoteService) GetDeviceCode(userID, deviceID uint) (bizRes.RemoteDeviceCodeResponse, error) {
	device, err := s.GetDevice(userID, deviceID)
	if err != nil {
		return bizRes.RemoteDeviceCodeResponse{}, err
	}
	if device.DeviceCodeHash == "" {
		return s.ResetDeviceCode(userID, deviceID)
	}
	return bizRes.RemoteDeviceCodeResponse{Hint: device.DeviceCodeHint}, nil
}

func (s *RemoteService) ResolveDeviceCode(userID uint, req bizReq.RemoteDeviceCodeResolveRequest, ip string) (bizRes.RemoteDeviceResolveResponse, error) {
	code := strings.TrimSpace(req.DeviceCode)
	if code == "" {
		return bizRes.RemoteDeviceResolveResponse{}, errors.New("设备码不能为空")
	}
	codeHash := hashString(code)
	prefix := codeHash
	if len(prefix) > 16 {
		prefix = prefix[:16]
	}
	attempt := modelBiz.RemoteDeviceCodeAttempt{FromUserID: &userID, CodeHashPrefix: prefix, IPHash: hashString(ip)}
	if req.FromDeviceID > 0 {
		fromDeviceID, err := s.validFromDeviceID(userID, req.FromDeviceID)
		if err != nil {
			attempt.Status = "failed"
			attempt.FailureReason = "invalid_from_device"
			global.AppDB.Create(&attempt)
			return bizRes.RemoteDeviceResolveResponse{}, err
		}
		attempt.FromDeviceID = fromDeviceID
	}
	var device modelBiz.RemoteDevice
	err := global.AppDB.Where("device_code_hash = ?", codeHash).First(&device).Error
	if err != nil {
		attempt.Status = "failed"
		attempt.FailureReason = "not_found"
		global.AppDB.Create(&attempt)
		return bizRes.RemoteDeviceResolveResponse{}, errors.New("设备码无效")
	}
	if device.DeviceType != remoteDeviceTypeDesktop || !device.RemoteEnabled || device.Status != remoteStatusActive {
		attempt.Status = "failed"
		attempt.TargetDeviceID = &device.ID
		attempt.FailureReason = "device_unavailable"
		global.AppDB.Create(&attempt)
		return bizRes.RemoteDeviceResolveResponse{}, errors.New("目标设备不可连接")
	}
	attempt.Status = "success"
	attempt.TargetDeviceID = &device.ID
	global.AppDB.Create(&attempt)
	return bizRes.RemoteDeviceResolveResponse{DeviceID: device.ID, DeviceName: device.DeviceName, Platform: device.Platform, ApprovalPolicy: device.ApprovalPolicy, RequiresConfirm: device.UserID != userID && device.ApprovalPolicy != remoteApprovalAllowAnyone}, nil
}

func (s *RemoteService) PublishLanToken(userID, deviceID uint, clientIP string, req bizReq.RemoteLanTokenRequest) (bizRes.RemoteDeviceResponse, error) {
	device, err := s.GetDevice(userID, deviceID)
	if err != nil {
		return bizRes.RemoteDeviceResponse{}, err
	}
	if device.DeviceType != remoteDeviceTypeDesktop {
		return bizRes.RemoteDeviceResponse{}, errors.New("只有桌面设备可以发布局域网地址")
	}
	ip := strings.TrimSpace(req.IP)
	token := strings.TrimSpace(req.TransientToken)
	if ip == "" || req.Port < 1 || req.Port > 65535 || token == "" {
		return bizRes.RemoteDeviceResponse{}, errors.New("局域网地址参数不完整")
	}
	if net.ParseIP(ip) == nil {
		return bizRes.RemoteDeviceResponse{}, errors.New("局域网地址无效")
	}
	expiresAt := remoteLanTokenExpiry(req.ExpiresAt)
	now := time.Now()
	if !expiresAt.After(now) {
		return bizRes.RemoteDeviceResponse{}, errors.New("令牌已过期")
	}
	maxExpiry := now.Add(remoteLanTokenMaxValidity)
	if expiresAt.After(maxExpiry) {
		expiresAt = maxExpiry
	}
	updates := map[string]any{
		"lan_ip":                    ip,
		"lan_port":                  req.Port,
		"lan_token":                 token,
		"lan_token_expires_at":      expiresAt,
		"lan_endpoint_last_seen_at": now,
		"lan_publisher_ip_hash":     hashString(normalizeClientIPForLanMatch(clientIP)),
		"updated_at":                now,
	}
	if err := global.AppDB.Model(&device).Updates(updates).Error; err != nil {
		return bizRes.RemoteDeviceResponse{}, err
	}
	device, err = s.GetDevice(userID, deviceID)
	if err != nil {
		return bizRes.RemoteDeviceResponse{}, err
	}
	response := bizRes.RemoteDeviceFromModel(device, true, true)
	response.Online = SharedRemoteSignalingService.IsDeviceOnline(device.ID)
	return response, nil
}

func (s *RemoteService) Connect(userID, targetDeviceID uint, req bizReq.RemoteConnectRequest, clientIP string) (bizRes.RemoteConnectionResponse, error) {
	var target modelBiz.RemoteDevice
	if err := global.AppDB.First(&target, targetDeviceID).Error; err != nil {
		return bizRes.RemoteConnectionResponse{}, err
	}
	if target.DeviceType != remoteDeviceTypeDesktop || !target.RemoteEnabled || target.Status != remoteStatusActive {
		return bizRes.RemoteConnectionResponse{}, errors.New("目标设备不可连接")
	}
	if req.FromDeviceID == 0 {
		return bizRes.RemoteConnectionResponse{}, errors.New("发起设备不能为空")
	}
	fromDeviceID, err := s.validFromDeviceID(userID, req.FromDeviceID)
	if err != nil {
		return bizRes.RemoteConnectionResponse{}, err
	}
	status := remoteConnectionPending
	reason := "waiting_for_approval"
	var grantID *uint
	if target.UserID == userID || target.ApprovalPolicy == remoteApprovalAllowAnyone {
		status = remoteConnectionAccepted
		reason = "auto_accepted"
	} else if grant, ok := s.activeGrant(target.ID, userID, fromDeviceID); ok {
		status = remoteConnectionAccepted
		reason = "grant_accepted"
		grantID = &grant.ID
		now := time.Now()
		global.AppDB.Model(&grant).Updates(map[string]any{"last_used_at": now, "updated_at": now})
	}
	conn := modelBiz.RemoteConnectionAttempt{FromUserID: userID, FromDeviceID: fromDeviceID, ToUserID: target.UserID, ToDeviceID: target.ID, GrantID: grantID, Status: status, Reason: reason}
	if status == remoteConnectionAccepted {
		now := time.Now()
		conn.CompletedAt = &now
	}
	if err := global.AppDB.Create(&conn).Error; err != nil {
		return bizRes.RemoteConnectionResponse{}, err
	}
	result := bizRes.RemoteConnectionFromModel(conn)
	if status == remoteConnectionAccepted {
		var err error
		conn, result, err = s.finalizeAcceptedConnection(conn, target, clientIP)
		if err != nil {
			return bizRes.RemoteConnectionResponse{}, err
		}
	}
	RecordRemoteAudit(&userID, fromDeviceID, &conn.ID, "remote.connect", auditStatusForConnection(conn.Status), conn.Status+":"+conn.Reason, clientIP, "")
	if conn.Status == remoteConnectionPending {
		SharedRemoteSignalingService.PushPendingConnect(conn)
	} else if conn.Status == remoteConnectionAccepted || conn.Status == remoteConnectionRejected {
		SharedRemoteSignalingService.PushConnectDecisionResponse(conn, result)
	}
	return result, nil
}

func (s *RemoteService) GetConnection(userID, connectionID uint) (modelBiz.RemoteConnectionAttempt, error) {
	var conn modelBiz.RemoteConnectionAttempt
	err := global.AppDB.Where("id = ? AND (from_user_id = ? OR to_user_id = ?)", connectionID, userID, userID).First(&conn).Error
	return conn, err
}

func (s *RemoteService) GetConnectionResponse(userID, connectionID uint) (bizRes.RemoteConnectionResponse, error) {
	conn, err := s.GetConnection(userID, connectionID)
	if err != nil {
		return bizRes.RemoteConnectionResponse{}, err
	}
	return bizRes.RemoteConnectionFromModel(conn), nil
}

func (s *RemoteService) ListConnections(userID uint, status string) ([]bizRes.RemoteConnectionResponse, error) {
	query := global.AppDB.Where("from_user_id = ? OR to_user_id = ?", userID, userID)
	if strings.TrimSpace(status) != "" {
		query = query.Where("status = ?", strings.TrimSpace(status))
	}
	var conns []modelBiz.RemoteConnectionAttempt
	if err := query.Order("updated_at desc").Limit(100).Find(&conns).Error; err != nil {
		return nil, err
	}
	responses := make([]bizRes.RemoteConnectionResponse, 0, len(conns))
	for _, conn := range conns {
		responses = append(responses, bizRes.RemoteConnectionFromModel(conn))
	}
	return responses, nil
}

func (s *RemoteService) ReportConnectionMetrics(userID, connectionID uint, req bizReq.RemoteConnectionMetricsRequest) (bizRes.RemoteConnectionResponse, error) {
	conn, err := s.GetConnection(userID, connectionID)
	if err != nil {
		return bizRes.RemoteConnectionResponse{}, err
	}
	updates := map[string]any{}
	transport := strings.TrimSpace(req.Transport)
	if transport == remoteLanTransport || transport == remoteP2PTransport || transport == remoteTunnelTransport {
		updates["transport"] = transport
		conn.Transport = transport
	}
	if req.FirstPacketLatencyMS != nil && *req.FirstPacketLatencyMS >= 0 && conn.FirstPacketLatencyMS == nil {
		now := time.Now()
		updates["first_packet_latency_ms"] = *req.FirstPacketLatencyMS
		updates["first_packet_at"] = now
		conn.FirstPacketLatencyMS = req.FirstPacketLatencyMS
		conn.FirstPacketAt = &now
	}
	if networkType := strings.TrimSpace(req.NetworkType); networkType != "" {
		updates["network_type"] = truncateRemoteMetricValue(networkType)
	}
	if appVersion := strings.TrimSpace(req.AppVersion); appVersion != "" {
		updates["app_version"] = truncateRemoteMetricValue(appVersion)
	}
	if requestID := strings.TrimSpace(req.RequestID); requestID != "" {
		updates["request_id"] = truncateRemoteMetricValue(requestID)
	}
	if len(updates) == 0 {
		RecordRemoteAudit(&userID, conn.FromDeviceID, &conn.ID, "remote.metrics", "success", "no metric changes", "", "")
		return bizRes.RemoteConnectionFromModel(conn), nil
	}
	updates["updated_at"] = time.Now()
	if err := global.AppDB.Model(&conn).Updates(updates).Error; err != nil {
		RecordRemoteAudit(&userID, conn.FromDeviceID, &conn.ID, "remote.metrics", "failed", "metrics update failed", "", "")
		return bizRes.RemoteConnectionResponse{}, err
	}
	RecordRemoteAudit(&userID, conn.FromDeviceID, &conn.ID, "remote.metrics", "success", "metrics reported", "", "")
	return s.GetConnectionResponse(userID, connectionID)
}

func (s *RemoteService) DecideConnection(userID, connectionID uint, accepted bool, req bizReq.RemoteConnectionDecisionRequest, clientIP string) (bizRes.RemoteConnectionResponse, error) {
	conn, err := s.GetConnection(userID, connectionID)
	if err != nil {
		return bizRes.RemoteConnectionResponse{}, err
	}
	if conn.ToUserID != userID {
		return bizRes.RemoteConnectionResponse{}, errors.New("无权处理该连接")
	}
	if conn.Status != remoteConnectionPending {
		return bizRes.RemoteConnectionResponse{}, errors.New("连接状态不可处理")
	}
	status := remoteConnectionRejected
	if accepted {
		status = remoteConnectionAccepted
	}
	now := time.Now()
	reason := strings.TrimSpace(req.Reason)
	if reason == "" {
		if accepted {
			reason = "approved"
		} else {
			reason = "rejected"
		}
	}
	updates := map[string]any{"status": status, "reason": reason, "completed_at": now}
	if accepted && req.Remember {
		grant := modelBiz.RemoteDeviceGrant{OwnerUserID: conn.ToUserID, TargetDeviceID: conn.ToDeviceID, GranteeUserID: conn.FromUserID, GranteeDeviceID: conn.FromDeviceID, Scope: "chat_only", GrantType: "device_code", Remembered: true, Status: remoteStatusActive}
		if err := global.AppDB.Create(&grant).Error; err != nil {
			return bizRes.RemoteConnectionResponse{}, err
		}
		updates["grant_id"] = grant.ID
	}
	if err := global.AppDB.Model(&conn).Updates(updates).Error; err != nil {
		return bizRes.RemoteConnectionResponse{}, err
	}
	updated, err := s.GetConnection(userID, connectionID)
	if err != nil {
		return bizRes.RemoteConnectionResponse{}, err
	}
	result := bizRes.RemoteConnectionFromModel(updated)
	if accepted {
		var target modelBiz.RemoteDevice
		if err := global.AppDB.First(&target, updated.ToDeviceID).Error; err != nil {
			return bizRes.RemoteConnectionResponse{}, err
		}
		updated, result, err = s.finalizeAcceptedConnection(updated, target, clientIP)
		if err != nil {
			return bizRes.RemoteConnectionResponse{}, err
		}
	}
	RecordRemoteAudit(&userID, &updated.ToDeviceID, &updated.ID, "remote.connection_decision", auditStatusForConnection(updated.Status), updated.Status+":"+updated.Reason, clientIP, "")
	SharedRemoteSignalingService.PushConnectDecisionResponse(updated, result)
	return result, nil
}

func (s *RemoteService) finalizeAcceptedConnection(conn modelBiz.RemoteConnectionAttempt, target modelBiz.RemoteDevice, clientIP string) (modelBiz.RemoteConnectionAttempt, bizRes.RemoteConnectionResponse, error) {
	now := time.Now()
	updates := map[string]any{"status": remoteConnectionAccepted, "completed_at": now, "updated_at": now}
	if conn.CompletedAt == nil {
		conn.CompletedAt = &now
	}
	if !SharedRemoteSignalingService.IsDeviceOnline(target.ID) {
		conn.Status = remoteConnectionRejected
		conn.Reason = remoteReasonDeviceOffline
		conn.CompletedAt = &now
		updates["status"] = remoteConnectionRejected
		updates["reason"] = remoteReasonDeviceOffline
		if err := global.AppDB.Model(&conn).Updates(updates).Error; err != nil {
			return modelBiz.RemoteConnectionAttempt{}, bizRes.RemoteConnectionResponse{}, err
		}
		return conn, bizRes.RemoteConnectionFromModel(conn), nil
	}
	if canOfferLanTransport(target, clientIP) {
		reason := strings.TrimSpace(conn.Reason)
		if reason == "" || reason == "waiting_for_approval" {
			reason = "approved"
		}
		conn.Status = remoteConnectionAccepted
		conn.Reason = reason
		conn.Transport = remoteLanTransport
		updates["reason"] = reason
		updates["transport"] = remoteLanTransport
		if err := global.AppDB.Model(&conn).Updates(updates).Error; err != nil {
			return modelBiz.RemoteConnectionAttempt{}, bizRes.RemoteConnectionResponse{}, err
		}
		return conn, remoteConnectionResponseWithLan(conn, target), nil
	}
	conn.Status = remoteConnectionAccepted
	conn.Reason = remoteReasonRemoteRequired
	conn.Transport = remoteTunnelTransport
	updates["reason"] = remoteReasonRemoteRequired
	updates["transport"] = remoteTunnelTransport
	if err := global.AppDB.Model(&conn).Updates(updates).Error; err != nil {
		return modelBiz.RemoteConnectionAttempt{}, bizRes.RemoteConnectionResponse{}, err
	}
	return conn, bizRes.RemoteConnectionFromModel(conn), nil
}

func canOfferLanTransport(target modelBiz.RemoteDevice, clientIP string) bool {
	if target.LanIP == "" || target.LanPort < 1 || target.LanPort > 65535 || strings.TrimSpace(target.LanToken) == "" {
		return false
	}
	if target.LanTokenExpiresAt == nil || !target.LanTokenExpiresAt.After(time.Now()) {
		return false
	}
	if !isPrivateIPv4Address(target.LanIP) {
		return false
	}
	if strings.TrimSpace(target.LanPublisherIPHash) == "" {
		return false
	}
	return target.LanPublisherIPHash == hashString(normalizeClientIPForLanMatch(clientIP))
}

func remoteConnectionResponseWithLan(conn modelBiz.RemoteConnectionAttempt, target modelBiz.RemoteDevice) bizRes.RemoteConnectionResponse {
	result := bizRes.RemoteConnectionFromModel(conn)
	result.Endpoint = &bizRes.RemoteLanEndpointResponse{
		IP:         target.LanIP,
		Port:       target.LanPort,
		LastSeenAt: target.LanEndpointLastSeenAt,
	}
	result.TransientToken = target.LanToken
	return result
}

func remoteLanTokenExpiry(raw int64) time.Time {
	if raw <= 0 {
		return time.Time{}
	}
	if raw >= 1_000_000_000_000 {
		return time.UnixMilli(raw)
	}
	return time.Unix(raw, 0)
}

func isPrivateIPv4Address(ip string) bool {
	parsed := net.ParseIP(strings.TrimSpace(ip))
	if parsed == nil {
		return false
	}
	ipv4 := parsed.To4()
	if ipv4 == nil {
		return false
	}
	switch {
	case ipv4[0] == 10:
		return true
	case ipv4[0] == 172 && ipv4[1] >= 16 && ipv4[1] <= 31:
		return true
	case ipv4[0] == 192 && ipv4[1] == 168:
		return true
	default:
		return false
	}
}

func (s *RemoteService) validFromDeviceID(userID, deviceID uint) (*uint, error) {
	if deviceID == 0 {
		return nil, nil
	}
	var device modelBiz.RemoteDevice
	if err := global.AppDB.Where("id = ? AND user_id = ? AND status = ?", deviceID, userID, remoteStatusActive).First(&device).Error; err != nil {
		return nil, errors.New("发起设备无效")
	}
	return &device.ID, nil
}

func (s *RemoteService) activeGrant(targetDeviceID, granteeUserID uint, granteeDeviceID *uint) (modelBiz.RemoteDeviceGrant, bool) {
	query := global.AppDB.Where("target_device_id = ? AND grantee_user_id = ? AND status = ?", targetDeviceID, granteeUserID, remoteStatusActive).
		Where("expires_at IS NULL OR expires_at > ?", time.Now())
	if granteeDeviceID != nil {
		query = query.Where("grantee_device_id IS NULL OR grantee_device_id = ?", *granteeDeviceID)
	}
	var grant modelBiz.RemoteDeviceGrant
	if err := query.Order("updated_at desc").First(&grant).Error; err != nil {
		return modelBiz.RemoteDeviceGrant{}, false
	}
	return grant, true
}

func (s *RemoteService) GetLegalDocument(docType, platform string) (modelBiz.RemoteLegalDocument, error) {
	docType = strings.TrimSpace(docType)
	platform = strings.TrimSpace(platform)
	if platform == "" {
		platform = "all"
	}
	if platform != "all" {
		var platformDoc modelBiz.RemoteLegalDocument
		err := global.AppDB.Where("type = ? AND published = ? AND platform = ?", docType, true, platform).Order("effective_at desc, id desc").First(&platformDoc).Error
		if err == nil {
			return platformDoc, nil
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return modelBiz.RemoteLegalDocument{}, err
		}
	}
	var fallbackDoc modelBiz.RemoteLegalDocument
	err := global.AppDB.Where("type = ? AND published = ? AND platform = ?", docType, true, "all").Order("effective_at desc, id desc").First(&fallbackDoc).Error
	return fallbackDoc, err
}

func (s *RemoteService) GetAppFooter(platform string) (modelBiz.RemoteAppFooterConfig, error) {
	platform = strings.ToLower(strings.TrimSpace(platform))
	if platform == "" {
		platform = "ios"
	}
	if platform != "all" {
		var platformConfig modelBiz.RemoteAppFooterConfig
		err := global.AppDB.Where("platform = ? AND published = ?", platform, true).Order("updated_at desc, id desc").First(&platformConfig).Error
		if err == nil {
			return platformConfig, nil
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return modelBiz.RemoteAppFooterConfig{}, err
		}
	}
	var fallbackConfig modelBiz.RemoteAppFooterConfig
	err := global.AppDB.Where("platform = ? AND published = ?", "all", true).Order("updated_at desc, id desc").First(&fallbackConfig).Error
	if err == nil {
		return fallbackConfig, nil
	}
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return defaultRemoteAppFooter(platform), nil
	}
	return modelBiz.RemoteAppFooterConfig{}, err
}

func (s *RemoteService) CheckAppUpdate(req bizReq.RemoteAppUpdateCheckRequest) (bizRes.RemoteAppUpdateCheckResponse, error) {
	platform := strings.ToLower(strings.TrimSpace(req.Platform))
	if !validRemoteAppUpdatePlatform(platform) {
		return bizRes.RemoteAppUpdateCheckResponse{}, errors.New("参数错误")
	}
	channel := strings.ToLower(strings.TrimSpace(req.Channel))
	if channel == "" {
		channel = "stable"
	}
	if channel != "stable" && channel != "beta" {
		channel = "stable"
	}
	packageArch := normalizeRemoteUpdateArch(req.PackageArch)
	update, found, err := findPublishedRemoteAppUpdate(platform, channel, packageArch)
	if err != nil || !found {
		return bizRes.RemoteAppUpdateCheckResponse{}, err
	}
	currentVersion := strings.TrimSpace(req.Version)
	currentBuild := strings.TrimSpace(req.BuildNumber)
	updateAvailable := compareRemoteVersion(update.Version, currentVersion) > 0
	if !updateAvailable && update.BuildNumber != "" && currentBuild != "" {
		updateAvailable = compareRemoteVersion(update.BuildNumber, currentBuild) > 0
	}
	forceUpdate := update.ForceUpdate
	if update.MinimumVersion != "" && compareRemoteVersion(update.MinimumVersion, currentVersion) > 0 {
		forceUpdate = true
		updateAvailable = true
	}
	return bizRes.RemoteAppUpdateCheckResponse{
		UpdateAvailable:   updateAvailable,
		LatestVersion:     update.Version,
		LatestBuildNumber: update.BuildNumber,
		PackageArch:       update.PackageArch,
		MinimumVersion:    update.MinimumVersion,
		ReleaseNotes:      update.ReleaseNotes,
		UpdateType:        update.UpdateType,
		DownloadURL:       update.DownloadURL,
		AppStoreURL:       update.AppStoreURL,
		PackageSHA256:     update.PackageSHA256,
		PackageFileSize:   update.PackageFileSize,
		ForceUpdate:       forceUpdate,
		ReleasedAt:        update.ReleasedAt,
	}, nil
}

func (s *RemoteService) ConsentLegal(userID uint, req bizReq.RemoteLegalConsentRequest) (modelBiz.RemoteLegalConsent, error) {
	var doc modelBiz.RemoteLegalDocument
	if err := global.AppDB.First(&doc, req.DocumentID).Error; err != nil {
		return modelBiz.RemoteLegalConsent{}, err
	}
	now := time.Now()
	var deviceID *uint
	if req.DeviceID > 0 {
		deviceID = &req.DeviceID
	}
	consent := modelBiz.RemoteLegalConsent{UserID: userID, DocumentID: doc.ID, DocumentType: doc.Type, DocumentVersion: doc.Version, Platform: req.Platform, DeviceID: deviceID, ConsentedAt: now}
	return consent, global.AppDB.Create(&consent).Error
}

func defaultRemoteAppFooter(platform string) modelBiz.RemoteAppFooterConfig {
	return modelBiz.RemoteAppFooterConfig{
		Platform:      platform,
		CompanyName:   "禾屿科技",
		CopyrightText: "© 2026 禾屿科技",
		ICPText:       "ICP备案信息待更新",
		Published:     true,
	}
}

func (s *RemoteService) GetSubscription(userID uint) (bizRes.RemoteSubscriptionResponse, error) {
	return (&RemoteEntitlementService{}).SubscriptionResponse(userID)
}

func auditStatusForConnection(status string) string {
	if status == remoteConnectionRejected {
		return "failed"
	}
	return "success"
}

func findPublishedRemoteAppUpdate(platform, channel, packageArch string) (modelBiz.RemoteAppUpdate, bool, error) {
	if platform == "macos" {
		for _, arch := range remoteUpdateArchCandidates(packageArch) {
			update, found, err := findPublishedRemoteAppUpdateByArch(platform, channel, arch)
			if err != nil || found {
				return update, found, err
			}
		}
	}
	update, found, err := findPublishedRemoteAppUpdateByArch(platform, channel, "")
	if err != nil || found {
		return update, found, err
	}
	return findPublishedRemoteAppUpdateByArch("all", channel, "")
}

func findPublishedRemoteAppUpdateByArch(platform, channel, packageArch string) (modelBiz.RemoteAppUpdate, bool, error) {
	var update modelBiz.RemoteAppUpdate
	db := global.AppDB.Where("platform = ? AND channel = ? AND published = ?", platform, channel, true)
	if packageArch != "" {
		db = db.Where("package_arch = ?", packageArch)
	}
	err := db.
		Order("released_at desc, id desc").
		First(&update).Error
	if err == nil {
		return update, true, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return modelBiz.RemoteAppUpdate{}, false, err
	}
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return modelBiz.RemoteAppUpdate{}, false, nil
	}
	return modelBiz.RemoteAppUpdate{}, false, err
}

func remoteUpdateArchCandidates(packageArch string) []string {
	seen := map[string]bool{}
	candidates := make([]string, 0, 3)
	for _, arch := range []string{packageArch, "universal"} {
		if arch == "" || seen[arch] {
			continue
		}
		seen[arch] = true
		candidates = append(candidates, arch)
	}
	return candidates
}

func normalizeRemoteUpdateArch(packageArch string) string {
	switch strings.ToLower(strings.TrimSpace(packageArch)) {
	case "arm64", "x86_64", "universal":
		return strings.ToLower(strings.TrimSpace(packageArch))
	default:
		return ""
	}
}

func validRemoteAppUpdatePlatform(platform string) bool {
	switch platform {
	case "android", "windows", "macos", "ios":
		return true
	default:
		return false
	}
}

func compareRemoteVersion(left, right string) int {
	left = strings.TrimSpace(left)
	right = strings.TrimSpace(right)
	if left == right {
		return 0
	}
	if left == "" {
		return -1
	}
	if right == "" {
		return 1
	}
	leftParts := splitRemoteVersion(left)
	rightParts := splitRemoteVersion(right)
	maxParts := len(leftParts)
	if len(rightParts) > maxParts {
		maxParts = len(rightParts)
	}
	for i := 0; i < maxParts; i++ {
		leftPart := "0"
		rightPart := "0"
		if i < len(leftParts) {
			leftPart = leftParts[i]
		}
		if i < len(rightParts) {
			rightPart = rightParts[i]
		}
		leftInt, leftErr := strconv.Atoi(leftPart)
		rightInt, rightErr := strconv.Atoi(rightPart)
		if leftErr == nil && rightErr == nil {
			if leftInt > rightInt {
				return 1
			}
			if leftInt < rightInt {
				return -1
			}
			continue
		}
		if leftPart > rightPart {
			return 1
		}
		if leftPart < rightPart {
			return -1
		}
	}
	return 0
}

func splitRemoteVersion(value string) []string {
	return strings.FieldsFunc(value, func(r rune) bool {
		return r == '.' || r == '-' || r == '_' || r == '+'
	})
}

func (s *RemoteService) issueTokens(user modelBiz.RemoteUser) (bizRes.RemoteAuthResponse, error) {
	accessToken, claims, err := utils.CreateRemoteAccessToken(user.ID, user.Phone, user.Email, user.TokenVersion)
	if err != nil {
		return bizRes.RemoteAuthResponse{}, err
	}
	refreshToken, err := randomToken(32)
	if err != nil {
		return bizRes.RemoteAuthResponse{}, err
	}
	refresh := modelBiz.RemoteUserToken{UserID: user.ID, TokenHash: hashString(refreshToken), TokenType: "refresh", ExpiresAt: time.Now().AddDate(0, 0, 30)}
	if err := global.AppDB.Create(&refresh).Error; err != nil {
		return bizRes.RemoteAuthResponse{}, err
	}
	return bizRes.RemoteAuthResponse{AccessToken: accessToken, RefreshToken: refreshToken, ExpiresAt: claims.ExpiresAt.Unix() * 1000, User: bizRes.RemoteUserFromModel(user)}, nil
}

func (s *RemoteService) buildDeletionRecord(user modelBiz.RemoteUser, req bizReq.RemoteAccountDeletionRequest, deletedAt time.Time) (modelBiz.RemoteAccountDeletionRecord, error) {
	return BuildRemoteAccountDeletionRecord(
		user,
		req.Reason,
		"self",
		remoteDeletionConfirmationSnapshot(req),
		deletedAt,
	)
}

func isValidRemoteDeletionFinalConfirm(value string) bool {
	value = strings.TrimSpace(value)
	return value == remoteDeleteConfirmWaive || value == remoteDeleteConfirmCleanup
}

func remoteDeletionConfirmationSnapshot(req bizReq.RemoteAccountDeletionRequest) string {
	return strings.Join([]string{
		strings.TrimSpace(req.ConfirmAccount),
		strings.TrimSpace(req.ConfirmDestroy),
		strings.TrimSpace(req.ConfirmWaiveRights),
	}, "/")
}

func BuildRemoteAccountDeletionRecord(user modelBiz.RemoteUser, reason, operator, confirmation string, deletedAt time.Time) (modelBiz.RemoteAccountDeletionRecord, error) {
	subscriptions, err := deletionSubscriptionsSnapshot(user.ID)
	if err != nil {
		return modelBiz.RemoteAccountDeletionRecord{}, err
	}
	orders, orderNos, err := deletionOrdersSnapshot(user.ID)
	if err != nil {
		return modelBiz.RemoteAccountDeletionRecord{}, err
	}
	devices, err := deletionDevicesSnapshot(user.ID)
	if err != nil {
		return modelBiz.RemoteAccountDeletionRecord{}, err
	}
	usages, err := deletionUsagesSnapshot(user.ID)
	if err != nil {
		return modelBiz.RemoteAccountDeletionRecord{}, err
	}
	operator = strings.TrimSpace(operator)
	if operator == "" {
		operator = "self"
	}
	confirmation = strings.TrimSpace(confirmation)
	if confirmation == "" {
		confirmation = fmt.Sprintf("%s/%s/%s", remoteDeleteConfirmAccount, remoteDeleteConfirmDestroy, remoteDeleteConfirmWaive)
	}
	return modelBiz.RemoteAccountDeletionRecord{
		UserID:               user.ID,
		EmailHash:            optionalHash(user.Email),
		EmailMasked:          maskEmail(user.Email),
		PhoneHash:            optionalHash(displayableRemotePhone(user.Phone)),
		PhoneMasked:          maskPhone(displayableRemotePhone(user.Phone)),
		StatusSnapshot:       user.Status,
		Reason:               truncateDeletionValue(reason, 500),
		Operator:             operator,
		ConfirmationSnapshot: truncateDeletionValue(confirmation, 191),
		SubscriptionSnapshot: shared.JSONMap{"items": subscriptions, "count": len(subscriptions)},
		OrderSnapshot:        shared.JSONMap{"items": orders, "count": len(orders), "outTradeNos": orderNos},
		DeviceSnapshot:       shared.JSONMap{"items": devices, "count": len(devices)},
		UsageSnapshot:        shared.JSONMap{"items": usages, "count": len(usages)},
		DeletedAtSnapshot:    deletedAt,
	}, nil
}

func (s *RemoteService) issueAuthCode(identity string, isEmail bool, purpose string) (bizRes.RemoteVerificationCodeResponse, error) {
	code, err := randomNumericCode(remoteAuthCodeDigits)
	if err != nil {
		return bizRes.RemoteVerificationCodeResponse{}, err
	}
	now := time.Now()
	expiresAt := now.Add(remoteAuthCodeValidity)
	codeHash := hashString(identity + ":" + purpose + ":" + code)
	db := global.AppDB.Model(&modelBiz.RemoteAuthCode{}).Where("purpose = ? AND consumed_at IS NULL AND revoked_at IS NULL", purpose)
	if isEmail {
		db = db.Where("email = ?", identity)
	} else {
		db = db.Where("phone = ?", identity)
	}
	if err := db.Updates(map[string]any{"revoked_at": now, "updated_at": now}).Error; err != nil {
		return bizRes.RemoteVerificationCodeResponse{}, err
	}
	authCode := modelBiz.RemoteAuthCode{Purpose: purpose, CodeHash: codeHash, ExpiresAt: expiresAt}
	if isEmail {
		authCode.Email = identity
	} else {
		authCode.Phone = identity
	}
	if err := global.AppDB.Create(&authCode).Error; err != nil {
		return bizRes.RemoteVerificationCodeResponse{}, err
	}
	if isEmail {
		if err := remoteSendAuthCodeEmail(identity, purpose, code, expiresAt); err != nil {
			_ = global.AppDB.Model(&authCode).Updates(map[string]any{"revoked_at": now, "updated_at": time.Now()}).Error
			return bizRes.RemoteVerificationCodeResponse{}, err
		}
	}
	return bizRes.RemoteVerificationCodeResponse{VerificationCode: "", ExpiresAt: expiresAt.UnixMilli()}, nil
}

func sendRemoteAuthCodeEmail(to, purpose, code string, expiresAt time.Time) error {
	cfg := global.AppConfig.Email
	host := strings.TrimSpace(cfg.Host)
	from := strings.TrimSpace(cfg.From)
	secret := strings.TrimSpace(cfg.Secret)
	if host == "" || from == "" || secret == "" || cfg.Port <= 0 {
		return errors.New("邮件服务未配置，请联系管理员。")
	}

	subject := "AnnaCode 邮箱验证码"
	scene := "注册账号"
	switch purpose {
	case remoteAuthPurposeLogin:
		scene = "登录"
	case remoteAuthPurposePassword:
		scene = "重置密码"
	}
	body := fmt.Sprintf("你的 AnnaCode %s验证码是：%s\n\n验证码将在 %s 过期。若不是你本人操作，请忽略这封邮件。", scene, code, expiresAt.Format("2006-01-02 15:04:05"))
	addr := net.JoinHostPort(host, strconv.Itoa(cfg.Port))
	fromAddress := mail.Address{Name: strings.TrimSpace(cfg.Nickname), Address: from}
	headers := []string{
		"From: " + fromAddress.String(),
		"To: " + strings.TrimSpace(to),
		"Subject: " + mime.QEncoding.Encode("UTF-8", subject),
		"MIME-Version: 1.0",
		"Content-Type: text/plain; charset=UTF-8",
		"Content-Transfer-Encoding: 8bit",
	}
	message := strings.Join(headers, "\r\n") + "\r\n\r\n" + body
	auth := remoteSMTPAuth(cfg.IsLoginAuth, from, secret, host)

	if cfg.IsSSL {
		conn, err := tls.Dial("tcp", addr, &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12})
		if err != nil {
			return fmt.Errorf("连接邮件服务器失败: %w", err)
		}
		defer conn.Close()
		client, err := smtp.NewClient(conn, host)
		if err != nil {
			return fmt.Errorf("初始化邮件客户端失败: %w", err)
		}
		defer client.Close()
		return remoteSendSMTPMessage(client, auth, from, []string{to}, []byte(message))
	}

	client, err := smtp.Dial(addr)
	if err != nil {
		return fmt.Errorf("连接邮件服务器失败: %w", err)
	}
	defer client.Close()
	if ok, _ := client.Extension("STARTTLS"); ok {
		if err := client.StartTLS(&tls.Config{ServerName: host, MinVersion: tls.VersionTLS12}); err != nil {
			return fmt.Errorf("启用邮件加密失败: %w", err)
		}
	}
	return remoteSendSMTPMessage(client, auth, from, []string{to}, []byte(message))
}

func remoteSMTPAuth(useLoginAuth bool, username, password, host string) smtp.Auth {
	if useLoginAuth {
		return remoteLoginAuth(username, password)
	}
	return smtp.PlainAuth("", username, password, host)
}

func remoteSendSMTPMessage(client *smtp.Client, auth smtp.Auth, from string, to []string, message []byte) error {
	if auth != nil {
		if ok, _ := client.Extension("AUTH"); ok {
			if err := client.Auth(auth); err != nil {
				return fmt.Errorf("邮件认证失败: %w", err)
			}
		}
	}
	if err := client.Mail(from); err != nil {
		return fmt.Errorf("设置发件人失败: %w", err)
	}
	for _, recipient := range to {
		if err := client.Rcpt(strings.TrimSpace(recipient)); err != nil {
			return fmt.Errorf("设置收件人失败: %w", err)
		}
	}
	writer, err := client.Data()
	if err != nil {
		return fmt.Errorf("写入邮件失败: %w", err)
	}
	if _, err := writer.Write(message); err != nil {
		_ = writer.Close()
		return fmt.Errorf("发送邮件失败: %w", err)
	}
	if err := writer.Close(); err != nil {
		return fmt.Errorf("完成邮件发送失败: %w", err)
	}
	return client.Quit()
}

type loginAuth struct {
	username string
	password string
}

func remoteLoginAuth(username, password string) smtp.Auth {
	return &loginAuth{username: username, password: password}
}

func (a *loginAuth) Start(*smtp.ServerInfo) (string, []byte, error) {
	return "LOGIN", []byte(a.username), nil
}

func (a *loginAuth) Next(_ []byte, more bool) ([]byte, error) {
	if more {
		return []byte(a.password), nil
	}
	return nil, nil
}

func (s *RemoteService) consumeAuthCode(identity string, isEmail bool, purpose, code string) error {
	return s.consumeAuthCodeWithDB(global.AppDB, identity, isEmail, purpose, code)
}

func (s *RemoteService) consumeAuthCodeWithDB(db *gorm.DB, identity string, isEmail bool, purpose, code string) error {
	codeHash := hashString(identity + ":" + purpose + ":" + strings.TrimSpace(code))
	var authCode modelBiz.RemoteAuthCode
	query := db.Where("purpose = ? AND code_hash = ?", purpose, codeHash)
	if isEmail {
		query = query.Where("email = ?", identity)
	} else {
		query = query.Where("phone = ?", identity)
	}
	if err := query.First(&authCode).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("验证码无效或已过期")
		}
		return err
	}
	if authCode.RevokedAt != nil || authCode.ConsumedAt != nil || time.Now().After(authCode.ExpiresAt) {
		return errors.New("验证码无效或已过期")
	}
	now := time.Now()
	result := db.Model(&modelBiz.RemoteAuthCode{}).
		Where("id = ? AND consumed_at IS NULL AND revoked_at IS NULL", authCode.ID).
		Updates(map[string]any{"consumed_at": now, "updated_at": now})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return errors.New("验证码无效或已过期")
	}
	return nil
}

func normalizeRemoteIdentity(email, _ string) (string, bool, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" {
		return "", true, errors.New("请输入邮箱地址。")
	}
	if _, err := mail.ParseAddress(email); err != nil || !strings.Contains(email, "@") {
		return "", true, errors.New("请输入正确的邮箱地址。")
	}
	return email, true, nil
}

func remoteUserIdentityQuery(identity string, isEmail bool) *gorm.DB {
	db := global.AppDB.Where("deleted_at IS NULL")
	if isEmail {
		return db.Where("email = ?", identity)
	}
	return db.Where("phone = ?", identity)
}

func remoteEmailPhonePlaceholder(email string) string {
	sum := sha256.Sum256([]byte(strings.ToLower(strings.TrimSpace(email))))
	return "email:" + hex.EncodeToString(sum[:])[:24]
}

func randomToken(size int) (string, error) {
	buf := make([]byte, size)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

func randomCode(size int) (string, error) {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	buf := make([]byte, size)
	raw := make([]byte, size)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	for i, b := range raw {
		buf[i] = alphabet[int(b)%len(alphabet)]
	}
	return string(buf), nil
}

func randomNumericCode(size int) (string, error) {
	const digits = "0123456789"
	buf := make([]byte, size)
	raw := make([]byte, size)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	for i, b := range raw {
		buf[i] = digits[int(b)%len(digits)]
	}
	return string(buf), nil
}

func hashString(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}

// normalizeClientIPForLanMatch collapses IPv4-mapped / IPv6 forms so Mac and phone
// behind the same NAT hash to the same publisher fingerprint.
func normalizeClientIPForLanMatch(clientIP string) string {
	ip := strings.TrimSpace(clientIP)
	if parsed := net.ParseIP(ip); parsed != nil {
		if v4 := parsed.To4(); v4 != nil {
			return v4.String()
		}
		return parsed.String()
	}
	return ip
}

func truncateRemoteMetricValue(value string) string {
	value = strings.TrimSpace(value)
	if len(value) <= 64 {
		return value
	}
	return value[:64]
}

func DeleteRemoteAccountData(tx *gorm.DB, user modelBiz.RemoteUser) error {
	userID := user.ID
	var outTradeNos []string
	if err := tx.Model(&modelBiz.RemoteSubscriptionOrder{}).Where("user_id = ?", userID).Pluck("out_trade_no", &outTradeNos).Error; err != nil {
		return err
	}
	var deviceIDs []uint
	if err := tx.Model(&modelBiz.RemoteDevice{}).Where("user_id = ?", userID).Pluck("id", &deviceIDs).Error; err != nil {
		return err
	}
	var connectionIDs []uint
	if err := tx.Model(&modelBiz.RemoteConnectionAttempt{}).Where("from_user_id = ? OR to_user_id = ?", userID, userID).Pluck("id", &connectionIDs).Error; err != nil {
		return err
	}

	deletions := []func() *gorm.DB{
		func() *gorm.DB { return tx.Unscoped().Where("user_id = ?", userID).Delete(&modelBiz.RemoteUserToken{}) },
		func() *gorm.DB { return tx.Unscoped().Where("user_id = ?", userID).Delete(&modelBiz.RemoteDevice{}) },
		func() *gorm.DB {
			return tx.Unscoped().Where("owner_user_id = ? OR grantee_user_id = ?", userID, userID).Delete(&modelBiz.RemoteDeviceGrant{})
		},
		func() *gorm.DB {
			return tx.Unscoped().Where("from_user_id = ? OR to_user_id = ?", userID, userID).Delete(&modelBiz.RemoteConnectionAttempt{})
		},
		func() *gorm.DB {
			return tx.Unscoped().Where("user_id = ?", userID).Delete(&modelBiz.RemoteLegalConsent{})
		},
		func() *gorm.DB {
			return tx.Unscoped().Where("user_id = ?", userID).Delete(&modelBiz.RemoteSubscription{})
		},
		func() *gorm.DB {
			return tx.Unscoped().Where("user_id = ?", userID).Delete(&modelBiz.RemoteSubscriptionOrder{})
		},
		func() *gorm.DB {
			return tx.Unscoped().Where("user_id = ?", userID).Delete(&modelBiz.RemoteEntitlementUsage{})
		},
		func() *gorm.DB {
			query := tx.Unscoped().Where("from_user_id = ?", userID)
			if len(deviceIDs) > 0 {
				query = query.Or("target_device_id IN ? OR from_device_id IN ?", deviceIDs, deviceIDs)
			}
			return query.Delete(&modelBiz.RemoteDeviceCodeAttempt{})
		},
		func() *gorm.DB {
			query := tx.Unscoped().Where("user_id = ?", userID)
			if len(deviceIDs) > 0 {
				query = query.Or("device_id IN ?", deviceIDs)
			}
			if len(connectionIDs) > 0 {
				query = query.Or("connection_id IN ?", connectionIDs)
			}
			return query.Delete(&modelBiz.RemoteAuditLog{})
		},
	}
	for _, deletion := range deletions {
		if err := deletion().Error; err != nil {
			return err
		}
	}

	authCodeQuery := tx.Unscoped().Where("email = ?", user.Email)
	if user.Phone != "" {
		authCodeQuery = authCodeQuery.Or("phone = ?", user.Phone)
	}
	if err := authCodeQuery.Delete(&modelBiz.RemoteAuthCode{}).Error; err != nil {
		return err
	}
	if len(outTradeNos) > 0 {
		if err := tx.Unscoped().Where("out_trade_no IN ?", outTradeNos).Delete(&modelBiz.RemotePaymentNotifyEvent{}).Error; err != nil {
			return err
		}
	}
	return nil
}

func deletionSubscriptionsSnapshot(userID uint) ([]map[string]any, error) {
	var subscriptions []modelBiz.RemoteSubscription
	if err := global.AppDB.Where("user_id = ?", userID).Order("id asc").Find(&subscriptions).Error; err != nil {
		return nil, err
	}
	items := make([]map[string]any, 0, len(subscriptions))
	for _, item := range subscriptions {
		items = append(items, map[string]any{
			"id":              item.ID,
			"planCode":        item.PlanCode,
			"status":          item.Status,
			"startedAt":       item.StartedAt,
			"expiresAt":       item.ExpiresAt,
			"provider":        item.Provider,
			"providerOrderId": item.ProviderOrderID,
		})
	}
	return items, nil
}

func deletionOrdersSnapshot(userID uint) ([]map[string]any, []string, error) {
	var orders []modelBiz.RemoteSubscriptionOrder
	if err := global.AppDB.Where("user_id = ?", userID).Order("id asc").Find(&orders).Error; err != nil {
		return nil, nil, err
	}
	items := make([]map[string]any, 0, len(orders))
	outTradeNos := make([]string, 0, len(orders))
	for _, item := range orders {
		if item.OutTradeNo != "" {
			outTradeNos = append(outTradeNos, item.OutTradeNo)
		}
		items = append(items, map[string]any{
			"id":             item.ID,
			"planCode":       item.PlanCode,
			"planName":       item.PlanName,
			"durationMonths": item.DurationMonths,
			"amountFen":      item.AmountFen,
			"currency":       item.Currency,
			"status":         item.Status,
			"outTradeNo":     item.OutTradeNo,
			"payOrderNo":     item.PayOrderNo,
			"channelCode":    item.ChannelCode,
			"paidAt":         item.PaidAt,
			"createdAt":      item.CreatedAt,
		})
	}
	return items, outTradeNos, nil
}

func deletionDevicesSnapshot(userID uint) ([]map[string]any, error) {
	var devices []modelBiz.RemoteDevice
	if err := global.AppDB.Where("user_id = ?", userID).Order("id asc").Find(&devices).Error; err != nil {
		return nil, err
	}
	items := make([]map[string]any, 0, len(devices))
	for _, item := range devices {
		items = append(items, map[string]any{
			"id":             item.ID,
			"deviceType":     item.DeviceType,
			"platform":       item.Platform,
			"deviceName":     item.DeviceName,
			"approvalPolicy": item.ApprovalPolicy,
			"remoteEnabled":  item.RemoteEnabled,
			"status":         item.Status,
			"lastSeenAt":     item.LastSeenAt,
		})
	}
	return items, nil
}

func deletionUsagesSnapshot(userID uint) ([]map[string]any, error) {
	var usages []modelBiz.RemoteEntitlementUsage
	if err := global.AppDB.Where("user_id = ?", userID).Order("id asc").Limit(200).Find(&usages).Error; err != nil {
		return nil, err
	}
	items := make([]map[string]any, 0, len(usages))
	for _, item := range usages {
		items = append(items, map[string]any{
			"id":            item.ID,
			"connectionId":  item.ConnectionID,
			"usageDate":     item.UsageDate,
			"mode":          item.Mode,
			"startedAt":     item.StartedAt,
			"endedAt":       item.EndedAt,
			"billedSeconds": item.BilledSeconds,
			"status":        item.Status,
		})
	}
	return items, nil
}

func optionalHash(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	return hashString(value)
}

func displayableRemotePhone(phone string) string {
	if strings.HasPrefix(phone, "email:") {
		return ""
	}
	return phone
}

func maskEmail(email string) string {
	email = strings.TrimSpace(strings.ToLower(email))
	parts := strings.Split(email, "@")
	if len(parts) != 2 || parts[0] == "" {
		return ""
	}
	name := parts[0]
	if len(name) <= 2 {
		return name[:1] + "***@" + parts[1]
	}
	return name[:1] + "***" + name[len(name)-1:] + "@" + parts[1]
}

func maskPhone(phone string) string {
	phone = strings.TrimSpace(phone)
	if len(phone) < 7 {
		return ""
	}
	return phone[:3] + "****" + phone[len(phone)-4:]
}

func truncateDeletionValue(value string, maxLength int) string {
	value = strings.TrimSpace(value)
	if len(value) <= maxLength {
		return value
	}
	return value[:maxLength]
}
