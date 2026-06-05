import service from '@/utils/request'
export const getFileList = (data) => {
  return service({
    url: '/attachments/getFileList',
    method: 'post',
    data
  })
}

export const deleteFile = (data) => {
  return service({
    url: '/attachments/deleteFile',
    method: 'post',
    data
  })
}

/**
 * 编辑文件名或者备注
 * @param data
 * @returns {*}
 */
export const editFileName = (data) => {
  return service({
    url: '/attachments/editFileName',
    method: 'post',
    data
  })
}

/**
 * 导入URL
 * @param data
 * @returns {*}
 */
export const importURL = (data) => {
  return service({
    url: '/attachments/importURL',
    method: 'post',
    data
  })
}


// 上传文件 暂时用于头像上传
export const uploadFile = (data, params = {}) => {
  return service({
    url: "/attachments/upload",
    method: "post",
    data,
    params
  });
};
