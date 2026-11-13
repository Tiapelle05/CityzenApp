import React, { useState, useEffect, useCallback } from 'react'
import { Lightbulb, MessageSquare, Star, CheckCircle2, UserCheck, XCircle } from 'lucide-react'
import { apiUrl, fetchCitizenReports, updateCitizenReport } from '../lib/api'
import { Spinner, Btn, SectionTitle, EmptyState, ErrorState, fmtDateTime } from './ui.jsx'
import { toast } from './Shared.jsx'

/** Suggerimenti e feedback inviati dai cittadini con l'app. I problemi non sono qui:
 *  diventano pratiche. Il cambio di stato (con una nota facoltativa) arriva al cittadino. */

const KIND = { suggestion:{ l:'Suggerimento', icon:Lightbulb }, feedback:{ l:'Feedback', icon:MessageSquare } }
const STATUS_STYLE = {
  received:    { background:'var(--bg-3)', color:'var(--text-2)' },
  in_progress: { background:'var(--yellow-light)', color:'var(--yellow)' },
  resolved:    { background:'var(--green-light)', color:'var(--green)' },
  closed:      { background:'var(--bg-4)', color:'var(--text-3)' },
}
const NEXT = {
  received:    [['in_progress', 'Prendi in carico', UserCheck], ['closed', 'Chiudi', XCircle]],
  in_progress: [['resolved', 'Segna come gestito', CheckCircle2], ['closed', 'Chiudi', XCircle]],
  resolved:    [['closed', 'Chiudi', XCircle]],
  closed:      [],
}
const FILTERS = [['', 'Tutti'], ['suggestion', 'Suggerimenti'], ['feedback', 'Feedback']]

function Rating({ value }) {
  return (
    <span aria-label={`Voto ${value} su 5`} style={{ display:'inline-flex', gap:1 }}>
      {[1, 2, 3, 4, 5].map(i => <Star key={i} size={14} aria-hidden="true" style={{ color:i <= value ? 'var(--yellow)' : 'var(--border-3)', fill:i <= value ? 'var(--yellow)' : 'none' }}/>)}
    </span>
  )
}

function ReportCard({ r, onChange }) {
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(null)
  const K = KIND[r.kind]
  async function move(status) {
    setBusy(status)
    try { await onChange(r, status, note.trim() || undefined); setNote('') }
    finally { setBusy(null) }
  }
  const next = NEXT[r.status] || []
  return (
    <li className="te-event">
      <div style={{ display:'flex', gap:8, alignItems:'center', flexWrap:'wrap' }}>
        <span className="te-chip" style={{ background:'var(--bg-2)', color:'var(--text-2)' }}><K.icon size={12} aria-hidden="true"/>{K.l}</span>
        {r.category_label && <span className="te-chip" style={{ background:'var(--bg-2)', color:'var(--text-2)' }}>{r.category_label}</span>}
        {r.rating != null && <Rating value={r.rating}/>}
        <span style={{ flex:1 }}/>
        <span className="te-chip" style={STATUS_STYLE[r.status]}>{r.status_label}</span>
      </div>
      {r.title && <p style={{ margin:'2px 0 0', fontSize:15, fontWeight:700, color:'var(--text-1)' }}>{r.title} {r.visibility === 'private' && <span className="te-chip" style={{ background:'var(--bg-3)', color:'var(--text-2)' }}>Privata</span>}</p>}
      <p style={{ margin:0, fontSize:14, color:'var(--text-1)', whiteSpace:'pre-wrap', overflowWrap:'anywhere' }}>{r.description}</p>
      {r.photo_url && (
        <a href={apiUrl(r.photo_url)} target="_blank" rel="noreferrer" aria-label={`Apri la foto di ${r.code} in una nuova scheda`}>
          <img src={apiUrl(r.photo_url)} alt={`Foto allegata a ${r.code}`} loading="lazy" style={{ width:'100%', maxHeight:180, objectFit:'cover', borderRadius:'var(--r-sm)', border:'1px solid var(--border)', display:'block' }}/>
        </a>
      )}
      <div style={{ fontSize:12, color:'var(--text-3)' }}><span className="mono">{r.code}</span> · {fmtDateTime(r.created_at)}</div>
      {next.length > 0 && (
        <div style={{ display:'flex', flexDirection:'column', gap:8 }}>
          <label htmlFor={`sug-note-${r.id}`} className="te-label" style={{ fontSize:12 }}>Nota per il cittadino <span style={{ fontWeight:400, color:'var(--text-3)' }}>(facoltativa)</span></label>
          <input id={`sug-note-${r.id}`} className="te-input" maxLength={500} value={note} onChange={e => setNote(e.target.value)} placeholder="Es. Grazie, lo valuteremo con il Comune"/>
          <div style={{ display:'flex', gap:8, flexWrap:'wrap' }}>
            {next.map(([s, label, Icon], i) => (
              <Btn key={s} size="sm" variant={i === 0 ? 'primary' : 'default'} loading={busy === s} disabled={!!busy} onClick={() => move(s)} icon={<Icon size={15}/>}>{label}</Btn>
            ))}
          </div>
        </div>
      )}
    </li>
  )
}

export default function AdminSuggestions() {
  const [kind, setKind] = useState('')
  const [openOnly, setOpenOnly] = useState(true)
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)

  const load = useCallback(() => {
    setError(null)
    fetchCitizenReports({ kind, limit:200 }).then(setData).catch(e => setError(e.message))
  }, [kind])
  useEffect(() => { load() }, [load])

  async function change(r, status, note) {
    try {
      const updated = await updateCitizenReport(r.id, status, note)
      setData(d => ({ ...d, items:d.items.map(x => x.id === r.id ? updated : x) }))
      toast(`${r.code}: ${updated.status_label.toLowerCase()}.`, 'success')
    } catch (e) { toast(e.message, 'danger', { title:'Stato non aggiornato' }) }
  }

  const items = (data?.items || []).filter(r => !openOnly || r.status === 'received' || r.status === 'in_progress')
  return (
    <section className="te-card te-card--pad" aria-labelledby="sug-title" style={{ maxWidth:860 }}>
      <SectionTitle as="h2" action={
        <label style={{ display:'inline-flex', alignItems:'center', gap:6, fontSize:13, color:'var(--text-2)' }}>
          <input type="checkbox" checked={openOnly} onChange={e => setOpenOnly(e.target.checked)}/>Solo da gestire
        </label>
      }><span id="sug-title">Suggerimenti e feedback dei cittadini</span></SectionTitle>
      <div role="group" aria-label="Filtra per tipo" style={{ display:'flex', gap:6, marginBottom:14, flexWrap:'wrap' }}>
        {FILTERS.map(([k, l]) => (
          <Btn key={k || 'all'} size="sm" variant={kind === k ? 'primary' : 'default'} aria-pressed={kind === k} onClick={() => setKind(k)}>{l}</Btn>
        ))}
      </div>
      {error ? <ErrorState onRetry={load}/>
        : data == null ? <div style={{ display:'flex', justifyContent:'center', padding:32 }}><Spinner/></div>
        : !items.length ? <EmptyState icon={Lightbulb} title={openOnly ? 'Niente da gestire' : 'Nessun suggerimento'} text="Suggerimenti e feedback inviati dall'app dei cittadini compaiono qui."/>
        : <ul style={{ listStyle:'none', margin:0, padding:0, display:'flex', flexDirection:'column', gap:10 }}>{items.map(r => <ReportCard key={r.id} r={r} onChange={change}/>)}</ul>}
    </section>
  )
}
