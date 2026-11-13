import React, { useState, useRef } from 'react'
import { Eye, EyeOff, AlertCircle, Clock } from 'lucide-react'
import { login } from '../lib/api'
import { LogoFull } from './Logo.jsx'
import { Btn } from './ui.jsx'

// Account demo: mostrati in sviluppo, oppure in build con VITE_SHOW_DEMO_USERS=true.
const SHOW_DEMO = import.meta.env.DEV || import.meta.env.VITE_SHOW_DEMO_USERS === 'true'
const DEMO_PASSWORD = 'admin123'
const DEMO_USERS = ['admin', 'polizia', 'eco', 'manutenzione', 'modellino']

export default function Login({ onLogin, notice }) {
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [showPw, setShowPw] = useState(false)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const userRef = useRef(null)

  async function submit(e) {
    e.preventDefault()
    if (!username.trim() || !password) { setError('Inserisci nome utente e password.'); return }
    setError('')
    setLoading(true)
    try {
      await login(username.trim(), password)
      onLogin()
    } catch (err) {
      setError(err.message || 'Accesso non riuscito. Riprova.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="te-login">
      <aside className="te-login-brand">
        <LogoFull size="md" white/>
        <div style={{ display:'flex', flexDirection:'column', gap:16 }}>
          <h1 style={{ fontSize:34, lineHeight:1.2, fontWeight:700, color:'#FFFFFF', letterSpacing:'-0.01em' }}>Centro operativo<br/>del Parco Robinson</h1>
          <p style={{ fontSize:16, color:'#C3CDC5', maxWidth:380 }}>Segnalazioni dai sensori del parco in tempo reale, per Polizia Locale, raccolta rifiuti e manutenzione.</p>
        </div>
        <p style={{ fontSize:13, color:'#A9B5AC' }}>Comune di Legnano · Accesso riservato al personale autorizzato</p>
      </aside>

      <main className="te-login-main">
        <div style={{ width:'100%', maxWidth:400, display:'flex', flexDirection:'column', gap:20 }}>
          <div className="te-login-mobile-logo"><LogoFull size="sm"/></div>
          <div>
            <h2 style={{ fontSize:24, fontWeight:700 }}>Accedi</h2>
            <p style={{ marginTop:4, color:'var(--text-3)' }}>Usa le credenziali fornite dal tuo ente.</p>
          </div>

          <form onSubmit={submit} noValidate style={{ display:'flex', flexDirection:'column', gap:16 }}>
            <div className="te-field">
              <label htmlFor="login-user" className="te-label">Nome utente</label>
              <input id="login-user" ref={userRef} className="te-input" style={{ minHeight:44, fontSize:15 }}
                value={username} onChange={e => setUsername(e.target.value)}
                autoComplete="username" autoCapitalize="none" spellCheck={false} autoFocus
                aria-invalid={!!error || undefined} aria-describedby={error ? 'login-error' : undefined}/>
            </div>

            <div className="te-field">
              <label htmlFor="login-pw" className="te-label">Password</label>
              <div style={{ position:'relative' }}>
                <input id="login-pw" type={showPw ? 'text' : 'password'} className="te-input" style={{ minHeight:44, fontSize:15, paddingRight:48 }}
                  value={password} onChange={e => setPassword(e.target.value)} autoComplete="current-password"
                  aria-invalid={!!error || undefined} aria-describedby={error ? 'login-error' : undefined}/>
                <button type="button" onClick={() => setShowPw(v => !v)} aria-label={showPw ? 'Nascondi password' : 'Mostra password'} aria-pressed={showPw}
                  style={{ position:'absolute', right:2, top:2, width:40, height:40, display:'inline-flex', alignItems:'center', justifyContent:'center', color:'var(--text-3)', borderRadius:6 }}>
                  {showPw ? <EyeOff size={18} aria-hidden="true"/> : <Eye size={18} aria-hidden="true"/>}
                </button>
              </div>
            </div>

            {notice && !error && (
              <div role="status" style={{ display:'flex', gap:8, alignItems:'flex-start', padding:'10px 12px', background:'var(--yellow-light)', border:'1px solid var(--yellow-mid)', borderRadius:'var(--r-sm)', color:'var(--text-1)', fontSize:14 }}>
                <Clock size={18} aria-hidden="true" style={{ flexShrink:0, marginTop:1, color:'var(--yellow)' }}/>{notice}
              </div>
            )}

            {error && (
              <div id="login-error" role="alert" style={{ display:'flex', gap:8, alignItems:'flex-start', padding:'10px 12px', background:'var(--red-light)', border:'1px solid var(--red-mid)', borderRadius:'var(--r-sm)', color:'#7A1A12', fontSize:14 }}>
                <AlertCircle size={18} aria-hidden="true" style={{ flexShrink:0, marginTop:1 }}/>{error}
              </div>
            )}

            <Btn type="submit" variant="primary" size="lg" full loading={loading}>{loading ? 'Accesso in corso…' : 'Accedi'}</Btn>
          </form>

          {SHOW_DEMO && (
            <details open style={{ border:'1px dashed var(--border-2)', borderRadius:'var(--r-md)', background:'var(--bg-2)', padding:'12px 14px' }}>
              <summary style={{ cursor:'pointer', fontSize:14, fontWeight:600, color:'var(--text-2)' }}>
                Account demo <span style={{ fontWeight:400, color:'var(--text-3)' }}>· password {DEMO_PASSWORD}</span>
              </summary>
              <div style={{ marginTop:10, display:'flex', flexWrap:'wrap', gap:6 }}>
                {DEMO_USERS.map(u => (
                  <button key={u} type="button" className="te-btn te-btn--secondary te-btn--sm"
                    onClick={() => { setUsername(u); setPassword(DEMO_PASSWORD); setError('') }}
                    aria-label={`Compila con l'account demo ${u}`}>{u}</button>
                ))}
              </div>
            </details>
          )}
        </div>
      </main>
    </div>
  )
}
