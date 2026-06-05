package admin

import (
	"errors"
	"strings"

	"heyu/server/global"
	"heyu/server/model/admin"
	"gorm.io/gorm"
)

type AttachmentCategoryService struct{}

var AttachmentCategoryServiceApp = new(AttachmentCategoryService)

func (attachmentCategoryService *AttachmentCategoryService) GetCategoryList() (categories []admin.AttachmentCategory, err error) {
	err = global.AppDB.Order("sort asc, id asc").Find(&categories).Error
	if err != nil {
		return nil, err
	}
	return buildAttachmentCategoryTree(categories, 0), nil
}

func (attachmentCategoryService *AttachmentCategoryService) SaveCategory(category admin.AttachmentCategory) error {
	category.Name = strings.TrimSpace(category.Name)
	if category.Name == "" {
		return errors.New("分类名称不能为空")
	}
	if len([]rune(category.Name)) > 20 {
		return errors.New("分类名称最多20个字符")
	}
	if category.ID != 0 && category.Pid == category.ID {
		return errors.New("上级分类不能选择自身")
	}
	if category.Pid != 0 {
		var parent admin.AttachmentCategory
		err := global.AppDB.First(&parent, category.Pid).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("上级分类不存在")
		}
		if err != nil {
			return err
		}
	}
	if category.ID == 0 {
		return global.AppDB.Create(&category).Error
	}
	var existing admin.AttachmentCategory
	if err := global.AppDB.First(&existing, category.ID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("分类不存在")
		}
		return err
	}
	return global.AppDB.Model(&existing).Updates(map[string]interface{}{
		"name": category.Name,
		"pid":  category.Pid,
		"sort": category.Sort,
	}).Error
}

func (attachmentCategoryService *AttachmentCategoryService) DeleteCategory(id uint) error {
	if id == 0 {
		return errors.New("分类不存在")
	}
	return global.AppDB.Transaction(func(tx *gorm.DB) error {
		var category admin.AttachmentCategory
		if err := tx.First(&category, id).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return errors.New("分类不存在")
			}
			return err
		}
		var childrenCount int64
		if err := tx.Model(&admin.AttachmentCategory{}).Where("pid = ?", id).Count(&childrenCount).Error; err != nil {
			return err
		}
		if childrenCount > 0 {
			return errors.New("请先删除下级分类")
		}
		if err := tx.Model(&admin.FileUploadAndDownload{}).Where("class_id = ?", id).Update("class_id", 0).Error; err != nil {
			return err
		}
		return tx.Delete(&category).Error
	})
}

func buildAttachmentCategoryTree(categories []admin.AttachmentCategory, pid uint) []admin.AttachmentCategory {
	result := make([]admin.AttachmentCategory, 0)
	for _, category := range categories {
		if category.Pid != pid {
			continue
		}
		category.Children = buildAttachmentCategoryTree(categories, category.ID)
		result = append(result, category)
	}
	return result
}
