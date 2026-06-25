import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { formatDateTime, formatPoint } from '../lib/format'
import { EmptyState, ErrorState, Loading } from '../components/States'

interface WithdrawalRow {
  id: string
  amount: number
  bank_account: string | null
  status: string
  created_at: string | null
  user_id: string
  profiles: { name: string | null; member_no: string | null } | null
}

export default function Withdrawals() {
  const [rows, setRows] = useState<WithdrawalRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busyId, setBusyId] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const { data, error: e } = await supabase
        .from('withdrawals')
        .select('id, amount, bank_account, status, created_at, user_id, profiles(name, member_no)')
        .eq('status', 'requested')
        .order('created_at', { ascending: true })
      if (e) throw e
      setRows((data ?? []) as unknown as WithdrawalRow[])
    } catch (e) {
      setError(e instanceof Error ? e.message : '인출 목록을 불러오지 못했습니다.')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  async function approve(id: string) {
    setBusyId(id)
    setError(null)
    try {
      const { error: e } = await supabase.rpc('approve_withdraw', { p_withdrawal_id: id })
      if (e) throw e
      setRows((prev) => prev.filter((r) => r.id !== id))
    } catch (e) {
      setError(e instanceof Error ? e.message : '승인에 실패했습니다.')
    } finally {
      setBusyId(null)
    }
  }

  async function reject(id: string) {
    const reason = window.prompt('거절 사유를 입력하세요.')
    if (reason == null) return
    setBusyId(id)
    setError(null)
    try {
      const { error: e } = await supabase.rpc('reject_withdraw', {
        p_withdrawal_id: id,
        p_reason: reason,
      })
      if (e) throw e
      setRows((prev) => prev.filter((r) => r.id !== id))
    } catch (e) {
      setError(e instanceof Error ? e.message : '거절에 실패했습니다.')
    } finally {
      setBusyId(null)
    }
  }

  if (loading) return <Loading />

  return (
    <>
      {error && <ErrorState message={error} />}
      <div className="card">
        <div className="ch">
          <h3>인출 대기 {rows.length}건</h3>
        </div>
        {rows.length === 0 ? (
          <EmptyState label="대기 중인 인출 신청이 없습니다." />
        ) : (
          <table className="tbl">
            <thead>
              <tr>
                <th>신청자</th>
                <th>회원번호</th>
                <th style={{ textAlign: 'right' }}>금액</th>
                <th>지급 계좌</th>
                <th>신청일</th>
                <th style={{ textAlign: 'right' }}>처리</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <td className="nm">{r.profiles?.name ?? '-'}</td>
                  <td className="num n">{r.profiles?.member_no ?? '-'}</td>
                  <td className="num r" style={{ textAlign: 'right', fontWeight: 700 }}>
                    {formatPoint(r.amount)}
                  </td>
                  <td className="num">{r.bank_account ?? '-'}</td>
                  <td className="num">{formatDateTime(r.created_at)}</td>
                  <td style={{ textAlign: 'right' }}>
                    <div style={{ display: 'inline-flex', gap: 8 }}>
                      <button
                        className="btn2 gh sm"
                        style={{ color: 'var(--red)' }}
                        disabled={busyId === r.id}
                        onClick={() => void reject(r.id)}
                      >
                        거절
                      </button>
                      <button
                        className="btn2 green sm"
                        disabled={busyId === r.id}
                        onClick={() => void approve(r.id)}
                      >
                        {busyId === r.id ? '처리 중…' : '승인'}
                      </button>
                    </div>
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
