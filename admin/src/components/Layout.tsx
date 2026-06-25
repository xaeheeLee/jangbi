import { NavLink, Outlet, useLocation } from 'react-router-dom'
import { useAuth } from '../lib/auth'

interface NavItem {
  to: string
  label: string
  ready: boolean
}

const NAV: NavItem[] = [
  { to: '/', label: '대시보드', ready: true },
  { to: '/members', label: '회원 승인', ready: true },
  { to: '/withdrawals', label: '인출 승인', ready: true },
  { to: '/documents', label: '서류 마스킹', ready: false },
  { to: '/premium', label: '프리미엄 명단', ready: false },
  { to: '/ratings', label: '평점 관리', ready: false },
  { to: '/jobs', label: '일감·매칭', ready: false },
  { to: '/photos', label: '현장 사진', ready: false },
  { to: '/tax', label: '세무 Export', ready: false },
]

const TITLES: Record<string, string> = Object.fromEntries(NAV.map((n) => [n.to, n.label]))

export default function Layout() {
  const { profile, signOut } = useAuth()
  const loc = useLocation()
  const title = TITLES[loc.pathname] ?? '전중배 관리자'
  const adminInitial = profile?.name?.[0] ?? '운'

  return (
    <div style={{ display: 'grid', gridTemplateColumns: '234px 1fr', height: '100vh' }}>
      {/* sidebar */}
      <aside
        style={{
          background: 'linear-gradient(180deg,#012a5e,#00193a)',
          color: '#fff',
          display: 'flex',
          flexDirection: 'column',
          padding: '18px 14px',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 8px 20px' }}>
          <span
            style={{
              width: 32, height: 32, borderRadius: 9, background: '#fff',
              display: 'grid', placeItems: 'center', color: '#002F6C',
              fontWeight: 800, fontSize: 13, letterSpacing: '-.04em',
            }}
          >
            전중
          </span>
          <span>
            <b style={{ fontSize: 14.5, fontWeight: 800, display: 'block', lineHeight: 1.15 }}>전중배 관리자</b>
            <small style={{ fontSize: 10, color: 'rgba(255,255,255,.55)', fontWeight: 600 }}>운영 콘솔</small>
          </span>
        </div>

        <nav style={{ display: 'flex', flexDirection: 'column', gap: 3, overflowY: 'auto' }}>
          {NAV.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.to === '/'}
              style={({ isActive }) => ({
                display: 'flex',
                alignItems: 'center',
                gap: 11,
                padding: '11px 12px',
                borderRadius: 11,
                color: isActive ? '#fff' : 'rgba(255,255,255,.72)',
                background: isActive ? 'rgba(255,255,255,.15)' : 'transparent',
                fontSize: 13.5,
                fontWeight: 700,
              })}
            >
              {item.label}
              {!item.ready && (
                <span
                  style={{
                    marginLeft: 'auto', fontSize: 10, fontWeight: 800,
                    color: 'rgba(255,255,255,.5)', border: '1px solid rgba(255,255,255,.2)',
                    borderRadius: 999, padding: '1px 7px',
                  }}
                >
                  준비중
                </span>
              )}
            </NavLink>
          ))}
        </nav>

        <div
          style={{
            marginTop: 'auto', display: 'flex', alignItems: 'center', gap: 10,
            padding: '12px 8px 4px', borderTop: '1px solid rgba(255,255,255,.12)',
          }}
        >
          <span
            style={{
              width: 34, height: 34, borderRadius: 10, background: 'rgba(255,255,255,.16)',
              display: 'grid', placeItems: 'center', fontWeight: 800, fontSize: 13,
            }}
          >
            {adminInitial}
          </span>
          <span style={{ flex: 1, minWidth: 0 }}>
            <b style={{ fontSize: 13, fontWeight: 800, display: 'block' }}>{profile?.name ?? '운영팀'}</b>
            <small style={{ fontSize: 11, color: 'rgba(255,255,255,.55)', fontWeight: 600 }}>관리자</small>
          </span>
          <button
            onClick={() => void signOut()}
            style={{
              fontSize: 11, fontWeight: 700, color: 'rgba(255,255,255,.8)',
              border: '1px solid rgba(255,255,255,.2)', borderRadius: 8, padding: '5px 9px',
            }}
          >
            로그아웃
          </button>
        </div>
      </aside>

      {/* content */}
      <section style={{ display: 'flex', flexDirection: 'column', minWidth: 0, background: 'var(--bg)' }}>
        <div
          style={{
            height: 62, display: 'flex', alignItems: 'center', gap: 12, padding: '0 24px',
            background: '#fff', borderBottom: '1px solid var(--line)', flex: 'none',
          }}
        >
          <h2 style={{ fontSize: 18, fontWeight: 800, letterSpacing: '-.02em' }}>{title}</h2>
        </div>
        <div style={{ padding: '22px 24px', overflow: 'auto', flex: 1 }}>
          <Outlet />
        </div>
      </section>
    </div>
  )
}
