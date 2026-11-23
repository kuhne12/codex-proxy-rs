import { defineStore } from 'pinia'
import { shallowRef } from 'vue'

export const useUiStore = defineStore(
  'ui',
  () => {
    const sidebarCollapsed = shallowRef(false)
    const showPluginKeys = shallowRef(false)

    function toggleSidebar(): void {
      sidebarCollapsed.value = !sidebarCollapsed.value
    }

    return {
      sidebarCollapsed,
      showPluginKeys,
      toggleSidebar,
    }
  },
  {
    persist: {
      key: 'codex-proxy-rs-ui',
      pick: ['sidebarCollapsed', 'showPluginKeys'],
    },
  },
)
