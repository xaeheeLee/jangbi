import { colors } from '../theme'

export function Loading({ label = '불러오는 중…' }: { label?: string }) {
  return (
    <div style={{ padding: '48px 0', textAlign: 'center', color: colors.ink3, fontSize: 13, fontWeight: 600 }}>
      {label}
    </div>
  )
}

export function ErrorState({ message }: { message: string }) {
  return (
    <div
      style={{
        margin: '12px 0',
        padding: '14px 16px',
        background: '#FEECEC',
        border: '1px solid #F6C9C9',
        borderRadius: 12,
        color: colors.red,
        fontSize: 13,
        fontWeight: 700,
      }}
    >
      {message}
    </div>
  )
}

export function EmptyState({ label = '데이터가 없습니다.' }: { label?: string }) {
  return (
    <div style={{ padding: '48px 0', textAlign: 'center', color: colors.ink3, fontSize: 13, fontWeight: 600 }}>
      {label}
    </div>
  )
}
