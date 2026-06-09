package request

import (
	"heyu/server/model/shared/request"
	"heyu/server/model/admin"
)

// api分页条件查询及排序结构体
type SearchApiParams struct {
	admin.APICatalogEntry
	request.PageInfo
	OrderKey string `json:"orderKey"` // 排序
	Desc     bool   `json:"desc"`     // 排序方式:升序false(默认)|降序true
}
