<script setup lang="ts">
import type { AccountQuotaWindow } from '@/api'

import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { quotaWindowDetails, quotaWindowLabel, quotaWindowPresentation } from '@/components/account/account-usage-window/presenter'

const props = withDefaults(defineProps<{
  label: string
  windows: AccountQuotaWindow[]
  showPercentage?: boolean
}>(), {
  showPercentage: true,
})
const { t } = useI18n({ useScope: 'global' })

const windowItems = computed(() => props.windows.map(window => ({
  ...quotaWindowDetails(window),
  key: window.key,
  label: quotaWindowLabel(window, false),
  labelTooltip: quotaWindowLabel(window),
  usedPercent: window.usedPercent,
  usedPercentDisplay: window.usedPercentDisplay,
  stale: window.stale,
  presentation: quotaWindowPresentation(window, '2px'),
})))
const highestUsageWindow = computed(() => props.windows.reduce((highest, window) => {
  if (typeof window.usedPercent !== 'number')
    return highest
  if (!highest || typeof highest.usedPercent !== 'number' || window.usedPercent > highest.usedPercent)
    return window
  return highest
}, undefined as AccountQuotaWindow | undefined))
const highestUsageDisplay = computed(() => highestUsageWindow.value?.usedPercentDisplay ?? '—')
const highestUsageTextClass = computed(() => highestUsageWindow.value
  ? quotaWindowPresentation(highestUsageWindow.value, '2px').percentTextClass
  : 'text-z-text-quaternary')
</script>

<template>
  <div class="col-span-full grid min-w-0 grid-cols-subgrid gap-y-1.5">
    <div class="col-span-full grid min-w-0 grid-cols-subgrid items-baseline text-[10px] leading-3 font-bold">
      <span class="min-w-0 truncate text-z-text-quaternary">
        {{ label }}
      </span>
      <strong
        v-if="showPercentage"
        class="shrink-0 font-mono font-heavy tabular-nums"
        :class="highestUsageTextClass"
      >
        {{ highestUsageDisplay }}
      </strong>
    </div>

    <div class="col-span-full grid min-w-0 gap-2">
      <div v-for="item in windowItems" :key="item.key" class="grid min-w-0 gap-1">
        <div class="flex flex-wrap items-baseline justify-between gap-x-2 text-[10px] leading-3.5">
          <span class="text-z-text-secondary">{{ item.label }}</span>
          <span class="flex items-baseline gap-1.5 font-mono tabular-nums">
            <span class="text-z-text-secondary">{{ item.usdDisplay }}</span>
            <span v-if="item.incompleteCost" class="text-z-warning-text">{{ t('accounts.quota.partialCost') }}</span>
            <strong :class="item.presentation.percentTextClass">{{ item.usedPercentDisplay }}</strong>
            <span v-if="item.stale" class="text-z-warning-text">{{ t('accounts.upstream.stale') }}</span>
          </span>
        </div>
        <div
          class="h-1 w-full overflow-hidden rounded-full bg-z-border-secondary"
          role="progressbar"
          :aria-label="item.labelTooltip"
          aria-valuemin="0"
          aria-valuemax="100"
          :aria-valuenow="item.stale ? undefined : item.usedPercent ?? undefined"
          :aria-valuetext="item.stale ? t('accounts.upstream.stale') : item.usedPercentDisplay"
        >
          <div
            class="h-full rounded-full transition-[width,background-color] duration-200 motion-reduce:transition-none"
            :class="item.presentation.barClass"
            :style="item.presentation.barStyle"
          />
        </div>
      </div>
    </div>
  </div>
</template>
