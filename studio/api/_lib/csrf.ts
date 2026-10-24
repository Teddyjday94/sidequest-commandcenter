import { createHmac, timingSafeEqual } from 'node:crypto'

import { readServerEnv } from './env.js'
import { HttpError } from './http.js'
import type { OwnerSession } from './owner-auth.js'

interface CsrfDependencies {
  secret?: string
  expectedToken?: string
}

function secureEqual(left: string, right: string): boolean {
  const leftBuffer = Buffer.from(left)
  const rightBuffer = Buffer.from(right)
  return leftBuffer.length === rightBuffer.length && timingSafeEqual(leftBuffer, rightBuffer)
}

function cookieValue(request: Request, name: string): string | null {
  const cookie = request.headers.get('cookie')
  if (!cookie) return null

  for (const part of cookie.split(';')) {
    const separator = part.indexOf('=')
    if (separator < 0 || part.slice(0, separator).trim() !== name) continue
    try {
      return decodeURIComponent(part.slice(separator + 1).trim())
    } catch {
      return null
    }
  }
  return null
}

export function createCsrfToken(session: OwnerSession, secret = readServerEnv().csrfSecret): string {
  return createHmac('sha256', secret).update(`sidequest-owner:v1:${session.userId}`).digest('base64url')
}

export function requireCsrf(
  request: Request,
  session: OwnerSession,
  dependencies: CsrfDependencies = {},
): void {
  const headerToken = request.headers.get('x-csrf-token')
  const cookieToken = cookieValue(request, 'sq_csrf')
  const expectedToken =
    dependencies.expectedToken ?? createCsrfToken(session, dependencies.secret ?? readServerEnv().csrfSecret)

  if (
    !headerToken ||
    !cookieToken ||
    !secureEqual(headerToken, cookieToken) ||
    !secureEqual(headerToken, expectedToken)
  ) {
    throw new HttpError(403, 'csrf_rejected')
  }
}
