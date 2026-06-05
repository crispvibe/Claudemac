<template>
  <div class="surface-panel remote-page">
    <div class="filter-panel compact-filter">
      <el-form :inline="true" :model="search">
        <el-form-item label="用户ID"><el-input-number v-model="search.userId" :min="0" /></el-form-item>
        <el-form-item label="名称"><el-input v-model="search.deviceName" clearable /></el-form-item>
        <el-form-item label="类型"><el-select v-model="search.deviceType" clearable><el-option label="desktop" value="desktop" /><el-option label="ios" value="ios" /></el-select></el-form-item>
        <el-form-item label="状态"><el-select v-model="search.status" clearable><el-option label="active" value="active" /><el-option label="disabled" value="disabled" /></el-select></el-form-item>
        <el-form-item><el-button type="primary" @click="reload">查询</el-button><el-button @click="reset">重置</el-button></el-form-item>
      </el-form>
    </div>
    <el-table :data="list">
      <el-table-column prop="id" label="ID" width="80" />
      <el-table-column prop="userId" label="用户ID" width="90" />
      <el-table-column prop="deviceName" label="设备名" min-width="160" />
      <el-table-column prop="deviceType" label="类型" width="100" />
      <el-table-column prop="platform" label="平台" width="100" />
      <el-table-column label="在线" width="90">
        <template #default="{ row }">
          <el-tag :type="row.online ? 'success' : 'info'" effect="plain">{{ row.online ? '在线' : '离线' }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="策略" min-width="170">
        <template #default="{ row }">
          <el-select :model-value="row.approvalPolicy" size="small" @change="value => update(row, { approvalPolicy: value })">
            <el-option label="每次询问" value="always_ask" />
            <el-option label="允许所有人" value="allow_anyone" />
          </el-select>
        </template>
      </el-table-column>
      <el-table-column label="远程" width="90">
        <template #default="{ row }">
          <el-switch :model-value="row.remoteEnabled" @change="value => update(row, { remoteEnabled: value })" />
        </template>
      </el-table-column>
      <el-table-column prop="status" label="状态" width="100" />
      <el-table-column prop="lastSeenAt" label="最近在线" min-width="180" />
      <el-table-column label="操作" fixed="right" width="180">
        <template #default="{ row }">
          <el-button link type="primary" @click="kick(row)">踢设备</el-button>
          <el-button link :type="row.status === 'active' ? 'danger' : 'success'" @click="toggleStatus(row)">{{ row.status === 'active' ? '禁用' : '启用' }}</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-pagination class="list-pager" v-model:current-page="page" v-model:page-size="pageSize" :page-sizes="[10, 30, 50, 100]" :total="total" layout="total, sizes, prev, pager, next, jumper" @current-change="load" @size-change="reload" />
  </div>
</template>

<script setup>
import { onMounted, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { kickRemoteDevice, listRemoteDevices, updateRemoteDevice } from '@/api/remoteAdmin'

const search = reactive({ userId: 0, deviceName: '', deviceType: '', platform: '', status: '' })
const list = ref([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(10)

const readPageData = (res) => res?.data || {}

const load = async () => {
  const data = readPageData(await listRemoteDevices({ ...search, page: page.value, pageSize: pageSize.value }))
  list.value = Array.isArray(data.list) ? data.list : []
  total.value = Number(data.total) || 0
}
const reload = () => { page.value = 1; load() }
const reset = () => { Object.assign(search, { userId: 0, deviceName: '', deviceType: '', platform: '', status: '' }); reload() }
const update = async (row, patch) => { await updateRemoteDevice({ id: row.id, ...patch }); ElMessage.success('更新成功'); load() }
const kick = async (row) => { await kickRemoteDevice({ id: row.id }); ElMessage.success(`已踢下线设备 ${row.id}`); load() }
const toggleStatus = (row) => update(row, { status: row.status === 'active' ? 'disabled' : 'active' })

onMounted(load)
</script>

<style scoped>
.compact-filter { margin-bottom: 16px; }
.list-pager { margin-top: 16px; display: flex; justify-content: flex-end; }
</style>
