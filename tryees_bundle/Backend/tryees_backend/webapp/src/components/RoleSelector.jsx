import React from 'react'
import { LogOut } from 'lucide-react'
import { LogoFull } from './Logo.jsx'
import { ROLE_META } from './ui.jsx'

const ROLES = [
  { key: 'police', desc: 'Allerte di sicurezza da telecamere e microfoni, mappa ed escalation.' },
  { key: 'eco', desc: 'Cestini da svuotare e umidità del terreno.' },
  { key: 'maintenance', desc: 'Stato dei dispositivi IoT, guasti e registro interventi.' },
  { key: 'modellino', desc: 'Il modellino del parco: sensori, allarmi e soglie.' },
  { key: 'admin', desc: 'Stato del sistema, pratiche, dispositivi e accessi.', adminOnly: true },
]

export default function RoleSelector({ username, isAdmin, onSelect, onLogout }) {
  const visible = ROLES.filter(r => !r.adminOnly || isAdmin)

  return (
    <div style={{ minHeight: '100dvh', display: 'flex', flexDirection: 'column', background: 'var(--bg)' }}>
      <header className="te-topbar" style={{ minHeight: 64, padding: '8px 24px', justifyContent: 'space-between' }}>
        <div className="te-topbar-brand">
          <LogoFull size="sm" />
        </div>

        <div className="te-topbar-actions" style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <span className="te-hide-sm" style={{ fontSize: 14, color: 'var(--text-2)' }}>
            Connesso come <strong style={{ color: 'var(--text-1)' }}>{username}</strong>
          </span>

          {isAdmin && (
            <span
              className="te-chip"
              style={{
                background: 'var(--role-admin-bg)',
                color: 'var(--role-admin)',
                fontWeight: 600,
                fontSize: 12,
              }}
            >
              Amministratore
            </span>
          )}

          <button
            type="button"
            className="te-btn te-btn--secondary"
            onClick={onLogout}
            title="Esci dall'applicazione"
            style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}
          >
            <LogOut size={16} aria-hidden="true" style={{ color: 'var(--red)' }} />
            <span>Esci</span>
          </button>
        </div>
      </header>

      {/* ── Contenuto Selezione Profilo ── */}
      <main
        style={{
          flex: 1,
          width: '100%',
          maxWidth: 1120,
          margin: '0 auto',
          padding: '48px 24px',
          display: 'flex',
          flexDirection: 'column',
          gap: 28,
        }}
      >
        <div>
          <h1 style={{ fontSize: 28, fontWeight: 700, letterSpacing: '-0.01em', color: 'var(--text-1)' }}>
            Con quale profilo vuoi lavorare?
          </h1>
          <p style={{ marginTop: 6, fontSize: 16, color: 'var(--text-3)', maxWidth: 640 }}>
            Ogni profilo apre la dashboard con i dati e le azioni del suo ambito operativo. Puoi cambiarlo in qualsiasi
            momento dal menu utente in alto a destra.
          </p>
        </div>

        <div className="te-roles">
          {visible.map((r, i) => {
            const m = ROLE_META[r.key]
            return (
              <button
                key={r.key}
                type="button"
                className="te-role-card"
                onClick={() => onSelect(r.key)}
                style={{
                  animation: `fadeUp .25s ease ${i * 40}ms both`,
                  cursor: 'pointer',
                  textAlign: 'left',
                }}
              >
                <span
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    width: '100%',
                    gap: 8,
                  }}
                >
                  <span className="te-role-icon" style={{ background: m.bg, color: m.c }}>
                    <m.icon size={22} aria-hidden="true" />
                  </span>
                  {r.adminOnly && (
                    <span
                      className="te-chip"
                      style={{ background: 'var(--role-admin-bg)', color: 'var(--role-admin)' }}
                    >
                      Solo admin
                    </span>
                  )}
                </span>
                <span style={{ display: 'flex', flexDirection: 'column', gap: 4, marginTop: 4 }}>
                  <span style={{ fontSize: 17, fontWeight: 700, color: 'var(--text-1)' }}>{m.label}</span>
                  <span style={{ fontSize: 14, color: 'var(--text-3)', lineHeight: 1.4 }}>{r.desc}</span>
                </span>
              </button>
            )
          })}
        </div>
      </main>
    </div>
  )
}
