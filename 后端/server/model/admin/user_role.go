package admin

// AccountRole 是账户和角色的连接表
type AccountRole struct {
	AccountID uint `gorm:"primaryKey;column:account_id"`
	RoleID    uint `gorm:"primaryKey;column:role_id"`
}

func (s *AccountRole) TableName() string {
	return "account_roles"
}