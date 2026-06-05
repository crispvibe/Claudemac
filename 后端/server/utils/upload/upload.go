package upload

import (
	"mime/multipart"

	"heyu/server/global"
)

// OSS 对象存储接口
type OSS interface {
	UploadFile(file *multipart.FileHeader) (string, string, error)
	DeleteFile(key string) error
}

// NewOss OSS的实例化方法
func NewOss() OSS {
	switch global.AppConfig.System.OssType {
	case "local":
		return &Local{}
	case "qiniu":
		return &Qiniu{}
	case "tencent-cos":
		return &TencentCOS{}
	case "aliyun-oss":
		return &AliyunOSS{}
	case "huawei-obs":
		return HuaWeiObs
	case "aws-s3":
		return &AwsS3{}
	case "cloudflare-r2":
		return &CloudflareR2{}
	case "minio":
		minioClient, err := GetMinio(global.AppConfig.Minio.Endpoint, global.AppConfig.Minio.AccessKeyId, global.AppConfig.Minio.AccessKeySecret, global.AppConfig.Minio.BucketName, global.AppConfig.Minio.UseSSL)
		if err != nil {
			global.AppLog.Warn("你配置了使用minio，但是初始化失败，请检查minio可用性或安全配置: " + err.Error())
			panic("minio初始化失败") // 建议这样做，用户自己配置了minio，如果报错了还要把服务开起来，使用起来也很危险
		}
		return minioClient
	default:
		return &Local{}
	}
}
