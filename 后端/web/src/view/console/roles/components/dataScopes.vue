<template>
  <div>
    <warning-bar
      title="此功能仅用于创建角色和角色的many2many关系表，具体使用还须自己结合表实现业务，详情参考示例代码（客户示例）。"
    />
    <div class="sticky top-0.5 z-10 my-4">
      <el-button class="float-left" type="primary" @click="all">全选</el-button>
      <el-button class="float-left" type="primary" @click="self"
        >本角色</el-button
      >
      <el-button class="float-left" type="primary" @click="selfAndChildren"
        >本角色及子角色</el-button
      >
      <el-button class="float-right" type="primary" @click="authDataEnter"
        >确 定</el-button
      >
    </div>
    <div class="clear-both pt-4">
      <el-checkbox-group v-model="dataRoleIds" @change="selectRole">
        <el-checkbox
          v-for="(item, key) in roles"
          :key="key"
          :label="item"
          >{{ item.roleName }}</el-checkbox
        >
      </el-checkbox-group>
    </div>
  </div>
</template>

<script setup>
  import { updateRoleDataScope } from '@/api/roles'
  import WarningBar from '@/components/warningBar/warningBar.vue'
  import { ref } from 'vue'
  import { ElMessage } from 'element-plus'

  defineOptions({
    name: 'RoleDataScopePanel'
  })

  const props = defineProps({
    row: {
      default: function () {
        return {}
      },
      type: Object
    },
    roleTree: {
      default: function () {
        return []
      },
      type: Array
    }
  })

  const roles = ref([])
  const needConfirm = ref(false)
  //   平铺角色
  const roundRoles = (roleTree) => {
	  roleTree &&
	    roleTree.forEach((item) => {
	      const obj = {}
	      obj.roleId = item.roleId
	      obj.roleName = item.roleName
	      roles.value.push(obj)
	      if (item.children && item.children.length) {
	        roundRoles(item.children)
	      }
	    })
  }

  const dataRoleIds = ref([])
  const init = () => {
	  roundRoles(props.roleTree)
	  props.row.dataRoleIds &&
	    props.row.dataRoleIds.forEach((item) => {
	      const obj =
	        roles.value &&
	        roles.value.filter(
	          (role) => role.roleId === item.roleId
	        ) &&
	        roles.value.filter(
	          (role) => role.roleId === item.roleId
	        )[0]
	      dataRoleIds.value.push(obj)
	    })
  }

  init()

  // 暴露给外层使用的切换拦截统一方法
  const enterAndNext = () => {
    authDataEnter()
  }

  const emit = defineEmits(['changeRow'])
  const all = () => {
	  dataRoleIds.value = [...roles.value]
	  emit('changeRow', 'dataRoleIds', dataRoleIds.value)
	  needConfirm.value = true
  }
  const self = () => {
	  dataRoleIds.value = roles.value.filter(
	    (item) => item.roleId === props.row.roleId
	  )
	  emit('changeRow', 'dataRoleIds', dataRoleIds.value)
	  needConfirm.value = true
  }
  const selfAndChildren = () => {
	  const arrBox = []
	  getChildrenId(props.row, arrBox)
	  dataRoleIds.value = roles.value.filter(
	    (item) => arrBox.indexOf(item.roleId) > -1
	  )
	  emit('changeRow', 'dataRoleIds', dataRoleIds.value)
	  needConfirm.value = true
  }
  const getChildrenId = (row, arrBox) => {
	  arrBox.push(row.roleId)
	  row.children &&
	    row.children.forEach((item) => {
	      getChildrenId(item, arrBox)
      })
  }
  // 提交
  const authDataEnter = async () => {
    const res = await updateRoleDataScope(props.row)
    if (res.code === 0) {
      ElMessage({ type: 'success', message: '资源设置成功' })
    }
  	}

  //   选择
  const selectRole = () => {
	  dataRoleIds.value = dataRoleIds.value.filter((item) => item)
	  emit('changeRow', 'dataRoleIds', dataRoleIds.value)
	  needConfirm.value = true
  }

  defineExpose({
    enterAndNext,
    needConfirm
  })
</script>
