import { createPinia } from 'pinia'
import { useAppStore } from '@/pinia/modules/app'
import { useUserStore } from '@/pinia/modules/user'

const store = createPinia()

export { store, useAppStore, useUserStore }
