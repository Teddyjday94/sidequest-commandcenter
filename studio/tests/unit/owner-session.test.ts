import { describe, expect, it, vi } from 'vitest'

import { createOwnerSessionManager } from '../../src/lib/owner-session.js'

function authClient(options: { token?: string; signInError?: Error } = {}) {
  const getSession = vi.fn().mockResolvedValue({
    data: { session: options.token ? { access_token: options.token } : null },
    error: null,
  })
  const signInWithPassword = vi.fn().mockResolvedValue({
    data: { session: options.token ? { access_token: options.token } : null },
    error: options.signInError ?? null,
  })
  const signOut = vi.fn().mockResolvedValue({ error: null })
  return { client: { auth: { getSession, signInWithPassword, signOut } }, getSession, signInWithPassword, signOut }
}

describe('owner session manager', () => {
  it('reads the current refreshed Supabase access token', async () => {
    const { client } = authClient({ token: 'fresh-token' })
    const manager = createOwnerSessionManager(client)

    await expect(manager.accessToken()).resolves.toBe('fresh-token')
  })

  it('signs in with the existing Sidequest email and password account', async () => {
    const { client, signInWithPassword } = authClient({ token: 'fresh-token' })
    const manager = createOwnerSessionManager(client)

    await manager.signIn('  ThomasDBiz26@gmail.com ', 'private-password')

    expect(signInWithPassword).toHaveBeenCalledWith({
      email: 'thomasdbiz26@gmail.com',
      password: 'private-password',
    })
  })

  it('surfaces authentication failures without storing a fake session', async () => {
    const failure = new Error('Invalid login credentials')
    const { client } = authClient({ signInError: failure })
    const manager = createOwnerSessionManager(client)

    await expect(manager.signIn('owner@example.test', 'wrong-password')).rejects.toBe(failure)
  })
})
