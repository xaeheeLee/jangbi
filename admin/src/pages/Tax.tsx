import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { formatDateTime, formatNumber } from '../lib/format'
import { downloadCsv } from '../lib/csv'
import { EmptyState, ErrorState, Loading } from '../components/States'
import { colors } from '../theme'

type TabKey = 'charges' | 'point_transactions' | 'withdrawals'

interface TabDef {
  key: TabKey
  label: string
  table: string
  columns: string
  headers: string[]
  // 한 row를 [표시셀...] 로. CSV/테이블 공용.
  map: (r: Record<string, unknown>) => (string | number | null)[]
  amountCols: number[] // tabular-num 정렬용 (우측정렬)
}

const TABS: TabDef[] = [
  {
    key: 'charges',
    label: '충전',
    table: 'charges',
    columns: 'created_at, user_id, point_amount, vat, pg_fee, total_deposit, status',
    headers: ['일시', '회원ID', '충전포인트', '부가세', 'PG수수료', '입금합계', '상태'],
    map: (r) => [
      formatDateTime(r.created_at as string),
      r.user_id as string,
      r.point_amount as number,
      r.vat as number,
      r.pg_fee as number,
      r.total_deposit as number,
      r.status as string,
    ],
    amountCols: [2, 3, 4, 5],
  },
  {
    key: 'point_transactions',
    label: '포인트 원장',
    table: 'point_transactions',
    columns: 'created_at, user_id, type, amount, balance_after, memo',
    headers: ['일시', '회원ID', '유형', '금액', '잔액(후)', '메모'],
    map: (r) => [
      formatDateTime(r.created_at as string),
      r.user_id as string,
      r.type as string,
      r.amount as number,
      r.balance_after as number,
      (r.memo as string) ?? '',
    ],
    amountCols: [3, 4],
  },
  {
    key: 'withdrawals',
    label: '인출',
    table: 'withdrawals',
    columns: 'created_at, processed_at, user_id, amount, bank_account, status',
    headers: ['신청일시', '처리일시', '회원ID', '금액', '지급계좌', '상태'],
    map: (r) => [
      formatDateTime(r.created_at as string),
      formatDateTime(r.processed_at as string),
      r.user_id as string,
      r.amount as number,
      (r.bank_account as string) ?? '',
      r.status as string,
    ],
    amountCols: [3],
  },
]

function todayStr(): string {
  return new Date().toISOString().slice(0, 10)
}
function monthAgoStr(): string {
  const d = new Date()
  d.setMonth(d.getMonth() - 1)
  return d.toISOString().slice(0, 10)
}

export default function Tax() {
  const [tab, setTab] = useState<TabKey>('charges')
  const [from, setFrom] = useState(monthAgoStr())
  const [to, setTo] = useState(todayStr())
  const [rows, setRows] = useState<Record<string, unknown>[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const def = TABS.find((t) => t.key === tab)!

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const fromTs = `${from}T00:00:00`
      const toTs = `${to}T23:59:59`
      const { data, error: e } = await supabase
        .from(def.table)
        .select(def.columns)
        .gte('created_at', fromTs)
        .lte('created_at', toTs)
        .order('created_at', { ascending: false })
        .limit(2000)
      if (e) throw e
      setRows((data ?? []) as unknown as Record<string, unknown>[])
    } catch (e) {
      setError(e instanceof Error ? e.message : '데이터를 불러오지 못했습니다.')
      setRows([])
    } finally {
      setLoading(false)
    }
  }, [def, from, to])

  useEffect(() => {
    void load()
  }, [load])

  function exportCsv() {
    const dataRows = rows.map((r) => def.map(r))
    downloadCsv(`${def.key}_${from}_${to}.csv`, def.headers, dataRows)
  }

  const inputStyle: React.CSSProperties = {
    height: 38,
    border: `1px solid ${colors.line}`,
    borderRadius: 10,
    padding: '0 12px',
    fontSize: 13,
    fontWeight: 700,
    color: colors.ink,
    background: '#fff',
  }

  return (
    <>
      {/* 필터바 */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 16, flexWrap: 'wrap' }}>
        <div
          style={{
            display: 'inline-flex',
            background: '#EEF1F5',
            borderRadius: 10,
            padding: 3,
            gap: 3,
          }}
        >
          {TABS.map((t) => (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              style={{
                height: 30,
                borderRadius: 8,
                fontSize: 12.5,
                fontWeight: 800,
                padding: '0 14px',
                color: tab === t.key ? colors.navy : colors.ink2,
                background: tab === t.key ? '#fff' : 'transparent',
                boxShadow: tab === t.key ? '0 1px 2px rgba(16,24,40,.08)' : 'none',
              }}
            >
              {t.label}
            </button>
          ))}
        </div>

        <input type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} style={inputStyle} />
        <span style={{ color: colors.ink3, fontWeight: 700 }}>~</span>
        <input type="date" value={to} min={from} max={todayStr()} onChange={(e) => setTo(e.target.value)} style={inputStyle} />
        <button className="btn2 gh" onClick={() => void load()}>
          조회
        </button>

        <button className="btn2 navy" style={{ marginLeft: 'auto' }} onClick={exportCsv} disabled={rows.length === 0}>
          CSV 다운로드
        </button>
      </div>

      {error && <ErrorState message={error} />}

      <div className="card">
        <div className="ch">
          <h3>{def.label} · {formatNumber(rows.length)}건</h3>
        </div>
        {loading ? (
          <Loading />
        ) : rows.length === 0 ? (
          <EmptyState label="조회 결과가 없습니다." />
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table className="tbl">
              <thead>
                <tr>
                  {def.headers.map((h, i) => (
                    <th key={h} style={def.amountCols.includes(i) ? { textAlign: 'right' } : undefined}>
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((r, ri) => {
                  const cells = def.map(r)
                  return (
                    <tr key={ri}>
                      {cells.map((c, ci) => {
                        const isAmount = def.amountCols.includes(ci)
                        return (
                          <td
                            key={ci}
                            className={isAmount ? 'num' : undefined}
                            style={isAmount ? { textAlign: 'right' } : undefined}
                          >
                            {isAmount && typeof c === 'number' ? formatNumber(c) : c}
                          </td>
                        )
                      })}
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  )
}
