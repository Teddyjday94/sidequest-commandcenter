import type { StudioApi } from '../lib/api.js'
import { StudioApiError } from '../lib/api.js'
import { button, element } from '../lib/dom.js'
import type { OwnerSessionManager } from '../lib/owner-session.js'
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

function permissionState(onConnect: (email: string, password: string) => Promise<void>): HTMLElement {
  const main = element('main', 'state-page')
  main.id = 'studio-main'
  const email = element('input')
  email.type = 'email'
  email.name = 'email'
  email.autocomplete = 'email'
  email.required = true
  email.setAttribute('aria-label', 'Sidequest email')
  const password = element('input')
  password.type = 'password'
  password.name = 'password'
  password.autocomplete = 'current-password'
  password.required = true
  password.setAttribute('aria-label', 'Password')
  const submit = button('Open command center', 'button-primary', 'submit')
  const error = element('p', 'session-error')
  error.setAttribute('role', 'alert')
  const form = element('form', 'session-form', [email, password, submit, error])
  form.addEventListener('submit', async (event) => {
    event.preventDefault()
    if (!email.value.trim() || !password.value) return
    submit.disabled = true
    submit.textContent = 'Opening…'
    error.textContent = ''
    try {
      await onConnect(email.value, password.value)
    } catch {
      error.textContent = 'Sign-in failed. Check your Sidequest email and password.'
      submit.disabled = false
      submit.textContent = 'Open command center'
    }
  })
  main.append(
    element('p', 'eyebrow', ['Private workspace']),
    element('h1', '', ['Sign in to your studio']),
    element('p', '', ['Use the same private Sidequest account you use for the client portal. No token copying required.']),
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

export function mountStudio(root: HTMLElement, api: StudioApi, ownerSession: OwnerSessionManager): void {
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
        show(permissionState(async (email, password) => {
          await ownerSession.signIn(email, password)
          try {
            await api.connectSession()
          } catch (connectError) {
            await ownerSession.signOut()
            throw connectError
          }
          await load()
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
