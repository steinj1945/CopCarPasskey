import { Link, Outlet, useNavigate, useLocation } from 'react-router-dom'

export default function Layout() {
  const navigate  = useNavigate()
  const { pathname } = useLocation()

  function logout() {
    localStorage.removeItem('token')
    navigate('/login')
  }

  const navLink = (to: string, label: string) =>
    <Link to={to} className={`px-3 py-2 rounded text-sm font-medium ${
      pathname.startsWith(to) ? 'bg-gray-900 text-white' : 'text-gray-300 hover:bg-gray-700 hover:text-white'
    }`}>{label}</Link>

  return (
    <div className="min-h-screen bg-gray-100">
      <nav className="bg-gray-800">
        <div className="max-w-5xl mx-auto px-4 flex items-center justify-between h-14">
          <div className="flex items-center gap-4">
            <span className="text-white font-semibold">CopCar Passkey</span>
            {navLink('/keys', 'Keys')}
            {navLink('/logs', 'Audit Log')}
          </div>
          <button onClick={logout} className="text-gray-300 hover:text-white text-sm">Sign out</button>
        </div>
      </nav>
      <main className="max-w-5xl mx-auto px-4 py-8">
        <Outlet />
      </main>
    </div>
  )
}
