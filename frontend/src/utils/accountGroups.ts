import type { AccountGroupRef } from '@/api'

export function isVisibleAccountGroup(group: AccountGroupRef) {
  return !group.pluginOwned
}

export function accountGroupUpdateBatches(
  records: { id: string, groups: AccountGroupRef[] }[],
  groupIds: string[] | undefined,
) {
  const batches = new Map<string, { ids: string[], groupIds: string[] | undefined }>()
  for (const record of records) {
    // 隐藏的插件关系按各记录保留，不能把某个账号或 Key 的内部组复制给其他记录
    const hiddenIds = record.groups.filter(group => !isVisibleAccountGroup(group)).map(group => group.id).sort()
    const key = groupIds === undefined
      ? ''
      : JSON.stringify(hiddenIds)
    const batch = batches.get(key)
    if (batch) {
      batch.ids.push(record.id)
    }
    else {
      batches.set(key, {
        ids: [record.id],
        groupIds: groupIds === undefined
          ? undefined
          : [
              ...new Set([
                ...groupIds,
                ...hiddenIds,
              ]),
            ],
      })
    }
  }
  return [
    ...batches.values(),
  ]
}
