package admin

type RoleDataScope struct {
	RoleID      uint `gorm:"primaryKey;column:role_id"`
	ScopeRoleID uint `gorm:"primaryKey;column:scope_role_id"`
}

func (RoleDataScope) TableName() string {
	return "role_data_scopes"
}