package upload

import (
	"errors"
	"io"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"heyu/server/global"
	"heyu/server/utils"
	"go.uber.org/zap"
)

var mu sync.Mutex

type Local struct{}

//@object: *Local
//@function: UploadFile
//@description: 上传文件
//@param: file *multipart.FileHeader
//@return: string, string, error

func (*Local) UploadFile(file *multipart.FileHeader) (string, string, error) {
	// 读取文件后缀
	ext := filepath.Ext(file.Filename)
	// 读取文件名并加密
	name := strings.TrimSuffix(file.Filename, ext)
	name = utils.MD5V([]byte(name))
	// 拼接新文件名
	filename := name + "_" + time.Now().Format("20060102150405") + ext
	// 尝试创建此路径
	mkdirErr := os.MkdirAll(global.AppConfig.Local.StorePath, os.ModePerm)
	if mkdirErr != nil {
		global.AppLog.Error("function os.MkdirAll() failed", zap.Any("err", mkdirErr.Error()))
		return "", "", errors.New("function os.MkdirAll() failed, err:" + mkdirErr.Error())
	}
	// 拼接路径和文件名
	p := global.AppConfig.Local.StorePath + "/" + filename
	filepath := global.AppConfig.Local.Path + "/" + filename

	f, openError := file.Open() // 读取文件
	if openError != nil {
		global.AppLog.Error("function file.Open() failed", zap.Any("err", openError.Error()))
		return "", "", errors.New("function file.Open() failed, err:" + openError.Error())
	}
	defer f.Close() // 创建文件 defer 关闭

	out, createErr := os.Create(p)
	if createErr != nil {
		global.AppLog.Error("function os.Create() failed", zap.Any("err", createErr.Error()))

		return "", "", errors.New("function os.Create() failed, err:" + createErr.Error())
	}
	defer out.Close() // 创建文件 defer 关闭

	_, copyErr := io.Copy(out, f) // 传输（拷贝）文件
	if copyErr != nil {
		global.AppLog.Error("function io.Copy() failed", zap.Any("err", copyErr.Error()))
		return "", "", errors.New("function io.Copy() failed, err:" + copyErr.Error())
	}
	return filepath, filename, nil
}

//@object: *Local
//@function: DeleteFile
//@description: 删除文件
//@param: key string
//@return: error

func (*Local) DeleteFile(key string) error {
	// 检查 key 是否为空
	if key == "" {
		return errors.New("key不能为空")
	}

	// 验证 key 是否包含非法字符或尝试访问存储路径之外的文件
	if strings.Contains(key, "..") || strings.ContainsAny(key, `\/:*?"<>|`) {
		return errors.New("非法的key")
	}

	p := filepath.Join(global.AppConfig.Local.StorePath, key)

	// 检查文件是否存在
	if _, err := os.Stat(p); os.IsNotExist(err) {
		return errors.New("文件不存在")
	}

	// 使用文件锁防止并发删除
	mu.Lock()
	defer mu.Unlock()

	err := os.Remove(p)
	if err != nil {
		return errors.New("文件删除失败: " + err.Error())
	}

	return nil
}
