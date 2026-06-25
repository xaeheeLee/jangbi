import { Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from './lib/auth'
import { Loading } from './components/States'
import Layout from './components/Layout'
import Login from './pages/Login'
import Dashboard from './pages/Dashboard'
import Members from './pages/Members'
import Withdrawals from './pages/Withdrawals'
import Placeholder from './pages/Placeholder'

export default function App() {
  const { session, profile, loading } = useAuth()

  if (loading) return <Loading label="세션 확인 중…" />

  const authed = !!session && !!profile?.is_admin

  if (!authed) {
    return (
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="*" element={<Navigate to="/login" replace />} />
      </Routes>
    )
  }

  return (
    <Routes>
      <Route path="/login" element={<Navigate to="/" replace />} />
      <Route element={<Layout />}>
        <Route index element={<Dashboard />} />
        <Route path="members" element={<Members />} />
        <Route path="withdrawals" element={<Withdrawals />} />
        <Route path="documents" element={<Placeholder title="서류 마스킹" />} />
        <Route path="premium" element={<Placeholder title="프리미엄 명단" />} />
        <Route path="ratings" element={<Placeholder title="평점 관리" />} />
        <Route path="jobs" element={<Placeholder title="일감·매칭" />} />
        <Route path="photos" element={<Placeholder title="현장 사진" />} />
        <Route path="tax" element={<Placeholder title="세무 Export" />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  )
}
