import { colors } from '../theme'

export default function Placeholder({ title }: { title: string }) {
  return (
    <div className="card">
      <div className="ch">
        <h3>{title}</h3>
      </div>
      <div style={{ padding: '64px 24px', textAlign: 'center' }}>
        <div
          style={{
            display: 'inline-block',
            fontSize: 12.5,
            fontWeight: 800,
            color: colors.ink3,
            background: colors.line2,
            borderRadius: 999,
            padding: '7px 16px',
          }}
        >
          준비 중
        </div>
        <p style={{ marginTop: 14, fontSize: 13.5, color: colors.ink2, fontWeight: 600 }}>
          {title} 기능은 곧 제공될 예정입니다.
        </p>
      </div>
    </div>
  )
}
