import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { formatDate, formatWon } from '../lib/format'
import { EmptyState, ErrorState, Loading } from '../components/States'
import { colors } from '../theme'

interface JobRow {
  id: string
  job_no: string | null
  region_name: string | null
  amount: number | null
  status: string | null
  work_date: string | null
  poster_id: string
  matched_worker_id: string | null
  poster: { name: string | null; member_no: string | null } | null
}

interface MismatchApp {
  job_id: string
  applicant_id: string
  status: string | null
}

const STATUS_FILTERS: { key: string; label: string; values: string[] }[] = [
  { key: 'all', label: '전체', values: [] },
  { key: 'active', label: '진행중', values: ['open', 'priority_window', 'designated_window'] },
  { key: 'matched', label: '매칭완료', values: ['matched'] },
  { key: 'completed', label: '완료', values: ['completed'] },
  { key: 'closed', label: '취소/만료', values: ['cancelled_by_poster', 'cancelled_by_worker', 'expired'] },
]

const STATUS_LABELS: Record<string, { label: string; cls: string }> = {
  open: { label: '모집중', cls: 'blue' },
  priority_window: { label: '우선배차', cls: 'prio' },
  designated_window: { label: '지정배차', cls: 'prio' },
  matched: { label: '매칭완료', cls: 'ok' },
  completed: { label: '완료', cls: 'ok' },
  cancelled_by_poster: { label: '발주취소', cls: 'no' },
  cancelled_by_worker: { label: '기사취소', cls: 'no' },
  expired: { label: '만료', cls: 'no' },
}

const LIMIT = 100

export default function Jobs() {
  const [rows, setRows] = useState<JobRow[]>([])
  const [mismatches, setMismatches] = useState<MismatchApp[]>([])
  const [filter, setFilter] = useState('all')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const sel = supabase
        .from('jobs')
        .select(
          'id, job_no, region_name, amount, status, work_date, poster_id, matched_worker_id, poster:profiles!jobs_poster_id_fkey(name, member_no)'
        )
        .order('work_date', { ascending: false })
        .limit(LIMIT)
      const flt = STATUS_FILTERS.find((f) => f.key === filter)
      const query = flt && flt.values.length > 0 ? sel.in('status', flt.values) : sel
      const { data, error: e } = await query
      if (e) throw e
      const list = (data ?? []) as unknown as JobRow[]
      setRows(list)

      if (list.length > 0) {
        const jobIds = list.map((j) => j.id)
        const { data: apps } = await supabase
          .from('job_applications')
          .select('job_id, applicant_id, status')
          .in('job_id', jobIds)
          .eq('equipment_mismatch', true)
        setMismatches((apps ?? []) as MismatchApp[])
      } else {
        setMismatches([])
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : '일감 목록을 불러오지 못했습니다.')
    } finally {
      setLoading(false)
    }
  }, [filter])

  useEffect(() => {
    void load()
  }, [load])

  const mismatchByJob = mismatches.reduce<Record<string, number>>((acc, m) => {
    acc[m.job_id] = (acc[m.job_id] ?? 0) + 1
    return acc
  }, {})

  return (
    <>
      <div
        style={{
          display: 'inline-flex',
          background: '#EEF1F5',
          borderRadius: 10,
          padding: 3,
          gap: 3,
          marginBottom: 16,
        }}
      >
        {STATUS_FILTERS.map((f) => (
          <button
            key={f.key}
            onClick={() => setFilter(f.key)}
            style={{
              height: 30,
              borderRadius: 8,
              fontSize: 12.5,
              fontWeight: 800,
              padding: '0 14px',
              color: filter === f.key ? colors.navy : colors.ink2,
              background: filter === f.key ? '#fff' : 'transparent',
              boxShadow: filter === f.key ? '0 1px 2px rgba(16,24,40,.08)' : 'none',
            }}
          >
            {f.label}
          </button>
        ))}
      </div>

      {error && <ErrorState message={error} />}

      {mismatches.length > 0 && (
        <div
          style={{
            display: 'flex',
            gap: 9,
            background: '#FEECEC',
            border: '1px solid #F6C9C9',
            borderRadius: 12,
            padding: '11px 14px',
            fontSize: 12.5,
            fontWeight: 700,
            color: colors.red,
            marginBottom: 14,
          }}
        >
          장비 불일치 지원이 포함된 일감 {Object.keys(mismatchByJob).length}건 — 아래 표에서 강조 표시됩니다.
        </div>
      )}

      <div className="card">
        <div className="ch">
          <h3>최근 일감 · {rows.length}건 {rows.length === LIMIT ? `(최대 ${LIMIT})` : ''}</h3>
        </div>
        {loading ? (
          <Loading />
        ) : rows.length === 0 ? (
          <EmptyState label="일감이 없습니다." />
        ) : (
          <table className="tbl">
            <thead>
              <tr>
                <th>일감번호</th>
                <th>지역</th>
                <th style={{ textAlign: 'right' }}>금액</th>
                <th>상태</th>
                <th>발주자</th>
                <th>작업일</th>
                <th>비고</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((j) => {
                const st = STATUS_LABELS[j.status ?? ''] ?? { label: j.status ?? '-', cls: 'no' }
                const mm = mismatchByJob[j.id]
                return (
                  <tr key={j.id} style={mm ? { background: '#FEF6F6' } : undefined}>
                    <td className="num n" style={{ fontWeight: 800 }}>{j.job_no ?? '-'}</td>
                    <td>{j.region_name ?? '-'}</td>
                    <td className="num" style={{ textAlign: 'right' }}>{formatWon(j.amount)}</td>
                    <td><span className={`bdg ${st.cls}`}>{st.label}</span></td>
                    <td className="nm">
                      {j.poster?.name ?? '-'}
                      {j.poster?.member_no ? (
                        <span style={{ color: colors.ink3, fontWeight: 600 }}> · {j.poster.member_no}</span>
                      ) : null}
                    </td>
                    <td className="num">{formatDate(j.work_date)}</td>
                    <td>
                      {mm ? <span className="bdg prio">장비 불일치 {mm}</span> : <span style={{ color: colors.ink3 }}>-</span>}
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
