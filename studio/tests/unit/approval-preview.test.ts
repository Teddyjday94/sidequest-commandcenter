import { describe, expect, it } from 'vitest'

import { approvalPreview } from '../../api/_lib/approval-preview.js'

describe('approval preview normalization', () => {
  it('renders the same valid alias used to establish completeness', () => {
    const preview = approvalPreview('send_draft', {
      recipient: '   ',
      to: 'owner@example.test',
      body: 'Exact proposed message',
    })

    expect(preview.complete).toBe(true)
    expect(preview.fields).toContainEqual({ label: 'Recipient', value: 'owner@example.test' })
    expect(preview.fields).toContainEqual({ label: 'Draft', value: 'Exact proposed message' })
  })

  it('never marks an unknown action complete from a generic summary', () => {
    const preview = approvalPreview('unknown_action', { summary: 'Do something external' })

    expect(preview.complete).toBe(false)
    expect(preview.fields).toEqual([{ label: 'Summary', value: 'Do something external' }])
  })
})
