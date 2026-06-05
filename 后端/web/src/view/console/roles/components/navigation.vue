<template>
  <div>
    <div class="sticky top-0.5 z-10 pb-2">
      <div class="flex gap-2 items-center mb-2">
        <el-input v-model="filterText" class="flex-1" placeholder="筛选" />
        <el-button type="primary" @click="relation">确 定</el-button>
      </div>
      <div class="flex items-center gap-2">
        <span class="whitespace-nowrap">默认首页：</span>
        <el-select
          :model-value="row.defaultEntry"
          filterable
          placeholder="请选择默认首页"
          class="flex-1"
          @change="handleDefaultEntryChange"
        >
          <el-option
            v-for="item in menuOptions"
            :key="item.value"
            :label="item.label"
            :value="item.value"
          />
        </el-select>
      </div>
    </div>
    <div class="tree-content clear-both">
      <el-scrollbar>
        <el-tree
          ref="menuTree"
          :data="menuTreeData"
          :default-checked-keys="menuTreeIds"
          :props="menuDefaultProps"
          default-expand-all
          highlight-current
          node-key="id"
          show-checkbox
          :filter-node-method="filterNode"
          @check="nodeChange"
        >
          <template #default="{ node, data }">
            <div class="flex items-center gap-2">
              <span>{{ node.label }}</span>
              <SvgIcon v-if="row.defaultEntry === data.name" icon="ant-design:home-filled" class="inline text-lg text-active" />
              <span v-if="data.menuBtn.length">
                <el-button type="primary" link @click.stop="() => OpenBtn(data)">
                  分配按钮
                </el-button>
              </span>
            </div>
          </template>
        </el-tree>
      </el-scrollbar>
    </div>
    <el-dialog v-model="btnVisible" title="分配按钮" destroy-on-close>
      <el-table
        ref="btnTableRef"
        :data="btnData"
        row-key="id"
        @selection-change="handleSelectionChange"
      >
        <el-table-column type="selection" width="55" />
        <el-table-column label="按钮名称" prop="name" />
        <el-table-column label="按钮备注" prop="desc" />
      </el-table>
      <template #footer>
        <div class="dialog-footer">
          <el-button @click="closeDialog">取 消</el-button>
          <el-button type="primary" @click="enterDialog">确 定</el-button>
        </div>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
  import {
    fetchNavigationTree,
    fetchRoleNavigation,
    assignRoleNavigation
  } from '@/api/navigation'
  import { updateRole } from '@/api/roles'
  import { getRoleButtonBindings, saveRoleButtonBindings } from '@/api/roleButtons'
  import { nextTick, ref, watch } from 'vue'
  import { ElMessage } from 'element-plus'

  defineOptions({
    name: 'RoleNavigationPanel'
  })

  const props = defineProps({
    row: {
      default: function () {
        return {}
      },
      type: Object
    }
  })

  const emit = defineEmits(['changeRow'])
  const filterText = ref('')
  const menuTreeData = ref([])
  const menuTreeIds = ref([])
  const needConfirm = ref(false)
  const menuTree = ref(null)
  const menuDefaultProps = ref({
    children: 'children',
    label: function (data) {
      return data.meta.title
    },
    disabled: function (data) {
      if (props.row.defaultEntry !== data.name) return false
      // 只在该节点已勾选时禁用，避免出现“默认首页未勾选却无法勾选”的死锁状态
      const checkedKeys = menuTree.value?.getCheckedKeys?.() || menuTreeIds.value
      return checkedKeys.includes(Number(data.id))
    }
  })

  const menuOptions = ref([])

  const isExternalRoute = (name) => {
    if (!name) return false
    return name.startsWith('http://') || name.startsWith('https://')
  }

  const findMenuByName = (menus, name) => {
    for (const item of menus || []) {
      if (item?.name === name) return item
      if (item?.children?.length) {
        const found = findMenuByName(item.children, name)
        if (found) return found
      }
    }
    return null
  }

  const buildOptionsFromCheckedLeafMenus = () => {
    const checkedLeafMenus = menuTree.value
      ? menuTree.value.getCheckedNodes(false, true)
      : []
    const options = checkedLeafMenus
      .filter((item) => item?.name && !isExternalRoute(item.name))
      .map((item) => ({
        label: item?.meta?.title || item.name,
        value: item.name
      }))

    // 确保当前默认首页能正常显示（即使历史数据不一致）
    if (props.row.defaultEntry && !options.some(o => o.value === props.row.defaultEntry)) {
      const found = findMenuByName(menuTreeData.value, props.row.defaultEntry)
      if (found && !isExternalRoute(found.name)) {
        options.push({
          label: found?.meta?.title || found.name,
          value: found.name
        })
      }
    }

    return options
  }

  const refreshDefaultEntryOptions = () => {
    menuOptions.value = buildOptionsFromCheckedLeafMenus()
  }

  const isDefaultEntryAllowed = (routeName) => {
    if (!routeName) return false
    const checkedLeafMenus = menuTree.value
      ? menuTree.value.getCheckedNodes(false, true)
      : []
    return checkedLeafMenus.some((item) => item?.name === routeName)
  }

  const init = async () => {
    // 获取所有菜单树
    const res = await fetchNavigationTree()
    menuTreeData.value = res.data.menus
    const res1 = await fetchRoleNavigation({ roleId: props.row.roleId })
    const menus = res1.data.menus
    const arr = []
    menus.forEach((item) => {
      // 防止直接选中父级造成全选
      if (!menus.some((same) => same.parentId === item.menuId)) {
        arr.push(Number(item.menuId))
      }
    })
    menuTreeIds.value = arr

    // 确保异步数据加载后，树的勾选状态与选项同步
    await nextTick()
    if (menuTree.value?.setCheckedKeys) {
      menuTree.value.setCheckedKeys(menuTreeIds.value)
      await nextTick()
    }
    refreshDefaultEntryOptions()
  }

  init()

  const setDefault = async (data) => {
    const res = await updateRole({
      roleId: props.row.roleId,
      roleName: props.row.roleName,
      parentId: props.row.parentId,
      defaultEntry: data.name
    })
    if (res.code === 0) {
      relation()
      emit('changeRow', 'defaultEntry', res.data.role.defaultEntry)
    }
  }

  const handleDefaultEntryChange = (val) => {
    // 兜底校验：未勾选菜单不允许被设置为默认首页
    if (!isDefaultEntryAllowed(val)) {
      ElMessage.warning('未勾选的菜单不可设置为默认首页，请先勾选后再选择')
      return
    }
    setDefault({ name: val })
  }

  const nodeChange = () => {
    needConfirm.value = true
    refreshDefaultEntryOptions()
  }
  // 暴露给外层使用的切换拦截统一方法
  const enterAndNext = () => {
    relation()
  }
  // 关联树 确认方法
  const relation = async () => {
    const checkArr = menuTree.value.getCheckedNodes(false, true)
    const res = await assignRoleNavigation({
      menus: checkArr,
      roleId: props.row.roleId
    })
    if (res.code === 0) {
      ElMessage({
        type: 'success',
        message: '菜单设置成功!'
      })

      refreshDefaultEntryOptions()
    }
  }

  defineExpose({ enterAndNext, needConfirm })

  const btnVisible = ref(false)

  const btnData = ref([])
  const multipleSelection = ref([])
  const btnTableRef = ref()
  let menuID = ''
  const OpenBtn = async (data) => {
    menuID = data.id
    const res = await getRoleButtonBindings({
      menuID: menuID,
      roleId: props.row.roleId
    })
    if (res.code === 0) {
      openDialog(data)
      await nextTick()
      if (res.data.selected) {
        res.data.selected.forEach((id) => {
          btnData.value.some((item) => {
            if (item.id === id) {
              btnTableRef.value.toggleRowSelection(item, true)
            }
          })
        })
      }
    }
  }

  const handleSelectionChange = (val) => {
    multipleSelection.value = val
  }

  const openDialog = (data) => {
    btnVisible.value = true
    btnData.value = data.menuBtn
  }

  const closeDialog = () => {
    btnVisible.value = false
  }
  const enterDialog = async () => {
    const selected = multipleSelection.value.map((item) => item.id)
    const res = await saveRoleButtonBindings({
      menuID,
      selected,
      roleId: props.row.roleId
    })
    if (res.code === 0) {
      ElMessage({ type: 'success', message: '设置成功' })
      btnVisible.value = false
    }
  }

  const filterNode = (value, data) => {
    if (!value) return true
    // console.log(data.mate.title)
    return data.meta.title.indexOf(value) !== -1
  }

  watch(filterText, (val) => {
    menuTree.value.filter(val)
  })
</script>
