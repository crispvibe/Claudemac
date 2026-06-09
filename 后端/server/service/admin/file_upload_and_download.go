package admin

import (
	"context"
	"crypto/md5"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"

	"gorm.io/gorm"
	"heyu/server/global"
	"heyu/server/model/admin"
	systemReq "heyu/server/model/admin/request"
	"heyu/server/utils/upload"
)

type FileUploadAndDownloadService struct{}

var FileUploadAndDownloadServiceApp = new(FileUploadAndDownloadService)

// 媒体库允许上传的文件扩展名白名单；SVG/HTML/JS 等可被浏览器直接执行的类型禁止进入
// 静态目录 /uploads/file 以防存储型 XSS 与目录投毒
var allowedUploadExts = map[string]struct{}{
	".png": {}, ".jpg": {}, ".jpeg": {}, ".gif": {}, ".webp": {}, ".bmp": {}, ".ico": {},
	".mp3": {}, ".wav": {}, ".m4a": {}, ".aac": {}, ".ogg": {},
	".mp4": {}, ".webm": {}, ".mov": {}, ".mkv": {}, ".avi": {},
	".pdf": {}, ".txt": {}, ".md": {}, ".csv": {}, ".json": {},
	".doc": {}, ".docx": {}, ".xls": {}, ".xlsx": {}, ".ppt": {}, ".pptx": {},
	".zip": {}, ".rar": {}, ".7z": {}, ".tar": {}, ".gz": {}, ".dmg": {},
}

const (
	defaultMaxUploadSize    int64 = 20 << 20  // 20MB 统一上限
	appPackageMaxUploadSize int64 = 300 << 20 // macOS DMG 安装包上限
)

func isAllowedUploadExt(ext string) bool {
	_, ok := allowedUploadExts[strings.ToLower(ext)]
	return ok
}

func uploadMaxSizeForExt(ext string) int64 {
	if strings.EqualFold(ext, ".dmg") {
		return appPackageMaxUploadSize
	}
	return defaultMaxUploadSize
}

func (fileUploadAndDownloadService *FileUploadAndDownloadService) UploadFile(fileHeader *multipart.FileHeader, classID uint, uploadedBy uint, noSave bool) (file admin.FileUploadAndDownload, err error) {
	if fileHeader == nil {
		return file, errors.New("文件不能为空")
	}
	if fileHeader.Size <= 0 {
		return file, errors.New("文件不能为空")
	}
	ext := strings.ToLower(filepath.Ext(fileHeader.Filename))
	if !isAllowedUploadExt(ext) {
		return file, errors.New("不允许上传该类型文件")
	}
	maxUploadSize := uploadMaxSizeForExt(ext)
	if fileHeader.Size > maxUploadSize {
		return file, fmt.Errorf("文件大小超过限制(最大 %dMB)", maxUploadSize>>20)
	}
	if !(noSave && classID == 0) {
		err = fileUploadAndDownloadService.ensureCategoryExists(classID)
	}
	if err != nil {
		return file, err
	}
	fileURL, fileKey, err := upload.NewOss().UploadFile(fileHeader)
	if err != nil {
		return file, err
	}
	file = admin.FileUploadAndDownload{
		Name:       strings.TrimSpace(fileHeader.Filename),
		Url:        fileURL,
		Key:        fileKey,
		ClassId:    classID,
		Mime:       fileHeader.Header.Get("Content-Type"),
		Ext:        strings.ToLower(filepath.Ext(fileHeader.Filename)),
		Size:       fileHeader.Size,
		UploadedBy: uploadedBy,
	}
	if file.Name == "" {
		file.Name = fileKey
	}
	if noSave {
		return file, nil
	}
	err = global.AppDB.Create(&file).Error
	return file, err
}

func (fileUploadAndDownloadService *FileUploadAndDownloadService) GetFileList(info systemReq.FileUploadAndDownloadSearch) (list []admin.FileUploadAndDownload, total int64, err error) {
	db := global.AppDB.Model(&admin.FileUploadAndDownload{})
	if keyword := strings.TrimSpace(info.Keyword); keyword != "" {
		db = db.Where("name LIKE ?", "%"+keyword+"%")
	}
	if info.ClassId > 0 {
		db = db.Where("class_id = ?", info.ClassId)
	}
	err = db.Count(&total).Error
	if err != nil {
		return nil, total, err
	}
	err = db.Scopes(info.PageInfo.Paginate()).Order("id desc").Find(&list).Error
	return list, total, err
}

func (fileUploadAndDownloadService *FileUploadAndDownloadService) DeleteFile(id uint) error {
	if id == 0 {
		return errors.New("文件不存在")
	}
	return global.AppDB.Transaction(func(tx *gorm.DB) error {
		var file admin.FileUploadAndDownload
		if err := tx.First(&file, id).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return errors.New("文件不存在")
			}
			return err
		}
		if err := upload.NewOss().DeleteFile(file.Key); err != nil {
			return err
		}
		return tx.Delete(&file).Error
	})
}

func (fileUploadAndDownloadService *FileUploadAndDownloadService) EditFileName(id uint, name string) error {
	name = strings.TrimSpace(name)
	if id == 0 {
		return errors.New("文件不存在")
	}
	if name == "" {
		return errors.New("文件名不能为空")
	}
	result := global.AppDB.Model(&admin.FileUploadAndDownload{}).Where("id = ?", id).Update("name", name)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return errors.New("文件不存在")
	}
	return nil
}

func (fileUploadAndDownloadService *FileUploadAndDownloadService) ImportURL(req systemReq.ImportURLReq, uploadedBy uint) (file admin.FileUploadAndDownload, err error) {
	if global.AppConfig.System.OssType != "local" {
		return file, errors.New("当前存储类型暂不支持URL导入")
	}
	if err = fileUploadAndDownloadService.ensureCategoryExists(req.ClassId); err != nil {
		return file, err
	}
	parsedURL, err := validateImportURL(req.URL)
	if err != nil {
		return file, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, parsedURL.String(), nil)
	if err != nil {
		return file, err
	}
	client := &http.Client{
		Timeout: 15 * time.Second,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
	response, err := client.Do(request)
	if err != nil {
		return file, errors.New("URL导入失败")
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return file, errors.New("URL导入失败")
	}
	const maxImportSize = 10 << 20
	content, err := io.ReadAll(io.LimitReader(response.Body, maxImportSize+1))
	if err != nil {
		return file, errors.New("URL导入失败")
	}
	if len(content) == 0 {
		return file, errors.New("远程文件为空")
	}
	if len(content) > maxImportSize {
		return file, errors.New("远程文件超过大小限制")
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		name = path.Base(parsedURL.Path)
	}
	name = sanitizeImportedFileName(name)
	if name == "" {
		name = fmt.Sprintf("import_%d", time.Now().Unix())
	}
	ext := filepath.Ext(name)
	if ext == "" {
		ext = filepath.Ext(parsedURL.Path)
		name += ext
	}
	if !isAllowedUploadExt(ext) {
		return file, errors.New("不允许导入该类型文件")
	}
	fileKey, fileURL, err := saveImportedLocalFile(name, content)
	if err != nil {
		return file, errors.New("URL导入失败")
	}
	file = admin.FileUploadAndDownload{
		Name:       name,
		Url:        fileURL,
		Key:        fileKey,
		ClassId:    req.ClassId,
		Mime:       response.Header.Get("Content-Type"),
		Ext:        strings.ToLower(ext),
		Size:       int64(len(content)),
		UploadedBy: uploadedBy,
	}
	err = global.AppDB.Create(&file).Error
	return file, err
}

func (fileUploadAndDownloadService *FileUploadAndDownloadService) ensureCategoryExists(classID uint) error {
	if classID == 0 {
		return nil
	}
	var category admin.AttachmentCategory
	if err := global.AppDB.First(&category, classID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("分类不存在")
		}
		return err
	}
	return nil
}

func validateImportURL(rawURL string) (*url.URL, error) {
	parsedURL, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil {
		return nil, errors.New("URL格式错误")
	}
	if parsedURL.Scheme != "http" && parsedURL.Scheme != "https" {
		return nil, errors.New("仅支持http或https地址")
	}
	hostname := parsedURL.Hostname()
	if hostname == "" {
		return nil, errors.New("URL格式错误")
	}
	if ip, err := netip.ParseAddr(hostname); err == nil {
		if !isPublicAddr(ip) {
			return nil, errors.New("不允许访问内网地址")
		}
		return parsedURL, nil
	}
	ips, err := net.LookupIP(hostname)
	if err != nil || len(ips) == 0 {
		return nil, errors.New("URL解析失败")
	}
	for _, ip := range ips {
		addr, ok := netip.AddrFromSlice(ip)
		if !ok || !isPublicAddr(addr) {
			return nil, errors.New("不允许访问内网地址")
		}
	}
	return parsedURL, nil
}

func isPublicAddr(addr netip.Addr) bool {
	return addr.IsValid() && !addr.IsLoopback() && !addr.IsPrivate() && !addr.IsMulticast() && !addr.IsLinkLocalUnicast() && !addr.IsLinkLocalMulticast() && !addr.IsUnspecified()
}

func sanitizeImportedFileName(name string) string {
	name = strings.TrimSpace(name)
	name = strings.ReplaceAll(name, "/", "_")
	name = strings.ReplaceAll(name, "\\", "_")
	return name
}

func saveImportedLocalFile(name string, content []byte) (fileKey string, fileURL string, err error) {
	ext := filepath.Ext(name)
	baseName := strings.TrimSuffix(name, ext)
	if baseName == "" {
		baseName = "import"
	}
	fileKey = fmt.Sprintf("%x_%d%s", md5.Sum([]byte(baseName)), time.Now().UnixNano(), ext)
	if err = os.MkdirAll(global.AppConfig.Local.StorePath, os.ModePerm); err != nil {
		return "", "", err
	}
	fullPath := filepath.Join(global.AppConfig.Local.StorePath, fileKey)
	if err = os.WriteFile(fullPath, content, 0o644); err != nil {
		return "", "", err
	}
	return fileKey, global.AppConfig.Local.Path + "/" + fileKey, nil
}
