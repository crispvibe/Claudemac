package task

import (
	"errors"
	"fmt"
	"heyu/server/model/shared"
	"time"

	"gorm.io/gorm"
)

var clearTableWhitelist = map[string]map[string]struct{}{
	"operation_logs": {
		"created_at": {},
	},
	"jwt_blacklists": {
		"created_at": {},
	},
}

//@function: ClearTable
//@description: 清理数据库表数据
//@param: db(数据库对象) *gorm.DB, tableName(表名) string, compareField(比较字段) string, interval(间隔) string
//@return: error

func ClearTable(db *gorm.DB) error {
	var ClearTableDetail []shared.ClearDB

	ClearTableDetail = append(ClearTableDetail, shared.ClearDB{
		TableName:    "operation_logs",
		CompareField: "created_at",
		Interval:     "2160h",
	})

	ClearTableDetail = append(ClearTableDetail, shared.ClearDB{
		TableName:    "jwt_blacklists",
		CompareField: "created_at",
		Interval:     "168h",
	})

	if db == nil {
		return errors.New("db Cannot be empty")
	}

	for _, detail := range ClearTableDetail {
		duration, err := time.ParseDuration(detail.Interval)
		if err != nil {
			return err
		}
		if duration < 0 {
			return errors.New("parse duration < 0")
		}
		allowedFields, ok := clearTableWhitelist[detail.TableName]
		if !ok {
			return fmt.Errorf("table %s is not allowed", detail.TableName)
		}
		if _, ok = allowedFields[detail.CompareField]; !ok {
			return fmt.Errorf("field %s is not allowed for table %s", detail.CompareField, detail.TableName)
		}
		err = db.Exec(fmt.Sprintf("DELETE FROM %s WHERE %s < ?", detail.TableName, detail.CompareField), time.Now().Add(-duration)).Error
		if err != nil {
			return err
		}
	}
	return nil
}
