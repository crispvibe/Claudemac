package internal

import (
	"fmt"
	"heyu/server/setting"
	"heyu/server/global"
	"gorm.io/gorm/logger"
)

type Writer struct {
	cfg    setting.GeneralDB
	writer logger.Writer
}

func NewWriter(cfg setting.GeneralDB) *Writer {
	return &Writer{cfg: cfg}
}

// Printf 格式化打印日志
func (c *Writer) Printf(message string, data ...any) {

	// 当有日志时候均需要输出到控制台
	fmt.Printf(message, data...)

	// 当开启了zap的情况，会打印到日志记录
	if c.cfg.LogZap {
		switch c.cfg.LogLevel() {
		case logger.Silent:
			global.AppLog.Debug(fmt.Sprintf(message, data...))
		case logger.Error:
			global.AppLog.Error(fmt.Sprintf(message, data...))
		case logger.Warn:
			global.AppLog.Warn(fmt.Sprintf(message, data...))
		case logger.Info:
			global.AppLog.Info(fmt.Sprintf(message, data...))
		default:
			global.AppLog.Info(fmt.Sprintf(message, data...))
		}
		return
	}
}
