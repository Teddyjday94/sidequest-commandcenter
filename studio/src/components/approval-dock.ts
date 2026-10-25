import type { ApprovalDTO, StudioSnapshot } from '../types.js'
import { button, element, emptyState, formatTime } from '../lib/dom.js'
import { sortApprovals } from '../lib/store.js'

export type ApprovalDecision = 'approve' | 'reject' | 'revise'

export function approvalDock(
  snapshot: StudioSnapshot,
  onDecision: (approval: ApprovalDTO, decision: ApprovalDecision, note: string) => Promise<void>,
): HTMLElement {
  const section = element('section', 'approval-dock surface')
  section.setAttribute('aria-labelledby', 'approval-title')
  const heading = element('div', 'section-heading inline-heading', [
    element('div', '', [element('p', 'eyebrow', ['Human gate']), element('h2', '', ['Approval dock'])]),
    element('p', 'section-note', ['No external action runs here']),
  ])
  heading.querySelector('h2')?.setAttribute('id', 'approval-title')
  section.append(heading)
  const approvals = sortApprovals(snapshot.approvals)
  if (approvals.length === 0) {
    section.append(emptyState('No decisions are waiting.', 'State-changing work remains blocked until an approval appears here.'))
    return section
  }

  const list = element('div', 'approval-list')
  for (const approval of approvals) {
    const article = element('article', `approval-item risk-${approval.risk}`)
    const controls = element('div', 'approval-actions')
    for (const [label, decision] of [
      ['Approve', 'approve'],
      ['Revise', 'revise'],
      ['Reject', 'reject'],
    ] as const) {
      const control = button(label, decision === 'approve' ? 'button-primary' : 'button-quiet')
      control.addEventListener('click', async () => {
        const note = approval.risk === 'high' || decision !== 'approve'
          ? window.prompt(`Add a note for “${approval.title}”`, '')
          : ''
        if (note === null || (approval.risk === 'high' && note.trim() === '')) return
        control.disabled = true
        try {
          await onDecision(approval, decision, note)
        } catch {
          // The shell reports the bounded failure state and keeps the approval pending.
        } finally {
          control.disabled = false
        }
      })
      controls.append(control)
    }
    article.append(
      element('div', 'approval-copy', [
        element('div', 'approval-meta', [
          element('span', 'risk-label', [`${approval.risk} risk`]),
          element('span', '', [`Requested ${formatTime(approval.requestedAt)}`]),
        ]),
        element('h3', '', [approval.title]),
        element('p', '', [approval.actionType.replaceAll('_', ' ')]),
      ]),
      controls,
    )
    list.append(article)
  }
  section.append(list)
  return section
}
