import type { MissionDTO, StudioSnapshot } from '../types.js'
import { button, element, emptyState, formatTime, textBlock } from '../lib/dom.js'
import { emergencyStopCopy } from '../lib/store.js'

export function autonomyControls(
  snapshot: StudioSnapshot,
  onMissionToggle: (mission: MissionDTO, enabled: boolean) => Promise<void>,
  onEmergencyStop: (enabled: boolean) => Promise<void>,
): HTMLElement {
  const section = element('section', 'autonomy-controls surface')
  section.setAttribute('aria-labelledby', 'autonomy-title')
  const copy = emergencyStopCopy(snapshot.autonomy.emergencyStop)
  const heading = element('div', 'section-heading inline-heading', [
    element('div', '', [element('p', 'eyebrow', ['Guardrails']), element('h2', '', ['Autonomy controls'])]),
    element('p', `safety-state ${snapshot.autonomy.emergencyStop ? 'is-stopped' : ''}`, [
      snapshot.autonomy.emergencyStop ? 'Automation stopped' : 'Internal automation available',
    ]),
  ])
  heading.querySelector('h2')?.setAttribute('id', 'autonomy-title')
  section.append(heading)

  const limits = element('div', 'limit-strip', [
    textBlock('Daily cap', String(snapshot.autonomy.dailyJobLimit)),
    textBlock('Retry cap', String(snapshot.autonomy.maximumAttempts)),
    textBlock('Runtime lease', `${snapshot.autonomy.runtimeMinutes} min`),
    textBlock('Operating window', `${snapshot.autonomy.windowStart}–${snapshot.autonomy.windowEnd}`),
    textBlock('Timezone', snapshot.autonomy.timezone),
  ])
  section.append(limits)

  const missionArea = element('div', 'mission-area', [element('h3', '', ['Recurring internal missions'])])
  if (snapshot.missions.length === 0) {
    missionArea.append(emptyState('No recurring missions are configured.', 'Mission definitions are created privately in the operations schema.'))
  } else {
    const missionList = element('div', 'mission-list')
    for (const mission of snapshot.missions) {
      const row = element('div', 'mission-row')
      const id = `mission-${mission.id}`
      const input = element('input')
      input.type = 'checkbox'
      input.id = id
      input.checked = mission.enabled
      input.disabled = snapshot.autonomy.emergencyStop
      input.addEventListener('change', async () => {
        input.disabled = true
        try {
          await onMissionToggle(mission, input.checked)
        } catch {
          input.checked = !input.checked
        } finally {
          input.disabled = snapshot.autonomy.emergencyStop
        }
      })
      const label = element('label', '', [
        element('span', 'mission-name', [mission.name]),
        element('span', 'mission-detail', [
          `${mission.jobKind} · every ${mission.cadenceMinutes} min · next ${formatTime(mission.nextRunAt)}`,
        ]),
      ])
      label.htmlFor = id
      row.append(label, input)
      missionList.append(row)
    }
    missionArea.append(missionList)
  }
  section.append(missionArea)

  const stopButton = button(copy.label, snapshot.autonomy.emergencyStop ? 'button-primary' : 'button-danger')
  const dialog = element('dialog', 'confirm-dialog')
  const cancel = button('Cancel', 'button-quiet')
  const confirm = button(copy.label, snapshot.autonomy.emergencyStop ? 'button-primary' : 'button-danger')
  cancel.addEventListener('click', () => dialog.close())
  confirm.addEventListener('click', async () => {
    confirm.disabled = true
    try {
      await onEmergencyStop(!snapshot.autonomy.emergencyStop)
      dialog.close()
    } catch {
      // Keep the confirmation open so the owner can retry or cancel.
    } finally {
      confirm.disabled = false
    }
  })
  dialog.append(
    element('form', 'dialog-body', [
      element('p', 'eyebrow', ['Confirm guardrail change']),
      element('h3', '', [copy.confirmation]),
      element('p', '', [copy.detail]),
      element('div', 'dialog-actions', [cancel, confirm]),
    ]),
  )
  stopButton.addEventListener('click', () => dialog.showModal())
  section.append(element('div', 'stop-zone', [element('p', '', [copy.detail]), stopButton]), dialog)
  return section
}
