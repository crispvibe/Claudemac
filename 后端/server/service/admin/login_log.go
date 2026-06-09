package admin

import (
	"heyu/server/global"
	"heyu/server/model/shared/request"
	"heyu/server/model/admin"
	systemReq "heyu/server/model/admin/request"
)

type LoginLogService struct{}

var LoginLogServiceApp = new(LoginLogService)

func (loginLogService *LoginLogService) CreateLoginLog(loginLog admin.LoginLog) (err error) {
	err = global.AppDB.Create(&loginLog).Error
	return err
}

func (loginLogService *LoginLogService) DeleteLoginLogByIds(ids request.IdsReq) (err error) {
	err = global.AppDB.Delete(&[]admin.LoginLog{}, "id in (?)", ids.Ids).Error
	return err
}

func (loginLogService *LoginLogService) DeleteLoginLog(loginLog admin.LoginLog) (err error) {
	err = global.AppDB.Delete(&loginLog).Error
	return err
}

func (loginLogService *LoginLogService) GetLoginLog(id uint) (loginLog admin.LoginLog, err error) {
	err = global.AppDB.Where("id = ?", id).First(&loginLog).Error
	return
}

func (loginLogService *LoginLogService) GetLoginLogInfoList(info systemReq.LoginLogSearch) (list interface{}, total int64, err error) {
	limit := info.PageSize
	offset := info.PageSize * (info.Page - 1)
	// 创建db
	db := global.AppDB.Model(&admin.LoginLog{})
	var loginLogs []admin.LoginLog
	// 如果有条件搜索 下方会自动创建搜索语句
	if info.Username != "" {
		db = db.Where("username LIKE ?", "%"+info.Username+"%")
	}
	if info.Status != false {
		db = db.Where("status = ?", info.Status)
	}
	err = db.Count(&total).Error
	if err != nil {
		return
	}
	err = db.Limit(limit).Offset(offset).Order("id desc").Preload("User").Find(&loginLogs).Error
	return loginLogs, total, err
}
