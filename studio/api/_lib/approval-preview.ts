import type { ApprovalPreviewFieldDTO } from '../../src/types.js'

type JsonRecord = Record<string, unknown>

interface PreviewRule {
  label: string
  keys: readonly string[]
  maximumLength?: number
}

interface ApprovalPreviewResult {
  fields: ApprovalPreviewFieldDTO[]
  complete: boolean
}

const sharedDestination: PreviewRule[] = [
  { label: 'Destination', keys: ['destination', 'channel'] },
  { label: 'Summary', keys: ['summary'], maximumLength: 1000 },
]

const rulesByAction: Record<string, readonly PreviewRule[]> = {
  send_draft: [
    { label: 'Recipient', keys: ['recipient', 'to'] },
    { label: 'Channel', keys: ['channel'] },
    { label: 'Subject', keys: ['subject'], maximumLength: 500 },
    { label: 'Draft', keys: ['body', 'message'], maximumLength: 4000 },
  ],
  publish_draft: [
    { label: 'Destination', keys: ['destination', 'channel'] },
    { label: 'Title', keys: ['title'], maximumLength: 500 },
    { label: 'Caption', keys: ['caption'], maximumLength: 2000 },
    { label: 'Draft', keys: ['body'], maximumLength: 4000 },
  ],
  deploy_preview: [
    { label: 'Project', keys: ['project'] },
    { label: 'Environment', keys: ['environment'] },
    { label: 'Preview URL', keys: ['url'], maximumLength: 1000 },
    { label: 'Summary', keys: ['summary'], maximumLength: 1000 },
  ],
  purchase_request: [
    { label: 'Vendor', keys: ['vendor'] },
    { label: 'Item', keys: ['item'], maximumLength: 1000 },
    { label: 'Amount', keys: ['amount'] },
    { label: 'Currency', keys: ['currency'] },
    { label: 'Summary', keys: ['summary'], maximumLength: 1000 },
  ],
}

function record(value: unknown): JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value) ? value as JsonRecord : {}
}

function boundedScalar(value: unknown, maximumLength: number): string | null {
  if (typeof value === 'string') {
    const bounded = value.trim().slice(0, maximumLength)
    return bounded === '' ? null : bounded
  }
  if (typeof value === 'number' && Number.isFinite(value)) return String(value).slice(0, maximumLength)
  if (typeof value === 'boolean') return value ? 'Yes' : 'No'
  return null
}

function hasScalar(source: JsonRecord, keys: readonly string[]): boolean {
  return keys.some((key) => boundedScalar(source[key], 4000) !== null)
}

function completeFor(actionType: string, source: JsonRecord): boolean {
  if (actionType === 'send_draft') {
    return hasScalar(source, ['recipient', 'to']) && hasScalar(source, ['body', 'message'])
  }
  if (actionType === 'publish_draft') {
    return hasScalar(source, ['destination', 'channel']) && hasScalar(source, ['body', 'caption'])
  }
  if (actionType === 'deploy_preview') {
    return hasScalar(source, ['project']) && hasScalar(source, ['environment']) && hasScalar(source, ['url'])
  }
  if (actionType === 'purchase_request') {
    return hasScalar(source, ['vendor'])
      && hasScalar(source, ['item'])
      && hasScalar(source, ['amount'])
      && hasScalar(source, ['currency'])
  }
  return false
}

export function approvalPreview(actionType: string, value: unknown): ApprovalPreviewResult {
  const source = record(value)
  const rules = rulesByAction[actionType] ?? sharedDestination
  const fields: ApprovalPreviewFieldDTO[] = []
  for (const rule of rules) {
    let safeValue: string | null = null
    for (const key of rule.keys) {
      safeValue = boundedScalar(source[key], rule.maximumLength ?? 500)
      if (safeValue !== null) break
    }
    if (safeValue !== null) fields.push({ label: rule.label, value: safeValue })
  }
  return { fields: fields.slice(0, 8), complete: completeFor(actionType, source) }
}
