import { emitter } from '@/utils/event-bus.js'

export const closeThisPage = () => {
  emitter.emit('closeThisPage')
}
