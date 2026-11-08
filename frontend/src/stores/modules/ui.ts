import { defineStore } from 'pinia'
import { shallowRef } from 'vue'

export const useUiStore = defineStore(
  'ui',
  () => {
    const sidebarCollapsed = shallowRef(false)
    const showPluginGroups = shallowRef(false)
    const showPluginKeys = shallowRef(false)

    function toggleSidebar(): void {
      sidebarCollapsed.value = !sidebarCollapsed.value
    }

    return {
      sidebarCollapsed,
      showPluginGroups,
      showPluginKeys,
      toggleSidebar,
    }
  },
  {
    persist: {
      key: 'codex-proxy-rs-ui',
      pick: ['sidebarCollapsed', 'showPluginGroups', 'showPluginKeys'],
    },
  },
)
