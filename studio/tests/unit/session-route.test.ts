import { describe, expect, it, vi } from 'vitest'

import { createSessionHandler } from '../../api/session.js'

const ownerId = '41000000-0000-0000-0000-000000000001'
const csrfSecret = 'a-secret-longer-than-thirty-two-characters'

function request(token = 'valid-token') {
  return new Request('https://studio.example.test/api/session', {
    method: 'POST',
    headers: { authorization: `Bearer ${token}` },
  })
}

function authClient(email: string) {
  const getUser = vi.fn().mockResolvedValue({
    data: { user: { id: ownerId, email } },
    error: null,
  })
  return { client: { auth: { getUser } }, getUser }
}

describe('owner session bootstrap', () => {
  it('sets a secure owner-bound CSRF session cookie after authentication', async () => {
    const { client, getUser } = authClient('ThomasDBiz26@gmail.com')
    const handler = createSessionHandler({
      admin: client,
      ownerEmail: 'thomasdbiz26@gmail.com',
      csrfSecret,
    })

    const response = await handler(request())

    expect(response.status).toBe(200)
    await expect(response.json()).resolves.toEqual({ connected: true })
    expect(response.headers.get('set-cookie')).toMatch(
      /^sq_csrf=[A-Za-z0-9_-]+; Path=\/; Secure; SameSite=Strict$/,
    )
    expect(getUser).toHaveBeenCalledWith('valid-token')
  })

  it('does not set a cookie for a different authenticated user', async () => {
    const { client } = authClient('someone-else@example.test')
    const handler = createSessionHandler({
      admin: client,
      ownerEmail: 'thomasdbiz26@gmail.com',
      csrfSecret,
    })

    const response = await handler(request())

    expect(response.status).toBe(403)
    await expect(response.json()).resolves.toEqual({ error: 'owner_required' })
    expect(response.headers.get('set-cookie')).toBeNull()
  })
})
