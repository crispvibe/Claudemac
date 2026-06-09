<template>
  <section class="audit-ledger-page">
    <section class="surface-panel audit-ledger-page__query-box">
      <div class="audit-ledger-page__query-head">
        <div>
          <h3 class="audit-ledger-page__title">访问记录</h3>
          <p class="audit-ledger-page__subtitle">按请求方法、路径和状态码过滤当前日志视图</p>
        </div>
        <span class="audit-ledger-page__count">{{ total }} 条</span>
      </div>

      <el-form :model="searchInfo" class="audit-ledger-page__query-form">
        <div class="audit-ledger-page__query-grid">
          <el-form-item label="请求方法">
            <el-input v-model="searchInfo.method" placeholder="搜索条件" />
          </el-form-item>
          <el-form-item label="请求路径">
            <el-input v-model="searchInfo.path" placeholder="搜索条件" />
          </el-form-item>
          <el-form-item label="结果状态码">
            <el-input v-model="searchInfo.status" placeholder="搜索条件" />
          </el-form-item>
        </div>
        <div class="audit-ledger-page__query-actions">
          <el-button type="primary" icon="search" @click="onSubmit"
            >查询</el-button
          >
          <el-button icon="refresh" @click="onReset">重置</el-button>
        </div>
      </el-form>
    </section>

    <section class="surface-panel audit-ledger-page__table-box">
      <div class="audit-ledger-page__toolbar">
        <div class="audit-ledger-page__toolbar-copy">
          <span class="audit-ledger-page__toolbar-title">请求轨迹</span>
          <span class="audit-ledger-page__toolbar-tip">当前页 {{ tableData.length }} 条记录</span>
        </div>
        <div class="audit-ledger-page__toolbar-actions">
        <el-button
          icon="delete"
          :disabled="!multipleSelection.length"
          @click="onDelete"
          >删除</el-button
        >
        </div>
      </div>
      <el-table
        ref="multipleTable"
        :data="tableData"
        style="width: 100%"
        tooltip-effect="dark"
        row-key="id"
        @selection-change="handleSelectionChange"
      >
        <el-table-column align="left" type="selection" width="55" />
        <el-table-column align="left" label="操作人" width="140">
          <template #default="scope">
            <div>
              {{ scope.row.user.userName }}({{ scope.row.user.nickName }})
            </div>
          </template>
        </el-table-column>
        <el-table-column align="left" label="日期" width="180">
          <template #default="scope">{{
            formatDate(scope.row.CreatedAt)
          }}</template>
        </el-table-column>
        <el-table-column align="left" label="状态码" prop="status" width="120">
          <template #default="scope">
            <el-tag type="success">{{ scope.row.status }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column align="left" label="请求IP" prop="ip" width="120" />
        <el-table-column
          align="left"
          label="请求方法"
          prop="method"
          width="120"
        />
        <el-table-column
          align="left"
          label="请求路径"
          prop="path"
          width="240"
        />
        <el-table-column align="left" label="请求" prop="path" width="80">
          <template #default="scope">
            <el-popover
              v-if="scope.row.body"
              placement="left-start"
              :width="444"
            >
              <div class="popover-box">
                <pre>{{ fmtBody(scope.row.body) }}</pre>
              </div>
              <template #reference>
                <el-icon style="cursor: pointer"><warning /></el-icon>
              </template>
            </el-popover>

            <span v-else>无</span>
          </template>
        </el-table-column>
        <el-table-column align="left" label="响应" prop="path" width="80">
          <template #default="scope">
            <el-popover
              v-if="scope.row.resp"
              placement="left-start"
              :width="444"
            >
              <div class="popover-box">
                <pre>{{ fmtBody(scope.row.resp) }}</pre>
              </div>
              <template #reference>
                <el-icon style="cursor: pointer"><warning /></el-icon>
              </template>
            </el-popover>
            <span v-else>无</span>
          </template>
        </el-table-column>
        <el-table-column align="left" label="操作">
          <template #default="scope">
            <el-button
              icon="delete"
              type="primary"
              link
              @click="deleteRecordFunc(scope.row)"
              >删除</el-button
            >
          </template>
        </el-table-column>
      </el-table>
      <footer class="audit-ledger-page__pager list-pager">
        <el-pagination
          :current-page="page"
          :page-size="pageSize"
          :page-sizes="[10, 30, 50, 100]"
          :total="total"
          layout="total, sizes, prev, pager, next, jumper"
          @current-change="handleCurrentChange"
          @size-change="handleSizeChange"
        />
      </footer>
    </section>
  </section>
</template>

<script setup>
  import {
    deleteOperationRecord,
    getOperationRecordList,
    deleteOperationRecordsByIDs
  } from '@/api/operationRecord' // 此处请自行替换地址
  import { formatDate } from '@/utils/format'
  import { ref } from 'vue'
  import { ElMessage, ElMessageBox } from 'element-plus'

  defineOptions({
    name: 'TraceLedgerPage'
  })

  const page = ref(1)
  const total = ref(0)
  const pageSize = ref(10)
  const tableData = ref([])
  const searchInfo = ref({})
  const onReset = () => {
    searchInfo.value = {}
  }
  // 条件搜索前端看此方法
  const onSubmit = () => {
    page.value = 1
    if (searchInfo.value.status === '') {
      searchInfo.value.status = null
    }
    getTableData()
  }

  // 分页
  const handleSizeChange = (val) => {
    pageSize.value = val
    getTableData()
  }

  const handleCurrentChange = (val) => {
    page.value = val
    getTableData()
  }

  // 查询
  const getTableData = async () => {
    const table = await getOperationRecordList({
      page: page.value,
      pageSize: pageSize.value,
      ...searchInfo.value
    })
    if (table.code === 0) {
      tableData.value = table.data.list
      total.value = table.data.total
      page.value = table.data.page
      pageSize.value = table.data.pageSize
    }
  }

  getTableData()

  const multipleSelection = ref([])
  const handleSelectionChange = (val) => {
    multipleSelection.value = val
  }
  const askDeleteConfirm = async (runner) => {
    ElMessageBox.confirm('确定要删除吗?', '提示', {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      type: 'warning'
    }).then(runner)
  }
  const syncDeleteSuccess = () => {
    ElMessage({
      type: 'success',
      message: '删除成功'
    })
  }
  const onDelete = async () => {
    askDeleteConfirm(async () => {
      const ids = []
      multipleSelection.value &&
        multipleSelection.value.forEach((item) => {
          ids.push(item.id)
        })
      const res = await deleteOperationRecordsByIDs({ ids })
      if (res.code === 0) {
        syncDeleteSuccess()
        if (tableData.value.length === ids.length && page.value > 1) {
          page.value--
        }
        getTableData()
      }
    })
  }
  const deleteRecordFunc = async (row) => {
    askDeleteConfirm(async () => {
      const res = await deleteOperationRecord({ id: row.id })
      if (res.code === 0) {
        syncDeleteSuccess()
        if (tableData.value.length === 1 && page.value > 1) {
          page.value--
        }
        getTableData()
      }
    })
  }
  const fmtBody = (value) => {
    try {
      return JSON.parse(value)
    } catch (_) {
      return value
    }
  }
</script>

<style lang="scss">
  .audit-ledger-page {
    @apply flex flex-col gap-4;
  }

  .audit-ledger-page__query-box,
  .audit-ledger-page__table-box {
    @apply p-4 md:p-5;
  }

  .audit-ledger-page__query-head,
  .audit-ledger-page__toolbar {
    @apply flex flex-col gap-3 md:flex-row md:items-center md:justify-between;
  }

  .audit-ledger-page__title {
    @apply text-base font-semibold text-slate-900 dark:text-slate-100;
  }

  .audit-ledger-page__subtitle,
  .audit-ledger-page__toolbar-tip {
    @apply text-sm text-slate-500 dark:text-slate-400;
  }

  .audit-ledger-page__count {
    @apply inline-flex items-center rounded-full bg-slate-100 px-3 py-1 text-sm text-slate-600 dark:bg-slate-800 dark:text-slate-300;
  }

  .audit-ledger-page__query-form {
    @apply mt-4 flex flex-col gap-4;
  }

  .audit-ledger-page__query-grid {
    @apply grid gap-4 md:grid-cols-2 xl:grid-cols-3;
  }

  .audit-ledger-page__query-grid .el-form-item {
    @apply mb-0;
  }

  .audit-ledger-page__query-actions,
  .audit-ledger-page__toolbar-actions {
    @apply flex flex-wrap items-center gap-3;
  }

  .audit-ledger-page__toolbar {
    @apply mb-4;
  }

  .audit-ledger-page__toolbar-copy {
    @apply flex flex-col gap-1;
  }

  .audit-ledger-page__toolbar-title {
    @apply text-sm font-semibold text-slate-900 dark:text-slate-100;
  }

  .audit-ledger-page__pager {
    @apply mt-4;
  }

  .table-expand {
    padding-left: 60px;
    font-size: 0;
    label {
      width: 90px;
      color: #99a9bf;
      .el-form-item {
        margin-right: 0;
        margin-bottom: 0;
        width: 50%;
      }
    }
  }
  .popover-box {
    background: #112435;
    color: #f08047;
    height: 600px;
    width: 420px;
    overflow: auto;
  }
  .popover-box::-webkit-scrollbar {
    display: none; /* Chrome Safari */
  }
</style>
