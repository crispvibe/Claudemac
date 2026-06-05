<template>
  <div class="w-full min-h-[75vh] flex items-center justify-center bg-transparent">
    <!-- 利用 mt-20 下压整个区域的视觉重力，抵消掉顶部Header带来的“假偏上” -->
    <div class="flex items-center gap-8 mt-20 mb-8 opacity-90 transition-all hover:opacity-100">
      
      <!-- 左侧：具有压迫感的极简巨型数字 降维为：极轻细、空灵的线条感数字 -->
      <div class="text-[88px] font-thin text-slate-400 dark:text-slate-500 leading-none tracking-[0.08em] select-none">
        404
      </div>
      
      <!-- 中部：一根非常克制但极具切割感的银灰色修长隔离线 -->
      <div class="w-[1px] h-[64px] bg-slate-200/60 dark:bg-slate-700/60 rounded-full mx-2"></div>
      
      <!-- 右侧：极其微型的提示区块与回链接 -->
      <div class="flex flex-col justify-center gap-1">
        <h2 class="text-lg font-medium text-slate-600 dark:text-slate-400 tracking-wide">页面未归档</h2>
        <p class="text-[13px] text-slate-500 dark:text-slate-400 max-w-[240px] leading-relaxed mb-3">
          由于路由地址变动或您的权限受限，系统阻止了该通路的加载。
        </p>
        <div>
          <el-button link class="!text-[#1f83ff] !p-0 font-semibold text-[13.5px] hover:!text-[#3b82f6] transition-colors tracking-widest" @click="refreshPage">
            刷新重试
          </el-button>
        </div>
      </div>

    </div>
  </div>
</template>

<script setup>
  defineOptions({
    name: 'StatusFallbackPage'
  })

  // 最极简纯粹的操作响应：仅执行页面刷新
  const refreshPage = () => {
    window.location.reload()
  }
</script>
