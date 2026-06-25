import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase, phoneToEmail } from './supabase'

interface AdminProfile {
  id: string
  name: string | null
  is_admin: boolean
}

interface AuthState {
  session: Session | null
  profile: AdminProfile | null
  loading: boolean
  signIn: (phone: string, password: string) => Promise<void>
  signOut: () => Promise<void>
}

const AuthContext = createContext<AuthState | undefined>(undefined)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [profile, setProfile] = useState<AdminProfile | null>(null)
  const [loading, setLoading] = useState(true)

  async function loadProfile(userId: string): Promise<AdminProfile | null> {
    const { data, error } = await supabase
      .from('profiles')
      .select('id, name, is_admin')
      .eq('id', userId)
      .single()
    if (error || !data) return null
    return data as AdminProfile
  }

  useEffect(() => {
    let active = true

    supabase.auth.getSession().then(async ({ data }) => {
      if (!active) return
      const s = data.session
      setSession(s)
      if (s) {
        const p = await loadProfile(s.user.id)
        if (active) setProfile(p)
      }
      if (active) setLoading(false)
    })

    const { data: sub } = supabase.auth.onAuthStateChange(async (_e, s) => {
      setSession(s)
      if (s) {
        const p = await loadProfile(s.user.id)
        setProfile(p)
      } else {
        setProfile(null)
      }
    })

    return () => {
      active = false
      sub.subscription.unsubscribe()
    }
  }, [])

  async function signIn(phone: string, password: string) {
    const email = phoneToEmail(phone)
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    })
    if (error) {
      throw new Error('휴대폰 번호 또는 비밀번호가 올바르지 않습니다.')
    }
    const p = await loadProfile(data.user.id)
    if (!p?.is_admin) {
      await supabase.auth.signOut()
      setSession(null)
      setProfile(null)
      throw new Error('관리자 권한이 없습니다.')
    }
    setProfile(p)
  }

  async function signOut() {
    await supabase.auth.signOut()
    setSession(null)
    setProfile(null)
  }

  return (
    <AuthContext.Provider value={{ session, profile, loading, signIn, signOut }}>
      {children}
    </AuthContext.Provider>
  )
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAuth(): AuthState {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used within AuthProvider')
  return ctx
}
