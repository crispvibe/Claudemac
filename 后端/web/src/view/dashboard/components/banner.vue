<template>
  <el-carousel class="-mt-2" indicator-position="outside" :interval="5000">
    <el-carousel-item
      class="lg:h-40"
      v-for="(item, index) in banners"
      :key="index"
    >
      <div class="h-full w-full rounded-2xl border border-slate-200 dark:border-slate-700 bg-gradient-to-r from-slate-900 via-slate-800 to-slate-700 dark:from-slate-100 dark:via-slate-200 dark:to-slate-300 px-8 py-6 text-white dark:text-slate-900 flex flex-col justify-center gap-3">
        <div class="text-xs tracking-[0.3em] uppercase opacity-70">系统公告</div>
        <div class="text-2xl font-semibold">{{ item.title }}</div>
        <div class="text-sm opacity-80 leading-6 max-w-2xl">{{ item.description }}</div>
      </div>
    </el-carousel-item>
  </el-carousel>
</template>

<script setup>
  const banners = [
    {
      title: '稳定、安全的支付业务后台',
      description: '统一管理账号、权限、菜单与接口配置，保持核心链路清晰可控。'
    },
    {
      title: '聚焦关键运营与审计能力',
      description: '围绕配置管理、权限控制与交易支撑场景构建简洁稳定的管理工作台。'
    }
  ]
</script>

<style scoped lang="scss"></style>
