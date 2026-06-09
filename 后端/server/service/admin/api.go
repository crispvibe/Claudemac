package admin

import (
	"errors"
	"fmt"
	"strings"

	"heyu/server/global"
	"heyu/server/model/shared/request"
	"heyu/server/model/admin"
	systemRes "heyu/server/model/admin/response"
	"gorm.io/gorm"
)

//@function: CreateApi
//@description: 新增基础api
//@param: api model.APICatalogEntry
//@return: err error

type ApiService struct{}

var ApiServiceApp = new(ApiService)

func (apiService *ApiService) CreateApi(api admin.APICatalogEntry) (err error) {
	if !errors.Is(global.AppDB.Where("path = ? AND method = ?", api.Path, api.Method).First(&admin.APICatalogEntry{}).Error, gorm.ErrRecordNotFound) {
		return errors.New("存在相同api")
	}
	return global.AppDB.Create(&api).Error
}

func (apiService *ApiService) GetApiGroups() (groups []string, groupApiMap map[string]string, err error) {
	var apis []admin.APICatalogEntry
	err = global.AppDB.Find(&apis).Error
	if err != nil {
		return
	}
	groupApiMap = make(map[string]string, 0)
	for i := range apis {
		pathArr := strings.Split(apis[i].Path, "/")
		newGroup := true
		for i2 := range groups {
			if groups[i2] == apis[i].ApiGroup {
				newGroup = false
			}
		}
		if newGroup {
			groups = append(groups, apis[i].ApiGroup)
		}
		groupApiMap[pathArr[1]] = apis[i].ApiGroup
	}
	return
}

func (apiService *ApiService) SyncApi() (newApis, deleteApis []admin.APICatalogEntry, err error) {
	newApis = make([]admin.APICatalogEntry, 0)
	deleteApis = make([]admin.APICatalogEntry, 0)
	var apis []admin.APICatalogEntry
	err = global.AppDB.Find(&apis).Error
	if err != nil {
		return
	}

	var cacheApis []admin.APICatalogEntry
	for i := range global.AppRouters {
		cacheApis = append(cacheApis, admin.APICatalogEntry{
			Path:   stripAdminSlug(global.AppRouters[i].Path),
			Method: global.AppRouters[i].Method,
		})
	}

	//对比数据库中的api和内存中的api，如果数据库中的api不存在于内存中，则把api放入删除数组，如果内存中的api不存在于数据库中，则把api放入新增数组
	for i := range cacheApis {
		var flag bool
		// 如果存在于内存不存在于api数组中
		for j := range apis {
			if cacheApis[i].Path == apis[j].Path && cacheApis[i].Method == apis[j].Method {
				flag = true
			}
		}
		if !flag {
			newApis = append(newApis, admin.APICatalogEntry{
				Path:        cacheApis[i].Path,
				Description: "",
				ApiGroup:    "",
				Method:      cacheApis[i].Method,
			})
		}
	}

	for i := range apis {
		var flag bool
		// 如果存在于api数组不存在于内存
		for j := range cacheApis {
			if cacheApis[j].Path == apis[i].Path && cacheApis[j].Method == apis[i].Method {
				flag = true
			}
		}
		if !flag {
			deleteApis = append(deleteApis, apis[i])
		}
	}
	return
}

func (apiService *ApiService) EnterSyncApi(syncApis systemRes.APISyncPayload) (err error) {
	return global.AppDB.Transaction(func(tx *gorm.DB) error {
		var txErr error
		if len(syncApis.NewApis) > 0 {
			txErr = tx.Create(&syncApis.NewApis).Error
			if txErr != nil {
				return txErr
			}
		}
		for i := range syncApis.DeleteApis {
			CasbinServiceApp.ClearCasbin(1, syncApis.DeleteApis[i].Path, syncApis.DeleteApis[i].Method)
			txErr = tx.Delete(&admin.APICatalogEntry{}, "path = ? AND method = ?", syncApis.DeleteApis[i].Path, syncApis.DeleteApis[i].Method).Error
			if txErr != nil {
				return txErr
			}
		}
		return nil
	})
}

//@function: DeleteApi
//@description: 删除基础api
//@param: api model.APICatalogEntry
//@return: err error

func (apiService *ApiService) DeleteApi(api admin.APICatalogEntry) (err error) {
	var entity admin.APICatalogEntry
	err = global.AppDB.First(&entity, "id = ?", api.ID).Error // 根据id查询api记录
	if errors.Is(err, gorm.ErrRecordNotFound) {                // api记录不存在
		return err
	}
	err = global.AppDB.Delete(&entity).Error
	if err != nil {
		return err
	}
	CasbinServiceApp.ClearCasbin(1, entity.Path, entity.Method)
	return nil
}

//@function: GetAPIInfoList
//@description: 分页获取数据,
//@param: api model.APICatalogEntry, info request.PageInfo, order string, desc bool
//@return: list interface{}, total int64, err error

func (apiService *ApiService) GetAPIInfoList(api admin.APICatalogEntry, info request.PageInfo, order string, desc bool) (list interface{}, total int64, err error) {
	limit := info.PageSize
	offset := info.PageSize * (info.Page - 1)
	db := global.AppDB.Model(&admin.APICatalogEntry{})
	var apiList []admin.APICatalogEntry

	if api.Path != "" {
		db = db.Where("path LIKE ?", "%"+api.Path+"%")
	}

	if api.Description != "" {
		db = db.Where("description LIKE ?", "%"+api.Description+"%")
	}

	if api.Method != "" {
		db = db.Where("method = ?", api.Method)
	}

	if api.ApiGroup != "" {
		db = db.Where("api_group = ?", api.ApiGroup)
	}

	err = db.Count(&total).Error

	if err != nil {
		return apiList, total, err
	}

	db = db.Limit(limit).Offset(offset)
	OrderStr := "id desc"
	if order != "" {
		orderMap := make(map[string]bool, 5)
		orderMap["id"] = true
		orderMap["path"] = true
		orderMap["api_group"] = true
		orderMap["description"] = true
		orderMap["method"] = true
		if !orderMap[order] {
			err = fmt.Errorf("非法的排序字段: %v", order)
			return apiList, total, err
		}
		OrderStr = order
		if desc {
			OrderStr = order + " desc"
		}
	}
	err = db.Order(OrderStr).Find(&apiList).Error
	return apiList, total, err
}

//@function: GetAllApis
//@description: 获取所有的api
//@return:  apis []model.APICatalogEntry, err error

func (apiService *ApiService) GetAllApis(roleID uint) (apis []admin.APICatalogEntry, err error) {
	parentRoleID, err := RoleServiceApp.GetParentRoleID(roleID)
	if err != nil {
		return nil, err
	}
	err = global.AppDB.Order("id desc").Find(&apis).Error
	if parentRoleID == 0 || !global.AppConfig.System.UseStrictAuth {
		return
	}
	paths := CasbinServiceApp.GetPolicyPathByRoleID(roleID)
	// 挑选 apis里面的path和method也在paths里面的api
	var scopedApis []admin.APICatalogEntry
	for i := range apis {
		for j := range paths {
			if paths[j].Path == apis[i].Path && paths[j].Method == apis[i].Method {
				scopedApis = append(scopedApis, apis[i])
			}
		}
	}
	return scopedApis, err
}

//@function: GetApiById
//@description: 根据id获取api
//@param: id float64
//@return: api model.APICatalogEntry, err error

func (apiService *ApiService) GetApiById(id int) (api admin.APICatalogEntry, err error) {
	err = global.AppDB.First(&api, "id = ?", id).Error
	return
}

//@function: UpdateApi
//@description: 根据id更新api
//@param: api model.APICatalogEntry
//@return: err error

func (apiService *ApiService) UpdateApi(api admin.APICatalogEntry) (err error) {
	var oldA admin.APICatalogEntry
	err = global.AppDB.First(&oldA, "id = ?", api.ID).Error
	if oldA.Path != api.Path || oldA.Method != api.Method {
		var duplicateApi admin.APICatalogEntry
		if ferr := global.AppDB.First(&duplicateApi, "path = ? AND method = ?", api.Path, api.Method).Error; ferr != nil {
			if !errors.Is(ferr, gorm.ErrRecordNotFound) {
				return ferr
			}
		} else {
			if duplicateApi.ID != api.ID {
				return errors.New("存在相同api路径")
			}
		}

	}
	if err != nil {
		return err
	}

	err = CasbinServiceApp.UpdateCasbinApi(oldA.Path, api.Path, oldA.Method, api.Method)
	if err != nil {
		return err
	}

	return global.AppDB.Save(&api).Error
}

//@function: DeleteApisByIds
//@description: 删除选中API
//@param: apis []model.APICatalogEntry
//@return: err error

func (apiService *ApiService) DeleteApisByIds(ids request.IdsReq) (err error) {
	return global.AppDB.Transaction(func(tx *gorm.DB) error {
		var apis []admin.APICatalogEntry
		err = tx.Find(&apis, "id in ?", ids.Ids).Error
		if err != nil {
			return err
		}
		err = tx.Delete(&[]admin.APICatalogEntry{}, "id in ?", ids.Ids).Error
		if err != nil {
			return err
		}
		for _, entry := range apis {
			CasbinServiceApp.ClearCasbin(1, entry.Path, entry.Method)
		}
		return err
	})
}
