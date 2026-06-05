<template>
  <el-sub-menu
    ref="subMenu"
    :index="routerInfo.name"
    popper-class="nav-submenu-popover"
    class="nav-submenu dark:text-slate-300 relative"
  >
    <template #title>
      <div
        v-if="!isCollapse"
        class="flex items-center"
        :style="{
          height: sideHeight
        }"
      >
        <el-icon v-if="routerInfo.meta.icon">
          <component :is="routerInfo.meta.icon" />
        </el-icon>
        <span>{{ routerInfo.meta.title }}</span>
      </div>
      <template v-else>
        <el-icon v-if="routerInfo.meta.icon">
          <component :is="routerInfo.meta.icon" />
        </el-icon>
        <span>{{ routerInfo.meta.title }}</span>
      </template>
    </template>
    <slot />
  </el-sub-menu>
</template>

<script setup>
  import { inject, computed } from 'vue'
  import { useAppStore } from '@/pinia'
  import { storeToRefs } from 'pinia'
  const appStore = useAppStore()
  const { config } = storeToRefs(appStore)

  defineOptions({
    name: 'AsyncSubmenu'
  })

  defineProps({
    routerInfo: {
      default: function () {
        return null
      },
      type: Object
    }
  })

  const isCollapse = inject('isCollapse', {
    default: false
  })

  const sideHeight = computed(() => {
    return config.value.layout_side_item_height + 'px'
  })
</script>

<style lang="scss">
  .nav-submenu {
    .el-sub-menu__title {
      height: v-bind('sideHeight') !important;
    }
  }

  .nav-submenu-popover.el-menu--popup {
    border-radius: 18px !important;
    overflow: hidden;
    padding: 8px 0;
    border: 1px solid rgba(226, 232, 240, 0.9);
    box-shadow: 0 12px 32px rgba(15, 23, 42, 0.12);
  }

  .nav-submenu-popover,
  .nav-submenu-popover .el-menu,
  .nav-submenu-popover.el-popper,
  .nav-submenu-popover.el-popper .el-menu--popup {
    border-radius: 18px !important;
    overflow: hidden;
  }

  .nav-submenu-popover.el-menu--popup .el-menu-item,
  .nav-submenu-popover.el-menu--popup .el-sub-menu__title,
  .nav-submenu-popover .el-menu-item,
  .nav-submenu-popover .el-sub-menu__title {
    margin: 0 8px;
    border-radius: 12px;
  }
</style>
