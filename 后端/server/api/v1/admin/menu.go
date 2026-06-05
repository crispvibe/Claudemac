package admin

import (
	"heyu/server/global"
	"heyu/server/model/shared/request"
	"heyu/server/model/shared/response"
	"heyu/server/model/admin"
	systemReq "heyu/server/model/admin/request"
	systemRes "heyu/server/model/admin/response"
	"heyu/server/utils"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type NavigationApi struct{}

// GetMenu
// @Tags      Navigation
// @Summary   获取用户动态路由
// @Security  ApiKeyAuth
// @Produce   application/json
// @Param     data  body      request.Empty                                                  true  "空"
// @Success   200   {object}  response.Response{data=systemRes.NavigationMenusResponse,msg=string}  "获取用户动态路由,返回包括系统菜单详情列表"
// @Router    /navigation/routes [post]
func (a *NavigationApi) GetMenu(c *gin.Context) {
	menus, err := menuService.GetMenuTree(utils.GetUserRoleID(c))
	if err != nil {
		global.AppLog.Error("获取失败!", zap.Error(err))
		response.ErrorMessage("获取失败", c)
		return
	}
	if menus == nil {
		menus = []admin.NavigationMenu{}
	}
	response.SuccessPayload(systemRes.NavigationMenusResponse{Menus: menus}, "获取成功", c)
}

// GetBaseMenuTree
// @Tags      Navigation
// @Summary   获取用户动态路由
// @Security  ApiKeyAuth
// @Produce   application/json
// @Param     data  body      request.Empty                                                      true  "空"
// @Success   200   {object}  response.Response{data=systemRes.NavigationEntriesResponse,msg=string}  "获取用户动态路由,返回包括系统菜单列表"
// @Router    /navigation/tree [post]
func (a *NavigationApi) GetBaseMenuTree(c *gin.Context) {
	roleID := utils.GetUserRoleID(c)
	menus, err := menuService.GetBaseMenuTree(roleID)
	if err != nil {
		global.AppLog.Error("获取失败!", zap.Error(err))
		response.ErrorMessage("获取失败", c)
		return
	}
	response.SuccessPayload(systemRes.NavigationEntriesResponse{Menus: menus}, "获取成功", c)
}

// AssignRoleNavigation
// @Tags      Navigation
// @Summary   增加menu和角色关联关系
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      systemReq.AssignRoleNavigationRequest  true  "角色ID"
// @Success   200   {object}  response.Response{msg=string}   "增加menu和角色关联关系"
// @Router    /navigation/assign-role [post]
func (a *NavigationApi) AssignRoleNavigation(c *gin.Context) {
	var roleNavigationRequest systemReq.AssignRoleNavigationRequest
	err := c.ShouldBindJSON(&roleNavigationRequest)
	if err != nil {
		failInvalidParams(c)
		return
	}
	if err := utils.Verify(roleNavigationRequest, utils.RoleIdVerify); err != nil {
		failValidation(c)
		return
	}
	adminRoleID := utils.GetUserRoleID(c)
	if err := menuService.AssignRoleNavigation(roleNavigationRequest.Menus, adminRoleID, roleNavigationRequest.RoleID); err != nil {
		global.AppLog.Error("添加失败!", zap.Error(err))
		response.ErrorMessage("添加失败", c)
	} else {
		response.SuccessMessage("添加成功", c)
	}
}

// GetRoleNavigation
// @Tags      Navigation
// @Summary   获取指定角色menu
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      request.GetRoleId                                          true  "角色ID"
// @Success   200   {object}  response.Response{data=map[string]interface{},msg=string}  "获取指定角色menu"
// @Router    /navigation/role-tree [post]
func (a *NavigationApi) GetRoleNavigation(c *gin.Context) {
	var param request.GetRoleId
	err := c.ShouldBindJSON(&param)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(param, utils.RoleIdVerify)
	if err != nil {
		failValidation(c)
		return
	}
	menus, err := menuService.GetRoleNavigation(&param)
	if err != nil {
		global.AppLog.Error("获取失败!", zap.Error(err))
		response.Result(response.ERROR, systemRes.NavigationMenusResponse{Menus: menus}, "获取失败", c)
		return
	}
	response.SuccessPayload(gin.H{"menus": menus}, "获取成功", c)
}

// AddBaseMenu
// @Tags      Menu
// @Summary   新增菜单
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      admin.NavigationEntry             true  "路由path, 父菜单ID, 路由name, 前端页面组件标识, 排序标记"
// @Success   200   {object}  response.Response{msg=string}  "新增菜单"
// @Router    /navigation/create [post]
func (a *NavigationApi) AddBaseMenu(c *gin.Context) {
	var menu admin.NavigationEntry
	err := c.ShouldBindJSON(&menu)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(menu, utils.MenuVerify)
	if err != nil {
		failValidation(c)
		return
	}
	err = utils.Verify(menu.Meta, utils.MenuMetaVerify)
	if err != nil {
		failValidation(c)
		return
	}
	err = menuService.AddBaseMenu(menu)
	if err != nil {
		global.AppLog.Error("添加失败!", zap.Error(err))
		response.ErrorMessage("添加失败", c)
		return
	}
	response.SuccessMessage("添加成功", c)
}

// DeleteBaseMenu
// @Tags      Menu
// @Summary   删除菜单
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      request.GetById                true  "菜单id"
// @Success   200   {object}  response.Response{msg=string}  "删除菜单"
// @Router    /navigation/delete [post]
func (a *NavigationApi) DeleteBaseMenu(c *gin.Context) {
	var menu request.GetById
	err := c.ShouldBindJSON(&menu)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(menu, utils.IdVerify)
	if err != nil {
		failValidation(c)
		return
	}
	err = baseMenuService.DeleteBaseMenu(menu.ID)
	if err != nil {
		global.AppLog.Error("删除失败!", zap.Error(err))
		response.ErrorMessage("删除失败", c)
		return
	}
	response.SuccessMessage("删除成功", c)
}

// UpdateBaseMenu
// @Tags      Menu
// @Summary   更新菜单
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      admin.NavigationEntry             true  "路由path, 父菜单ID, 路由name, 前端页面组件标识, 排序标记"
// @Success   200   {object}  response.Response{msg=string}  "更新菜单"
// @Router    /navigation/update [post]
func (a *NavigationApi) UpdateBaseMenu(c *gin.Context) {
	var menu admin.NavigationEntry
	err := c.ShouldBindJSON(&menu)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(menu, utils.MenuVerify)
	if err != nil {
		failValidation(c)
		return
	}
	err = utils.Verify(menu.Meta, utils.MenuMetaVerify)
	if err != nil {
		failValidation(c)
		return
	}
	err = baseMenuService.UpdateBaseMenu(menu)
	if err != nil {
		global.AppLog.Error("更新失败!", zap.Error(err))
		response.ErrorMessage("更新失败", c)
		return
	}
	response.SuccessMessage("更新成功", c)
}

// GetBaseMenuById
// @Tags      Menu
// @Summary   根据id获取菜单
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      request.GetById                                                   true  "菜单id"
// @Success   200   {object}  response.Response{data=systemRes.NavigationEntryResponse,msg=string}  "根据id获取菜单,返回包括系统菜单列表"
// @Router    /navigation/detail [post]
func (a *NavigationApi) GetBaseMenuById(c *gin.Context) {
	var idInfo request.GetById
	err := c.ShouldBindJSON(&idInfo)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(idInfo, utils.IdVerify)
	if err != nil {
		failValidation(c)
		return
	}
	menu, err := baseMenuService.GetBaseMenuById(idInfo.ID)
	if err != nil {
		global.AppLog.Error("获取失败!", zap.Error(err))
		response.ErrorMessage("获取失败", c)
		return
	}
	response.SuccessPayload(systemRes.NavigationEntryResponse{Menu: menu}, "获取成功", c)
}

// GetMenuList
// @Tags      Menu
// @Summary   分页获取基础menu列表
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      request.PageInfo                                        true  "页码, 每页大小"
// @Success   200   {object}  response.Response{data=response.PageResult,msg=string}  "分页获取基础menu列表,返回包括列表,总数,页码,每页数量"
// @Router    /navigation/list [post]
func (a *NavigationApi) GetMenuList(c *gin.Context) {
	roleID := utils.GetUserRoleID(c)
	menuList, err := menuService.GetInfoList(roleID)
	if err != nil {
		global.AppLog.Error("获取失败!", zap.Error(err))
		response.ErrorMessage("获取失败", c)
		return
	}
	response.SuccessPayload(menuList, "获取成功", c)
}
