package admin

import (
	"fmt"
	"time"

	"heyu/server/global"
	"heyu/server/model/shared"
	"heyu/server/model/shared/request"
	"heyu/server/model/shared/response"
	"heyu/server/model/admin"
	systemReq "heyu/server/model/admin/request"
	systemRes "heyu/server/model/admin/response"
	"heyu/server/utils"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// Login
// @Tags     Base
// @Summary  用户登录
// @Produce   application/json
// @Param    data  body      systemReq.Login                                             true  "用户名, 密码"
// @Success  200   {object}  response.Response{data=systemRes.LoginResponse,msg=string}  "返回包括用户信息与过期时间"
// @Router   /auth/login [post]
func (b *BaseApi) Login(c *gin.Context) {
	var l systemReq.Login
	err := c.ShouldBindJSON(&l)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(l, utils.LoginVerify)
	if err != nil {
		failValidation(c)
		return
	}
	key := c.ClientIP()
	err = verifyLoginCaptcha(l, key)
	if err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}

	failedLoginCacheTTL := 900
	maxFailedLoginAttempts := 10
	failedAttempts := failedLoginAttempts(key)
	_, ok := global.BlackCache.Get(loginFailedCounterKey(key))
	if failedAttempts >= maxFailedLoginAttempts {
		// 频繁失败触发锁定，广播到通知中心
		notificationService.PublishAsync(admin.SecurityNotification{
			Category: admin.NotificationCategorySecurity,
			Level:    admin.NotificationLevelDanger,
			Title:    "检测到疑似暴力登录",
			Content:  "来源 IP " + c.ClientIP() + " 在短时间内登录失败次数过多，已临时冻结该 IP 的登录请求。",
			Source:   "auth.login",
			RefType:  "ip",
			RefID:    c.ClientIP(),
		})
		response.ErrorMessage("登录失败次数过多，请稍后再试", c)
		return
	}
	if !ok {
		global.BlackCache.Set(loginFailedCounterKey(key), 0, time.Second*time.Duration(failedLoginCacheTTL))
	}

	u := &admin.Account{Username: l.Username, Password: l.Password}
	user, err := userService.Login(u)
	if err != nil {
		global.AppLog.Error("登陆失败! 用户名不存在或者密码错误!", zap.Error(err))
		markLoginFailure(key)
		response.ErrorMessage("用户名不存在或者密码错误", c)
		// 记录登录失败日志
		loginLogService.CreateLoginLog(admin.LoginLog{
			Username:     l.Username,
			Ip:           c.ClientIP(),
			Agent:        c.Request.UserAgent(),
			Status:       false,
			ErrorMessage: "用户名不存在或者密码错误",
		})
		return
	}
	if user.Enable != 1 {
		global.AppLog.Error("登陆失败! 用户被禁止登录!")
		markLoginFailure(key)
		response.ErrorMessage("用户被禁止登录", c)
		// 记录登录失败日志
		loginLogService.CreateLoginLog(admin.LoginLog{
			Username:     l.Username,
			Ip:           c.ClientIP(),
			Agent:        c.Request.UserAgent(),
			Status:       false,
			ErrorMessage: "用户被禁止登录",
			UserID:       user.ID,
		})
		return
	}
	b.TokenNext(c, *user)
}

// TokenNext 登录以后签发jwt
func (b *BaseApi) TokenNext(c *gin.Context, user admin.Account) {
	token, claims, err := utils.LoginToken(&user)
	if err != nil {
		global.AppLog.Error("获取token失败!", zap.Error(err))
		response.ErrorMessage("获取token失败", c)
		return
	}
	// 记录登录成功日志
	loginLogService.CreateLoginLog(admin.LoginLog{
		Username: user.Username,
		Ip:       c.ClientIP(),
		Agent:    c.Request.UserAgent(),
		Status:   true,
		ErrorMessage: "登录成功",
	})
	clearLoginFailure(c.ClientIP())
	if !global.AppConfig.System.UseMultipoint {
		utils.SetToken(c, token, int(claims.RegisteredClaims.ExpiresAt.Unix()-time.Now().Unix()))
		response.SuccessPayload(systemRes.LoginResponse{
			User:      user,
			ExpiresAt: claims.RegisteredClaims.ExpiresAt.Unix() * 1000,
		}, "登录成功", c)
		return
	}

	if jwtStr, err := jwtService.GetRedisJWT(user.Username); err == redis.Nil {
		if err := utils.SetRedisJWT(token, user.Username); err != nil {
			global.AppLog.Error("设置登录状态失败!", zap.Error(err))
			response.ErrorMessage("设置登录状态失败", c)
			return
		}
		utils.SetToken(c, token, int(claims.RegisteredClaims.ExpiresAt.Unix()-time.Now().Unix()))
		response.SuccessPayload(systemRes.LoginResponse{
			User:      user,
			ExpiresAt: claims.RegisteredClaims.ExpiresAt.Unix() * 1000,
		}, "登录成功", c)
	} else if err != nil {
		global.AppLog.Error("设置登录状态失败!", zap.Error(err))
		response.ErrorMessage("设置登录状态失败", c)
	} else {
		var blackJWT admin.JwtBlacklist
		blackJWT.Jwt = jwtStr
		if err := jwtService.JsonInBlacklist(blackJWT); err != nil {
			response.ErrorMessage("jwt作废失败", c)
			return
		}
		if err := utils.SetRedisJWT(token, user.GetUsername()); err != nil {
			response.ErrorMessage("设置登录状态失败", c)
			return
		}
		utils.SetToken(c, token, int(claims.RegisteredClaims.ExpiresAt.Unix()-time.Now().Unix()))
		response.SuccessPayload(systemRes.LoginResponse{
			User:      user,
			ExpiresAt: claims.RegisteredClaims.ExpiresAt.Unix() * 1000,
		}, "登录成功", c)
	}
}

// Register
// @Tags      Account
// @Summary  用户注册账号
// @Produce   application/json
// @Param    data  body      systemReq.Register                                            true  "用户名, 昵称, 密码, 角色ID"
// @Success  200   {object}  response.Response{data=systemRes.UserProfileResponse,msg=string}  "用户注册账号,返回包括用户信息"
// @Router   /accounts/create [post]
func (b *BaseApi) Register(c *gin.Context) {
	var r systemReq.Register
	err := c.ShouldBindJSON(&r)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(r, utils.RegisterVerify)
	if err != nil {
		failValidation(c)
		return
	}
	var roles []admin.Role
	for _, v := range r.RoleIds {
		roles = append(roles, admin.Role{
			RoleID: v,
		})
	}
	user := &admin.Account{Username: r.Username, NickName: r.NickName, Password: r.Password, HeaderImg: r.HeaderImg, PrimaryRoleID: r.PrimaryRoleID, Roles: roles, Enable: r.Enable, Phone: r.Phone, Email: r.Email}
	userReturn, err := userService.Register(*user)
	if err != nil {
		global.AppLog.Error("注册失败!", zap.Error(err))
		response.Result(response.ERROR, systemRes.UserProfileResponse{User: userReturn}, "注册失败", c)
		return
	}
	notificationService.PublishAsync(admin.SecurityNotification{
		Category: admin.NotificationCategorySecurity,
		Level:    admin.NotificationLevelWarning,
		Title:    "后台新增账号",
		Content:  "管理员新增后台账号：" + r.Username + "，请确认是否为预期操作。",
		Source:   "accounts.create",
		RefType:  "account",
		RefID:    r.Username,
	})
	response.SuccessPayload(systemRes.UserProfileResponse{User: userReturn}, "注册成功", c)
}

// ChangePassword
// @Tags      Account
// @Summary   用户修改密码
// @Security  ApiKeyAuth
// @Produce  application/json
// @Param     data  body      systemReq.ChangePasswordReq    true  "用户名, 原密码, 新密码"
// @Success   200   {object}  response.Response{msg=string}  "用户修改密码"
// @Router    /accounts/password/change [post]
func (b *BaseApi) ChangePassword(c *gin.Context) {
	var req systemReq.ChangePasswordReq
	err := c.ShouldBindJSON(&req)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(req, utils.ChangePasswordVerify)
	if err != nil {
		failValidation(c)
		return
	}
	uid := utils.GetUserID(c)
	u := &admin.Account{BaseModel: global.BaseModel{ID: uid}, Password: req.Password}
	err = userService.ChangePassword(u, req.NewPassword)
	if err != nil {
		global.AppLog.Error("修改失败!", zap.Error(err))
		response.ErrorMessage("修改失败，原密码与当前账户不符", c)
		return
	}
	response.SuccessMessage("修改成功", c)
}

// GetUserList
// @Tags      Account
// @Summary   分页获取用户列表
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      systemReq.GetUserList                                        true  "页码, 每页大小"
// @Success   200   {object}  response.Response{data=response.PageResult,msg=string}  "分页获取用户列表,返回包括列表,总数,页码,每页数量"
// @Router    /accounts/list [post]
func (b *BaseApi) GetUserList(c *gin.Context) {
	var pageInfo systemReq.GetUserList
	err := c.ShouldBindJSON(&pageInfo)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(pageInfo, utils.PageInfoVerify)
	if err != nil {
		failValidation(c)
		return
	}
	list, total, err := userService.GetUserInfoList(pageInfo)
	if err != nil {
		global.AppLog.Error("获取失败!", zap.Error(err))
		response.ErrorMessage("获取失败", c)
		return
	}
	response.SuccessPayload(response.PageResult{
		List:     list,
		Total:    total,
		Page:     pageInfo.Page,
		PageSize: pageInfo.PageSize,
	}, "获取成功", c)
}

// SetUserPrimaryRole
// @Tags      Account
// @Summary   更改用户权限
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      systemReq.SetUserPrimaryRole   true  "用户UUID, 角色ID"
// @Success   200   {object}  response.Response{msg=string}  "设置用户权限"
// @Router    /accounts/role/primary [post]
func (b *BaseApi) SetUserPrimaryRole(c *gin.Context) {
	var sua systemReq.SetUserPrimaryRole
	err := c.ShouldBindJSON(&sua)
	if err != nil {
		response.ErrorMessage("参数错误", c)
		return
	}
	if UserVerifyErr := utils.Verify(sua, utils.SetUserRoleVerify); UserVerifyErr != nil {
		response.ErrorMessage("参数校验失败", c)
		return
	}
	err = userService.SetUserPrimaryRole(sua.ID, sua.RoleID)
	if err != nil {
		global.AppLog.Error("修改失败!", zap.Error(err))
		response.ErrorMessage("修改失败", c)
		return
	}
	operatorID := utils.GetUserID(c)
	notificationService.PublishAsync(admin.SecurityNotification{
		Category: admin.NotificationCategorySecurity,
		Level:    admin.NotificationLevelWarning,
		Title:    "用户主角色已变更",
		Content: fmt.Sprintf(
			"操作人ID=%d 将账号ID=%d 的主角色切换为 RoleID=%d，请确认是否为预期操作。",
			operatorID, sua.ID, sua.RoleID,
		),
		Source:  "accounts.role.primary",
		RefType: "account",
		RefID:   fmt.Sprintf("%d", sua.ID),
	})
	response.SuccessMessage("修改成功", c)
}

// SetUserRoles
// @Tags      Account
// @Summary   设置用户权限
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      systemReq.SetUserRoles         true  "用户UUID, 角色ID"
// @Success   200   {object}  response.Response{msg=string}  "设置用户权限"
// @Router    /accounts/roles/update [post]
func (b *BaseApi) SetUserRoles(c *gin.Context) {
	var sua systemReq.SetUserRoles
	err := c.ShouldBindJSON(&sua)
	if err != nil {
		failInvalidParams(c)
		return
	}
	roleID := utils.GetUserRoleID(c)
	err = userService.SetUserRoles(roleID, sua.ID, sua.RoleIds)
	if err != nil {
		global.AppLog.Error("修改失败!", zap.Error(err))
		response.ErrorMessage("修改失败", c)
		return
	}
	response.SuccessMessage("修改成功", c)
}

// DeleteUser
// @Tags      Account
// @Summary   删除用户
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      request.GetById                true  "用户ID"
// @Success   200   {object}  response.Response{msg=string}  "删除用户"
// @Router    /accounts/remove [delete]
func (b *BaseApi) DeleteUser(c *gin.Context) {
	var reqId request.GetById
	err := c.ShouldBindJSON(&reqId)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(reqId, utils.IdVerify)
	if err != nil {
		failValidation(c)
		return
	}
	jwtId := utils.GetUserID(c)
	if jwtId == uint(reqId.ID) {
		response.ErrorMessage("删除失败, 无法删除自己。", c)
		return
	}
	err = userService.DeleteUser(reqId.ID)
	if err != nil {
		global.AppLog.Error("删除失败!", zap.Error(err))
		response.ErrorMessage("删除失败", c)
		return
	}
	response.SuccessMessage("删除成功", c)
}

// SetUserInfo
// @Tags      Account
// @Summary   设置用户信息
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      admin.Account                                             true  "ID, 用户名, 昵称, 头像链接"
// @Success   200   {object}  response.Response{data=map[string]interface{},msg=string}  "设置用户信息"
// @Router    /accounts/update [put]
func (b *BaseApi) SetUserInfo(c *gin.Context) {
	var user systemReq.ChangeUserInfo
	err := c.ShouldBindJSON(&user)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(user, utils.IdVerify)
	if err != nil {
		failValidation(c)
		return
	}
	if len(user.RoleIds) != 0 {
		roleID := utils.GetUserRoleID(c)
		err = userService.SetUserRoles(roleID, user.ID, user.RoleIds)
		if err != nil {
			global.AppLog.Error("设置失败!", zap.Error(err))
			response.ErrorMessage("设置失败", c)
			return
		}
	}
	err = userService.SetUserInfo(admin.Account{
		BaseModel: global.BaseModel{
			ID: user.ID,
		},
		NickName:  user.NickName,
		HeaderImg: user.HeaderImg,
		Phone:     user.Phone,
		Email:     user.Email,
		Enable:    user.Enable,
	})
	if err != nil {
		global.AppLog.Error("设置失败!", zap.Error(err))
		response.ErrorMessage("设置失败", c)
		return
	}
	response.SuccessMessage("设置成功", c)
}

// SetSelfInfo
// @Tags      Account
// @Summary   设置个人资料
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      admin.Account                                             true  "昵称, 头像链接, 手机号, 邮箱"
// @Success   200   {object}  response.Response{data=map[string]interface{},msg=string}  "设置个人资料"
// @Router    /accounts/profile [put]
func (b *BaseApi) SetSelfInfo(c *gin.Context) {
	var user systemReq.ChangeUserInfo
	err := c.ShouldBindJSON(&user)
	if err != nil {
		failInvalidParams(c)
		return
	}
	user.ID = utils.GetUserID(c)
	err = userService.SetSelfInfo(admin.Account{
		BaseModel: global.BaseModel{
			ID: user.ID,
		},
		NickName:  user.NickName,
		HeaderImg: user.HeaderImg,
		Phone:     user.Phone,
		Email:     user.Email,
		Enable:    user.Enable,
	})
	if err != nil {
		global.AppLog.Error("设置失败!", zap.Error(err))
		response.ErrorMessage("设置失败", c)
		return
	}
	response.SuccessMessage("设置成功", c)
}

// SetSelfSetting
// @Tags      Account
// @Summary   设置用户配置
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      map[string]interface{}  true  "用户配置数据"
// @Success   200   {object}  response.Response{data=map[string]interface{},msg=string}  "设置用户配置"
// @Router    /accounts/preferences [put]
func (b *BaseApi) SetSelfSetting(c *gin.Context) {
	var req shared.JSONMap
	err := c.ShouldBindJSON(&req)
	if err != nil {
		failInvalidParams(c)
		return
	}

	err = userService.SetSelfSetting(req, utils.GetUserID(c))
	if err != nil {
		global.AppLog.Error("设置失败!", zap.Error(err))
		response.ErrorMessage("设置失败", c)
		return
	}
	response.SuccessMessage("设置成功", c)
}

// GetUserInfo
// @Tags      Account
// @Summary   获取用户信息
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Success   200  {object}  response.Response{data=map[string]interface{},msg=string}  "获取用户信息"
// @Router    /accounts/profile [get]
func (b *BaseApi) GetUserInfo(c *gin.Context) {
	uuid := utils.GetUserUuid(c)
	ReqUser, err := userService.GetUserInfo(uuid)
	if err != nil {
		global.AppLog.Error("获取失败!", zap.Error(err))
		response.ErrorMessage("获取失败", c)
		return
	}
	response.SuccessPayload(gin.H{"userInfo": ReqUser}, "获取成功", c)
}

// ResetPassword
// @Tags      Account
// @Summary   重置用户密码
// @Security  ApiKeyAuth
// @Produce  application/json
// @Param     data  body      admin.Account                 true  "ID"
// @Success   200   {object}  response.Response{msg=string}  "重置用户密码"
// @Router    /accounts/password/reset [post]
func (b *BaseApi) ResetPassword(c *gin.Context) {
	var rps systemReq.ResetPassword
	err := c.ShouldBindJSON(&rps)
	if err != nil {
		failInvalidParams(c)
		return
	}
	roleID := utils.GetUserRoleID(c)
	err = userService.ResetPassword(roleID, rps.ID, rps.Password)
	if err != nil {
		global.AppLog.Error("重置失败!", zap.Error(err))
		response.ErrorMessage("重置失败", c)
		return
	}
	operatorID := utils.GetUserID(c)
	notificationService.PublishAsync(admin.SecurityNotification{
		Category: admin.NotificationCategorySecurity,
		Level:    admin.NotificationLevelDanger,
		Title:    "管理员重置了账号密码",
		Content: fmt.Sprintf(
			"操作人ID=%d 重置了账号ID=%d 的登录密码。若非本人操作请立即排查入侵风险。",
			operatorID, rps.ID,
		),
		Source:  "accounts.password.reset",
		RefType: "account",
		RefID:   fmt.Sprintf("%d", rps.ID),
	})
	response.SuccessMessage("重置成功", c)
}
