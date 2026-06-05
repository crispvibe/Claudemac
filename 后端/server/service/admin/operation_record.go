package admin

import (
	"heyu/server/global"
	"heyu/server/model/shared/request"
	"heyu/server/model/admin"
	systemReq "heyu/server/model/admin/request"
)

// OperationRecordService 负责操作日志的读写与清理。
type OperationRecordService struct{}

var OperationRecordServiceApp = new(OperationRecordService)

// DeleteOperationRecordsByIDs 批量删除操作日志。
func (operationRecordService *OperationRecordService) DeleteOperationRecordsByIDs(ids request.IdsReq) (err error) {
	err = global.AppDB.Delete(&[]admin.OperationRecord{}, "id in (?)", ids.Ids).Error
	return err
}

// DeleteOperationRecord 删除单条操作日志。
func (operationRecordService *OperationRecordService) DeleteOperationRecord(record admin.OperationRecord) (err error) {
	err = global.AppDB.Delete(&record).Error
	return err
}

// GetOperationRecord 根据 ID 获取单条操作日志。
func (operationRecordService *OperationRecordService) GetOperationRecord(id uint) (record admin.OperationRecord, err error) {
	err = global.AppDB.Where("id = ?", id).First(&record).Error
	return
}

// GetOperationRecordList 分页获取操作日志列表。
func (operationRecordService *OperationRecordService) GetOperationRecordList(info systemReq.OperationRecordSearch) (list interface{}, total int64, err error) {
	limit := info.PageSize
	offset := info.PageSize * (info.Page - 1)
	// 创建db
	db := global.AppDB.Model(&admin.OperationRecord{})
	var records []admin.OperationRecord
	// 如果有条件搜索 下方会自动创建搜索语句
	if info.Method != "" {
		db = db.Where("method = ?", info.Method)
	}
	if info.Path != "" {
		db = db.Where("path LIKE ?", "%"+info.Path+"%")
	}
	if info.Status != 0 {
		db = db.Where("status = ?", info.Status)
	}
	err = db.Count(&total).Error
	if err != nil {
		return
	}
	err = db.Order("id desc").Limit(limit).Offset(offset).Preload("User").Find(&records).Error
	return records, total, err
}
