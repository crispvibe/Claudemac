package admin

import (
	"errors"
	"strconv"

	"gorm.io/gorm"

	gormadapter "github.com/casbin/gorm-adapter/v3"
	"heyu/server/global"
	"heyu/server/model/admin/request"
	"heyu/server/utils"
	_ "github.com/go-sql-driver/mysql"
)

//@function: UpdateCasbin
//@description: 更新casbin权限
//@param: roleId string, casbinInfos []request.CasbinInfo
//@return: error

type CasbinService struct{}

var CasbinServiceApp = new(CasbinService)

func (casbinService *CasbinService) UpdateCasbin(adminRoleID, roleID uint, casbinInfos []request.CasbinInfo) error {

	err := RoleServiceApp.CheckRoleScope(adminRoleID, roleID)
	if err != nil {
		return err
	}

	if global.AppConfig.System.UseStrictAuth {
		apis, e := ApiServiceApp.GetAllApis(adminRoleID)
		if e != nil {
			return e
		}

		for i := range casbinInfos {
			hasApi := false
			for j := range apis {
				if apis[j].Path == casbinInfos[i].Path && apis[j].Method == casbinInfos[i].Method {
					hasApi = true
					break
				}
			}
			if !hasApi {
				return errors.New("存在api不在权限列表中")
			}
		}
	}

	roleKey := strconv.Itoa(int(roleID))
	casbinService.ClearCasbin(0, roleKey)
	rules := [][]string{}
	//做权限去重处理
	deduplicateMap := make(map[string]bool)
	for _, v := range casbinInfos {
		key := roleKey + v.Path + v.Method
		if _, ok := deduplicateMap[key]; !ok {
			deduplicateMap[key] = true
			rules = append(rules, []string{roleKey, v.Path, v.Method})
		}
	}
	if len(rules) == 0 {
		return nil
	} // 设置空权限无需调用 AddPolicies 方法
	e := utils.GetCasbin()
	success, _ := e.AddPolicies(rules)
	if !success {
		return errors.New("存在相同api,添加失败,请联系管理员")
	}
	return nil
}

//@function: UpdateCasbinApi
//@description: API更新随动
//@param: oldPath string, newPath string, oldMethod string, newMethod string
//@return: error

func (casbinService *CasbinService) UpdateCasbinApi(oldPath string, newPath string, oldMethod string, newMethod string) error {
	err := global.AppDB.Model(&gormadapter.CasbinRule{}).Where("v1 = ? AND v2 = ?", oldPath, oldMethod).Updates(map[string]interface{}{
		"v1": newPath,
		"v2": newMethod,
	}).Error
	if err != nil {
		return err
	}

	e := utils.GetCasbin()
	return e.LoadPolicy()
}

//@function: GetPolicyPathByRoleID
//@description: 获取权限列表
//@param: roleId string
//@return: pathMaps []request.CasbinInfo

func (casbinService *CasbinService) GetPolicyPathByRoleID(roleID uint) (pathMaps []request.CasbinInfo) {
	e := utils.GetCasbin()
	roleKey := strconv.Itoa(int(roleID))
	list, _ := e.GetFilteredPolicy(0, roleKey)
	for _, v := range list {
		pathMaps = append(pathMaps, request.CasbinInfo{
			Path:   v[1],
			Method: v[2],
		})
	}
	return pathMaps
}

//@function: ClearCasbin
//@description: 清除匹配的权限
//@param: v int, p ...string
//@return: bool

func (casbinService *CasbinService) ClearCasbin(v int, p ...string) bool {
	e := utils.GetCasbin()
	success, _ := e.RemoveFilteredPolicy(v, p...)
	return success
}

//@function: RemoveFilteredPolicy
//@description: 使用数据库方法清理筛选的politicy 此方法需要调用FreshCasbin方法才可以在系统中即刻生效
//@param: db *gorm.DB, roleId string
//@return: error

func (casbinService *CasbinService) RemoveFilteredPolicy(db *gorm.DB, roleID string) error {
	return db.Delete(&gormadapter.CasbinRule{}, "v0 = ?", roleID).Error
}

//@function: SyncPolicy
//@description: 同步目前数据库的policy 此方法需要调用FreshCasbin方法才可以在系统中即刻生效
//@param: db *gorm.DB, roleId string, rules [][]string
//@return: error

func (casbinService *CasbinService) SyncPolicy(db *gorm.DB, roleID string, rules [][]string) error {
	err := casbinService.RemoveFilteredPolicy(db, roleID)
	if err != nil {
		return err
	}
	return casbinService.AddPolicies(db, rules)
}

//@function: AddPolicies
//@description: 添加匹配的权限
//@param: v int, p ...string
//@return: bool

func (casbinService *CasbinService) AddPolicies(db *gorm.DB, rules [][]string) error {
	var casbinRules []gormadapter.CasbinRule
	for i := range rules {
		casbinRules = append(casbinRules, gormadapter.CasbinRule{
			Ptype: "p",
			V0:    rules[i][0],
			V1:    rules[i][1],
			V2:    rules[i][2],
		})
	}
	return db.Create(&casbinRules).Error
}

func (casbinService *CasbinService) FreshCasbin() (err error) {
	e := utils.GetCasbin()
	err = e.LoadPolicy()
	return err
}
