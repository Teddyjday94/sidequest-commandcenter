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
      data: { user: { id: string; email?: string | null } | null }
      error: { message: string } | null
    }>
  }
}

export interface OwnerAuthDependencies {
  admin?: OwnerAuthClient
  ownerUserId?: string | undefined
  ownerEmail?: string | undefined
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
  const environment = dependencies.ownerUserId || dependencies.ownerEmail ? null : readServerEnv()
  const ownerUserId = dependencies.ownerUserId ?? environment?.ownerUserId
  const ownerEmail = (dependencies.ownerEmail ?? environment?.ownerEmail)?.toLowerCase()
  const { data, error } = await admin.auth.getUser(accessToken)

  if (error || !data.user) {
    throw new HttpError(401, 'invalid_session')
  }
  const matchesId = ownerUserId !== undefined && data.user.id === ownerUserId
  const matchesEmail = ownerEmail !== undefined && data.user.email?.toLowerCase() === ownerEmail
  if (!matchesId && !matchesEmail) {
    throw new HttpError(403, 'owner_required')
  }

  return { userId: data.user.id, accessToken }
}
