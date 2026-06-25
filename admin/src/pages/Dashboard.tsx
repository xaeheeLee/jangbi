import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { colors, shadowSm } from '../theme'
import { formatNumber } from '../lib/format'
import { ErrorState, Loading } from '../components/States'

interface Stats {
  totalMembers: number
  pendingMembers: number
  pendingWithdrawals: number
  activeJobs: number
}

async function countAll(table: string): Promise<number> {
  const { count, error } = await supabase
    .from(table)
    .select('*', { count: 'exact', head: true })
  if (error) throw error
  return count ?? 0
}

export default function Dashboard() {
  const [stats, setStats] = useState<Stats | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let active = true
    ;(async () => {
      setLoading(true)
      setError(null)
      try {
        const [totalMembers, pendingMembers, pendingWithdrawals, activeJobs] = await Promise.all([
          countAll('profiles'),
          supabase
            .from('profiles')
            .select('*', { count: 'exact', head: true })
            .eq('membership_status', 'pending')
            .then(({ count, error: e }) => {
              if (e) throw e
              return count ?? 0
            }),
          supabase
            .from('withdrawals')
            .select('*', { count: 'exact', head: true })
            .eq('status', 'requested')
            .then(({ count, error: e }) => {
              if (e) throw e
              return count ?? 0
            }),
          supabase
            .from('jobs')
            .select('*', { count: 'exact', head: true })
            .in('status', ['open', 'priority_window'])
            .then(({ count, error: e }) => {
              if (e) throw e
              return count ?? 0
            }),
        ])
        if (active) setStats({ totalMembers, pendingMembers, pendingWithdrawals, activeJobs })
      } catch (e) {
        if (active) setError(e instanceof Error ? e.message : '통계를 불러오지 못했습니다.')
      } finally {
        if (active) setLoading(false)
      }
    })()
    return () => {
      active = false
    }
  }, [])

  if (loading) return <Loading />
  if (error) return <ErrorState message={error} />
  if (!stats) return null

  const cards = [
    { label: '전체 회원', value: stats.totalMembers, suffix: '명', warn: false },
    { label: '승인 대기', value: stats.pendingMembers, suffix: '명', warn: stats.pendingMembers > 0 },
    { label: '인출 대기', value: stats.pendingWithdrawals, suffix: '건', warn: stats.pendingWithdrawals > 0 },
    { label: '활성 일감', value: stats.activeJobs, suffix: '건', warn: false },
  ]

  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 14 }}>
      {cards.map((c) => (
        <div
          key={c.label}
          style={{
            background: '#fff',
            border: `1px solid ${colors.line}`,
            borderRadius: 14,
            boxShadow: shadowSm,
            padding: 18,
          }}
        >
          <div style={{ fontSize: 12.5, fontWeight: 700, color: colors.ink2 }}>{c.label}</div>
          <div
            className="num"
            style={{
              fontSize: 28,
              fontWeight: 800,
              color: colors.ink,
              marginTop: 12,
              letterSpacing: '-.02em',
            }}
          >
            {formatNumber(c.value)}
            <span style={{ fontSize: 15, marginLeft: 3 }}>{c.suffix}</span>
          </div>
          {c.warn && (
            <div style={{ fontSize: 11.5, fontWeight: 700, marginTop: 6, color: colors.red }}>
              처리 필요
            </div>
          )}
        </div>
      ))}
    </div>
  )
}
