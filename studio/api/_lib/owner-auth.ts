import { readServerEnv } from './env.js'
import { HttpError } from './http.js'
import { getAdminClient } from './supabase.js'

export interface OwnerSession {
  userId: string
  accessToken: string
}

export interface OwnerAuthClient {
  auth: {
    getUser(accessToken: string): Promise<{
      data: { user: { id: string } | null }
      error: { message: string } | null
    }>
  }
}

export interface OwnerAuthDependencies {
  admin?: OwnerAuthClient
  ownerUserId?: string
}

function bearerToken(request: Request): string {
  const authorization = request.headers.get('authorization')
  const match = authorization?.match(/^Bearer\s+(\S+)$/i)
  const token = match?.[1]

  if (!token || token.length > 8192) {
    throw new HttpError(401, 'missing_session')
  }

  return token
}

export async function requireOwner(
  request: Request,
  dependencies: OwnerAuthDependencies = {},
): Promise<OwnerSession> {
  const accessToken = bearerToken(request)
  const admin = dependencies.admin ?? getAdminClient()
  const ownerUserId = dependencies.ownerUserId ?? readServerEnv().ownerUserId
  const { data, error } = await admin.auth.getUser(accessToken)

  if (error || !data.user) {
    throw new HttpError(401, 'invalid_session')
  }
  if (data.user.id !== ownerUserId) {
    throw new HttpError(403, 'owner_required')
  }

  return { userId: data.user.id, accessToken }
}
