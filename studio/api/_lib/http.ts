export class HttpError extends Error {
  readonly status: number
  readonly code: string

  constructor(status: number, code: string) {
    super(code)
    this.name = 'HttpError'
    this.status = status
    this.code = code
  }
}

export function jsonResponse(body: unknown, status = 200, headers: HeadersInit = {}): Response {
  const responseHeaders = new Headers(headers)
  responseHeaders.set('content-type', 'application/json; charset=utf-8')
  responseHeaders.set('x-content-type-options', 'nosniff')

  return new Response(JSON.stringify(body), { status, headers: responseHeaders })
}

export function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    return jsonResponse({ error: error.code }, error.status, { 'cache-control': 'private, no-store' })
  }

  return jsonResponse({ error: 'internal_error' }, 500, { 'cache-control': 'private, no-store' })
}
