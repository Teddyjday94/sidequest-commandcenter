import { describe, expect, it, vi } from 'vitest'

import { HttpError } from '../../api/_lib/http.js'
import { createEmergencyStopHandler } from '../../api/emergency-stop.js'
import { createMissionToggleHandler } from '../../api/mission-toggle.js'

const ownerId = '41000000-0000-4000-8000-000000000001'

function fakeAdmin(userId = ownerId) {
  const getUser = vi.fn().mockResolvedValue({ data: { user: { id: userId } }, error: null })
  const rpc = vi.fn(async (name: string, args: Record<string, unknown>) => {
    if (name === 'set_mission_enabled') {
      return { data: { id: args.p_mission_id, enabled: args.p_enabled }, error: null }
    }
    if (name === 'set_emergency_stop') {
      return { data: { enabled: args.p_enabled }, error: null }
    }
    return { data: null, error: { message: 'unexpected procedure' } }
  })
  const schema = vi.fn().mockReturnValue({ rpc })
  return { client: { auth: { getUser }, schema }, schema, rpc }
}

function post(path: string, body: unknown, headers: Record<string, string> = {}) {
  return new Request(`https://studio.example.test/api/${path}`, {
    method: 'POST',
    headers: {
      authorization: 'Bearer valid-owner-token',
      'content-type': 'application/json',
      ...headers,
    },
    body: JSON.stringify(body),
  })
}

const allowCsrf = vi.fn()

describe('POST /api/mission-toggle', () => {
  it('rejects a non-owner before parsing or calling the database', async () => {
    const admin = fakeAdmin('42000000-0000-4000-8000-000000000002')
    const handler = createMissionToggleHandler({ admin: admin.client, ownerUserId: ownerId, csrf: allowCsrf })

    const response = await handler(post('mission-toggle', { missionId: 'weekday-research', enabled: true }))

    expect(response.status).toBe(403)
    expect(admin.schema).not.toHaveBeenCalled()
  })

  it('rejects CSRF before any database call', async () => {
    const admin = fakeAdmin()
    const csrf = vi.fn(() => {
      throw new HttpError(403, 'csrf_rejected')
    })
    const handler = createMissionToggleHandler({ admin: admin.client, ownerUserId: ownerId, csrf })

    const response = await handler(post('mission-toggle', { missionId: 'weekday-research', enabled: true }))

    expect(response.status).toBe(403)
    expect(admin.schema).not.toHaveBeenCalled()
  })

  it.each([
    [{ missionId: '', enabled: true }, 'invalid_mission_id'],
    [{ missionId: 'UPPERCASE', enabled: true }, 'invalid_mission_id'],
    [{ missionId: 'weekday-research', enabled: 'yes' }, 'invalid_enabled'],
    [{ missionId: 'weekday-research', enabled: true, procedure: 'anything' }, 'invalid_request_body'],
  ])('rejects a non-canonical body before a database call', async (body, errorCode) => {
    const admin = fakeAdmin()
    const handler = createMissionToggleHandler({ admin: admin.client, ownerUserId: ownerId, csrf: allowCsrf })

    const response = await handler(post('mission-toggle', body))

    expect(response.status).toBe(400)
    expect(await response.json()).toEqual({ error: errorCode })
    expect(admin.schema).not.toHaveBeenCalled()
  })

  it('caps the request body before calling the database', async () => {
    const admin = fakeAdmin()
    const handler = createMissionToggleHandler({ admin: admin.client, ownerUserId: ownerId, csrf: allowCsrf })
    const request = post('mission-toggle', { missionId: 'weekday-research', enabled: true }, { 'content-length': '8193' })

    const response = await handler(request)

    expect(response.status).toBe(413)
    expect(admin.schema).not.toHaveBeenCalled()
  })

  it('calls only the fixed mission procedure with the authenticated actor', async () => {
    const admin = fakeAdmin()
    const handler = createMissionToggleHandler({ admin: admin.client, ownerUserId: ownerId, csrf: allowCsrf })

    const first = await handler(post('mission-toggle', { missionId: 'weekday-research', enabled: true }))
    const second = await handler(post('mission-toggle', { missionId: 'weekday-research', enabled: true }))

    expect(first.status).toBe(200)
    expect(await second.json()).toEqual({ id: 'weekday-research', enabled: true })
    expect(admin.rpc).toHaveBeenCalledTimes(2)
    expect(admin.rpc).toHaveBeenNthCalledWith(1, 'set_mission_enabled', {
      p_mission_id: 'weekday-research',
      p_enabled: true,
      p_actor: ownerId,
    })
  })
})

describe('POST /api/emergency-stop', () => {
  it('requires CSRF before any database call', async () => {
    const admin = fakeAdmin()
    const csrf = vi.fn(() => {
      throw new HttpError(403, 'csrf_rejected')
    })
    const handler = createEmergencyStopHandler({ admin: admin.client, ownerUserId: ownerId, csrf })

    const response = await handler(post('emergency-stop', { enabled: true }))

    expect(response.status).toBe(403)
    expect(admin.schema).not.toHaveBeenCalled()
  })

  it.each([
    [{ enabled: 'yes' }, 'invalid_enabled'],
    [{ enabled: true, actor: 'somebody-else' }, 'invalid_request_body'],
  ])('rejects a non-canonical body before a database call', async (body, errorCode) => {
    const admin = fakeAdmin()
    const handler = createEmergencyStopHandler({ admin: admin.client, ownerUserId: ownerId, csrf: allowCsrf })

    const response = await handler(post('emergency-stop', body))

    expect(response.status).toBe(400)
    expect(await response.json()).toEqual({ error: errorCode })
    expect(admin.schema).not.toHaveBeenCalled()
  })

  it('calls only the fixed emergency-stop procedure with the authenticated actor', async () => {
    const admin = fakeAdmin()
    const handler = createEmergencyStopHandler({ admin: admin.client, ownerUserId: ownerId, csrf: allowCsrf })

    const response = await handler(post('emergency-stop', { enabled: true }))

    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({ enabled: true })
    expect(admin.rpc).toHaveBeenCalledWith('set_emergency_stop', {
      p_enabled: true,
      p_actor: ownerId,
    })
  })
})
