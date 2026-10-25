import { createClient } from '@supabase/supabase-js'

interface AuthError {
  message: string
}

interface OwnerAuthClient {
  auth: {
    getSession(): Promise<{
      data: { session: { access_token: string } | null }
      error: AuthError | null
    }>
    signInWithPassword(credentials: { email: string; password: string }): Promise<{
      data: { session: { access_token: string } | null }
      error: AuthError | null
    }>
    signOut(options?: { scope?: 'local' }): Promise<{ error: AuthError | null }>
  }
}

export interface OwnerSessionManager {
  accessToken(): Promise<string>
  signIn(email: string, password: string): Promise<void>
  signOut(): Promise<void>
}

function browserAuthClient(): OwnerAuthClient {
  const url = import.meta.env.VITE_SUPABASE_URL?.trim()
  const publishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim()
  if (!url || !publishableKey) throw new Error('owner_auth_config_missing')

  return createClient(url, publishableKey, {
    auth: {
      autoRefreshToken: true,
      detectSessionInUrl: false,
      persistSession: true,
      storage: sessionStorage,
    },
  })
}

export function createOwnerSessionManager(
  client: OwnerAuthClient = browserAuthClient(),
): OwnerSessionManager {
  return {
    async accessToken() {
      const { data, error } = await client.auth.getSession()
      if (error) throw error
      return data.session?.access_token ?? ''
    },
    async signIn(email, password) {
      const { error } = await client.auth.signInWithPassword({
        email: email.trim().toLowerCase(),
        password,
      })
      if (error) throw error
    },
    async signOut() {
      const { error } = await client.auth.signOut({ scope: 'local' })
      if (error) throw error
    },
  }
}
