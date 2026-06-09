<template>
  <div class="p-2 lg:p-4 bg-transparent max-w-5xl mx-auto mb-10">
    <!-- 个人信息卡片 -->
    <div class="bg-white/60 backdrop-blur-[60px] rounded-[24px] shadow-[0_4px_24px_rgba(0,0,0,0.04)] border border-white/80 p-8 mb-6">
      <div class="flex flex-col md:flex-row items-center gap-8">
        <!-- 头像 -->
        <div class="profile-avatar-field flex-shrink-0 w-24 h-24 rounded-full overflow-hidden shadow-sm border border-gray-100 bg-white object-cover relative group hover:border-[#1f83ff]/30 transition-all">
          <SelectImage
            v-model="userStore.userInfo.headerImg"
            file-type="image"
            rounded
          />
        </div>
        
        <div class="flex-1 w-full text-center md:text-left">
          <div class="flex flex-col md:flex-row items-center gap-4 mb-2">
            <h1 v-if="!editFlag" class="text-2xl font-bold text-[#1e293b] flex items-center justify-center md:justify-start gap-3">
              {{ userStore.userInfo.nickName }}
              <el-button link type="primary" @click="openEdit">
                <el-icon :size="18"><edit /></el-icon>
              </el-button>
            </h1>
            <div v-else class="flex items-center gap-2">
               <el-input v-model="nickName" class="w-48" style="border-radius:8px" size="default" />
               <el-button type="primary" plain size="default" style="border-radius:8px" @click="enterEdit">保存</el-button>
               <el-button plain size="default" style="border-radius:8px" @click="closeEdit">取消</el-button>
            </div>
          </div>
          <div class="text-[#64748b] text-sm mt-2">账号：{{ userStore.userInfo.userName }}</div>
        </div>
      </div>
    </div>

    <!-- 安全与设置中心 -->
    <div class="bg-white/60 backdrop-blur-[60px] rounded-[24px] shadow-[0_4px_24px_rgba(0,0,0,0.04)] border border-white/80 p-8">
      <h2 class="text-lg font-bold text-[#1e293b] mb-4">安全设置</h2>
      <div class="space-y-1">
         <!-- 手机号 -->
         <div class="flex items-center justify-between py-4 border-b border-gray-100/60 last:border-0 hover:bg-gray-50/30 px-2 rounded-lg transition-colors">
           <div class="flex items-center gap-3 text-gray-700">
             <el-icon class="text-gray-400"><phone /></el-icon>
             <span class="font-medium text-[14px] w-20">手机号码</span>
             <span class="text-[14px] text-gray-500">{{ userStore.userInfo.phone || '未设置' }}</span>
           </div>
           <el-button link type="primary" @click="openChangePhone">修改</el-button>
         </div>

         <!-- 邮箱 -->
         <div class="flex items-center justify-between py-4 border-b border-gray-100/60 last:border-0 hover:bg-gray-50/30 px-2 rounded-lg transition-colors">
           <div class="flex items-center gap-3 text-gray-700">
             <el-icon class="text-gray-400"><message /></el-icon>
             <span class="font-medium text-[14px] w-20">邮箱地址</span>
             <span class="text-[14px] text-gray-500">{{ userStore.userInfo.email || '未设置' }}</span>
           </div>
           <el-button link type="primary" @click="openChangeEmail">修改</el-button>
         </div>

         <!-- 密码 -->
         <div class="flex items-center justify-between py-4 border-b border-gray-100/60 last:border-0 hover:bg-gray-50/30 px-2 rounded-lg transition-colors">
           <div class="flex items-center gap-3 text-gray-700">
             <el-icon class="text-gray-400"><lock /></el-icon>
             <span class="font-medium text-[14px] w-20">账号密码</span>
             <span class="text-[14px] text-gray-500">已设置保护</span>
           </div>
           <el-button link type="primary" @click="showPassword = true">修改</el-button>
         </div>
      </div>
    </div>
    
    <!-- 统一倒角安全表单弹窗组 -->
    <el-dialog
      v-model="showPassword"
      title="修改密码"
      width="400px"
      custom-class="profile-action-dialog"
      @close="clearPassword"
    >
      <el-form ref="modifyPwdForm" :model="pwdModify" :rules="rules" label-width="80px" class="py-2">
        <el-form-item :minlength="6" label="原密码" prop="password">
          <el-input v-model="pwdModify.password" show-password style="border-radius:6px;" />
        </el-form-item>
        <el-form-item :minlength="6" label="新密码" prop="newPassword">
          <el-input v-model="pwdModify.newPassword" show-password style="border-radius:6px;" />
        </el-form-item>
        <el-form-item :minlength="6" label="确认密码" prop="confirmPassword">
          <el-input v-model="pwdModify.confirmPassword" show-password style="border-radius:6px;" />
        </el-form-item>
      </el-form>
      <template #footer>
        <div class="flex justify-end gap-2 mt-1">
          <el-button style="border-radius: 8px" @click="showPassword = false">取 消</el-button>
          <el-button type="primary" style="border-radius: 8px" @click="savePassword">确 定</el-button>
        </div>
      </template>
    </el-dialog>

    <el-dialog
      v-model="changePhoneFlag"
      title="修改手机号"
      width="400px"
      custom-class="profile-action-dialog"
    >
      <el-form :model="phoneForm" label-width="70px" class="py-2">
        <el-form-item label="手机号">
          <el-input v-model="phoneForm.phone" placeholder="请输入新的手机号码" style="border-radius:6px;">
            <template #prefix><el-icon><phone /></el-icon></template>
          </el-input>
        </el-form-item>
      </el-form>
      <template #footer>
        <div class="flex justify-end gap-2 mt-1">
          <el-button style="border-radius: 8px" @click="closeChangePhone">取 消</el-button>
          <el-button type="primary" style="border-radius: 8px" @click="changePhone">确 定</el-button>
        </div>
      </template>
    </el-dialog>

    <el-dialog
      v-model="changeEmailFlag"
      title="修改邮箱"
      width="400px"
      custom-class="profile-action-dialog"
    >
      <el-form :model="emailForm" label-width="70px" class="py-2">
        <el-form-item label="邮箱">
          <el-input v-model="emailForm.email" placeholder="请输入新的邮箱地址" style="border-radius:6px;">
            <template #prefix><el-icon><message /></el-icon></template>
          </el-input>
        </el-form-item>
      </el-form>
      <template #footer>
        <div class="flex justify-end gap-2 mt-1">
          <el-button style="border-radius: 8px" @click="closeChangeEmail">取 消</el-button>
          <el-button type="primary" style="border-radius: 8px" @click="changeEmail">确 定</el-button>
        </div>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
  import { setSelfInfo, changePassword } from '@/api/user.js'
  import { reactive, ref, watch } from 'vue'
  import { ElMessage } from 'element-plus'
  import { useUserStore } from '@/pinia/modules/user'
  import SelectImage from '@/components/selectImage/selectImage.vue'
  defineOptions({
    name: 'ProfileWorkspacePage'
  })

  const userStore = useUserStore()
  const modifyPwdForm = ref(null)
  const showPassword = ref(false)
  const pwdModify = ref({})
  const nickName = ref('')
  const editFlag = ref(false)

  const rules = reactive({
    password: [
      { required: true, message: '请输入密码', trigger: 'blur' },
      { min: 6, message: '最少6个字符', trigger: 'blur' }
    ],
    newPassword: [
      { required: true, message: '请输入新密码', trigger: 'blur' },
      { min: 6, message: '最少6个字符', trigger: 'blur' }
    ],
    confirmPassword: [
      { required: true, message: '请输入确认密码', trigger: 'blur' },
      { min: 6, message: '最少6个字符', trigger: 'blur' },
      {
        validator: (rule, value, callback) => {
          if (value !== pwdModify.value.newPassword) {
            callback(new Error('两次密码不一致'))
          } else {
            callback()
          }
        },
        trigger: 'blur'
      }
    ]
  })

  const savePassword = async () => {
    modifyPwdForm.value.validate((valid) => {
      if (valid) {
        changePassword({
          password: pwdModify.value.password,
          newPassword: pwdModify.value.newPassword
        }).then((res) => {
          if (res.code === 0) {
            ElMessage.success('修改密码成功！')
            showPassword.value = false
          }
        })
      }
    })
  }

  const clearPassword = () => {
    pwdModify.value = {
      password: '',
      newPassword: '',
      confirmPassword: ''
    }
    modifyPwdForm.value?.clearValidate()
  }

  const openEdit = () => {
    nickName.value = userStore.userInfo.nickName
    editFlag.value = true
  }

  const closeEdit = () => {
    nickName.value = ''
    editFlag.value = false
  }

  const enterEdit = async () => {
    const nextNickName = nickName.value.trim()
    if (!nextNickName) {
      ElMessage.warning('昵称不能为空')
      return
    }
    if (nextNickName === userStore.userInfo.nickName) {
      closeEdit()
      return
    }
    const res = await setSelfInfo({
      nickName: nextNickName
    })
    if (res.code === 0) {
      userStore.ResetUserInfo({ nickName: nextNickName })
      ElMessage.success('修改成功')
      closeEdit()
    }
  }

  const changePhoneFlag = ref(false)
  const phoneForm = reactive({
    phone: ''
  })

  const openChangePhone = () => {
    phoneForm.phone = userStore.userInfo.phone || ''
    changePhoneFlag.value = true
  }

  const closeChangePhone = () => {
    changePhoneFlag.value = false
    phoneForm.phone = ''
  }

  const changePhone = async () => {
    const nextPhone = phoneForm.phone.trim()
    if (!nextPhone) {
      ElMessage.warning('手机号不能为空')
      return
    }
    if (nextPhone === (userStore.userInfo.phone || '')) {
      ElMessage.info('手机号未发生变化')
      closeChangePhone()
      return
    }
    if (!/^1([38][0-9]|4[014-9]|[59][0-35-9]|6[2567]|7[0-8])\d{8}$/.test(nextPhone)) {
      ElMessage.warning('请输入合法手机号')
      return
    }
    const res = await setSelfInfo({ phone: nextPhone })
    if (res.code === 0) {
      ElMessage.success('修改成功')
      userStore.ResetUserInfo({ phone: nextPhone })
      closeChangePhone()
    }
  }

  const changeEmailFlag = ref(false)
  const emailForm = reactive({
    email: ''
  })

  const openChangeEmail = () => {
    emailForm.email = userStore.userInfo.email || ''
    changeEmailFlag.value = true
  }

  const closeChangeEmail = () => {
    changeEmailFlag.value = false
    emailForm.email = ''
  }

  const changeEmail = async () => {
    const nextEmail = emailForm.email.trim()
    if (!nextEmail) {
      ElMessage.warning('邮箱不能为空')
      return
    }
    if (nextEmail === (userStore.userInfo.email || '')) {
      ElMessage.info('邮箱未发生变化')
      closeChangeEmail()
      return
    }
    if (!/^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/.test(nextEmail)) {
      ElMessage.warning('请输入正确的邮箱')
      return
    }
    const res = await setSelfInfo({ email: nextEmail })
    if (res.code === 0) {
      ElMessage.success('修改成功')
      userStore.ResetUserInfo({ email: nextEmail })
      closeChangeEmail()
    }
  }

  watch(() => userStore.userInfo.headerImg, async(val, oldVal) => {
    if (typeof oldVal === 'undefined' || val === oldVal) {
      return
    }
    const res = await setSelfInfo({ headerImg: val })
    if (res.code === 0) {
      userStore.ResetUserInfo({ headerImg: val })
      ElMessage({
        type: 'success',
        message: '设置成功',
      })
    }
  })

</script>

<style lang="scss" scoped>
 /* 弹窗样式收口 */
 .profile-action-dialog.el-dialog {
   border-radius: 24px !important;
   box-shadow: 0 20px 60px rgba(0, 0, 0, 0.1) !important;
 }
 
 /* 头像上传区域样式收口 */
 .profile-avatar-field :deep(> div) {
   width: 100%;
   height: 100%;
   display: flex;
  align-items: center;
  justify-content: center;
  margin: 0 !important;
  padding: 0 !important;
 }
 
 /* 约束底层图片容器尺寸 */
 .profile-avatar-field :deep(.w-40),
 .profile-avatar-field :deep(.h-40) {
   width: 100% !important;
   height: 100% !important;
   min-width: 100% !important;
  min-height: 100% !important;
  border: none !important; 
  margin: 0 !important;
  padding: 0 !important;
  border-radius: 50% !important;
 }
 
 /* 隐藏默认上传文字 */
 .profile-avatar-field :deep(.flex.justify-center.items-center) {
   font-size: 0 !important; 
   background: transparent !important; 
   width: 100% !important;
  height: 100% !important;
 }
 
 /* 调整上传图标样式 */
 .profile-avatar-field :deep(.el-icon) {
   font-size: 28px !important; 
   color: #cbd5e1 !important; 
   transition: all 0.3s ease;
  margin: 0 !important;
 }
 
 /* 悬浮态图标反馈 */
 .profile-avatar-field:hover :deep(.el-icon) {
   color: #3b82f6 !important;
   transform: scale(1.1);
 }
</style>
