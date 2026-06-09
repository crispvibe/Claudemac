import service from '@/utils/request'

// 操作日志接口已切换至去 Sys 化的新路径，后端保留一段旧路径过渡期，若回滚可临时切回
export const deleteOperationRecord = (data) => {
  return service({
    url: '/operation-logs/delete',
    method: 'delete',
    data
  })
}

export const deleteOperationRecordsByIDs = (data) => {
  return service({
    url: '/operation-logs/deleteByIds',
    method: 'delete',
    data
  })
}

export const getOperationRecordList = (params) => {
  return service({
    url: '/operation-logs/list',
    method: 'get',
    params
  })
}
