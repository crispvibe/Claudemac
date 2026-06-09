package response

import "heyu/server/model/admin"


type NavigationMenusResponse struct {
	Menus []admin.NavigationMenu `json:"menus"`
}


type NavigationEntriesResponse struct {
	Menus []admin.NavigationEntry `json:"menus"`
}


type NavigationEntryResponse struct {
	Menu admin.NavigationEntry `json:"menu"`
}
