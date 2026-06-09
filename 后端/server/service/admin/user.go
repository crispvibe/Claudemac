package admin

import (
	"errors"
	"fmt"
	"time"

	"heyu/server/model/shared"
	systemReq "heyu/server/model/admin/request"

	"heyu/server/global"
	"heyu/server/model/admin"
	"heyu/server/utils"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

//@function: Register
//@description: 用户注册
//@param: u model.Account
//@return: userInter admin.Account, err error

type UserService struct{}

var UserServiceApp = new(UserService)

func (userService *UserService) Register(u admin.Account) (userInter admin.Account, err error) {
	var user admin.Account
	if !errors.Is(global.AppDB.Where("username = ?", u.Username).First(&user).Error, gorm.ErrRecordNotFound) { // 判断用户名是否注册
		return userInter, errors.New("用户名已注册")
	}
	// 否则 附加uuid 密码hash加密 注册
	u.Password = utils.BcryptHash(u.Password)
	u.UUID = uuid.New()
	err = global.AppDB.Create(&u).Error
	return u, err
}

//@function: Login
//@description: 用户登录
//@param: u *model.Account
//@return: err error, userInter *model.Account

func (userService *UserService) Login(u *admin.Account) (userInter *admin.Account, err error) {
	if nil == global.AppDB {
		return nil, fmt.Errorf("db not init")
	}

	var user admin.Account
	err = global.AppDB.Where("username = ?", u.Username).Preload("Roles").Preload("PrimaryRole").First(&user).Error
	if err == nil {
		if ok := utils.BcryptCheck(u.Password, user.Password); !ok {
			return nil, errors.New("密码错误")
		}
		MenuServiceApp.EnsureUserDefaultEntry(&user)
	}
	return &user, err
}

//@function: ChangePassword
//@description: 修改用户密码
//@param: u *model.Account, newPassword string
//@return: err error

func (userService *UserService) ChangePassword(u *admin.Account, newPassword string) (err error) {
	var user admin.Account
	err = global.AppDB.Select("id, password").Where("id = ?", u.ID).First(&user).Error
	if err != nil {
		return err
	}
	if ok := utils.BcryptCheck(u.Password, user.Password); !ok {
		return errors.New("原密码错误")
	}
	pwd := utils.BcryptHash(newPassword)
	err = global.AppDB.Model(&user).Update("password", pwd).Error
	return err
}

//@function: GetUserInfoList
//@description: 分页获取数据
//@param: info request.PageInfo
//@return: err error, list interface{}, total int64

func (userService *UserService) GetUserInfoList(info systemReq.GetUserList) (list interface{}, total int64, err error) {
	limit := info.PageSize
	offset := info.PageSize * (info.Page - 1)
	db := global.AppDB.Model(&admin.Account{})
	var userList []admin.Account

	if info.NickName != "" {
		db = db.Where("nick_name LIKE ?", "%"+info.NickName+"%")
	}
	if info.Phone != "" {
		db = db.Where("phone LIKE ?", "%"+info.Phone+"%")
	}
	if info.Username != "" {
		db = db.Where("username LIKE ?", "%"+info.Username+"%")
	}
	if info.Email != "" {
		db = db.Where("email LIKE ?", "%"+info.Email+"%")
	}

	err = db.Count(&total).Error
	if err != nil {
		return
	}
	err = db.Limit(limit).Offset(offset).Preload("Roles").Preload("PrimaryRole").Find(&userList).Error
	return userList, total, err
}

//@function: SetUserPrimaryRole
//@description: 设置一个用户的权限
//@param: id uint, roleID uint
//@return: err error

func (userService *UserService) SetUserPrimaryRole(id uint, roleID uint) (err error) {

	assignErr := global.AppDB.Where("account_id = ? AND role_id = ?", id, roleID).First(&admin.AccountRole{}).Error
	if errors.Is(assignErr, gorm.ErrRecordNotFound) {
		return errors.New("该用户无此角色")
	}

	var role admin.Role
	err = global.AppDB.Where("role_id = ?", roleID).First(&role).Error
	if err != nil {
		return err
	}
	var roleMenus []admin.RoleNavigationBinding
	var roleMenuIDs []uint
	err = global.AppDB.Where("role_id = ?", roleID).Find(&roleMenus).Error
	if err != nil {
		return err
	}

	for i := range roleMenus {
		roleMenuIDs = append(roleMenuIDs, roleMenus[i].MenuId)
	}

	var ownedMenus []admin.NavigationEntry
	err = global.AppDB.Preload("Parameters").Where("id in (?)", roleMenuIDs).Find(&ownedMenus).Error
	if err != nil {
		return err
	}
	hasMenu := false
	for i := range ownedMenus {
		if ownedMenus[i].Name == role.DefaultEntry {
			hasMenu = true
			break
		}
	}
	if !hasMenu {
		return errors.New("找不到默认路由,无法切换本角色")
	}

	err = global.AppDB.Model(&admin.Account{}).Where("id = ?", id).Update("primary_role_id", roleID).Error
	return err
}

//@function: SetUserRoles
//@description: 设置一个用户的权限
//@param: id uint, roleIds []string
//@return: err error

func (userService *UserService) SetUserRoles(adminRoleID, id uint, roleIds []uint) (err error) {
	return global.AppDB.Transaction(func(tx *gorm.DB) error {
		var user admin.Account
		primaryRoleID := uint(0)
		TxErr := tx.Where("id = ?", id).First(&user).Error
		if TxErr != nil {
			global.AppLog.Debug(TxErr.Error())
			return errors.New("查询用户数据失败")
		}
		if len(roleIds) == 0 {
			return errors.New("至少保留一个角色")
		}
		primaryRoleID = roleIds[0]
		TxErr = tx.Delete(&[]admin.AccountRole{}, "account_id = ?", id).Error
		if TxErr != nil {
			return TxErr
		}
		var userRoles []admin.AccountRole
		for _, v := range roleIds {
			e := RoleServiceApp.CheckRoleScope(adminRoleID, v)
			if e != nil {
				return e
			}
			userRoles = append(userRoles, admin.AccountRole{
				AccountID: id, RoleID: v,
			})
		}
		TxErr = tx.Create(&userRoles).Error
		if TxErr != nil {
			return TxErr
		}
		TxErr = tx.Model(&user).Update("primary_role_id", primaryRoleID).Error
		if TxErr != nil {
			return TxErr
		}
		// 返回 nil 提交事务
		return nil
	})
}

//@function: DeleteUser
//@description: 删除用户
//@param: id float64
//@return: err error

func (userService *UserService) DeleteUser(id int) (err error) {
	return global.AppDB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("id = ?", id).Delete(&admin.Account{}).Error; err != nil {
			return err
		}
		if err := tx.Delete(&[]admin.AccountRole{}, "account_id = ?", id).Error; err != nil {
			return err
		}
		return nil
	})
}

//@function: SetUserInfo
//@description: 设置用户信息
//@param: reqUser model.Account
//@return: err error, user model.Account

func (userService *UserService) SetUserInfo(req admin.Account) error {
	return global.AppDB.Model(&admin.Account{}).
		Select("updated_at", "nick_name", "header_img", "phone", "email", "enable").
		Where("id=?", req.ID).
		Updates(map[string]interface{}{
			"updated_at": time.Now(),
			"nick_name":  req.NickName,
			"header_img": req.HeaderImg,
			"phone":      req.Phone,
			"email":      req.Email,
			"enable":     req.Enable,
		}).Error
}

//@function: SetSelfInfo
//@description: 设置用户信息
//@param: reqUser model.Account
//@return: err error, user model.Account

func (userService *UserService) SetSelfInfo(req admin.Account) error {
	return global.AppDB.Model(&admin.Account{}).
		Select("updated_at", "nick_name", "header_img", "phone", "email").
		Where("id=?", req.ID).
		Updates(map[string]interface{}{
			"updated_at": time.Now(),
			"nick_name":  req.NickName,
			"header_img": req.HeaderImg,
			"phone":      req.Phone,
			"email":      req.Email,
		}).Error
}

//@function: SetSelfSetting
//@description: 设置用户配置
//@param: req datatypes.JSON, uid uint
//@return: err error

func (userService *UserService) SetSelfSetting(req shared.JSONMap, uid uint) error {
	return global.AppDB.Model(&admin.Account{}).Where("id = ?", uid).Update("origin_setting", req).Error
}

//@function: GetUserInfo
//@description: 获取用户信息
//@param: uuid uuid.UUID
//@return: err error, user admin.Account

func (userService *UserService) GetUserInfo(uuid uuid.UUID) (user admin.Account, err error) {
	var reqUser admin.Account
	err = global.AppDB.Preload("Roles").Preload("PrimaryRole").First(&reqUser, "uuid = ?", uuid).Error
	if err != nil {
		return reqUser, err
	}
	MenuServiceApp.EnsureUserDefaultEntry(&reqUser)
	return reqUser, err
}

//@function: FindUserById
//@description: 通过id获取用户信息
//@param: id int
//@return: err error, user *model.Account

func (userService *UserService) FindUserById(id int) (user *admin.Account, err error) {
	var u admin.Account
	err = global.AppDB.Where("id = ?", id).First(&u).Error
	return &u, err
}

//@function: FindUserByUuid
//@description: 通过uuid获取用户信息
//@param: uuid string
//@return: err error, user *model.Account

func (userService *UserService) FindUserByUuid(uuid string) (user *admin.Account, err error) {
	var u admin.Account
	if err = global.AppDB.Where("uuid = ?", uuid).First(&u).Error; err != nil {
		return &u, errors.New("用户不存在")
	}
	return &u, nil
}

//@function: ResetPassword
//@description: 重置用户密码
//@param: ID uint, password string
//@return: err error

func (userService *UserService) ResetPassword(adminRoleID, ID uint, password string) (err error) {
	var user admin.Account
	err = global.AppDB.Select("id, primary_role_id").Where("id = ?", ID).First(&user).Error
	if err != nil {
		return err
	}
	if err = RoleServiceApp.CheckRoleScope(adminRoleID, user.PrimaryRoleID); err != nil {
		return err
	}
	err = global.AppDB.Model(&admin.Account{}).Where("id = ?", ID).Update("password", utils.BcryptHash(password)).Error
	return err
}
