import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { formatDateTime, formatPhone } from '../lib/format'
import { EmptyState, ErrorState, Loading } from '../components/States'
import { colors } from '../theme'

interface MemberRow {
  id: string
  name: string | null
  member_no: string | null
  phone: string | null
  admin_score: number | null
}

interface ScoreLog {
  user_id: string
  delta: number | null
  reason: string | null
  created_at: string | null
}

export default function Ratings() {
  const [rows, setRows] = useState<MemberRow[]>([])
  const [lastLog, setLastLog] = useState<Record<string, ScoreLog>>({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busyId, setBusyId] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const { data, error: e } = await supabase
        .from('profiles')
        .select('id, name, member_no, phone, admin_score')
        .order('created_at', { ascending: true })
      if (e) throw e
      const list = (data ?? []) as MemberRow[]
      setRows(list)

      // admin_score_log 최근 변경(테이블이 없으면 조용히 무시)
      try {
        const { data: logs } = await supabase
          .from('admin_score_log')
          .select('user_id, delta, reason, created_at')
          .order('created_at', { ascending: false })
          .limit(500)
        if (logs) {
          const map: Record<string, ScoreLog> = {}
          for (const l of logs as ScoreLog[]) {
            if (!map[l.user_id]) map[l.user_id] = l
          }
          setLastLog(map)
        }
      } catch {
        setLastLog({})
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : '회원 목록을 불러오지 못했습니다.')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  async function adjust(m: MemberRow, delta: number) {
    const reason = window.prompt(`${m.name ?? '회원'} 평점 ${delta > 0 ? '+1' : '-1'} 사유를 입력하세요.`)
    if (reason == null) return
    setBusyId(m.id)
    setError(null)
    try {
      const { error: e } = await supabase.rpc('admin_adjust_score', {
        p_user_id: m.id,
        p_delta: delta,
        p_reason: reason,
      })
      if (e) throw e
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : '평점 조정에 실패했습니다.')
      setBusyId(null)
    }
  }

  if (loading) return <Loading />

  return (
    <>
      {error && <ErrorState message={error} />}
      <div className="card">
        <div className="ch">
          <h3>평점 관리 · {rows.length}명</h3>
          <span style={{ marginLeft: 'auto', fontSize: 12, color: colors.ink3, fontWeight: 600 }}>
            기본 50 · ±1 조정(매칭 2순위·비공개)
          </span>
        </div>
        {rows.length === 0 ? (
          <EmptyState label="회원이 없습니다." />
        ) : (
          <table className="tbl">
            <thead>
              <tr>
                <th>이름</th>
                <th>회원번호</th>
                <th>연락처</th>
                <th style={{ textAlign: 'right' }}>평점</th>
                <th>최근 변경</th>
                <th style={{ textAlign: 'right' }}>조정</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((m) => {
                const log = lastLog[m.id]
                return (
                  <tr key={m.id}>
                    <td className="nm">{m.name ?? '-'}</td>
                    <td className="num n">{m.member_no ?? '-'}</td>
                    <td className="num">{formatPhone(m.phone)}</td>
                    <td className="num" style={{ textAlign: 'right', fontWeight: 800 }}>
                      {m.admin_score ?? 50}
                    </td>
                    <td style={{ color: colors.ink3, fontSize: 12 }}>
                      {log
                        ? `${(log.delta ?? 0) > 0 ? '+' : ''}${log.delta ?? 0} · ${formatDateTime(log.created_at)}${
                            log.reason ? ` · ${log.reason}` : ''
                          }`
                        : '-'}
                    </td>
                    <td style={{ textAlign: 'right' }}>
                      <div style={{ display: 'inline-flex', gap: 8 }}>
                        <button
                          className="btn2 gh sm"
                          disabled={busyId === m.id}
                          onClick={() => void adjust(m, -1)}
                        >
                          −1
                        </button>
                        <button
                          className="btn2 navy sm"
                          disabled={busyId === m.id}
                          onClick={() => void adjust(m, 1)}
                        >
                          +1
                        </button>
                      </div>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        )}
      </div>
    </>
  )
}
