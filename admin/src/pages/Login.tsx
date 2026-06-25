import { useState, type FormEvent } from 'react'
import { useAuth } from '../lib/auth'
import { colors, shadow } from '../theme'

export default function Login() {
  const { signIn } = useAuth()
  const [phone, setPhone] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setBusy(true)
    try {
      await signIn(phone, password)
    } catch (err) {
      setError(err instanceof Error ? err.message : '로그인에 실패했습니다.')
    } finally {
      setBusy(false)
    }
  }

  const inputStyle: React.CSSProperties = {
    width: '100%',
    height: 46,
    border: `1.5px solid ${colors.line}`,
    borderRadius: 11,
    padding: '0 14px',
    fontSize: 14,
    fontWeight: 600,
    color: colors.ink,
    outline: 'none',
    background: '#fff',
  }

  return (
    <div
      style={{
        minHeight: '100vh',
        display: 'grid',
        placeItems: 'center',
        background: 'radial-gradient(1200px 600px at 50% -200px,#f3f5f9 0%,#E9ECF2 60%)',
        padding: 24,
      }}
    >
      <div
        style={{
          width: 380,
          maxWidth: '100%',
          background: '#fff',
          border: `1px solid ${colors.line}`,
          borderRadius: 18,
          boxShadow: shadow,
          padding: 32,
        }}
      >
        <div style={{ textAlign: 'center', marginBottom: 24 }}>
          <div
            style={{
              width: 48, height: 48, borderRadius: 13, background: colors.navy,
              display: 'grid', placeItems: 'center', margin: '0 auto 14px',
              color: '#fff', fontWeight: 800, fontSize: 15, letterSpacing: '-.04em',
            }}
          >
            전중
          </div>
          <h1 style={{ fontSize: 20, fontWeight: 800, color: colors.ink }}>전중배 관리자</h1>
          <p style={{ marginTop: 6, fontSize: 13, color: colors.ink2, fontWeight: 600 }}>운영 콘솔 로그인</p>
        </div>

        <form onSubmit={onSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 11 }}>
          <input
            type="tel"
            placeholder="휴대폰 번호"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            autoComplete="username"
            style={inputStyle}
            required
          />
          <input
            type="password"
            placeholder="비밀번호"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="current-password"
            style={inputStyle}
            required
          />

          {error && (
            <div
              style={{
                fontSize: 12.5, fontWeight: 700, color: colors.red,
                background: '#FEECEC', borderRadius: 9, padding: '10px 12px',
              }}
            >
              {error}
            </div>
          )}

          <button
            type="submit"
            disabled={busy}
            className="btn2 navy"
            style={{ height: 46, marginTop: 4, fontSize: 14 }}
          >
            {busy ? '로그인 중…' : '로그인'}
          </button>
        </form>
      </div>
    </div>
  )
}
