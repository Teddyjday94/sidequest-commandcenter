import { createClient } from '@supabase/supabase-js'

import { readServerEnv } from './env.js'

export function getAdminClient(source: Record<string, string | undefined> = process.env) {
  const env = readServerEnv(source)

  return createClient(env.supabaseUrl, env.serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
    db: { schema: 'ops' },
  })
}
