import type { ApprovalDTO, StudioSnapshot } from '../types.js'

export class StudioApiError extends Error {
  constructor(readonly status: number, readonly code: string) {
    super(code)
    this.name = 'StudioApiError'
  }
}

export interface StudioApi {
  connectSession(): Promise<{ connected: boolean }>
  snapshot(): Promise<StudioSnapshot>
  toggleMission(missionId: string, enabled: boolean): Promise<{ id: string; enabled: boolean }>
  setEmergencyStop(enabled: boolean): Promise<{ enabled: boolean }>
  resolveApproval(
    approvalId: string,
    decision: 'approve' | 'reject' | 'revise',
    note: string,
  ): Promise<ApprovalDTO>
}

function cookie(name: string): string {
  const prefix = `${name}=`
  const match = document.cookie.split(';').map((part) => part.trim()).find((part) => part.startsWith(prefix))
  return match ? decodeURIComponent(match.slice(prefix.length)) : ''
}

async function parseResponse<T>(response: Response): Promise<T> {
  const data = (await response.json().catch(() => ({}))) as { error?: unknown } & T
  if (!response.ok) {
    throw new StudioApiError(response.status, typeof data.error === 'string' ? data.error : 'request_failed')
  }
  return data
}

type ReadAccessToken = () => string | Promise<string>
type Fetcher = typeof fetch

export function createStudioApi(
  readAccessToken: ReadAccessToken = () => sessionStorage.getItem('sidequest_owner_token') ?? '',
  fetcher: Fetcher = fetch,
): StudioApi {
  async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const accessToken = await readAccessToken()
    if (!accessToken) throw new StudioApiError(401, 'missing_session')
    const headers = new Headers(init.headers)
    headers.set('authorization', `Bearer ${accessToken}`)
    if (init.method && init.method !== 'GET') {
      headers.set('content-type', 'application/json')
      headers.set('x-csrf-token', cookie('sq_csrf'))
    }
    return parseResponse<T>(await fetcher(path, { ...init, headers }))
  }

  async function connectSession(): Promise<{ connected: boolean }> {
    const accessToken = await readAccessToken()
    if (!accessToken) throw new StudioApiError(401, 'missing_session')
    return parseResponse(
      await fetcher('/api/session', {
        method: 'POST',
        headers: { authorization: `Bearer ${accessToken}` },
      }),
    )
  }

  return {
    connectSession,
    snapshot: () => request<StudioSnapshot>('/api/snapshot'),
    toggleMission: (missionId, enabled) =>
      request('/api/mission-toggle', { method: 'POST', body: JSON.stringify({ missionId, enabled }) }),
    setEmergencyStop: (enabled) =>
      request('/api/emergency-stop', { method: 'POST', body: JSON.stringify({ enabled }) }),
    resolveApproval: (approvalId, decision, note) =>
      request('/api/approval-resolve', { method: 'POST', body: JSON.stringify({ approvalId, decision, note }) }),
  }
}
