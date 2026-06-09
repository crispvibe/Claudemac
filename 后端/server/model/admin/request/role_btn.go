package request

type RoleButtonBindingRequest struct {
	MenuID   uint   `json:"menuID"`
	RoleID   uint   `json:"roleId"`
	Selected []uint `json:"selected"`
}
