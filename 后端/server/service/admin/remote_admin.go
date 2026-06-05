package admin

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/mail"
	"net/url"
	"strings"
	"time"

	"gorm.io/gorm"
	"heyu/server/global"
	adminReq "heyu/server/model/admin/request"
	modelBiz "heyu/server/model/biz"
	bizService "heyu/server/service/biz"
	"heyu/server/utils"
)

type RemoteAdminService struct{}

type remoteAdminDeviceResponse struct {
	modelBiz.RemoteDevice
	Online bool `json:"online"`
}

type remoteAdminSubscriptionOrderResponse struct {
	modelBiz.RemoteSubscriptionOrder
	Email string `json:"email"`
}

func (s *RemoteAdminService) ListUsers(req adminReq.RemoteUserSearch) (any, int64, error) {
	db := global.AppDB.Model(&modelBiz.RemoteUser{})
	if strings.TrimSpace(req.Phone) != "" {
		db = db.Where("phone LIKE ?", "%"+strings.TrimSpace(req.Phone)+"%")
	}
	if strings.TrimSpace(req.Email) != "" {
		db = db.Where("email LIKE ?", "%"+strings.TrimSpace(req.Email)+"%")
	}
	if strings.TrimSpace(req.Status) != "" {
		db = db.Where("status = ?", strings.TrimSpace(req.Status))
	}
	return paginate[modelBiz.RemoteUser](db, &req.PageInfo, "id desc")
}

func (s *RemoteAdminService) UpdateUserStatus(req adminReq.RemoteStatusUpdate) error {
	if req.ID == 0 || !validStatus(req.Status, "active", "disabled") {
		return errors.New("参数错误")
	}
	now := time.Now()
	return global.AppDB.Transaction(func(tx *gorm.DB) error {
		updates := map[string]any{"status": req.Status, "updated_at": now}
		if req.Status == "disabled" {
			updates["token_version"] = gorm.Expr("token_version + ?", 1)
		}
		if err := tx.Model(&modelBiz.RemoteUser{}).Where("id = ?", req.ID).Updates(updates).Error; err != nil {
			return err
		}
		if req.Status == "disabled" {
			if err := tx.Model(&modelBiz.RemoteUserToken{}).Where("user_id = ? AND token_type = ? AND revoked_at IS NULL", req.ID, "refresh").Updates(map[string]any{"revoked_at": now, "updated_at": now}).Error; err != nil {
				return err
			}
			bizService.SharedRemoteSignalingService.KickUser(req.ID)
			bizService.RecordRemoteAudit(&req.ID, nil, nil, "remote.admin_ban_user", "success", "user disabled", "", "")
		}
		return nil
	})
}

func (s *RemoteAdminService) SaveUser(req adminReq.RemoteUserSave) (modelBiz.RemoteUser, error) {
	email := strings.ToLower(strings.TrimSpace(req.Email))
	phone := strings.TrimSpace(req.Phone)
	status := strings.TrimSpace(req.Status)
	password := strings.TrimSpace(req.Password)
	if status == "" {
		status = "active"
	}
	if !validStatus(status, "active", "disabled") {
		return modelBiz.RemoteUser{}, errors.New("请选择正确的账号状态。")
	}
	if email == "" {
		return modelBiz.RemoteUser{}, errors.New("邮箱不能为空。")
	}
	if _, err := mail.ParseAddress(email); err != nil {
		return modelBiz.RemoteUser{}, errors.New("邮箱格式不正确。")
	}
	if phone == "" {
		phone = remoteAdminEmailPhonePlaceholder(email)
	}
	if req.ID == 0 && password == "" {
		return modelBiz.RemoteUser{}, errors.New("新增远程用户必须设置初始密码。")
	}
	if password != "" && len(password) < 6 {
		return modelBiz.RemoteUser{}, errors.New("密码至少 6 位。")
	}

	now := time.Now()
	user := modelBiz.RemoteUser{}
	err := global.AppDB.Transaction(func(tx *gorm.DB) error {
		if req.ID == 0 {
			user = modelBiz.RemoteUser{Phone: phone, Email: email, PasswordHash: utils.BcryptHash(password), Status: status}
			if err := tx.Create(&user).Error; err != nil {
				return err
			}
			return nil
		}

		if err := tx.First(&user, req.ID).Error; err != nil {
			return err
		}
		updates := map[string]any{"phone": phone, "email": email, "status": status, "updated_at": now}
		if password != "" {
			updates["password_hash"] = utils.BcryptHash(password)
			updates["token_version"] = gorm.Expr("token_version + ?", 1)
		}
		if user.Status != "disabled" && status == "disabled" {
			updates["token_version"] = gorm.Expr("token_version + ?", 1)
		}
		if err := tx.Model(&modelBiz.RemoteUser{}).Where("id = ?", req.ID).Updates(updates).Error; err != nil {
			return err
		}
		if password != "" || status == "disabled" {
			if err := tx.Model(&modelBiz.RemoteUserToken{}).
				Where("user_id = ? AND token_type = ? AND revoked_at IS NULL", req.ID, "refresh").
				Updates(map[string]any{"revoked_at": now, "updated_at": now}).Error; err != nil {
				return err
			}
			bizService.SharedRemoteSignalingService.KickUser(req.ID)
		}
		return tx.First(&user, req.ID).Error
	})
	if err != nil {
		return modelBiz.RemoteUser{}, err
	}
	return user, nil
}

func (s *RemoteAdminService) KickUser(req adminReq.RemoteAdminIDRequest) error {
	if req.ID == 0 {
		return errors.New("参数错误")
	}
	now := time.Now()
	if err := global.AppDB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&modelBiz.RemoteUser{}).Where("id = ?", req.ID).Updates(map[string]any{"token_version": gorm.Expr("token_version + ?", 1), "updated_at": now}).Error; err != nil {
			return err
		}
		return tx.Model(&modelBiz.RemoteUserToken{}).
			Where("user_id = ? AND token_type = ? AND revoked_at IS NULL", req.ID, "refresh").
			Updates(map[string]any{"revoked_at": now, "updated_at": now}).Error
	}); err != nil {
		bizService.RecordRemoteAudit(&req.ID, nil, nil, "remote.admin_kick_user", "failed", "kick user failed", "", "")
		return err
	}
	bizService.SharedRemoteSignalingService.KickUser(req.ID)
	bizService.RecordRemoteAudit(&req.ID, nil, nil, "remote.admin_kick_user", "success", "user sessions invalidated", "", "")
	return nil
}

func (s *RemoteAdminService) BanUser(req adminReq.RemoteAdminIDRequest) error {
	if req.ID == 0 {
		return errors.New("参数错误")
	}
	now := time.Now()
	if err := global.AppDB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&modelBiz.RemoteUser{}).Where("id = ?", req.ID).Updates(map[string]any{"status": "disabled", "token_version": gorm.Expr("token_version + ?", 1), "updated_at": now}).Error; err != nil {
			return err
		}
		return tx.Model(&modelBiz.RemoteUserToken{}).
			Where("user_id = ? AND token_type = ? AND revoked_at IS NULL", req.ID, "refresh").
			Updates(map[string]any{"revoked_at": now, "updated_at": now}).Error
	}); err != nil {
		bizService.RecordRemoteAudit(&req.ID, nil, nil, "remote.admin_ban_user", "failed", "ban user failed", "", "")
		return err
	}
	bizService.SharedRemoteSignalingService.KickUser(req.ID)
	bizService.RecordRemoteAudit(&req.ID, nil, nil, "remote.admin_ban_user", "success", "user disabled", "", "")
	return nil
}

func (s *RemoteAdminService) DeleteUser(req adminReq.RemoteAdminIDRequest) error {
	if req.ID == 0 {
		return errors.New("参数错误")
	}
	var user modelBiz.RemoteUser
	if err := global.AppDB.First(&user, req.ID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("用户不存在或已删除")
		}
		return err
	}

	deletedAt := time.Now()
	record, err := bizService.BuildRemoteAccountDeletionRecord(user, "后台删除远程用户", "admin", "后台确认删除远程用户", deletedAt)
	if err != nil {
		return err
	}
	if err := global.AppDB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&record).Error; err != nil {
			return err
		}
		if err := bizService.DeleteRemoteAccountData(tx, user); err != nil {
			return err
		}
		return tx.Unscoped().Delete(&user).Error
	}); err != nil {
		return err
	}
	bizService.SharedRemoteSignalingService.KickUser(req.ID)
	return nil
}

func (s *RemoteAdminService) ListDevices(req adminReq.RemoteDeviceSearch) (any, int64, error) {
	db := global.AppDB.Model(&modelBiz.RemoteDevice{})
	if req.UserID > 0 {
		db = db.Where("user_id = ?", req.UserID)
	}
	if strings.TrimSpace(req.DeviceName) != "" {
		db = db.Where("device_name LIKE ?", "%"+strings.TrimSpace(req.DeviceName)+"%")
	}
	if strings.TrimSpace(req.DeviceType) != "" {
		db = db.Where("device_type = ?", strings.TrimSpace(req.DeviceType))
	}
	if strings.TrimSpace(req.Platform) != "" {
		db = db.Where("platform = ?", strings.TrimSpace(req.Platform))
	}
	if strings.TrimSpace(req.Status) != "" {
		db = db.Where("status = ?", strings.TrimSpace(req.Status))
	}

	var total int64
	if err := db.Count(&total).Error; err != nil {
		return []remoteAdminDeviceResponse{}, 0, err
	}

	var devices []modelBiz.RemoteDevice
	if err := db.Scopes(req.PageInfo.Paginate()).Order("updated_at desc").Find(&devices).Error; err != nil {
		return []remoteAdminDeviceResponse{}, 0, err
	}

	responses := make([]remoteAdminDeviceResponse, 0, len(devices))
	for _, device := range devices {
		responses = append(responses, remoteAdminDeviceResponse{
			RemoteDevice: device,
			Online:       bizService.SharedRemoteSignalingService.IsDeviceOnline(device.ID),
		})
	}
	return responses, total, nil
}

func (s *RemoteAdminService) UpdateDevice(req adminReq.RemoteDeviceUpdate) error {
	if req.ID == 0 {
		return errors.New("参数错误")
	}
	updates := map[string]any{}
	if strings.TrimSpace(req.DeviceName) != "" {
		updates["device_name"] = strings.TrimSpace(req.DeviceName)
	}
	if validStatus(req.ApprovalPolicy, "always_ask", "allow_anyone") {
		updates["approval_policy"] = req.ApprovalPolicy
	}
	if req.RemoteEnabled != nil {
		updates["remote_enabled"] = *req.RemoteEnabled
	}
	if validStatus(req.Status, "active", "disabled") {
		updates["status"] = req.Status
	}
	if len(updates) == 0 {
		return nil
	}
	if err := global.AppDB.Model(&modelBiz.RemoteDevice{}).Where("id = ?", req.ID).Updates(updates).Error; err != nil {
		return err
	}
	if req.RemoteEnabled != nil && !*req.RemoteEnabled || req.Status == "disabled" {
		bizService.SharedRemoteSignalingService.KickDevice(req.ID)
		bizService.RecordRemoteAudit(nil, &req.ID, nil, "remote.admin_kick_device", "success", "device disabled", "", "")
	}
	return nil
}

func (s *RemoteAdminService) KickDevice(req adminReq.RemoteAdminIDRequest) error {
	if req.ID == 0 {
		return errors.New("参数错误")
	}
	now := time.Now()
	if err := global.AppDB.Model(&modelBiz.RemoteDevice{}).Where("id = ?", req.ID).Updates(map[string]any{
		"lan_token":                 "",
		"lan_token_expires_at":      nil,
		"lan_endpoint_last_seen_at": nil,
		"updated_at":                now,
	}).Error; err != nil {
		bizService.RecordRemoteAudit(nil, &req.ID, nil, "remote.admin_kick_device", "failed", "kick device failed", "", "")
		return err
	}
	bizService.SharedRemoteSignalingService.KickDevice(req.ID)
	bizService.RecordRemoteAudit(nil, &req.ID, nil, "remote.admin_kick_device", "success", "device kicked", "", "")
	return nil
}

func (s *RemoteAdminService) DeleteDevice(req adminReq.RemoteAdminIDRequest) error {
	if req.ID == 0 {
		return errors.New("参数错误")
	}
	var device modelBiz.RemoteDevice
	if err := global.AppDB.First(&device, req.ID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("设备不存在或已删除")
		}
		return err
	}
	var connectionIDs []uint
	if err := global.AppDB.Model(&modelBiz.RemoteConnectionAttempt{}).
		Where("from_device_id = ? OR to_device_id = ?", req.ID, req.ID).
		Pluck("id", &connectionIDs).Error; err != nil {
		return err
	}
	if err := global.AppDB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Unscoped().
			Where("target_device_id = ? OR grantee_device_id = ?", req.ID, req.ID).
			Delete(&modelBiz.RemoteDeviceGrant{}).Error; err != nil {
			return err
		}
		if err := tx.Unscoped().
			Where("target_device_id = ? OR from_device_id = ?", req.ID, req.ID).
			Delete(&modelBiz.RemoteDeviceCodeAttempt{}).Error; err != nil {
			return err
		}
		auditQuery := tx.Unscoped().Where("device_id = ?", req.ID)
		if len(connectionIDs) > 0 {
			auditQuery = auditQuery.Or("connection_id IN ?", connectionIDs)
		}
		if err := auditQuery.Delete(&modelBiz.RemoteAuditLog{}).Error; err != nil {
			return err
		}
		if err := tx.Unscoped().
			Where("from_device_id = ? OR to_device_id = ?", req.ID, req.ID).
			Delete(&modelBiz.RemoteConnectionAttempt{}).Error; err != nil {
			return err
		}
		return tx.Unscoped().Delete(&device).Error
	}); err != nil {
		return err
	}
	bizService.SharedRemoteSignalingService.KickDevice(req.ID)
	return nil
}

func (s *RemoteAdminService) ListConnections(req adminReq.RemoteConnectionSearch) (any, int64, error) {
	db := global.AppDB.Model(&modelBiz.RemoteConnectionAttempt{})
	if req.FromUserID > 0 {
		db = db.Where("from_user_id = ?", req.FromUserID)
	}
	if req.ToUserID > 0 {
		db = db.Where("to_user_id = ?", req.ToUserID)
	}
	if req.ToDeviceID > 0 {
		db = db.Where("to_device_id = ?", req.ToDeviceID)
	}
	if strings.TrimSpace(req.Status) != "" {
		db = db.Where("status = ?", strings.TrimSpace(req.Status))
	}
	if strings.TrimSpace(req.Transport) != "" {
		db = db.Where("transport = ?", strings.TrimSpace(req.Transport))
	}
	return paginate[modelBiz.RemoteConnectionAttempt](db, &req.PageInfo, "id desc")
}

func (s *RemoteAdminService) DeleteConnection(req adminReq.RemoteAdminIDRequest) error {
	return deleteRemoteAdminRecord(req.ID, &modelBiz.RemoteConnectionAttempt{}, "连接记录不存在或已删除")
}

func (s *RemoteAdminService) ListCodeAttempts(req adminReq.RemoteCodeAttemptSearch) (any, int64, error) {
	db := global.AppDB.Model(&modelBiz.RemoteDeviceCodeAttempt{})
	if req.TargetDeviceID > 0 {
		db = db.Where("target_device_id = ?", req.TargetDeviceID)
	}
	if req.FromUserID > 0 {
		db = db.Where("from_user_id = ?", req.FromUserID)
	}
	if strings.TrimSpace(req.Status) != "" {
		db = db.Where("status = ?", strings.TrimSpace(req.Status))
	}
	return paginate[modelBiz.RemoteDeviceCodeAttempt](db, &req.PageInfo, "id desc")
}

func (s *RemoteAdminService) DeleteCodeAttempt(req adminReq.RemoteAdminIDRequest) error {
	return deleteRemoteAdminRecord(req.ID, &modelBiz.RemoteDeviceCodeAttempt{}, "设备码日志不存在或已删除")
}

func (s *RemoteAdminService) ListLegalDocuments(req adminReq.RemoteLegalDocumentSearch) (any, int64, error) {
	db := global.AppDB.Model(&modelBiz.RemoteLegalDocument{})
	if strings.TrimSpace(req.Type) != "" {
		db = db.Where("type = ?", strings.TrimSpace(req.Type))
	}
	if strings.TrimSpace(req.Platform) != "" {
		db = db.Where("platform = ?", strings.TrimSpace(req.Platform))
	}
	if req.Published != nil {
		db = db.Where("published = ?", *req.Published)
	}
	return paginate[modelBiz.RemoteLegalDocument](db, &req.PageInfo, "id desc")
}

func (s *RemoteAdminService) SaveLegalDocument(req adminReq.RemoteLegalDocumentSave) (modelBiz.RemoteLegalDocument, error) {
	if strings.TrimSpace(req.Type) == "" || strings.TrimSpace(req.Platform) == "" || strings.TrimSpace(req.Version) == "" || strings.TrimSpace(req.Title) == "" {
		return modelBiz.RemoteLegalDocument{}, errors.New("参数错误")
	}
	format := strings.TrimSpace(req.ContentFormat)
	if format == "" {
		format = "markdown"
	}
	doc := modelBiz.RemoteLegalDocument{
		Type:          strings.TrimSpace(req.Type),
		Platform:      strings.TrimSpace(req.Platform),
		Version:       strings.TrimSpace(req.Version),
		Title:         strings.TrimSpace(req.Title),
		ContentFormat: format,
		Content:       req.Content,
		Published:     req.Published,
		EffectiveAt:   req.EffectiveAt,
	}
	if doc.Published && doc.EffectiveAt == nil {
		now := time.Now()
		doc.EffectiveAt = &now
	}
	if req.ID == 0 {
		err := global.AppDB.Create(&doc).Error
		return doc, err
	}
	doc.ID = req.ID
	err := global.AppDB.Model(&modelBiz.RemoteLegalDocument{}).Where("id = ?", req.ID).Updates(map[string]any{
		"type": doc.Type, "platform": doc.Platform, "version": doc.Version, "title": doc.Title,
		"content_format": doc.ContentFormat, "content": doc.Content, "published": doc.Published, "effective_at": doc.EffectiveAt,
	}).Error
	return doc, err
}

func (s *RemoteAdminService) DeleteLegalDocument(req adminReq.RemoteAdminIDRequest) error {
	return deleteRemoteAdminRecord(req.ID, &modelBiz.RemoteLegalDocument{}, "协议文档不存在或已删除")
}

func (s *RemoteAdminService) GetAppFooter(req adminReq.RemoteAppFooterGet) (modelBiz.RemoteAppFooterConfig, error) {
	platform := strings.ToLower(strings.TrimSpace(req.Platform))
	if platform == "" {
		platform = "ios"
	}
	var config modelBiz.RemoteAppFooterConfig
	if err := global.AppDB.Where("platform = ?", platform).Order("updated_at desc, id desc").First(&config).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return modelBiz.RemoteAppFooterConfig{
				Platform:      platform,
				CompanyName:   "禾屿科技",
				CopyrightText: "© 2026 禾屿科技",
				ICPText:       "ICP备案信息待更新",
				Published:     true,
			}, nil
		}
		return modelBiz.RemoteAppFooterConfig{}, err
	}
	return config, nil
}

func (s *RemoteAdminService) SaveAppFooter(req adminReq.RemoteAppFooterSave) (modelBiz.RemoteAppFooterConfig, error) {
	platform := strings.ToLower(strings.TrimSpace(req.Platform))
	if platform == "" {
		platform = "ios"
	}
	config := modelBiz.RemoteAppFooterConfig{
		Platform:      platform,
		CompanyName:   strings.TrimSpace(req.CompanyName),
		CopyrightText: strings.TrimSpace(req.CopyrightText),
		ICPText:       strings.TrimSpace(req.ICPText),
		RecordText:    strings.TrimSpace(req.RecordText),
		SupportURL:    strings.TrimSpace(req.SupportURL),
		PrivacyURL:    strings.TrimSpace(req.PrivacyURL),
		Published:     req.Published,
	}
	if config.CompanyName == "" || config.CopyrightText == "" || config.ICPText == "" {
		return modelBiz.RemoteAppFooterConfig{}, errors.New("公司名称、版权文案和 ICP 不能为空。")
	}
	if req.ID > 0 {
		config.ID = req.ID
		err := global.AppDB.Model(&modelBiz.RemoteAppFooterConfig{}).Where("id = ?", req.ID).Updates(map[string]any{
			"platform":       config.Platform,
			"company_name":   config.CompanyName,
			"copyright_text": config.CopyrightText,
			"icp_text":       config.ICPText,
			"record_text":    config.RecordText,
			"support_url":    config.SupportURL,
			"privacy_url":    config.PrivacyURL,
			"published":      config.Published,
		}).Error
		if err != nil {
			return modelBiz.RemoteAppFooterConfig{}, err
		}
		return config, global.AppDB.First(&config, req.ID).Error
	}

	var existing modelBiz.RemoteAppFooterConfig
	err := global.AppDB.Where("platform = ?", platform).First(&existing).Error
	if err == nil {
		req.ID = existing.ID
		return s.SaveAppFooter(req)
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return modelBiz.RemoteAppFooterConfig{}, err
	}
	err = global.AppDB.Create(&config).Error
	return config, err
}

func (s *RemoteAdminService) ListAppUpdates(req adminReq.RemoteAppUpdateSearch) (any, int64, error) {
	db := global.AppDB.Model(&modelBiz.RemoteAppUpdate{})
	if platform := strings.ToLower(strings.TrimSpace(req.Platform)); platform != "" {
		db = db.Where("platform = ?", platform)
	}
	if channel := strings.ToLower(strings.TrimSpace(req.Channel)); channel != "" {
		db = db.Where("channel = ?", channel)
	}
	if packageArch := normalizeRemoteUpdateArch(req.PackageArch); packageArch != "" {
		db = db.Where("package_arch = ?", packageArch)
	}
	if req.Published != nil {
		db = db.Where("published = ?", *req.Published)
	}
	return paginate[modelBiz.RemoteAppUpdate](db, &req.PageInfo, "released_at desc, id desc")
}

func (s *RemoteAdminService) SaveAppUpdate(req adminReq.RemoteAppUpdateSave) (modelBiz.RemoteAppUpdate, error) {
	update, err := buildRemoteAppUpdate(req)
	if err != nil {
		return modelBiz.RemoteAppUpdate{}, err
	}
	if req.ID == 0 {
		err := global.AppDB.Create(&update).Error
		return update, err
	}
	update.ID = req.ID
	updates := map[string]any{
		"platform":          update.Platform,
		"channel":           update.Channel,
		"version":           update.Version,
		"build_number":      update.BuildNumber,
		"package_arch":      update.PackageArch,
		"minimum_version":   update.MinimumVersion,
		"release_notes":     update.ReleaseNotes,
		"update_type":       update.UpdateType,
		"download_url":      update.DownloadURL,
		"app_store_url":     update.AppStoreURL,
		"package_file_id":   update.PackageFileID,
		"package_file_name": update.PackageFileName,
		"package_file_size": update.PackageFileSize,
		"package_sha256":    update.PackageSHA256,
		"force_update":      update.ForceUpdate,
		"published":         update.Published,
		"released_at":       update.ReleasedAt,
	}
	result := global.AppDB.Model(&modelBiz.RemoteAppUpdate{}).Where("id = ?", req.ID).Updates(updates)
	if result.Error != nil {
		return modelBiz.RemoteAppUpdate{}, result.Error
	}
	if result.RowsAffected == 0 {
		return modelBiz.RemoteAppUpdate{}, errors.New("版本记录不存在或已删除")
	}
	return update, global.AppDB.First(&update, req.ID).Error
}

func (s *RemoteAdminService) DeleteAppUpdate(req adminReq.RemoteAdminIDRequest) error {
	return deleteRemoteAdminRecord(req.ID, &modelBiz.RemoteAppUpdate{}, "版本记录不存在或已删除")
}

func (s *RemoteAdminService) ListLegalConsents(req adminReq.RemoteLegalConsentSearch) (any, int64, error) {
	db := global.AppDB.Model(&modelBiz.RemoteLegalConsent{})
	if req.UserID > 0 {
		db = db.Where("user_id = ?", req.UserID)
	}
	if req.DocumentID > 0 {
		db = db.Where("document_id = ?", req.DocumentID)
	}
	if strings.TrimSpace(req.DocumentType) != "" {
		db = db.Where("document_type = ?", strings.TrimSpace(req.DocumentType))
	}
	if strings.TrimSpace(req.Platform) != "" {
		db = db.Where("platform = ?", strings.TrimSpace(req.Platform))
	}
	return paginate[modelBiz.RemoteLegalConsent](db, &req.PageInfo, "id desc")
}

func (s *RemoteAdminService) DeleteLegalConsent(req adminReq.RemoteAdminIDRequest) error {
	return deleteRemoteAdminRecord(req.ID, &modelBiz.RemoteLegalConsent{}, "协议同意记录不存在或已删除")
}

func (s *RemoteAdminService) ListSubscriptions(req adminReq.RemoteSubscriptionSearch) (any, int64, error) {
	db := global.AppDB.Model(&modelBiz.RemoteSubscription{})
	if req.UserID > 0 {
		db = db.Where("user_id = ?", req.UserID)
	}
	if strings.TrimSpace(req.PlanCode) != "" {
		db = db.Where("plan_code = ?", strings.TrimSpace(req.PlanCode))
	}
	if strings.TrimSpace(req.Status) != "" {
		db = db.Where("status = ?", strings.TrimSpace(req.Status))
	}
	return paginate[modelBiz.RemoteSubscription](db, &req.PageInfo, "id desc")
}

func (s *RemoteAdminService) ListSubscriptionPlans(req adminReq.RemoteSubscriptionPlanSearch) (any, int64, error) {
	db := global.AppDB.Model(&modelBiz.RemoteSubscriptionPlan{})
	if strings.TrimSpace(req.Code) != "" {
		db = db.Where("code LIKE ?", "%"+strings.TrimSpace(req.Code)+"%")
	}
	if strings.TrimSpace(req.Status) != "" {
		db = db.Where("status = ?", strings.TrimSpace(req.Status))
	}
	return paginate[modelBiz.RemoteSubscriptionPlan](db, &req.PageInfo, "sort asc, id desc")
}

func (s *RemoteAdminService) ListSubscriptionOrders(req adminReq.RemoteSubscriptionOrderSearch) (any, int64, error) {
	db := global.AppDB.Model(&modelBiz.RemoteSubscriptionOrder{})
	if req.UserID > 0 {
		db = db.Where("user_id = ?", req.UserID)
	}
	if strings.TrimSpace(req.Email) != "" {
		var userIDs []uint
		if err := global.AppDB.Model(&modelBiz.RemoteUser{}).
			Where("email LIKE ?", "%"+strings.TrimSpace(req.Email)+"%").
			Pluck("id", &userIDs).Error; err != nil {
			return []modelBiz.RemoteSubscriptionOrder{}, 0, err
		}
		if len(userIDs) == 0 {
			return []modelBiz.RemoteSubscriptionOrder{}, 0, nil
		}
		db = db.Where("user_id IN ?", userIDs)
	}
	if strings.TrimSpace(req.PlanCode) != "" {
		db = db.Where("plan_code = ?", strings.TrimSpace(req.PlanCode))
	}
	if strings.TrimSpace(req.Status) != "" {
		db = db.Where("status = ?", strings.TrimSpace(req.Status))
	}
	if strings.TrimSpace(req.OutTradeNo) != "" {
		db = db.Where("out_trade_no LIKE ?", "%"+strings.TrimSpace(req.OutTradeNo)+"%")
	}
	if strings.TrimSpace(req.PayOrderNo) != "" {
		db = db.Where("pay_order_no LIKE ?", "%"+strings.TrimSpace(req.PayOrderNo)+"%")
	}

	var total int64
	if err := db.Count(&total).Error; err != nil {
		return []remoteAdminSubscriptionOrderResponse{}, 0, err
	}

	var orders []modelBiz.RemoteSubscriptionOrder
	if err := db.Scopes(req.PageInfo.Paginate()).Order("id desc").Find(&orders).Error; err != nil {
		return []remoteAdminSubscriptionOrderResponse{}, 0, err
	}

	userIDs := make([]uint, 0, len(orders))
	for _, order := range orders {
		if order.UserID > 0 {
			userIDs = append(userIDs, order.UserID)
		}
	}
	type userEmailRow struct {
		ID    uint
		Email string
	}
	var users []userEmailRow
	emailMap := make(map[uint]string, len(userIDs))
	if len(userIDs) > 0 {
		if err := global.AppDB.Model(&modelBiz.RemoteUser{}).Select("id", "email").Where("id IN ?", userIDs).Find(&users).Error; err != nil {
			return []remoteAdminSubscriptionOrderResponse{}, 0, err
		}
		for _, user := range users {
			emailMap[user.ID] = user.Email
		}
	}

	responses := make([]remoteAdminSubscriptionOrderResponse, 0, len(orders))
	for _, order := range orders {
		responses = append(responses, remoteAdminSubscriptionOrderResponse{
			RemoteSubscriptionOrder: order,
			Email:                   emailMap[order.UserID],
		})
	}
	return responses, total, nil
}

func (s *RemoteAdminService) ListAccountDeletions(req adminReq.RemoteAccountDeletionSearch) (any, int64, error) {
	db := global.AppDB.Model(&modelBiz.RemoteAccountDeletionRecord{})
	if req.UserID > 0 {
		db = db.Where("user_id = ?", req.UserID)
	}
	if strings.TrimSpace(req.EmailMasked) != "" {
		db = db.Where("email_masked LIKE ?", "%"+strings.TrimSpace(req.EmailMasked)+"%")
	}
	if strings.TrimSpace(req.EmailHash) != "" {
		db = db.Where("email_hash = ?", strings.TrimSpace(req.EmailHash))
	}
	if strings.TrimSpace(req.Operator) != "" {
		db = db.Where("operator = ?", strings.TrimSpace(req.Operator))
	}
	return paginate[modelBiz.RemoteAccountDeletionRecord](db, &req.PageInfo, "id desc")
}

func (s *RemoteAdminService) SaveSubscriptionPlan(req adminReq.RemoteSubscriptionPlanSave) (modelBiz.RemoteSubscriptionPlan, error) {
	code := strings.TrimSpace(req.Code)
	name := strings.TrimSpace(req.Name)
	status := strings.TrimSpace(req.Status)
	if status == "" {
		status = "active"
	}
	currency := strings.ToUpper(strings.TrimSpace(req.Currency))
	if currency == "" {
		currency = "CNY"
	}
	if code == "" || name == "" || (req.DurationMonths != 6 && req.DurationMonths != 12) || req.PriceFen <= 0 || !validStatus(status, "active", "disabled") {
		return modelBiz.RemoteSubscriptionPlan{}, errors.New("请完整填写套餐名称、时长和价格。")
	}
	plan := modelBiz.RemoteSubscriptionPlan{
		Code:           code,
		Name:           name,
		Description:    strings.TrimSpace(req.Description),
		DurationMonths: req.DurationMonths,
		PriceFen:       req.PriceFen,
		Currency:       currency,
		Status:         status,
		Sort:           req.Sort,
	}
	if req.ID == 0 {
		err := global.AppDB.Create(&plan).Error
		return plan, err
	}
	plan.ID = req.ID
	err := global.AppDB.Model(&modelBiz.RemoteSubscriptionPlan{}).Where("id = ?", req.ID).Updates(map[string]any{
		"code": code, "name": name, "description": plan.Description, "duration_months": plan.DurationMonths,
		"price_fen": plan.PriceFen, "currency": plan.Currency, "status": plan.Status, "sort": plan.Sort,
	}).Error
	return plan, err
}

func (s *RemoteAdminService) SaveSubscription(req adminReq.RemoteSubscriptionSave) (modelBiz.RemoteSubscription, error) {
	status := strings.TrimSpace(req.Status)
	if req.UserID == 0 || strings.TrimSpace(req.PlanCode) == "" || !validStatus(status, "free", "trial", "active", "expired", "canceled") {
		return modelBiz.RemoteSubscription{}, errors.New("参数错误")
	}
	startedAt := req.StartedAt
	if startedAt == nil && (status == "trial" || status == "active") {
		now := time.Now()
		startedAt = &now
	}
	sub := modelBiz.RemoteSubscription{UserID: req.UserID, PlanCode: strings.TrimSpace(req.PlanCode), Status: status, StartedAt: startedAt, ExpiresAt: req.ExpiresAt, Provider: strings.TrimSpace(req.Provider), ProviderOrderID: strings.TrimSpace(req.ProviderOrderID)}
	if req.ID == 0 {
		err := global.AppDB.Create(&sub).Error
		return sub, err
	}
	sub.ID = req.ID
	err := global.AppDB.Model(&modelBiz.RemoteSubscription{}).Where("id = ?", req.ID).Updates(map[string]any{"user_id": sub.UserID, "plan_code": sub.PlanCode, "status": sub.Status, "started_at": sub.StartedAt, "expires_at": sub.ExpiresAt, "provider": sub.Provider, "provider_order_id": sub.ProviderOrderID}).Error
	return sub, err
}

func paginate[T any](db *gorm.DB, pageInfo interface {
	Paginate() func(*gorm.DB) *gorm.DB
}, order string) ([]T, int64, error) {
	var total int64
	var list []T
	if err := db.Count(&total).Error; err != nil {
		return list, 0, err
	}
	err := db.Scopes(pageInfo.Paginate()).Order(order).Find(&list).Error
	return list, total, err
}

func validStatus(value string, allowed ...string) bool {
	value = strings.TrimSpace(value)
	for _, item := range allowed {
		if value == item {
			return true
		}
	}
	return false
}

func deleteRemoteAdminRecord(id uint, model any, notFoundMessage string) error {
	if id == 0 {
		return errors.New("参数错误")
	}
	result := global.AppDB.Where("id = ?", id).Delete(model)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return errors.New(notFoundMessage)
	}
	return nil
}

func remoteAdminEmailPhonePlaceholder(email string) string {
	sum := sha256.Sum256([]byte(strings.ToLower(strings.TrimSpace(email))))
	return "email:" + hex.EncodeToString(sum[:])[:24]
}

func buildRemoteAppUpdate(req adminReq.RemoteAppUpdateSave) (modelBiz.RemoteAppUpdate, error) {
	platform := normalizeRemoteUpdatePlatform(req.Platform)
	channel := normalizeRemoteUpdateChannel(req.Channel)
	updateType := normalizeRemoteUpdateType(req.UpdateType, platform)
	packageArch := normalizeRemoteUpdateArch(req.PackageArch)
	if packageArch == "" {
		packageArch = "universal"
	}
	version := strings.TrimSpace(req.Version)
	if platform == "" || version == "" {
		return modelBiz.RemoteAppUpdate{}, errors.New("平台和版本号不能为空。")
	}
	downloadURL := strings.TrimSpace(req.DownloadURL)
	appStoreURL := strings.TrimSpace(req.AppStoreURL)
	if downloadURL != "" && !isValidRemoteHTTPURL(downloadURL) {
		return modelBiz.RemoteAppUpdate{}, errors.New("下载链接必须是 http/https URL。")
	}
	if appStoreURL != "" && !isValidRemoteHTTPURL(appStoreURL) {
		return modelBiz.RemoteAppUpdate{}, errors.New("App Store 链接必须是 http/https URL。")
	}
	if req.Published {
		switch platform {
		case "ios":
			if appStoreURL == "" && downloadURL == "" {
				return modelBiz.RemoteAppUpdate{}, errors.New("发布 iOS 版本必须填写 App Store 链接或下载链接。")
			}
		default:
			if downloadURL == "" {
				return modelBiz.RemoteAppUpdate{}, errors.New("发布该平台版本必须填写下载链接。")
			}
		}
	}
	if platform == "macos" && updateType == "file" && downloadURL != "" && !strings.Contains(strings.ToLower(downloadURL), ".dmg") {
		return modelBiz.RemoteAppUpdate{}, errors.New("macOS 文件更新链接应指向 DMG 文件。")
	}
	releasedAt := req.ReleasedAt
	if req.Published && releasedAt == nil {
		now := time.Now()
		releasedAt = &now
	}
	return modelBiz.RemoteAppUpdate{
		Platform:        platform,
		Channel:         channel,
		Version:         version,
		BuildNumber:     strings.TrimSpace(req.BuildNumber),
		PackageArch:     packageArch,
		MinimumVersion:  strings.TrimSpace(req.MinimumVersion),
		ReleaseNotes:    strings.TrimSpace(req.ReleaseNotes),
		UpdateType:      updateType,
		DownloadURL:     downloadURL,
		AppStoreURL:     appStoreURL,
		PackageFileID:   req.PackageFileID,
		PackageFileName: strings.TrimSpace(req.PackageFileName),
		PackageFileSize: req.PackageFileSize,
		PackageSHA256:   strings.TrimSpace(req.PackageSHA256),
		ForceUpdate:     req.ForceUpdate,
		Published:       req.Published,
		ReleasedAt:      releasedAt,
	}, nil
}

func normalizeRemoteUpdatePlatform(platform string) string {
	switch strings.ToLower(strings.TrimSpace(platform)) {
	case "android", "windows", "macos", "ios", "all":
		return strings.ToLower(strings.TrimSpace(platform))
	default:
		return ""
	}
}

func normalizeRemoteUpdateChannel(channel string) string {
	channel = strings.ToLower(strings.TrimSpace(channel))
	if channel == "" {
		return "stable"
	}
	if validStatus(channel, "stable", "beta") {
		return channel
	}
	return "stable"
}

func normalizeRemoteUpdateArch(packageArch string) string {
	switch strings.ToLower(strings.TrimSpace(packageArch)) {
	case "arm64", "x86_64", "universal":
		return strings.ToLower(strings.TrimSpace(packageArch))
	default:
		return ""
	}
}

func normalizeRemoteUpdateType(updateType, platform string) string {
	updateType = strings.ToLower(strings.TrimSpace(updateType))
	if validStatus(updateType, "link", "file", "app_store") {
		return updateType
	}
	switch platform {
	case "macos":
		return "file"
	case "ios":
		return "app_store"
	default:
		return "link"
	}
}

func isValidRemoteHTTPURL(value string) bool {
	parsed, err := url.ParseRequestURI(value)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return false
	}
	return parsed.Scheme == "http" || parsed.Scheme == "https"
}
