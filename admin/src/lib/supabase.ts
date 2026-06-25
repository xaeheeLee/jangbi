import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

if (!url || !key) {
  throw new Error('Supabase 환경변수(VITE_SUPABASE_URL / VITE_SUPABASE_PUBLISHABLE_KEY)가 없습니다.')
}

export const supabase = createClient(url, key, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
})

// 휴대폰 번호 → 로그인용 이메일 (앱과 동일 규칙)
export function phoneToEmail(phone: string): string {
  const digits = phone.replace(/\D/g, '')
  return `${digits}@phone.jeonjungbae.app`
}
