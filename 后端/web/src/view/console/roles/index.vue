<template>
  <div class="role-access-page">
    <warning-bar title="注：右上角头像下拉可切换角色" />
    <div class="surface-panel">
      <div class="action-strip">
        <el-button type="primary" icon="plus" @click="addRole(0)"
          >新增角色</el-button
        >
      </div>
      <el-table
        :data="tableData"
        :tree-props="{ children: 'children', hasChildren: 'hasChildren' }"
        row-key="roleId"
        style="width: 100%"
      >
        <el-table-column label="角色ID" min-width="180" prop="roleId" />
        <el-table-column
          align="left"
          label="角色名称"
          min-width="180"
          prop="roleName"
        />
        <el-table-column align="left" label="操作" width="460">
          <template #default="scope">
            <el-button
              icon="setting"
              type="primary"
              link
              @click="openDrawer(scope.row)"
              >设置权限</el-button
            >
            <el-button
              icon="plus"
              type="primary"
              link
              @click="addRole(scope.row.roleId)"
              >新增子角色</el-button
            >
            <el-button
              icon="copy-document"
              type="primary"
              link
              @click="openCloneRoleDialog(scope.row)"
              >拷贝</el-button
            >
            <el-button
              icon="edit"
              type="primary"
              link
              @click="editRole(scope.row)"
              >编辑</el-button
            >
            <el-button
              icon="delete"
              type="primary"
              link
              @click="deleteRole(scope.row)"
              >删除</el-button
            >
          </template>
        </el-table-column>
      </el-table>
    </div>
    <!-- 新增角色弹窗 -->
    <el-drawer v-model="roleFormVisible" :size="appStore.drawerSize" :show-close="false">
      <template #header>
        <div class="flex justify-between items-center">
          <span class="text-lg">{{ roleTitleForm }}</span>
          <div>
            <el-button @click="closeRoleDialog">取 消</el-button>
            <el-button type="primary" @click="submitRoleForm"
              >确 定</el-button
            >
          </div>
        </div>
      </template>
      <el-form
        ref="roleForm"
        :model="form"
        :rules="rules"
        label-width="80px"
      >
        <el-form-item label="父级角色" prop="parentId">
          <el-cascader
            v-model="form.parentId"
            style="width: 100%"
            :disabled="dialogType === 'add'"
            :options="roleOptions"
            :props="{
              checkStrictly: true,
              label: 'roleName',
              value: 'roleId',
              disabled: 'disabled',
              emitPath: false
            }"
            :show-all-levels="false"
            filterable
          />
        </el-form-item>
        <el-form-item label="角色ID" prop="roleId">
          <el-input
            v-model="form.roleId"
            :disabled="dialogType === 'edit'"
            autocomplete="off"
            maxlength="15"
          />
        </el-form-item>
        <el-form-item label="角色姓名" prop="roleName">
          <el-input v-model="form.roleName" autocomplete="off" />
        </el-form-item>
      </el-form>
    </el-drawer>

    <el-drawer
      v-if="drawer"
      v-model="drawer"
      :size="appStore.drawerSize"
      title="角色配置"
    >
      <el-tabs :before-leave="autoEnter" type="border-card">
        <el-tab-pane label="角色菜单">
          <RoleNavigationPanel ref="menus" :row="activeRow" @changeRow="changeRow" />
        </el-tab-pane>
        <el-tab-pane label="角色api">
          <RoleApiScopesPanel ref="apis" :row="activeRow" @changeRow="changeRow" />
        </el-tab-pane>
        <el-tab-pane label="数据权限">
          <RoleDataScopesPanel
            ref="datas"
            :role-tree="tableData"
            :row="activeRow"
            @changeRow="changeRow"
          />
        </el-tab-pane>
      </el-tabs>
    </el-drawer>
  </div>
</template>

<script setup>
  import {
    fetchRoleList,
    removeRole,
    createRole,
    updateRole,
    cloneRole
  } from '@/api/roles'

  import RoleNavigationPanel from '@/view/console/roles/components/navigation.vue'
  import RoleApiScopesPanel from '@/view/console/roles/components/apiScopes.vue'
  import RoleDataScopesPanel from '@/view/console/roles/components/dataScopes.vue'
  import WarningBar from '@/components/warningBar/warningBar.vue'

  import { ref } from 'vue'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import { useAppStore } from "@/pinia"

  defineOptions({
    name: 'RoleAccessMatrix'
  })

  const mustUint = (rule, value, callback) => {
    if (!/^[0-9]*[1-9][0-9]*$/.test(value)) {
      return callback(new Error('请输入正整数'))
    }
    return callback()
  }

  const roleOptions = ref([
    {
      roleId: 0,
      roleName: '根角色/严格模式下为当前角色'
    }
  ])
  const drawer = ref(false)
  const dialogType = ref('add')
  const activeRow = ref({})
  const appStore = useAppStore()

  const roleTitleForm = ref('新增角色')
  const roleFormVisible = ref(false)
  const apiDialogFlag = ref(false)
  const copyForm = ref({})

  const form = ref({
    roleId: 0,
    roleName: '',
    parentId: 0
  })
  const rules = ref({
    roleId: [
      { required: true, message: '请输入角色ID', trigger: 'blur' },
      { validator: mustUint, trigger: 'blur', message: '必须为正整数' }
    ],
    roleName: [
      { required: true, message: '请输入角色名', trigger: 'blur' }
    ],
    parentId: [{ required: true, message: '请选择父角色', trigger: 'blur' }]
  })

  const tableData = ref([])

  // 查询
  const getTableData = async () => {
    const table = await fetchRoleList()
    if (table.code === 0) {
      tableData.value = table.data
    }
  }

  getTableData()

  const changeRow = (key, value) => {
    activeRow.value[key] = value
  }
  const menus = ref(null)
  const apis = ref(null)
  const datas = ref(null)
  const autoEnter = (activeName, oldActiveName) => {
    const paneArr = [menus, apis, datas]
    if (oldActiveName) {
      if (paneArr[oldActiveName].value.needConfirm) {
        paneArr[oldActiveName].value.enterAndNext()
        paneArr[oldActiveName].value.needConfirm = false
      }
    }
  }
  // 拷贝角色
  const openCloneRoleDialog = (row) => {
    setOptions()
    roleTitleForm.value = '拷贝角色'
    dialogType.value = 'copy'
    for (const k in form.value) {
      form.value[k] = row[k]
    }
    copyForm.value = row
    roleFormVisible.value = true
  }
  const openDrawer = (row) => {
    drawer.value = true
    activeRow.value = row
  }
  // 删除角色
  const deleteRole = (row) => {
    ElMessageBox.confirm('确定要删除吗?', '提示', {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      type: 'warning'
    })
      .then(async () => {
        const res = await removeRole({ roleId: row.roleId })
        if (res.code === 0) {
          ElMessage({
            type: 'success',
            message: '删除成功'
          })

          getTableData()
        }
      })
      .catch(() => {
        ElMessage({
          type: 'info',
          message: '已取消删除'
        })
      })
  }
  // 初始化表单
  const roleForm = ref(null)
  const initForm = () => {
    if (roleForm.value) {
      roleForm.value.resetFields()
    }
    form.value = {
      roleId: 0,
      roleName: '',
      parentId: 0
    }
  }
  // 关闭窗口
  const closeRoleDialog = () => {
    initForm()
    roleFormVisible.value = false
    apiDialogFlag.value = false
  }
  // 确定弹窗

  const submitRoleForm = () => {
    roleForm.value.validate(async (valid) => {
      if (valid) {
        form.value.roleId = Number(form.value.roleId)
        switch (dialogType.value) {
          case 'add':
            {
              const res = await createRole(form.value)
              if (res.code === 0) {
                ElMessage({
                  type: 'success',
                  message: '创建成功'
                })
                getTableData()
                closeRoleDialog()
              }
            }
            break
          case 'edit':
            {
              const res = await updateRole(form.value)
              if (res.code === 0) {
                ElMessage({
                  type: 'success',
                  message: '编辑成功'
                })
                getTableData()
                closeRoleDialog()
              }
            }
            break
          case 'copy': {
            const data = {
              role: {
                roleId: 0,
                roleName: '',
                dataRoleIds: [],
                parentId: 0
              },
              oldRoleId: 0
            }
            data.role.roleId = form.value.roleId
            data.role.roleName = form.value.roleName
            data.role.parentId = form.value.parentId
            data.role.dataRoleIds = copyForm.value.dataRoleIds
            data.oldRoleId = copyForm.value.roleId
            const res = await cloneRole(data)
            if (res.code === 0) {
              ElMessage({
                type: 'success',
                message: '拷贝成功'
              })
              getTableData()
            }
          }
        }

        initForm()
        roleFormVisible.value = false
      }
    })
  }
  const setOptions = () => {
    roleOptions.value = [
      {
        roleId: 0,
        roleName: '根角色(严格模式下为当前用户角色)'
      }
    ]
    setRoleOptions(tableData.value, roleOptions.value, false)
  }
  const setRoleOptions = (roleData, optionsData, disabled) => {
    roleData &&
      roleData.forEach((item) => {
        if (item.children && item.children.length) {
          const option = {
            roleId: item.roleId,
            roleName: item.roleName,
            disabled: disabled || item.roleId === form.value.roleId,
            children: []
          }
          setRoleOptions(
            item.children,
            option.children,
            disabled || item.roleId === form.value.roleId
          )
          optionsData.push(option)
        } else {
          const option = {
            roleId: item.roleId,
            roleName: item.roleName,
            disabled: disabled || item.roleId === form.value.roleId
          }
          optionsData.push(option)
        }
      })
  }
  // 增加角色
  const addRole = (parentId) => {
    initForm()
    roleTitleForm.value = '新增角色'
    dialogType.value = 'add'
    form.value.parentId = parentId
    setOptions()
    roleFormVisible.value = true
  }
  // 编辑角色
  const editRole = (row) => {
    setOptions()
    roleTitleForm.value = '编辑角色'
    dialogType.value = 'edit'
    for (const key in form.value) {
      form.value[key] = row[key]
    }
    setOptions()
    roleForm.value && roleForm.value.clearValidate()
    roleFormVisible.value = true
  }
</script>

<style lang="scss">
  .role-access-page {
    .el-input-number {
      margin-left: 15px;
      span {
        display: none;
      }
    }
  }
  .tree-content {
    margin-top: 10px;
    height: calc(100vh - 158px);
    overflow: auto;
  }
</style>
