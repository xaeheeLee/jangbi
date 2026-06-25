import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { formatDate, formatPhone } from '../lib/format'
import { EmptyState, ErrorState, Loading } from '../components/States'

interface PendingMember {
  id: string
  name: string | null
  member_no: string | null
  phone: string | null
  equipment_category: string | null
  equipment_model: string | null
  created_at: string | null
}

const DOC_LABELS: Record<string, string> = {
  business_reg: '사업자등록증',
  license: '조종사면허',
  insurance: '보험증권',
  equipment_reg: '차량등록증',
  photo: '통장/사진',
}
const DOC_ORDER = ['business_reg', 'license', 'insurance', 'equipment_reg', 'photo']

export default function Members() {
  const [members, setMembers] = useState<PendingMember[]>([])
  const [docs, setDocs] = useState<Record<string, Set<string>>>({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [approving, setApproving] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const { data, error: e } = await supabase
        .from('profiles')
        .select('id, name, member_no, phone, equipment_category, equipment_model, created_at')
        .eq('membership_status', 'pending')
        .order('created_at', { ascending: true })
      if (e) throw e
      const list = (data ?? []) as PendingMember[]
      setMembers(list)

      if (list.length > 0) {
        const ids = list.map((m) => m.id)
        const { data: docRows } = await supabase
          .from('member_documents')
          .select('user_id, doc_type')
          .in('user_id', ids)
        const map: Record<string, Set<string>> = {}
        for (const r of (docRows ?? []) as { user_id: string; doc_type: string }[]) {
          const set = (map[r.user_id] ??= new Set())
          set.add(r.doc_type)
        }
        setDocs(map)
      } else {
        setDocs({})
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

  async function approve(userId: string) {
    setApproving(userId)
    setError(null)
    try {
      const { error: e } = await supabase.rpc('approve_member', { p_user_id: userId })
      if (e) throw e
      setMembers((prev) => prev.filter((m) => m.id !== userId))
    } catch (e) {
      setError(e instanceof Error ? e.message : '승인에 실패했습니다.')
    } finally {
      setApproving(null)
    }
  }

  if (loading) return <Loading />

  return (
    <>
      {error && <ErrorState message={error} />}
      <div className="card">
        <div className="ch">
          <h3>승인 대기 회원 {members.length}명</h3>
        </div>
        {members.length === 0 ? (
          <EmptyState label="승인 대기 중인 회원이 없습니다." />
        ) : (
          <table className="tbl">
            <thead>
              <tr>
                <th>이름</th>
                <th>회원번호</th>
                <th>연락처</th>
                <th>신청 장비</th>
                <th>가입일</th>
                <th>서류</th>
                <th style={{ textAlign: 'right' }}></th>
              </tr>
            </thead>
            <tbody>
              {members.map((m) => {
                const have = docs[m.id] ?? new Set<string>()
                const count = DOC_ORDER.filter((d) => have.has(d)).length
                const equip = [m.equipment_category, m.equipment_model].filter(Boolean).join(' · ') || '-'
                return (
                  <tr key={m.id}>
                    <td className="nm">{m.name ?? '-'}</td>
                    <td className="num n">{m.member_no ?? '-'}</td>
                    <td className="num">{formatPhone(m.phone)}</td>
                    <td>{equip}</td>
                    <td className="num">{formatDate(m.created_at)}</td>
                    <td>
                      <span
                        className={`bdg ${count === DOC_ORDER.length ? 'ok' : 'wait'}`}
                        title={DOC_ORDER.map((d) => `${DOC_LABELS[d]}: ${have.has(d) ? 'O' : 'X'}`).join('\n')}
                      >
                        {count}/{DOC_ORDER.length}
                      </span>
                    </td>
                    <td style={{ textAlign: 'right' }}>
                      <button
                        className="btn2 green sm"
                        disabled={approving === m.id}
                        onClick={() => void approve(m.id)}
                      >
                        {approving === m.id ? '처리 중…' : '승인'}
                      </button>
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
