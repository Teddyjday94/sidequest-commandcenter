import { describe, expect, it, vi } from 'vitest'

import { requireCsrf } from '../../api/_lib/csrf.js'
import { readServerEnv } from '../../api/_lib/env.js'
import { HttpError } from '../../api/_lib/http.js'
import { requireOwner } from '../../api/_lib/owner-auth.js'

const ownerId = '41000000-0000-0000-0000-000000000001'

function request(headers: HeadersInit = {}) {
  return new Request('https://studio.example.test/api/snapshot', { headers })
}

function authClient(userId: string | null, error: { message: string } | null = null) {
  const getUser = vi.fn().mockResolvedValue({
    data: { user: userId ? { id: userId } : null },
    error,
  })

  return { client: { auth: { getUser } }, getUser }
}

describe('requireOwner', () => {
  it('rejects a request without a bearer token before auth lookup', async () => {
    const { client, getUser } = authClient(ownerId)

    await expect(requireOwner(request(), { admin: client, ownerUserId: ownerId })).rejects.toMatchObject({
      status: 401,
      code: 'missing_session',
    })
    expect(getUser).not.toHaveBeenCalled()
  })

  it('rejects an expired token', async () => {
    const { client } = authClient(null, { message: 'JWT expired at a private timestamp' })

    await expect(
      requireOwner(request({ authorization: 'Bearer expired-token' }), {
        admin: client,
        ownerUserId: ownerId,
      }),
    ).rejects.toMatchObject({ status: 401, code: 'invalid_session' })
  })

  it('rejects a valid non-owner', async () => {
    const { client } = authClient('42000000-0000-0000-0000-000000000002')

    await expect(
      requireOwner(request({ authorization: 'Bearer valid-token' }), {
        admin: client,
        ownerUserId: ownerId,
      }),
    ).rejects.toMatchObject({ status: 403, code: 'owner_required' })
  })

  it('returns the owner session without exposing auth internals', async () => {
    const { client, getUser } = authClient(ownerId)

    const session = await requireOwner(request({ authorization: 'Bearer valid-token' }), {
      admin: client,
      ownerUserId: ownerId,
    })

    expect(session).toEqual({ userId: ownerId, accessToken: 'valid-token' })
    expect(getUser).toHaveBeenCalledWith('valid-token')
  })
})

describe('server environment', () => {
  it('fails closed when any required setting is absent', () => {
    expect(() => readServerEnv({})).toThrowError(HttpError)
    expect(() => readServerEnv({})).toThrow(/server_configuration_error/)
  })

  it('accepts a complete server-only configuration', () => {
    expect(
      readServerEnv({
        SUPABASE_URL: 'https://project.supabase.co',
        SUPABASE_ANON_KEY: 'anon-test-value',
        SUPABASE_SERVICE_ROLE_KEY: 'service-role-test-value',
        COMMAND_CENTER_OWNER_USER_ID: ownerId,
        SESSION_CSRF_SECRET: 'a-secret-longer-than-thirty-two-characters',
      }),
    ).toMatchObject({ ownerUserId: ownerId })
  })
})

describe('requireCsrf', () => {
  it('requires matching owner-bound cookie and header tokens', () => {
    const token = 'signed-owner-token'
    const csrfRequest = request({
      cookie: `sq_csrf=${token}`,
      'x-csrf-token': token,
    })

    expect(() =>
      requireCsrf(csrfRequest, { userId: ownerId, accessToken: 'valid-token' }, {
        secret: 'a-secret-longer-than-thirty-two-characters',
        expectedToken: token,
      }),
    ).not.toThrow()
  })

  it('rejects a missing or mismatched token', () => {
    expect(() =>
      requireCsrf(request({ 'x-csrf-token': 'wrong' }), { userId: ownerId, accessToken: 'token' }, {
        secret: 'a-secret-longer-than-thirty-two-characters',
        expectedToken: 'expected',
      }),
    ).toThrow(/csrf_rejected/)
  })
})
