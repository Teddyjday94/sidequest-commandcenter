import { HttpError } from './http.js'
import { readJsonObject } from './validation.js'

type JsonRecord = Record<string, unknown>

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const errorCodePattern = /^[a-z][a-z0-9_]{0,99}$/

export async function readWorkerBody(request: Request, maximumBytes = 8192): Promise<JsonRecord> {
  return readJsonObject(request, maximumBytes)
}

export function workerJobId(body: JsonRecord): string {
  const value = typeof body.jobId === 'string' ? body.jobId : ''
  if (!uuidPattern.test(value)) throw new HttpError(400, 'invalid_job_id')
  return value.toLowerCase()
}

export function workerResult(body: JsonRecord): JsonRecord {
  const value = body.result
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new HttpError(400, 'invalid_result')
  }
  if (Buffer.byteLength(JSON.stringify(value), 'utf8') > 32_768) {
    throw new HttpError(413, 'result_too_large')
  }
  return value as JsonRecord
}

export function workerFailure(body: JsonRecord): {
  code: string
  summary: string
  retryable: boolean
} {
  const code = typeof body.code === 'string' ? body.code : ''
  const summary = typeof body.summary === 'string' ? body.summary.trim() : ''
  if (!errorCodePattern.test(code)) throw new HttpError(400, 'invalid_error_code')
  if (summary.length === 0 || summary.length > 1000) throw new HttpError(400, 'invalid_error_summary')
  if (typeof body.retryable !== 'boolean') throw new HttpError(400, 'invalid_retryable')
  return { code, summary, retryable: body.retryable }
}

export function boundedWorkerPayload(value: unknown): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new HttpError(502, 'worker_unavailable')
  }
  const source = value as JsonRecord
  const allowed = [
    'id',
    'workflow_id',
    'agent_id',
    'kind',
    'priority',
    'attempts',
    'max_attempts',
    'lease_expires_at',
    'status',
    'input',
  ]
  const result: JsonRecord = {}
  for (const key of allowed) {
    if (key in source) result[key] = source[key]
  }
  if (Buffer.byteLength(JSON.stringify(result), 'utf8') > 65_536) {
    throw new HttpError(502, 'worker_unavailable')
  }
  return result
}

