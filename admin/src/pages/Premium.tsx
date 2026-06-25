import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { formatPhone } from '../lib/format'
import { EmptyState, ErrorState, Loading } from '../components/States'
import { colors } from '../theme'

interface MemberRow {
  id: string
  name: string | null
  member_no: string | null
  phone: string | null
  is_premium: boolean | null
}

export default function Premium() {
  const [rows, setRows] = useState<MemberRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busyId, setBusyId] = useState<string | null>(null)
  const [onlyPremium, setOnlyPremium] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const { data, error: e } = await supabase
        .from('profiles')
        .select('id, name, member_no, phone, is_premium')
        .order('is_premium', { ascending: false })
        .order('created_at', { ascending: true })
      if (e) throw e
      setRows((data ?? []) as MemberRow[])
    } catch (e) {
      setError(e instanceof Error ? e.message : '회원 목록을 불러오지 못했습니다.')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  async function toggle(m: MemberRow) {
    const next = !m.is_premium
    setBusyId(m.id)
    setError(null)
    try {
      const { error: e } = await supabase.rpc('set_premium', { p_user_id: m.id, p_on: next })
      if (e) throw e
      setRows((prev) => prev.map((r) => (r.id === m.id ? { ...r, is_premium: next } : r)))
    } catch (e) {
      setError(e instanceof Error ? e.message : '변경에 실패했습니다.')
    } finally {
      setBusyId(null)
    }
  }

  if (loading) return <Loading />

  const visible = onlyPremium ? rows.filter((r) => r.is_premium) : rows
  const premiumCount = rows.filter((r) => r.is_premium).length

  return (
    <>
      {error && <ErrorState message={error} />}
      <div className="card">
        <div className="ch">
          <h3>
            프리미엄 회원 <span className="n">{premiumCount}</span>명{' '}
            <span style={{ color: colors.ink3, fontWeight: 600, fontSize: 12.5 }}>/ 전체 {rows.length}명</span>
          </h3>
          <button
            className={onlyPremium ? 'btn2 navy sm' : 'btn2 gh sm'}
            style={{ marginLeft: 'auto' }}
            onClick={() => setOnlyPremium((v) => !v)}
          >
            {onlyPremium ? '전체 보기' : '프리미엄만'}
          </button>
        </div>
        {visible.length === 0 ? (
          <EmptyState label="해당하는 회원이 없습니다." />
        ) : (
          <table className="tbl">
            <thead>
              <tr>
                <th>이름</th>
                <th>회원번호</th>
                <th>연락처</th>
                <th>상태</th>
                <th style={{ textAlign: 'right' }}>프리미엄</th>
              </tr>
            </thead>
            <tbody>
              {visible.map((m) => (
                <tr key={m.id}>
                  <td className="nm">{m.name ?? '-'}</td>
                  <td className="num n">{m.member_no ?? '-'}</td>
                  <td className="num">{formatPhone(m.phone)}</td>
                  <td>
                    {m.is_premium ? (
                      <span className="bdg ok">프리미엄</span>
                    ) : (
                      <span className="bdg no">일반</span>
                    )}
                  </td>
                  <td style={{ textAlign: 'right' }}>
                    <button
                      className={m.is_premium ? 'btn2 gh sm' : 'btn2 navy sm'}
                      style={m.is_premium ? { color: colors.red } : undefined}
                      disabled={busyId === m.id}
                      onClick={() => void toggle(m)}
                    >
                      {busyId === m.id ? '처리 중…' : m.is_premium ? '해제' : '지정'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </>
  )
}
