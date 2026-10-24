import { HttpError } from './http.js'

export interface ServerEnv {
  supabaseUrl: string
  anonKey: string
  serviceRoleKey: string
  ownerUserId: string
  csrfSecret: string
}

type EnvironmentSource = Record<string, string | undefined>

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function configurationError(): never {
  throw new HttpError(500, 'server_configuration_error')
}

function required(source: EnvironmentSource, key: string): string {
  const value = source[key]?.trim()
  return value ? value : configurationError()
}

export function readServerEnv(source: EnvironmentSource = process.env): ServerEnv {
  const supabaseUrl = required(source, 'SUPABASE_URL')
  const anonKey = required(source, 'SUPABASE_ANON_KEY')
  const serviceRoleKey = required(source, 'SUPABASE_SERVICE_ROLE_KEY')
  const ownerUserId = required(source, 'COMMAND_CENTER_OWNER_USER_ID')
  const csrfSecret = required(source, 'SESSION_CSRF_SECRET')

  let parsedUrl: URL
  try {
    parsedUrl = new URL(supabaseUrl)
  } catch {
    return configurationError()
  }

  const isLocalHttp =
    parsedUrl.protocol === 'http:' && (parsedUrl.hostname === '127.0.0.1' || parsedUrl.hostname === 'localhost')
  if (parsedUrl.protocol !== 'https:' && !isLocalHttp) {
    return configurationError()
  }
  if (!uuidPattern.test(ownerUserId) || csrfSecret.length < 32) {
    return configurationError()
  }

  return { supabaseUrl, anonKey, serviceRoleKey, ownerUserId, csrfSecret }
}
