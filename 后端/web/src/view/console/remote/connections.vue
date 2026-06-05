<template>
  <div class="surface-panel remote-page">
    <div class="filter-panel compact-filter">
      <el-form :inline="true" :model="search">
        <el-form-item label="发起用户"><el-input-number v-model="search.fromUserId" :min="0" /></el-form-item>
        <el-form-item label="目标用户"><el-input-number v-model="search.toUserId" :min="0" /></el-form-item>
        <el-form-item label="目标设备"><el-input-number v-model="search.toDeviceId" :min="0" /></el-form-item>
        <el-form-item label="状态"><el-select v-model="search.status" clearable><el-option label="pending" value="pending" /><el-option label="accepted" value="accepted" /><el-option label="rejected" value="rejected" /></el-select></el-form-item>
        <el-form-item label="传输"><el-select v-model="search.transport" clearable><el-option label="lan" value="lan" /><el-option label="p2p" value="p2p" /><el-option label="turn" value="turn" /></el-select></el-form-item>
        <el-form-item><el-button type="primary" @click="reload">查询</el-button><el-button @click="reset">重置</el-button></el-form-item>
      </el-form>
    </div>
    <el-table :data="list">
      <el-table-column label="connection_id" width="120">
        <template #default="{ row }">{{ row.connectionId || row.id }}</template>
      </el-table-column>
      <el-table-column prop="fromUserId" label="发起用户" width="100" />
      <el-table-column prop="fromDeviceId" label="发起设备" width="100" />
      <el-table-column prop="toUserId" label="目标用户" width="100" />
      <el-table-column prop="toDeviceId" label="目标设备" width="100" />
      <el-table-column prop="status" label="状态" width="110" />
      <el-table-column prop="reason" label="原因" min-width="160" />
      <el-table-column prop="transport" label="传输" width="90" />
      <el-table-column prop="firstPacketLatencyMs" label="首包(ms)" width="110" />
      <el-table-column prop="firstPacketAt" label="首包时间" min-width="180" />
      <el-table-column prop="CreatedAt" label="创建时间" min-width="180" />
    </el-table>
    <el-pagination class="list-pager" v-model:current-page="page" v-model:page-size="pageSize" :page-sizes="[10, 30, 50, 100]" :total="total" layout="total, sizes, prev, pager, next, jumper" @current-change="load" @size-change="reload" />
  </div>
</template>

<script setup>
import { onMounted, reactive, ref } from 'vue'
import { listRemoteConnections } from '@/api/remoteAdmin'

const search = reactive({ fromUserId: 0, toUserId: 0, toDeviceId: 0, status: '', transport: '' })
const list = ref([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(10)

const readPageData = (res) => res?.data || {}

const load = async () => {
  const data = readPageData(await listRemoteConnections({ ...search, page: page.value, pageSize: pageSize.value }))
  list.value = Array.isArray(data.list) ? data.list : []
  total.value = Number(data.total) || 0
}
const reload = () => { page.value = 1; load() }
const reset = () => { Object.assign(search, { fromUserId: 0, toUserId: 0, toDeviceId: 0, status: '', transport: '' }); reload() }

onMounted(load)
</script>

<style scoped>
.compact-filter { margin-bottom: 16px; }
.list-pager { margin-top: 16px; display: flex; justify-content: flex-end; }
</style>
