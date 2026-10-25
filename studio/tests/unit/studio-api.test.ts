import { describe, expect, it, vi } from 'vitest'

import { createStudioApi } from '../../src/lib/api.js'

describe('Studio API owner session', () => {
  it('bootstraps the CSRF cookie with the current Supabase access token', async () => {
    const fetcher = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ connected: true }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      }),
    )
    const api = createStudioApi(async () => 'fresh-access-token', fetcher)

    await expect(api.connectSession()).resolves.toEqual({ connected: true })

    expect(fetcher).toHaveBeenCalledOnce()
    const [path, init] = fetcher.mock.calls[0] as [string, RequestInit]
    expect(path).toBe('/api/session')
    expect(init.method).toBe('POST')
    expect(new Headers(init.headers).get('authorization')).toBe('Bearer fresh-access-token')
  })
})
