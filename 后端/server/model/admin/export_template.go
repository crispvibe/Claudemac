package admin

import "heyu/server/global"

type ExportTemplate struct {
	global.BaseModel
	DBName       string `json:"dbName" gorm:"column:db_name;comment:数据库名"`
	Name         string `json:"name" gorm:"column:name;comment:模板名称"`
	SourceTable  string `json:"tableName" gorm:"column:table_name;comment:数据表名"`
	TemplateID   string `json:"templateId" gorm:"column:template_id;comment:模板ID"`
	TemplateInfo string `json:"templateInfo" gorm:"column:template_info;type:text;comment:模板信息"`
	SQL          string `json:"sql" gorm:"column:sql;type:text;comment:查询SQL"`
	ImportSQL    string `json:"importSql" gorm:"column:import_sql;type:text;comment:导入SQL"`
	Limit        int64  `json:"limit" gorm:"column:limit;comment:条数限制"`
	OrderBy      string `json:"order" gorm:"column:order;comment:排序字段"`
}

func (ExportTemplate) TableName() string {
	return "export_templates"
}