import { createCsrfToken } from './_lib/csrf.js'
import { readServerEnv } from './_lib/env.js'
import { errorResponse, HttpError, jsonResponse } from './_lib/http.js'
import { requireOwner, type OwnerAuthClient } from './_lib/owner-auth.js'
import { getAdminClient } from './_lib/supabase.js'

interface SessionDependencies {
  admin?: OwnerAuthClient
  ownerUserId?: string
  ownerEmail?: string
  csrfSecret?: string
}

export function createSessionHandler(dependencies: SessionDependencies = {}) {
  return async function POST(request: Request): Promise<Response> {
    try {
      const needsEnvironment =
        (!dependencies.ownerUserId && !dependencies.ownerEmail) || !dependencies.csrfSecret
      const environment = needsEnvironment ? readServerEnv() : null
      const admin = dependencies.admin ?? getAdminClient()
      const session = await requireOwner(request, {
        admin,
        ownerUserId: dependencies.ownerUserId ?? environment?.ownerUserId,
        ownerEmail: dependencies.ownerEmail ?? environment?.ownerEmail,
      })
      const csrfToken = createCsrfToken(session, dependencies.csrfSecret ?? environment?.csrfSecret)

      return jsonResponse({ connected: true }, 200, {
        'cache-control': 'private, no-store',
        'set-cookie': `sq_csrf=${encodeURIComponent(csrfToken)}; Path=/; Secure; SameSite=Strict`,
      })
    } catch (error) {
      if (!(error instanceof HttpError)) console.error('session_bootstrap_failed')
      return errorResponse(error)
    }
  }
}

export const POST = createSessionHandler()
