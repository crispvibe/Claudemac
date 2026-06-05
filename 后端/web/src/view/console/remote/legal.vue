<template>
  <div class="surface-panel remote-page">
    <div class="action-strip"><el-button type="primary" @click="openDoc()">新增协议</el-button></div>
    <el-tabs v-model="tab" @tab-change="loadActive">
      <el-tab-pane label="协议文档" name="docs">
        <el-table :data="docs.list">
          <el-table-column prop="id" label="ID" width="80" />
          <el-table-column prop="type" label="类型" min-width="160" />
          <el-table-column prop="platform" label="平台" width="100" />
          <el-table-column prop="version" label="版本" width="120" />
          <el-table-column prop="title" label="标题" min-width="180" />
          <el-table-column prop="published" label="发布" width="90" />
          <el-table-column prop="effectiveAt" label="生效时间" min-width="180" />
          <el-table-column label="操作" fixed="right" width="100"><template #default="{ row }"><el-button link type="primary" @click="openDoc(row)">编辑</el-button></template></el-table-column>
        </el-table>
      </el-tab-pane>
      <el-tab-pane label="同意记录" name="consents">
        <el-table :data="consents.list">
          <el-table-column prop="id" label="ID" width="80" />
          <el-table-column prop="userId" label="用户ID" width="100" />
          <el-table-column prop="documentId" label="文档ID" width="100" />
          <el-table-column prop="documentType" label="类型" min-width="160" />
          <el-table-column prop="documentVersion" label="版本" width="120" />
          <el-table-column prop="platform" label="平台" width="100" />
          <el-table-column prop="consentedAt" label="同意时间" min-width="180" />
        </el-table>
      </el-tab-pane>
    </el-tabs>
    <el-pagination class="list-pager" v-model:current-page="activeState.page" v-model:page-size="activeState.pageSize" :page-sizes="[10, 30, 50, 100]" :total="activeState.total" layout="total, sizes, prev, pager, next, jumper" @current-change="loadActive" @size-change="reloadActive" />

    <el-drawer v-model="drawer" size="55%" :show-close="false">
      <template #header><div class="flex justify-between items-center"><span class="text-lg">协议文档</span><div><el-button @click="drawer=false">取消</el-button><el-button type="primary" @click="submitDoc">保存</el-button></div></div></template>
      <el-form label-width="100px" :model="form">
        <el-form-item label="类型"><el-input v-model="form.type" /></el-form-item>
        <el-form-item label="平台"><el-input v-model="form.platform" placeholder="all / ios / macos / windows" /></el-form-item>
        <el-form-item label="版本"><el-input v-model="form.version" /></el-form-item>
        <el-form-item label="标题"><el-input v-model="form.title" /></el-form-item>
        <el-form-item label="格式"><el-select v-model="form.contentFormat"><el-option label="markdown" value="markdown" /><el-option label="html" value="html" /></el-select></el-form-item>
        <el-form-item label="发布"><el-switch v-model="form.published" /></el-form-item>
        <el-form-item label="内容"><el-input v-model="form.content" type="textarea" :rows="14" /></el-form-item>
      </el-form>
    </el-drawer>
  </div>
</template>

<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { listRemoteLegalConsents, listRemoteLegalDocuments, saveRemoteLegalDocument } from '@/api/remoteAdmin'

const createState = (loader, search = {}) => reactive({ loader, search, list: [], total: 0, page: 1, pageSize: 10 })
const docs = createState(listRemoteLegalDocuments, { type: '', platform: '', published: null })
const consents = createState(listRemoteLegalConsents, { userId: 0, documentId: 0, documentType: '', platform: '' })
const tab = ref('docs')
const activeState = computed(() => tab.value === 'docs' ? docs : consents)

const readPageData = (res) => res?.data || {}

const load = async (state) => {
  const data = readPageData(await state.loader({ ...state.search, page: state.page, pageSize: state.pageSize }))
  state.list = Array.isArray(data.list) ? data.list : []
  state.total = Number(data.total) || 0
}
const loadActive = () => load(activeState.value)
const reloadActive = () => { activeState.value.page = 1; loadActive() }

const drawer = ref(false)
const form = reactive({ id: 0, type: 'privacy_policy', platform: 'all', version: '', title: '', contentFormat: 'markdown', content: '', published: false })
const openDoc = (row = {}) => { Object.assign(form, { id: 0, type: 'privacy_policy', platform: 'all', version: '', title: '', contentFormat: 'markdown', content: '', published: false }, row); drawer.value = true }
const submitDoc = async () => { await saveRemoteLegalDocument(form); drawer.value = false; load(docs); ElMessage.success('保存成功') }

onMounted(loadActive)
</script>

<style scoped>
.action-strip { margin-bottom: 12px; }
.list-pager { margin-top: 16px; display: flex; justify-content: flex-end; }
</style>
