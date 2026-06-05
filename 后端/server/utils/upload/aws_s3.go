package upload

import (
	"errors"
	"fmt"
	"mime/multipart"
	"time"

	"heyu/server/global"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/credentials"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
	"go.uber.org/zap"
)

type AwsS3 struct{}

//@object: *AwsS3
//@function: UploadFile
//@description: Upload file to Aws S3 using aws-sdk-go
//@param: file *multipart.FileHeader
//@return: string, string, error

func (*AwsS3) UploadFile(file *multipart.FileHeader) (string, string, error) {
	session := newSession()
	uploader := s3manager.NewUploader(session)

	fileKey := fmt.Sprintf("%d%s", time.Now().Unix(), file.Filename)
	filename := global.AppConfig.AwsS3.PathPrefix + "/" + fileKey
	f, openError := file.Open()
	if openError != nil {
		global.AppLog.Error("function file.Open() failed", zap.Any("err", openError.Error()))
		return "", "", errors.New("function file.Open() failed, err:" + openError.Error())
	}
	defer f.Close() // 创建文件 defer 关闭

	_, err := uploader.Upload(&s3manager.UploadInput{
		Bucket: aws.String(global.AppConfig.AwsS3.Bucket),
		Key:    aws.String(filename),
		Body:   f,
		ContentType: aws.String(file.Header.Get("Content-Type")),
	})
	if err != nil {
		global.AppLog.Error("function uploader.Upload() failed", zap.Any("err", err.Error()))
		return "", "", err
	}

	return global.AppConfig.AwsS3.BaseURL + "/" + filename, fileKey, nil
}

//@object: *AwsS3
//@function: DeleteFile
//@description: Delete file from Aws S3 using aws-sdk-go
//@param: file *multipart.FileHeader
//@return: string, string, error

func (*AwsS3) DeleteFile(key string) error {
	session := newSession()
	svc := s3.New(session)
	filename := global.AppConfig.AwsS3.PathPrefix + "/" + key
	bucket := global.AppConfig.AwsS3.Bucket

	_, err := svc.DeleteObject(&s3.DeleteObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(filename),
	})
	if err != nil {
		global.AppLog.Error("function svc.DeleteObject() failed", zap.Any("err", err.Error()))
		return errors.New("function svc.DeleteObject() failed, err:" + err.Error())
	}

	_ = svc.WaitUntilObjectNotExists(&s3.HeadObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(filename),
	})
	return nil
}

// newSession Create S3 session
func newSession() *session.Session {
	sess, _ := session.NewSession(&aws.Config{
		Region:           aws.String(global.AppConfig.AwsS3.Region),
		Endpoint:         aws.String(global.AppConfig.AwsS3.Endpoint), //minio在这里设置地址,可以兼容
		S3ForcePathStyle: aws.Bool(global.AppConfig.AwsS3.S3ForcePathStyle),
		DisableSSL:       aws.Bool(global.AppConfig.AwsS3.DisableSSL),
		Credentials: credentials.NewStaticCredentials(
			global.AppConfig.AwsS3.SecretID,
			global.AppConfig.AwsS3.SecretKey,
			"",
		),
	})
	return sess
}
