package initialize

import (
	"heyu/server/global"
	"heyu/server/model/admin"
)

type joinTableRegistration struct {
	Model     any
	Field     string
	JoinTable any
}

var joinTableRegistrations = []joinTableRegistration{
	{Model: &admin.Account{}, Field: "Roles", JoinTable: &admin.AccountRole{}},
	{Model: &admin.Role{}, Field: "Users", JoinTable: &admin.AccountRole{}},
	{Model: &admin.Role{}, Field: "NavigationEntries", JoinTable: &admin.RoleNavigationBinding{}},
	{Model: &admin.NavigationEntry{}, Field: "Roles", JoinTable: &admin.RoleNavigationBinding{}},
	{Model: &admin.Role{}, Field: "DataRoleIds", JoinTable: &admin.RoleDataScope{}},
}

func RegisterJoinTables() error {
	if global.AppDB == nil {
		return nil
	}
	for _, item := range joinTableRegistrations {
		if err := global.AppDB.SetupJoinTable(item.Model, item.Field, item.JoinTable); err != nil {
			return err
		}
	}
	return nil
}
