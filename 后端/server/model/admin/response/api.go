package response

import (
	"heyu/server/model/admin"
)

type APIEntryResponse struct {
	Api admin.APICatalogEntry `json:"api"`
}

type APIEntryListResponse struct {
	Apis []admin.APICatalogEntry `json:"apis"`
}

type APISyncPayload struct {
	NewApis    []admin.APICatalogEntry `json:"newApis"`
	DeleteApis []admin.APICatalogEntry `json:"deleteApis"`
}

// 兼容别名，便于存量代码渐进迁移，不影响 JSON 行为。