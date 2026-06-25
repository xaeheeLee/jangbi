import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { EmptyState, ErrorState, Loading } from '../components/States'
import { colors } from '../theme'

const BUCKET = 'member-docs'

const DOC_LABELS: Record<string, string> = {
  business_reg: '사업자등록증',
  license: '건설기계조종사면허',
  insurance: '자동차보험증권',
  vehicle_reg: '차량등록증',
  bankbook: '통장사본',
}
const DOC_ORDER = ['business_reg', 'license', 'insurance', 'vehicle_reg', 'bankbook']

interface DocRow {
  id: string
  user_id: string
  doc_type: string
  original_path: string | null
  masked_path: string | null
  created_at: string | null
  profiles: { name: string | null; member_no: string | null } | null
}

interface MemberGroup {
  user_id: string
  name: string | null
  member_no: string | null
  docs: DocRow[]
}

export default function Documents() {
  const [groups, setGroups] = useState<MemberGroup[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busyId, setBusyId] = useState<string | null>(null)
  const fileInputs = useRef<Record<string, HTMLInputElement | null>>({})

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const { data, error: e } = await supabase
        .from('member_documents')
        .select('id, user_id, doc_type, original_path, masked_path, created_at, profiles(name, member_no)')
        .order('created_at', { ascending: false })
      if (e) throw e
      const rows = (data ?? []) as unknown as DocRow[]

      const byUser = new Map<string, MemberGroup>()
      for (const r of rows) {
        let g = byUser.get(r.user_id)
        if (!g) {
          g = { user_id: r.user_id, name: r.profiles?.name ?? null, member_no: r.profiles?.member_no ?? null, docs: [] }
          byUser.set(r.user_id, g)
        }
        g.docs.push(r)
      }
      for (const g of byUser.values()) {
        g.docs.sort((a, b) => DOC_ORDER.indexOf(a.doc_type) - DOC_ORDER.indexOf(b.doc_type))
      }
      setGroups([...byUser.values()])
    } catch (e) {
      setError(e instanceof Error ? e.message : '서류를 불러오지 못했습니다.')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  async function viewOriginal(doc: DocRow) {
    if (!doc.original_path) return
    setError(null)
    try {
      const { data, error: e } = await supabase.storage
        .from(BUCKET)
        .createSignedUrl(doc.original_path, 60)
      if (e || !data?.signedUrl) throw e ?? new Error('서명 URL 생성 실패')
      window.open(data.signedUrl, '_blank', 'noopener,noreferrer')
    } catch (e) {
      setError(e instanceof Error ? e.message : '원본을 열 수 없습니다.')
    }
  }

  async function uploadMasked(doc: DocRow, file: File) {
    setBusyId(doc.id)
    setError(null)
    try {
      const ext = file.name.split('.').pop()?.toLowerCase() || 'jpg'
      const path = `${doc.user_id}/${doc.doc_type}_masked.${ext}`
      const { error: upErr } = await supabase.storage
        .from(BUCKET)
        .upload(path, file, { upsert: true })
      if (upErr) throw upErr
      const { error: rpcErr } = await supabase.rpc('set_masked_document', {
        p_doc_id: doc.id,
        p_masked_path: path,
      })
      if (rpcErr) throw rpcErr
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : '마스킹본 업로드에 실패했습니다.')
    } finally {
      setBusyId(null)
    }
  }

  if (loading) return <Loading />

  return (
    <>
      <div
        style={{
          display: 'flex',
          gap: 9,
          background: '#FCF0D8',
          border: '1px solid #F0DCAE',
          borderRadius: 12,
          padding: '11px 14px',
          fontSize: 12.5,
          fontWeight: 700,
          color: '#B45309',
          marginBottom: 16,
        }}
      >
        민감정보 — 원본은 검수용입니다. 검수 후 반드시 마스킹본을 업로드하세요. 발주자에게는 마스킹본만 노출됩니다.
      </div>

      {error && <ErrorState message={error} />}

      {groups.length === 0 ? (
        <EmptyState label="제출된 가입 서류가 없습니다." />
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          {groups.map((g) => (
            <div key={g.user_id} className="card">
              <div className="ch">
                <h3>
                  {g.name ?? '-'}{' '}
                  <span className="n" style={{ fontSize: 12.5 }}>#{g.member_no ?? '-'}</span>
                </h3>
                <span style={{ marginLeft: 'auto', fontSize: 12, color: colors.ink3, fontWeight: 600 }}>
                  서류 {g.docs.length}건
                </span>
              </div>
              <table className="tbl">
                <thead>
                  <tr>
                    <th>서류 종류</th>
                    <th>원본</th>
                    <th>마스킹본</th>
                    <th style={{ textAlign: 'right' }}>처리</th>
                  </tr>
                </thead>
                <tbody>
                  {g.docs.map((doc) => (
                    <tr key={doc.id}>
                      <td className="nm">{DOC_LABELS[doc.doc_type] ?? doc.doc_type}</td>
                      <td>
                        {doc.original_path ? <span className="bdg ok">원본 ○</span> : <span className="bdg no">원본 ×</span>}
                      </td>
                      <td>
                        {doc.masked_path ? <span className="bdg ok">마스킹 ○</span> : <span className="bdg wait">마스킹 ×</span>}
                      </td>
                      <td style={{ textAlign: 'right' }}>
                        <div style={{ display: 'inline-flex', gap: 8 }}>
                          <button
                            className="btn2 gh sm"
                            disabled={!doc.original_path}
                            onClick={() => void viewOriginal(doc)}
                          >
                            원본 보기
                          </button>
                          <input
                            type="file"
                            accept="image/*,application/pdf"
                            style={{ display: 'none' }}
                            ref={(el) => {
                              fileInputs.current[doc.id] = el
                            }}
                            onChange={(ev) => {
                              const f = ev.target.files?.[0]
                              if (f) void uploadMasked(doc, f)
                              ev.target.value = ''
                            }}
                          />
                          <button
                            className="btn2 navy sm"
                            disabled={busyId === doc.id}
                            onClick={() => fileInputs.current[doc.id]?.click()}
                          >
                            {busyId === doc.id ? '업로드 중…' : '마스킹본 업로드'}
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ))}
        </div>
      )}
    </>
  )
}
