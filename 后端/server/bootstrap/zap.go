package bootstrap

import (
    "fmt"
    "heyu/server/bootstrap/internal"
    "heyu/server/global"
    "heyu/server/utils"
    "go.uber.org/zap"
    "go.uber.org/zap/zapcore"
    "os"
)

// Zap 获取 zap.Logger
func Zap() (logger *zap.Logger) {
	if ok, _ := utils.PathExists(global.AppConfig.Zap.Director); !ok { // 判断是否有Director文件夹
		fmt.Printf("create %v directory\n", global.AppConfig.Zap.Director)
		_ = os.Mkdir(global.AppConfig.Zap.Director, os.ModePerm)
	}
	levels := global.AppConfig.Zap.Levels()
	length := len(levels)
	cores := make([]zapcore.Core, 0, length)
	for i := 0; i < length; i++ {
		core := internal.NewZapCore(levels[i])
		cores = append(cores, core)
	}
    // 构建基础 logger（错误级别的入库逻辑已在自定义 ZapCore 中处理）
    logger = zap.New(zapcore.NewTee(cores...))
	// 启用 Error 及以上级别的堆栈捕捉，确保 entry.Stack 可用
	opts := []zap.Option{zap.AddStacktrace(zapcore.ErrorLevel)}
	if global.AppConfig.Zap.ShowLine {
		opts = append(opts, zap.AddCaller())
	}
	logger = logger.WithOptions(opts...)
	return logger
}
