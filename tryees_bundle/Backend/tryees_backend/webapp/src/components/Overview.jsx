import React from 'react'
import { KpiCard, fmt1, sevColor, STATUS_META } from './ui.jsx'

const ORDER = ['open', 'in_progress', 'resolved', 'closed']
const PLURAL = { open:'Aperte', in_progress:'In carico', resolved:'Risolte', closed:'Chiuse' }

export default function Overview({ data }) {
  if (!data?.length) return null
  const byStatus = Object.fromEntries(data.map(r => [r.status, r]))
  const total  = data.reduce((a, r) => a + r.count, 0)
  const active = (byStatus.open?.count || 0) + (byStatus.in_progress?.count || 0)
  const maxSev = Math.max(...data.filter(r => r.status === 'open' || r.status === 'in_progress').map(r => r.max_severity), 0)
  return (
    <section aria-label="Riepilogo pratiche" className="te-kpis">
      <KpiCard label="Pratiche attive" value={active} sub={`su ${total} totali`}/>
      {ORDER.filter(s => byStatus[s]).map(s => (
        <KpiCard key={s} label={PLURAL[s] || STATUS_META[s]?.l} value={byStatus[s].count} sub={`sev. media ${fmt1(byStatus[s].avg_severity)}`}/>
      ))}
      <KpiCard label="Severità massima attiva" value={active ? fmt1(maxSev) : '—'} sub={active ? 'su 10' : 'nessuna pratica attiva'} color={active ? sevColor(maxSev) : 'var(--text-1)'}/>
    </section>
  )
}
