import { Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from './lib/auth'
import { Loading } from './components/States'
import Layout from './components/Layout'
import Login from './pages/Login'
import Dashboard from './pages/Dashboard'
import Members from './pages/Members'
import Withdrawals from './pages/Withdrawals'
import Premium from './pages/Premium'
import Ratings from './pages/Ratings'
import Tax from './pages/Tax'
import Jobs from './pages/Jobs'
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
        <Route path="premium" element={<Premium />} />
        <Route path="ratings" element={<Ratings />} />
        <Route path="jobs" element={<Jobs />} />
        <Route path="photos" element={<Placeholder title="현장 사진" />} />
        <Route path="tax" element={<Tax />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  )
}
