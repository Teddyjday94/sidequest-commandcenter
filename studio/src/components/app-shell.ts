import type { StudioApi } from '../lib/api.js'
import { StudioApiError } from '../lib/api.js'
import { button, element } from '../lib/dom.js'
import type { AgentDTO, ApprovalDTO, MissionDTO, StudioSnapshot } from '../types.js'
import { agentWorkbench } from './agent-workbench.js'
import { approvalDock, type ApprovalDecision } from './approval-dock.js'
import { autonomyControls } from './autonomy-controls.js'
import { liveLedger } from './live-ledger.js'
import { morningBrief } from './morning-brief.js'
import { studioFloor } from './studio-floor.js'

function loadingState(): HTMLElement {
  const main = element('main', 'state-page')
  main.id = 'studio-main'
  main.setAttribute('aria-busy', 'true')
  main.append(element('p', 'eyebrow', ['Sidequest / private operations']), element('h1', '', ['Opening the studio…']), element('p', '', ['Reading the latest owner-safe snapshot.']))
  return main
}

function permissionState(onConnect: (token: string) => void): HTMLElement {
  const main = element('main', 'state-page')
  main.id = 'studio-main'
  const input = element('input')
  input.type = 'password'
  input.name = 'owner-token'
  input.autocomplete = 'off'
  input.required = true
  input.setAttribute('aria-label', 'Owner session token')
  const submit = button('Connect this session', 'button-primary', 'submit')
  const form = element('form', 'session-form', [input, submit])
  form.addEventListener('submit', (event) => {
    event.preventDefault()
    if (input.value.trim()) onConnect(input.value.trim())
  })
  main.append(
    element('p', 'eyebrow', ['Private workspace']),
    element('h1', '', ['Owner session required']),
    element('p', '', ['Use an active owner session to open the command center. The token remains in this browser tab only.']),
    form,
  )
  return main
}

function errorState(message: string, onRetry: () => void): HTMLElement {
  const main = element('main', 'state-page')
  main.id = 'studio-main'
  const retry = button('Try again', 'button-primary')
  retry.addEventListener('click', onRetry)
  main.append(element('p', 'eyebrow', ['Snapshot unavailable']), element('h1', '', ['The studio could not refresh.']), element('p', '', [message]), retry)
  return main
}

export function mountStudio(root: HTMLElement, api: StudioApi): void {
  let snapshot: StudioSnapshot | null = null
  let selectedAgentId: string | null = null
  let notice = ''

  const show = (node: HTMLElement) => root.replaceChildren(node)
  const announce = (message: string) => {
    notice = message
  }

  async function load(): Promise<void> {
    show(loadingState())
    try {
      snapshot = await api.snapshot()
      if (!selectedAgentId || !snapshot.agents.some((agent) => agent.id === selectedAgentId)) {
        selectedAgentId = snapshot.agents[0]?.id ?? null
      }
      render()
    } catch (error) {
      if (error instanceof StudioApiError && (error.status === 401 || error.status === 403)) {
        show(permissionState((token) => {
          sessionStorage.setItem('sidequest_owner_token', token)
          void load()
        }))
        return
      }
      show(errorState('No state was changed. Check the private API connection and retry.', () => void load()))
    }
  }

  async function refreshWith(action: () => Promise<unknown>, success: string): Promise<void> {
    try {
      await action()
      announce(success)
      snapshot = await api.snapshot()
      render()
    } catch (error) {
      announce(error instanceof StudioApiError ? `Action blocked: ${error.code}` : 'Action failed safely.')
      render()
      throw error
    }
  }

  function selectAgent(agent: AgentDTO): void {
    selectedAgentId = agent.id
    render()
    document.querySelector<HTMLElement>('.workbench')?.focus({ preventScroll: false })
  }

  async function decide(approval: ApprovalDTO, decision: ApprovalDecision, note: string): Promise<void> {
    await refreshWith(
      () => api.resolveApproval(approval.id, decision, note),
      `${approval.title} marked ${decision}. External action is still manual.`,
    )
  }

  async function toggleMission(mission: MissionDTO, enabled: boolean): Promise<void> {
    await refreshWith(() => api.toggleMission(mission.id, enabled), `${mission.name} ${enabled ? 'enabled' : 'disabled'}.`)
  }

  async function setStop(enabled: boolean): Promise<void> {
    await refreshWith(() => api.setEmergencyStop(enabled), enabled ? 'Emergency stop engaged.' : 'Automation resumed.')
  }

  function render(): void {
    if (!snapshot) return
    const shell = element('div', `app-shell ${snapshot.autonomy.emergencyStop ? 'automation-stopped' : ''}`)
    const header = element('header', 'topbar', [
      element('a', 'wordmark', [element('span', 'wordmark-mark', ['SQ']), element('span', '', ['Agent Studio'])]),
      element('div', 'topbar-status', [
        element('span', 'meta-label', ['System']),
        element('strong', '', [snapshot.autonomy.emergencyStop ? 'Stopped by owner' : 'Guarded autonomy']),
      ]),
    ])
    const brand = header.querySelector('a')
    if (brand) brand.setAttribute('href', '#studio-main')
    const selected = snapshot.agents.find((agent) => agent.id === selectedAgentId) ?? null
    const main = element('main', 'studio-layout')
    main.id = 'studio-main'
    if (notice) {
      const alert = element('p', 'action-notice', [notice])
      alert.setAttribute('role', 'status')
      main.append(alert)
      notice = ''
    }
    main.append(
      morningBrief(snapshot),
      element('div', 'floor-workbench', [studioFloor(snapshot, selectedAgentId, selectAgent), agentWorkbench(snapshot, selected)]),
      element('div', 'ledger-approvals', [liveLedger(snapshot), approvalDock(snapshot, decide)]),
      autonomyControls(snapshot, toggleMission, setStop),
    )
    const footer = element('footer', 'site-footer', [
      element('p', '', ['Private command center · internal work only']),
      element('p', '', [`Snapshot ${new Date(snapshot.serverTime).toLocaleString()}`]),
    ])
    shell.append(header, main, footer)
    show(shell)
  }

  void load()
}
