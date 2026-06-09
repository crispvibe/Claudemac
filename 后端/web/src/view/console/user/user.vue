<template>
  <div class="account-page">
    <header class="page-heading">
      <div>
        <span class="page-kicker">系统管理</span>
        <h2>账号管理</h2>
        <p>管理员可新增、编辑、启停、分配角色、删除账号并重置密码。</p>
      </div>
      <el-button type="primary" icon="plus" @click="addUser">新增用户</el-button>
    </header>

    <div class="filter-panel">
      <el-form ref="searchForm" :inline="true" :model="searchInfo">
        <el-form-item label="用户名">
          <el-input v-model="searchInfo.username" placeholder="用户名" />
        </el-form-item>
        <el-form-item label="昵称">
          <el-input v-model="searchInfo.nickname" placeholder="昵称" />
        </el-form-item>
        <el-form-item label="手机号">
          <el-input v-model="searchInfo.phone" placeholder="手机号" />
        </el-form-item>
        <el-form-item label="邮箱">
          <el-input v-model="searchInfo.email" placeholder="邮箱" />
        </el-form-item>
        <el-form-item>
          <el-button type="primary" icon="search" @click="onSubmit">
            查询
          </el-button>
          <el-button icon="refresh" @click="onReset"> 重置 </el-button>
        </el-form-item>
      </el-form>
    </div>
    <div class="surface-panel">
      <div class="table-toolbar">
        <div>
          <h3>用户列表</h3>
          <span>共 {{ total }} 个账号</span>
        </div>
      </div>
      <el-table :data="tableData" row-key="id">
        <el-table-column align="left" label="头像" min-width="75">
          <template #default="scope">
            <CustomPic style="margin-top: 8px" :pic-src="scope.row.headerImg" />
          </template>
        </el-table-column>
        <el-table-column align="left" label="ID" min-width="50" prop="id" />
        <el-table-column
          align="left"
          label="用户名"
          min-width="150"
          prop="userName"
        />
        <el-table-column
          align="left"
          label="昵称"
          min-width="150"
          prop="nickName"
        />
        <el-table-column
          align="left"
          label="手机号"
          min-width="180"
          prop="phone"
        />
        <el-table-column
          align="left"
          label="邮箱"
          min-width="180"
          prop="email"
        />
        <el-table-column align="left" label="用户角色" min-width="200">
          <template #default="scope">
            <el-cascader
              v-model="scope.row.roleIds"
              :options="roleOptions"
              :show-all-levels="false"
              collapse-tags
              :props="{
                multiple: true,
                checkStrictly: true,
                label: 'roleName',
                value: 'roleId',
                disabled: 'disabled',
                emitPath: false
              }"
              :clearable="false"
              @visible-change="
                (flag) => {
                  changeUserRoles(scope.row, flag, 0)
                }
              "
              @remove-tag="
                (removeAuth) => {
                  changeUserRoles(scope.row, false, removeAuth)
                }
              "
            />
          </template>
        </el-table-column>
        <el-table-column align="left" label="启用" min-width="150">
          <template #default="scope">
            <el-switch
              v-model="scope.row.enable"
              inline-prompt
              :active-value="1"
              :inactive-value="2"
              @change="
                () => {
                  switchEnable(scope.row)
                }
              "
            />
          </template>
        </el-table-column>

        <el-table-column label="操作" :min-width="appStore.operateMinWith" fixed="right">
          <template #default="scope">
            <el-button
              type="primary"
              link
              icon="delete"
              @click="deleteUserFunc(scope.row)"
              >删除</el-button
            >
            <el-button
              type="primary"
              link
              icon="edit"
              @click="openEdit(scope.row)"
              >编辑</el-button
            >
            <el-button
              type="primary"
              link
              icon="magic-stick"
              @click="resetPasswordFunc(scope.row)"
              >重置密码</el-button
            >
          </template>
        </el-table-column>
      </el-table>
      <div class="list-pager">
        <el-pagination
          :current-page="page"
          :page-size="pageSize"
          :page-sizes="[10, 30, 50, 100]"
          :total="total"
          layout="total, sizes, prev, pager, next, jumper"
          @current-change="handleCurrentChange"
          @size-change="handleSizeChange"
        />
      </div>
    </div>
    <!-- 重置密码对话框 -->
    <el-dialog
      v-model="resetPwdDialog"
      title="重置密码"
      width="500px"
      :close-on-click-modal="false"
      :close-on-press-escape="false"
    >
      <el-form :model="resetPwdInfo" ref="resetPwdForm" label-width="100px">
        <el-form-item label="用户账号">
          <el-input v-model="resetPwdInfo.userName" disabled />
        </el-form-item>
        <el-form-item label="用户昵称">
          <el-input v-model="resetPwdInfo.nickName" disabled />
        </el-form-item>
        <el-form-item label="新密码">
          <div class="flex w-full">
            <el-input class="flex-1" v-model="resetPwdInfo.password" placeholder="请输入新密码" show-password />
            <el-button type="primary" @click="generateRandomPassword" style="margin-left: 10px">
              生成随机密码
            </el-button>
          </div>
        </el-form-item>
      </el-form>
      <template #footer>
        <div class="dialog-footer">
          <el-button @click="closeResetPwdDialog">取 消</el-button>
          <el-button type="primary" @click="confirmResetPassword">确 定</el-button>
        </div>
      </template>
    </el-dialog>

    <el-drawer
      v-model="addUserDialog"
      :size="appStore.drawerSize"
      :show-close="false"
    >
      <template #header>
        <div class="drawer-header">
          <span>{{ dialogFlag === 'add' ? '新增用户' : '编辑用户' }}</span>
          <div>
            <el-button @click="closeAddUserDialog">取 消</el-button>
            <el-button type="primary" @click="enterAddUserDialog"
              >确 定</el-button
            >
          </div>
        </div>
      </template>

      <el-form
        ref="userForm"
        :rules="rules"
        :model="userInfo"
        label-width="80px"
      >
        <el-form-item
          v-if="dialogFlag === 'add'"
          label="用户名"
          prop="userName"
        >
          <el-input v-model="userInfo.userName" />
        </el-form-item>
        <el-form-item v-if="dialogFlag === 'add'" label="密码" prop="password">
          <el-input v-model="userInfo.password" />
        </el-form-item>
        <el-form-item label="昵称" prop="nickName">
          <el-input v-model="userInfo.nickName" />
        </el-form-item>
        <el-form-item label="手机号" prop="phone">
          <el-input v-model="userInfo.phone" />
        </el-form-item>
        <el-form-item label="邮箱" prop="email">
          <el-input v-model="userInfo.email" />
        </el-form-item>
        <el-form-item label="用户角色" prop="primaryRoleId">
          <el-cascader
            v-model="userInfo.roleIds"
            style="width: 100%"
            :options="roleOptions"
            :show-all-levels="false"
            :props="{
              multiple: true,
              checkStrictly: true,
              label: 'roleName',
              value: 'roleId',
              disabled: 'disabled',
              emitPath: false
            }"
            :clearable="false"
          />
        </el-form-item>
        <el-form-item label="启用" prop="disabled">
          <el-switch
            v-model="userInfo.enable"
            inline-prompt
            :active-value="1"
            :inactive-value="2"
          />
        </el-form-item>
        <el-form-item label="头像" label-width="80px">
          <SelectImage v-model="userInfo.headerImg" />
        </el-form-item>
      </el-form>
    </el-drawer>
  </div>
</template>

<script setup>
  import {
    getUserList,
    setUserRoles,
    register,
    deleteUser
  } from '@/api/user'

  import { fetchRoleList } from '@/api/roles'
  import CustomPic from '@/components/customPic/index.vue'
  import { setUserInfo, resetPassword } from '@/api/user.js'

  import { nextTick, ref, watch } from 'vue'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import SelectImage from '@/components/selectImage/selectImage.vue'
  import { useAppStore } from "@/pinia";

  defineOptions({
    name: 'AccountRosterPage'
  })

  const appStore = useAppStore()

  const searchInfo = ref({
    username: '',
    nickname: '',
    phone: '',
    email: ''
  })

  const onSubmit = () => {
    page.value = 1
    getTableData()
  }

  const onReset = () => {
    searchInfo.value = {
      username: '',
      nickname: '',
      phone: '',
      email: ''
    }
    getTableData()
  }
  // 初始化相关
  const buildRoleOptions = (roleTreeData, optionsData) => {
    roleTreeData &&
      roleTreeData.forEach((item) => {
        if (item.children && item.children.length) {
          const option = {
            roleId: item.roleId,
            roleName: item.roleName,
            children: []
          }
          buildRoleOptions(item.children, option.children)
          optionsData.push(option)
        } else {
          const option = {
            roleId: item.roleId,
            roleName: item.roleName
          }
          optionsData.push(option)
        }
      })
  }

  const page = ref(1)
  const total = ref(0)
  const pageSize = ref(10)
  const tableData = ref([])
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
    const table = await getUserList({
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

  watch(
    () => tableData.value,
    () => {
      syncUserRoleIds()
    }
  )

  const roleOptions = ref([])
  const setOptions = (roleData) => {
    roleOptions.value = []
    buildRoleOptions(roleData, roleOptions.value)
  }

  const initPage = async () => {
    getTableData()
    const res = await fetchRoleList()
    setOptions(res.data)
  }

  initPage()

  // 重置密码对话框相关
  const resetPwdDialog = ref(false)
  const resetPwdForm = ref(null)
  const resetPwdInfo = ref({
    id: '',
    userName: '',
    nickName: '',
    password: ''
  })

  // 生成随机密码
  const generateRandomPassword = () => {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*'
    let password = ''
    for (let i = 0; i < 12; i++) {
      password += chars.charAt(Math.floor(Math.random() * chars.length))
    }
    resetPwdInfo.value.password = password
    // 复制到剪贴板
    navigator.clipboard.writeText(password).then(() => {
      ElMessage({
        type: 'success',
        message: '密码已复制到剪贴板'
      })
    }).catch(() => {
      ElMessage({
        type: 'error',
        message: '复制失败，请手动复制'
      })
    })
  }

  // 打开重置密码对话框
  const resetPasswordFunc = (row) => {
    resetPwdInfo.value.id = row.id
    resetPwdInfo.value.userName = row.userName
    resetPwdInfo.value.nickName = row.nickName
    resetPwdInfo.value.password = ''
    resetPwdDialog.value = true
  }

  // 确认重置密码
  const confirmResetPassword = async () => {
    if (!resetPwdInfo.value.password) {
      ElMessage({
        type: 'warning',
        message: '请输入或生成密码'
      })
      return
    }

    const res = await resetPassword({
      id: resetPwdInfo.value.id,
      password: resetPwdInfo.value.password
    })

    if (res.code === 0) {
      ElMessage({
        type: 'success',
        message: res.msg || '密码重置成功'
      })
      resetPwdDialog.value = false
    } else {
      ElMessage({
        type: 'error',
        message: res.msg || '密码重置失败'
      })
    }
  }

  // 关闭重置密码对话框
  const closeResetPwdDialog = () => {
    resetPwdInfo.value.password = ''
    resetPwdDialog.value = false
  }
  const syncUserRoleIds = () => {
    tableData.value &&
      tableData.value.forEach((user) => {
        user.roleIds =
          user.roles &&
          user.roles.map((i) => {
            return i.roleId
          })
      })
  }

  const deleteUserFunc = async (row) => {
    ElMessageBox.confirm('确定要删除吗?', '提示', {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      type: 'warning'
    }).then(async () => {
      const res = await deleteUser({ id: row.id })
      if (res.code === 0) {
        ElMessage.success('删除成功')
        await getTableData()
      }
    })
  }

  // 弹窗相关
  const userInfo = ref({
    userName: '',
    password: '',
    nickName: '',
    headerImg: '',
    primaryRoleId: '',
    roleIds: [],
    enable: 1
  })

  const rules = ref({
    userName: [
      { required: true, message: '请输入用户名', trigger: 'blur' },
      { min: 5, message: '最低5位字符', trigger: 'blur' }
    ],
    password: [
      { required: true, message: '请输入用户密码', trigger: 'blur' },
      { min: 6, message: '最低6位字符', trigger: 'blur' }
    ],
    nickName: [{ required: true, message: '请输入用户昵称', trigger: 'blur' }],
    phone: [
      {
        pattern: /^1([38][0-9]|4[014-9]|[59][0-35-9]|6[2567]|7[0-8])\d{8}$/,
        message: '请输入合法手机号',
        trigger: 'blur'
      }
    ],
    email: [
      {
        pattern: /^([0-9A-Za-z\-_.]+)@([0-9a-z]+\.[a-z]{2,3}(\.[a-z]{2})?)$/g,
        message: '请输入正确的邮箱',
        trigger: 'blur'
      }
    ],
    primaryRoleId: [
      { required: true, message: '请选择用户角色', trigger: 'blur' }
    ]
  })
  const userForm = ref(null)
  const enterAddUserDialog = async () => {
    userInfo.value.primaryRoleId = userInfo.value.roleIds[0]
    userForm.value.validate(async (valid) => {
      if (valid) {
        const req = {
          ...userInfo.value
        }
        if (dialogFlag.value === 'add') {
          const res = await register(req)
          if (res.code === 0) {
            ElMessage({ type: 'success', message: '创建成功' })
            await getTableData()
            closeAddUserDialog()
          }
        }
        if (dialogFlag.value === 'edit') {
          const res = await setUserInfo(req)
          if (res.code === 0) {
            ElMessage({ type: 'success', message: '编辑成功' })
            await getTableData()
            closeAddUserDialog()
          }
        }
      }
    })
  }

  const addUserDialog = ref(false)
  const closeAddUserDialog = () => {
    userForm.value.resetFields()
    userInfo.value.headerImg = ''
    userInfo.value.roleIds = []
    addUserDialog.value = false
  }

  const dialogFlag = ref('add')

  const addUser = () => {
    dialogFlag.value = 'add'
    addUserDialog.value = true
  }

  const previousRoleSelections = {}
  const changeUserRoles = async (row, flag, removedRoleId) => {
    if (flag) {
      if (!removedRoleId) {
        previousRoleSelections[row.id] = [...row.roleIds]
      }
      return
    }
    await nextTick()
    const res = await setUserRoles({
      id: row.id,
      roleIds: row.roleIds
    })
    if (res.code === 0) {
      ElMessage({ type: 'success', message: '角色设置成功' })
    } else {
      if (!removedRoleId) {
        row.roleIds = [...previousRoleSelections[row.id]]
        delete previousRoleSelections[row.id]
      } else {
        row.roleIds = [removedRoleId, ...row.roleIds]
      }
    }
  }

  const openEdit = (row) => {
    dialogFlag.value = 'edit'
    userInfo.value = JSON.parse(JSON.stringify(row))
    addUserDialog.value = true
  }

  const switchEnable = async (row) => {
    userInfo.value = JSON.parse(JSON.stringify(row))
    await nextTick()
    const req = {
      ...userInfo.value
    }
    const res = await setUserInfo(req)
    if (res.code === 0) {
      ElMessage({
        type: 'success',
        message: `${req.enable === 2 ? '禁用' : '启用'}成功`
      })
      await getTableData()
      userInfo.value.headerImg = ''
      userInfo.value.roleIds = []
    }
  }
</script>

<style lang="scss">
  .account-page {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .page-heading {
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    gap: 16px;
    padding: 2px 2px 0;
  }

  .page-kicker {
    display: block;
    color: #64748b;
    font-size: 12px;
    font-weight: 650;
    margin-bottom: 4px;
  }

  .page-heading h2 {
    margin: 0;
    color: #111827;
    font-size: 22px;
    font-weight: 700;
    letter-spacing: 0;
  }

  .page-heading p {
    margin: 6px 0 0;
    color: #64748b;
    font-size: 13px;
  }

  .table-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    margin-bottom: 14px;
  }

  .table-toolbar h3 {
    margin: 0 0 4px;
    color: #111827;
    font-size: 16px;
    font-weight: 650;
  }

  .table-toolbar span {
    color: #64748b;
    font-size: 13px;
  }

  .drawer-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    font-size: 18px;
  }

  .header-img-box {
    @apply w-52 h-52 border border-solid border-gray-300 rounded-xl flex justify-center items-center cursor-pointer;
  }

  @media (max-width: 768px) {
    .page-heading {
      align-items: flex-start;
      flex-direction: column;
    }
  }
</style>
