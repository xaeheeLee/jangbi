import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { EmptyState, ErrorState, Loading } from '../components/States'
import { colors } from '../theme'

interface CronJob {
  jobname: string | null
  schedule: string | null
  active: boolean | null
}

interface AppSetting {
  key: string
  value: string | null
  description: string | null
}

// cron 표현식 → 한글 설명(간단 병기). 분 시 일 월 요일.
function describeCron(expr: string | null | undefined): string {
  if (!expr) return ''
  const parts = expr.trim().split(/\s+/)
  if (parts.length !== 5) return ''
  const [min, hour, dom, mon, dow] = parts

  // 매분
  if (min === '*' && hour === '*' && dom === '*' && mon === '*' && dow === '*') return '매분'
  // N분마다
  const everyMin = /^\*\/(\d+)$/.exec(min)
  if (everyMin && hour === '*' && dom === '*' && mon === '*' && dow === '*') {
    return `${everyMin[1]}분마다`
  }
  // 매시 정각/특정분
  if (hour === '*' && dom === '*' && mon === '*' && dow === '*' && /^\d+$/.test(min)) {
    return `매시 ${min}분`
  }
  // 매일 HH:MM
  if (/^\d+$/.test(min) && /^\d+$/.test(hour) && dom === '*' && mon === '*' && dow === '*') {
    const hh = hour.padStart(2, '0')
    const mm = min.padStart(2, '0')
    return `매일 ${hh}:${mm}`
  }
  return ''
}

export default function System() {
  const [crons, setCrons] = useState<CronJob[]>([])
  const [cronError, setCronError] = useState<string | null>(null)
  const [settings, setSettings] = useState<AppSetting[]>([])
  const [settingsError, setSettingsError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    setLoading(true)
    setCronError(null)
    setSettingsError(null)
    try {
      const [cronRes, settingRes] = await Promise.allSettled([
        supabase.rpc('list_cron_jobs'),
        supabase.from('app_settings').select('key, value, description').order('key', { ascending: true }),
      ])

      if (cronRes.status === 'fulfilled') {
        if (cronRes.value.error) {
          setCronError(cronRes.value.error.message)
        } else {
          setCrons((cronRes.value.data ?? []) as CronJob[])
        }
      } else {
        setCronError('자동화 현황을 불러오지 못했습니다.')
      }

      if (settingRes.status === 'fulfilled') {
        if (settingRes.value.error) {
          setSettingsError(settingRes.value.error.message)
        } else {
          setSettings((settingRes.value.data ?? []) as AppSetting[])
        }
      } else {
        setSettingsError('운영 정책을 불러오지 못했습니다.')
      }
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  if (loading) return <Loading />

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* 자동화(cron) 현황 */}
      <div className="card">
        <div className="ch">
          <h3>자동화 (cron) 현황</h3>
          <span style={{ marginLeft: 'auto', fontSize: 12, color: colors.ink3, fontWeight: 600 }}>
            pg_cron 등록 작업
          </span>
        </div>
        {cronError ? (
          <div style={{ padding: '16px 18px' }}>
            <ErrorState message={cronError} />
          </div>
        ) : crons.length === 0 ? (
          <EmptyState label="등록된 자동화 작업이 없습니다." />
        ) : (
          <table className="tbl">
            <thead>
              <tr>
                <th>작업명</th>
                <th>스케줄</th>
                <th>설명</th>
                <th style={{ textAlign: 'right' }}>활성</th>
              </tr>
            </thead>
            <tbody>
              {crons.map((c, i) => {
                const desc = describeCron(c.schedule)
                return (
                  <tr key={c.jobname ?? i}>
                    <td className="nm">{c.jobname ?? '-'}</td>
                    <td className="num" style={{ fontFamily: 'monospace', fontSize: 12.5 }}>
                      {c.schedule ?? '-'}
                    </td>
                    <td style={{ color: colors.ink2 }}>{desc || '-'}</td>
                    <td style={{ textAlign: 'right' }}>
                      {c.active ? (
                        <span className="bdg ok">활성</span>
                      ) : (
                        <span className="bdg no">중지</span>
                      )}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        )}
      </div>

      {/* 운영 정책(app_settings) */}
      <div className="card">
        <div className="ch">
          <h3>운영 정책 (app_settings)</h3>
          <span style={{ marginLeft: 'auto', fontSize: 12, color: colors.ink3, fontWeight: 600 }}>
            읽기 전용 · 수정은 추후
          </span>
        </div>
        {settingsError ? (
          <div style={{ padding: '16px 18px' }}>
            <ErrorState message={settingsError} />
          </div>
        ) : settings.length === 0 ? (
          <EmptyState label="등록된 설정이 없습니다." />
        ) : (
          <table className="tbl">
            <thead>
              <tr>
                <th>키</th>
                <th style={{ textAlign: 'right' }}>값</th>
                <th>설명</th>
              </tr>
            </thead>
            <tbody>
              {settings.map((s) => (
                <tr key={s.key}>
                  <td className="nm" style={{ fontFamily: 'monospace', fontSize: 12.5 }}>{s.key}</td>
                  <td className="num n" style={{ textAlign: 'right', fontWeight: 800 }}>{s.value ?? '-'}</td>
                  <td style={{ color: colors.ink2 }}>{s.description ?? '-'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
