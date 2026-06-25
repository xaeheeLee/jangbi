import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { formatDateTime } from '../lib/format'
import { EmptyState, ErrorState, Loading } from '../components/States'
import { colors } from '../theme'

const BUCKET = 'job-photos'

const PHASE_LABELS: Record<string, string> = {
  arrival: '현장 도착',
  work: '작업 중',
  done: '작업 종료',
}
const PHASE_ORDER = ['arrival', 'work', 'done']
const POINT_PER_PHASE = 1

interface PhotoRow {
  id: string
  job_id: string
  phase: string
  storage_path: string
  taken_at: string | null
  jobs: { job_no: string | null; region_name: string | null } | null
}

interface JobGroup {
  job_id: string
  job_no: string | null
  region_name: string | null
  photos: PhotoRow[]
}

export default function Photos() {
  const [groups, setGroups] = useState<JobGroup[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const { data, error: e } = await supabase
        .from('job_photos')
        .select('id, job_id, phase, storage_path, taken_at, jobs(job_no, region_name)')
        .order('taken_at', { ascending: false })
      if (e) throw e
      const rows = (data ?? []) as unknown as PhotoRow[]

      const byJob = new Map<string, JobGroup>()
      for (const r of rows) {
        let g = byJob.get(r.job_id)
        if (!g) {
          g = { job_id: r.job_id, job_no: r.jobs?.job_no ?? null, region_name: r.jobs?.region_name ?? null, photos: [] }
          byJob.set(r.job_id, g)
        }
        g.photos.push(r)
      }
      for (const g of byJob.values()) {
        g.photos.sort((a, b) => PHASE_ORDER.indexOf(a.phase) - PHASE_ORDER.indexOf(b.phase))
      }
      setGroups([...byJob.values()])
    } catch (e) {
      setError(e instanceof Error ? e.message : '현장 사진을 불러오지 못했습니다.')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  async function viewPhoto(p: PhotoRow) {
    setError(null)
    try {
      const { data, error: e } = await supabase.storage
        .from(BUCKET)
        .createSignedUrl(p.storage_path, 60)
      if (e || !data?.signedUrl) throw e ?? new Error('서명 URL 생성 실패')
      window.open(data.signedUrl, '_blank', 'noopener,noreferrer')
    } catch (e) {
      setError(e instanceof Error ? e.message : '사진을 열 수 없습니다.')
    }
  }

  if (loading) return <Loading />

  return (
    <>
      <div
        style={{
          display: 'flex',
          gap: 9,
          background: colors.primaryBg,
          border: '1px solid #DCE8FB',
          borderRadius: 12,
          padding: '11px 14px',
          fontSize: 12.5,
          fontWeight: 600,
          color: colors.ink2,
          marginBottom: 16,
        }}
      >
        현장 사진은 도착·작업·종료 3단계로 적립(단계당 1점). 3종 완비 시 보너스 포함 누적 40점마다 우선배차권 1장이 자동 지급됩니다.
      </div>

      {error && <ErrorState message={error} />}

      {groups.length === 0 ? (
        <EmptyState label="업로드된 현장 사진이 없습니다." />
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          {groups.map((g) => {
            const phases = new Set(g.photos.map((p) => p.phase))
            const done = PHASE_ORDER.filter((p) => phases.has(p)).length
            return (
              <div key={g.job_id} className="card">
                <div className="ch">
                  <h3>
                    <span className="n" style={{ fontWeight: 800 }}>{g.job_no ?? '-'}</span>{' '}
                    <span style={{ fontSize: 13, fontWeight: 600 }}>{g.region_name ?? ''}</span>
                  </h3>
                  <span
                    className={`bdg ${done === PHASE_ORDER.length ? 'ok' : 'wait'}`}
                    style={{ marginLeft: 'auto' }}
                  >
                    {done}/{PHASE_ORDER.length} 단계
                  </span>
                </div>
                <table className="tbl">
                  <thead>
                    <tr>
                      <th>단계</th>
                      <th>촬영 시각</th>
                      <th style={{ textAlign: 'right' }}>점수</th>
                      <th style={{ textAlign: 'right' }}>보기</th>
                    </tr>
                  </thead>
                  <tbody>
                    {g.photos.map((p) => (
                      <tr key={p.id}>
                        <td className="nm">{PHASE_LABELS[p.phase] ?? p.phase}</td>
                        <td className="num">{formatDateTime(p.taken_at)}</td>
                        <td className="num g" style={{ textAlign: 'right', fontWeight: 700 }}>
                          +{POINT_PER_PHASE}
                        </td>
                        <td style={{ textAlign: 'right' }}>
                          <button className="btn2 gh sm" onClick={() => void viewPhoto(p)}>
                            사진 보기
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )
          })}
        </div>
      )}
    </>
  )
}
