import React, { useState, useEffect } from 'react'
import { getToken, clearToken, fetchMe } from './lib/api'
import Login from './components/Login.jsx'
import RoleSelector from './components/RoleSelector.jsx'
import PoliceDashboard from './components/PoliceDashboard.jsx'
import EcoDashboard from './components/EcoDashboard.jsx'
import MaintenanceDashboard from './components/MaintenanceDashboard.jsx'
import AdminDashboard from './components/AdminDashboard.jsx'
import ModellinoDashboard from './components/ModellinoDashboard.jsx'
import { ErrorState, ROLE_META } from './components/ui.jsx'
import { LogoIcon } from './components/Logo.jsx'

const USERNAME_ROLE = { admin:'admin', polizia:'police', eco:'eco', manutenzione:'maintenance', modellino:'modellino' }
const TYPE_ROLE     = { admin:'admin', ente:'police', op_eco:'eco' }
const DASHBOARDS = { admin:AdminDashboard, police:PoliceDashboard, eco:EcoDashboard, maintenance:MaintenanceDashboard, modellino:ModellinoDashboard }

// Vista corrente in sessionStorage: un refresh riapre la stessa pagina invece della home.
const ROLE_KEY = 'te_role', ROLE_PICKER = 'select'
const loadRole  = () => { try { return sessionStorage.getItem(ROLE_KEY) } catch { return null } }
const saveRole  = r => { try { sessionStorage.setItem(ROLE_KEY, r || ROLE_PICKER) } catch {} }
const clearView = () => { try { sessionStorage.removeItem(ROLE_KEY); sessionStorage.removeItem('te_admin_tab') } catch {} }

export default function App() {
  const [authed,setAuthed]   = useState(!!getToken())
  const [user,setUser]       = useState(null)
  const [role,setRole]       = useState(null)
  const [meError,setMeError] = useState(null)
  const [attempt,setAttempt] = useState(0)
  const [expired,setExpired] = useState(false)

  useEffect(() => {
    const h = e => { clearView(); setAuthed(false); setUser(null); setRole(null); setExpired(!!e.detail?.expired) }
    window.addEventListener('te:logout', h)
    return () => window.removeEventListener('te:logout', h)
  }, [])

  useEffect(() => {
    if (!authed || user) return
    setMeError(null)
    fetchMe()
      .then(me => {
        setUser(me)
        const fixed = USERNAME_ROLE[me.username] || TYPE_ROLE[me.type]
        // Solo l'admin può cambiare profilo: per lui vale l'ultimo scelto (o il selettore) prima del refresh
        const saved = me.type === 'admin' ? loadRole() : null
        if (saved === ROLE_PICKER) return
        if (DASHBOARDS[saved]) setRole(saved)
        else if (fixed) setRole(fixed)
      })
      // 401: il token è già stato rimosso da api.js. Errore di rete: resta loggato e offri "Riprova".
      .catch(e => { if (e.status === 401) setAuthed(false); else setMeError(e.message) })
  }, [authed, user, attempt])

  useEffect(() => {
    document.title = !authed ? 'Accedi · Treeyes' : role ? `${ROLE_META[role]?.label} · Treeyes` : 'Treeyes — Centro operativo'
  }, [authed, role])

  function logout() { clearToken(); setAuthed(false); setUser(null); setRole(null) }
  const isAdmin   = user?.type === 'admin'
  const pickRole   = r => { if (isAdmin) saveRole(r); setRole(r) }
  const switchRole = isAdmin ? () => pickRole(null) : null

  if (!authed)  return <Login onLogin={() => { setExpired(false); setAuthed(true) }} notice={expired ? 'La sessione è scaduta: accedi di nuovo per continuare.' : null} />
  if (meError)  return <div style={{ height:'100dvh' }}><ErrorState title="Impossibile caricare il profilo" text={meError} onRetry={() => setAttempt(a => a + 1)}/></div>
  if (!user)    return <Splash />
  if (!role)    return <RoleSelector username={user.username} isAdmin={isAdmin} onSelect={pickRole} onLogout={logout} />

  const Dashboard = DASHBOARDS[role]
  return Dashboard ? <Dashboard onLogout={logout} onSwitchRole={switchRole} username={user.username} role={role}/> : null
}

function Splash() {
  return (
    <div role="status" aria-label="Caricamento" style={{ height:'100dvh', display:'flex', alignItems:'center', justifyContent:'center', flexDirection:'column', gap:16 }}>
      <LogoIcon size={44}/>
      <div style={{ width:24, height:24, border:'2px solid var(--border)', borderTopColor:'var(--accent)', borderRadius:'50%', animation:'spin .75s linear infinite' }} />
      <div style={{ fontSize:13, color:'var(--text-3)' }}>Caricamento del profilo…</div>
    </div>
  )
}
