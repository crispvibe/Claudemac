<template>
  <div 
    class="fixed inset-0 bg-[#f5f5f7]/80 backdrop-blur-sm flex items-center justify-center z-[999] transition-opacity"
    @click.self="closeModal"
  >
    <!-- 全新居中纯文本提示卡片 -->
    <div class="bg-white rounded-[24px] shadow-[0_20px_40px_-10px_rgba(0,0,0,0.08)] border border-gray-100 w-full max-w-[340px] mx-4 transform transition-all duration-300 ease-in-out relative flex flex-col items-center px-8 py-10">
      
      <!-- 极简关闭 -->
      <div class="absolute right-5 top-5 text-gray-300 hover:text-gray-600 transition-colors cursor-pointer w-8 h-8 flex items-center justify-center rounded-full hover:bg-gray-50" @click="closeModal">
        <close class="w-4 h-4" />
      </div>

      <!-- 纯文本标题与信息 -->
      <h3 class="text-[20px] font-semibold text-[#1d1d1f] tracking-tight mb-2 mt-4 text-center">{{ displayData.title }}</h3>
      
      <p class="text-[14px] text-[#86868b] text-center leading-relaxed mb-8 max-w-[260px]">
        {{ displayData.message }}
      </p>

      <!-- 独立胶囊操作按钮 -->
      <el-button
        class="w-[180px] h-[46px] text-[15px] font-medium rounded-full transition-all duration-300 border-0 bg-[#1d1d1f] hover:bg-[#333336] text-white tracking-widest shadow-md shadow-gray-900/10 mx-auto block"
        @click="handleConfirm"
      >
        好 的
      </el-button>
      
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue';

const props = defineProps({
  errorData: {
    type: Object,
    required: true
  }
});

const emits = defineEmits(['close', 'confirm']);

// 纯文本定义的预设错误
const presetErrors = {
  500: {
    title: '服务暂时不可用'
  },
  404: {
    title: '请求资源不存在'
  },
  401: {
    title: '登录已失效'
  },
  'network': {
    title: '网络连接异常'
  }
};

const displayData = computed(() => {
  const preset = presetErrors[props.errorData.code];
  if (preset) {
    return {
      ...preset,
      message: props.errorData.message || '系统未提供进一步的说明。'
    };
  }

  return {
    title: '系统提示',
    message: props.errorData.message || '发生了一项未知异常。'
  };
});

const closeModal = () => {
   emits('close')
};

const handleConfirm = () => {
  emits('confirm', props.errorData.code);
  closeModal();
};
</script>
