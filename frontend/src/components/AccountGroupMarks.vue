<script setup lang="ts">
import type { AccountGroupRef } from '@/api'

import { computed } from 'vue'
import { useI18n } from 'vue-i18n'

const props = defineProps<{
  groups: AccountGroupRef[]
  hidePluginGroups?: boolean
}>()

const { t } = useI18n({ useScope: 'global' })

const visibleGroups = computed(() => props.groups.filter(group => !props.hidePluginGroups || !group.pluginOwned))

const fullNames = computed(() =>
  visibleGroups.value.map(group => (group.enabled
    ? group.name
    : t('common.status.disabledName', { name: group.name }))).join('、'),
)
</script>

<template>
  <div
    v-if="visibleGroups.length > 0"
    class="flex min-w-0 flex-wrap items-center gap-1.5"
    :title="fullNames"
    :aria-label="fullNames"
  >
    <span
      v-for="group in visibleGroups"
      :key="group.id"
      class="size-4 shrink-0 rounded-sm"
      :style="{ backgroundColor: group.color }"
      :title="group.name"
    />
  </div>
  <span v-else class="text-xs text-z-text-quaternary">—</span>
</template>
