import { defineStore } from 'pinia'
import { shallowRef } from 'vue'

export const useUiStore = defineStore(
  'ui',
  () => {
    const sidebarCollapsed = shallowRef(false)
    const showPluginGroups = shallowRef(false)

    function toggleSidebar(): void {
      sidebarCollapsed.value = !sidebarCollapsed.value
    }

    return {
      sidebarCollapsed,
      showPluginGroups,
      toggleSidebar,
    }
  },
  {
    persist: {
      key: 'codex-proxy-rs-ui',
      pick: ['sidebarCollapsed', 'showPluginGroups'],
    },
  },
)
