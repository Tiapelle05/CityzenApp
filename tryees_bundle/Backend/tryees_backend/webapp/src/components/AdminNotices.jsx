import React, { useState, useEffect, useCallback } from 'react'
import { Megaphone, Trash2, CircleStop } from 'lucide-react'
import { fetchParks, fetchNotices, createNotice, updateNotice, deleteNotice } from '../lib/api'
import { Spinner, Btn, SectionTitle, EmptyState, ErrorState, useConfirm, fmtDateTime } from './ui.jsx'
import { toast } from './Shared.jsx'

/** Avvisi del parco mostrati ai cittadini nell'app (Home e Avvisi). Un avviso
 *  'alert' porta lo stato del parco ad "Attenzione": lo può pubblicare solo un admin. */

const LEVELS = { info:'Informazione', warning:'Avviso', alert:'Attenzione' }
const LEVEL_STYLE = {
  info:    { background:'var(--bg-3)', color:'var(--text-2)' },
  warning: { background:'var(--yellow-light)', color:'var(--yellow)' },
  alert:   { background:'var(--red-light)', color:'var(--red)' },
}
const STATE_LABEL = { active:'In corso', scheduled:'Programmato', expired:'Terminato' }
const EMPTY = { title:'', body:'', level:'info', starts_at:'', ends_at:'' }

// <input type="datetime-local"> lavora in ora locale senza fuso: si converte in ISO UTC per il backend
const toIso = v => v ? new Date(v).toISOString() : null

export default function AdminNotices() {
  const [parks, setParks] = useState([])
  const [parkId, setParkId] = useState(null)
  const [notices, setNotices] = useState(null)
  const [error, setError] = useState(null)
  const [showExpired, setShowExpired] = useState(false)
  const [form, setForm] = useState(EMPTY)
  const [touched, setTouched] = useState(false)
  const [saving, setSaving] = useState(false)
  const [dialog, ask] = useConfirm()
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  useEffect(() => {
    fetchParks().then(ps => { setParks(ps || []); if (ps?.length) setParkId(ps[0].id) }).catch(e => setError(e.message))
  }, [])

  const load = useCallback(() => {
    if (parkId == null) return
    setError(null)
    fetchNotices(parkId, showExpired).then(setNotices).catch(e => setError(e.message))
  }, [parkId, showExpired])
  useEffect(() => { load() }, [load])

  const missing = !form.title.trim() || !form.body.trim()
  const badWindow = form.starts_at && form.ends_at && new Date(form.ends_at) <= new Date(form.starts_at)
  const err = cond => touched && cond

  async function publish(e) {
    e.preventDefault(); setTouched(true)
    if (missing || badWindow) return
    if (form.level === 'alert' && !(await ask({ title:'Pubblicare un avviso di attenzione?', message:'Nell\'app lo stato del parco passerà ad "Attenzione" finché l\'avviso è in corso.', confirmLabel:'Pubblica', icon:Megaphone }))) return
    setSaving(true)
    try {
      await createNotice(parkId, { title:form.title.trim(), body:form.body.trim(), level:form.level, starts_at:toIso(form.starts_at), ends_at:toIso(form.ends_at) })
      toast('Avviso pubblicato.', 'success'); setForm(EMPTY); setTouched(false); load()
    } catch (e2) { toast(e2.message, 'danger', { title:'Pubblicazione non riuscita' }) }
    finally { setSaving(false) }
  }
  async function stop(n) {
    try { await updateNotice(parkId, n.id, { ends_at:new Date().toISOString() }); toast('Avviso terminato.', 'success'); load() }
    catch (e) { toast(e.message, 'danger', { title:'Avviso non terminato' }) }
  }
  async function remove(n) {
    if (!(await ask({ title:`Eliminare l'avviso «${n.title}»?`, message:'Sparisce subito dall\'app dei cittadini. L\'operazione non è annullabile.', confirmLabel:'Elimina', tone:'danger', icon:Trash2 }))) return
    try { await deleteNotice(parkId, n.id); toast('Avviso eliminato.', 'success'); load() }
    catch (e) { toast(e.message, 'danger', { title:'Eliminazione non riuscita' }) }
  }

  return (
    <div className="te-grid-2 te-grid-2--main-side" style={{ maxWidth:1080, alignItems:'start' }}>
      <section className="te-card te-card--pad" aria-labelledby="ntc-list-title">
        <SectionTitle as="h2" action={
          <label style={{ display:'inline-flex', alignItems:'center', gap:6, fontSize:13, color:'var(--text-2)' }}>
            <input type="checkbox" checked={showExpired} onChange={e => setShowExpired(e.target.checked)}/>Mostra terminati
          </label>
        }><span id="ntc-list-title">Avvisi per i cittadini</span></SectionTitle>
        {parks.length > 1 && (
          <div className="te-field" style={{ marginBottom:12, maxWidth:280 }}>
            <label htmlFor="ntc-park" className="te-label">Parco</label>
            <select id="ntc-park" className="te-select" value={parkId ?? ''} onChange={e => setParkId(Number(e.target.value))}>
              {parks.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </div>
        )}
        {error ? <ErrorState onRetry={load}/>
          : notices == null ? <div style={{ display:'flex', justifyContent:'center', padding:32 }}><Spinner/></div>
          : !notices.length ? <EmptyState icon={Megaphone} title="Nessun avviso" text="Gli avvisi pubblicati qui compaiono nella Home dell'app dei cittadini."/>
          : (
            <ul style={{ listStyle:'none', margin:0, padding:0, display:'flex', flexDirection:'column', gap:10 }}>
              {notices.map(n => (
                <li key={n.id} className="te-event" style={n.state === 'expired' ? { opacity:.65 } : undefined}>
                  <div style={{ display:'flex', gap:8, alignItems:'center', flexWrap:'wrap' }}>
                    <span className="te-chip" style={LEVEL_STYLE[n.level]}>{LEVELS[n.level]}</span>
                    <span className="te-chip" style={{ background:'var(--bg-2)', color:'var(--text-2)' }}>{STATE_LABEL[n.state]}</span>
                    <strong style={{ fontSize:14, flex:1, minWidth:160 }}>{n.title}</strong>
                  </div>
                  <p style={{ margin:0, fontSize:13, color:'var(--text-2)', whiteSpace:'pre-wrap', overflowWrap:'anywhere' }}>{n.body}</p>
                  <div style={{ display:'flex', gap:8, alignItems:'center', flexWrap:'wrap', fontSize:12, color:'var(--text-3)' }}>
                    <span style={{ flex:1, minWidth:200 }}>
                      Dal {fmtDateTime(n.starts_at)}{n.ends_at ? ` al ${fmtDateTime(n.ends_at)}` : ', senza scadenza'}{n.created_by ? ` · ${n.created_by}` : ''}
                    </span>
                    {n.state !== 'expired' && <Btn size="sm" onClick={() => stop(n)} icon={<CircleStop size={15}/>}>Termina ora</Btn>}
                    <Btn size="sm" variant="danger" onClick={() => remove(n)} icon={<Trash2 size={15}/>} ariaLabel={`Elimina l'avviso ${n.title}`}>Elimina</Btn>
                  </div>
                </li>
              ))}
            </ul>
          )}
      </section>

      <section className="te-card te-card--pad" aria-labelledby="ntc-new-title">
        <SectionTitle as="h2"><span id="ntc-new-title">Nuovo avviso</span></SectionTitle>
        <form onSubmit={publish} noValidate style={{ display:'flex', flexDirection:'column', gap:14 }}>
          <div className="te-field">
            <label htmlFor="ntc-title" className="te-label">Titolo</label>
            <input id="ntc-title" className="te-input" maxLength={120} value={form.title} onChange={e => set('title', e.target.value)} placeholder="Es. Manutenzione fontanelle" aria-invalid={err(!form.title.trim()) || undefined}/>
            {err(!form.title.trim()) && <span className="te-field-error">Campo obbligatorio.</span>}
          </div>
          <div className="te-field">
            <label htmlFor="ntc-body" className="te-label">Testo</label>
            <textarea id="ntc-body" className="te-textarea" rows={3} maxLength={1000} value={form.body} onChange={e => set('body', e.target.value)} placeholder="Es. Fontanelle della zona giochi chiuse fino alle 14." aria-invalid={err(!form.body.trim()) || undefined}/>
            {err(!form.body.trim()) && <span className="te-field-error">Campo obbligatorio.</span>}
          </div>
          <div className="te-field">
            <label htmlFor="ntc-level" className="te-label">Livello</label>
            <select id="ntc-level" className="te-select" value={form.level} onChange={e => set('level', e.target.value)} aria-describedby="ntc-level-hint">
              {Object.entries(LEVELS).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
            </select>
            <span id="ntc-level-hint" className="te-hint">"Attenzione" porta lo stato del parco ad Attenzione nell'app.</span>
          </div>
          <div style={{ display:'grid', gridTemplateColumns:'repeat(auto-fit,minmax(180px,1fr))', gap:14 }}>
            <div className="te-field">
              <label htmlFor="ntc-start" className="te-label">Inizio</label>
              <input id="ntc-start" type="datetime-local" className="te-input" value={form.starts_at} onChange={e => set('starts_at', e.target.value)} aria-describedby="ntc-start-hint"/>
              <span id="ntc-start-hint" className="te-hint">Vuoto: subito.</span>
            </div>
            <div className="te-field">
              <label htmlFor="ntc-end" className="te-label">Fine</label>
              <input id="ntc-end" type="datetime-local" className="te-input" value={form.ends_at} onChange={e => set('ends_at', e.target.value)} aria-invalid={err(badWindow) || undefined} aria-describedby="ntc-end-hint"/>
              <span id="ntc-end-hint" className={err(badWindow) ? 'te-field-error' : 'te-hint'}>{err(badWindow) ? 'La fine deve essere dopo l\'inizio.' : 'Vuoto: finché non lo termini.'}</span>
            </div>
          </div>
          <Btn type="submit" variant="primary" loading={saving} disabled={parkId == null} icon={<Megaphone size={16}/>}>Pubblica avviso</Btn>
        </form>
      </section>
      {dialog}
    </div>
  )
}
