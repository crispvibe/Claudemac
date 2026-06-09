<template>
  <div class="surface-panel remote-page">
    <div class="filter-panel compact-filter">
      <el-form :inline="true" :model="search">
        <el-form-item label="邮箱"><el-input v-model="search.email" clearable /></el-form-item>
        <el-form-item label="状态">
          <el-select v-model="search.status" clearable>
            <el-option label="active" value="active" />
            <el-option label="disabled" value="disabled" />
          </el-select>
        </el-form-item>
        <el-form-item><el-button type="primary" @click="reload">查询</el-button><el-button @click="reset">重置</el-button></el-form-item>
      </el-form>
    </div>
    <el-table :data="list">
      <el-table-column prop="id" label="ID" width="80" />
      <el-table-column prop="email" label="邮箱" min-width="220">
        <template #default="{ row }">{{ row.email || row.phone || '-' }}</template>
      </el-table-column>
      <el-table-column prop="status" label="状态" width="120" />
      <el-table-column prop="lastLoginAt" label="最近登录" min-width="180" />
      <el-table-column prop="CreatedAt" label="创建时间" min-width="180" />
      <el-table-column label="操作" fixed="right" width="220">
        <template #default="{ row }">
          <el-button link type="primary" @click="kick(row)">踢下线</el-button>
          <el-button link type="warning" @click="setStatus(row, row.status === 'active' ? 'disabled' : 'active')">{{ row.status === 'active' ? '禁用' : '启用' }}</el-button>
          <el-button link type="danger" @click="ban(row)">封禁</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-pagination class="list-pager" v-model:current-page="page" v-model:page-size="pageSize" :page-sizes="[10, 30, 50, 100]" :total="total" layout="total, sizes, prev, pager, next, jumper" @current-change="load" @size-change="reload" />
  </div>
</template>

<script setup>
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { banRemoteUser, kickRemoteUser, listRemoteUsers, updateRemoteUserStatus } from '@/api/remoteAdmin'

const search = reactive({ email: '', status: '' })
const list = ref([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(10)

const readPageData = (res) => res?.data || {}

const load = async () => {
  const data = readPageData(await listRemoteUsers({ ...search, page: page.value, pageSize: pageSize.value }))
  list.value = Array.isArray(data.list) ? data.list : []
  total.value = Number(data.total) || 0
}
const reload = () => { page.value = 1; load() }
const reset = () => { Object.assign(search, { email: '', status: '' }); reload() }
const setStatus = async (row, status) => { await updateRemoteUserStatus({ id: row.id, status }); ElMessage.success('更新成功'); load() }
const kick = async (row) => { await kickRemoteUser({ id: row.id }); ElMessage.success(`已踢下线用户 ${row.id}`) }
const ban = async (row) => {
  await ElMessageBox.confirm(`确认封禁用户 ${row.id} 并撤销刷新令牌？`, '确认操作', { type: 'warning' })
  await banRemoteUser({ id: row.id })
  ElMessage.success('已封禁')
  load()
}

onMounted(load)
</script>

<style scoped>
.compact-filter { margin-bottom: 16px; }
.list-pager { margin-top: 16px; display: flex; justify-content: flex-end; }
</style>
