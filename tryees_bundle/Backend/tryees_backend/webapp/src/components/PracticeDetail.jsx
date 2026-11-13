import React, { useState, useEffect } from 'react'
import { ArrowLeft, ArrowUpRight, UserCheck, CheckCircle2, XCircle, Trash2, Camera, Mic, Trash, Lightbulb, Sprout, Activity, Video, MousePointerClick, Siren, MessageSquare } from 'lucide-react'
import { StatusBadge, SeverityBadge, Ts, Spinner, Btn, Tabs, OverflowMenu, EmptyState, useConfirm, fmtDateTime, timeAgo, useNow, TYPE_LABEL, CATEGORY_LABEL, DANGER_LABELS, alarmLabel } from './ui.jsx'
import { AuditTrail, EscalationModal, toast } from './Shared.jsx'
import { apiUrl, deletePractice } from '../lib/api'

const TRANS  = { open:['in_progress','closed'], in_progress:['resolved','closed'], resolved:['closed'], closed:[] }
const TLABEL = { in_progress:'Prendi in carico', resolved:'Segna come risolta', closed:'Chiudi pratica' }
const TICON  = { in_progress:UserCheck, resolved:CheckCircle2, closed:XCircle }
const TDONE  = { in_progress:'presa in carico', resolved:'segnata come risolta', closed:'chiusa' }

/**
 * Dettaglio pratica condiviso (Polizia, Eco, Admin). `onClose` compare come "indietro" quando il pannello
 * è sovrapposto (tablet/smartphone). `canDelete`: solo admin (il backend risponde 403 agli altri).
 */
export default function PracticeDetail({ practice:p, loading, onUpdateStatus, onDeleted, onClose, canDelete, escalation = true, showActuators = true, transitions: transOverride, labels = {}, emptyText }) {
  const [updating,setU] = useState(null)
  const [tab,setTab]    = useState('eventi')
  const [showEsc,setEsc] = useState(false)
  const [dialog, ask] = useConfirm()
  const [note, setNote] = useState('')
  const now = useNow(30000)
  useEffect(() => { setNote('') }, [p?.id])

  if (loading) return <div style={{ display:'flex', alignItems:'center', justifyContent:'center', height:'100%' }}><Spinner size={24} label="Caricamento pratica"/></div>
  if (!p) return (
    <EmptyState icon={MousePointerClick} title="Seleziona una pratica" text={emptyText || "Scegli una voce dall'elenco o un segnaposto sulla mappa per vederne eventi, attivazioni e registro."}/>
  )

  const transitions = (transOverride || TRANS)[p.status] || []
  const [primary, ...secondary] = transitions
  const L = { ...TLABEL, ...labels }

  async function changeStatus(s) {
    if (s === 'closed' && !(await ask({ title:`Chiudere la pratica #${p.id}?`, message:'Una pratica chiusa non può essere riaperta dalla dashboard.', confirmLabel:L.closed, icon:XCircle }))) return
    setU(s)
    try { await onUpdateStatus(p.id, s, hasCitizen ? note.trim() || undefined : undefined); setNote(''); toast(`Pratica #${p.id} ${TDONE[s]}.`, 'success') }
    catch (e) { toast(e.message || 'Cambio di stato non riuscito.', 'danger', { title:'Stato non aggiornato' }) }
    finally { setU(null) }
  }
  async function doDelete() {
    if (!(await ask({ title:`Eliminare definitivamente la pratica #${p.id}?`, message:'La pratica e il suo registro verranno cancellati. L\'operazione non è annullabile.', confirmLabel:'Elimina', tone:'danger', icon:Trash2 }))) return
    try { await deletePractice(p.id); toast(`Pratica #${p.id} eliminata.`, 'success'); onDeleted?.(p.id) }
    catch (e) { toast(e.message || 'Eliminazione non riuscita.', 'danger', { title:'Eliminazione non consentita' }) }
  }

  const activeActuators = (p.actuators || []).filter(a => !a.resolved).length
  const events = [...(p.events || [])].sort((a, b) => new Date(b.sampling_time || b.transmission_time) - new Date(a.sampling_time || a.transmission_time))
  const lastEvent = events[0]
  const PrimaryIcon = primary && TICON[primary]
  const closed = p.status === 'closed'
  const hasCitizen = events.some(e => e.type === 'citizen')

  const menuItems = [
    ...secondary.map(s => ({ label:L[s], icon:TICON[s], onClick:() => changeStatus(s) })),
    canDelete && secondary.length > 0 && 'sep',
    canDelete && { label:'Elimina', icon:Trash2, danger:true, onClick:doDelete },
  ].filter(Boolean)

  return (
    <div key={p.id} style={{ height:'100%', display:'flex', flexDirection:'column', overflow:'hidden', animation:'fadeIn .2s ease' }}>
      <div className="te-detail-head">
        {onClose && (
          <button type="button" className="te-btn te-btn--link te-only-overlay" onClick={onClose} style={{ alignSelf:'flex-start', marginLeft:-6, gap:4, fontSize:15 }}>
            <ArrowLeft size={18} aria-hidden="true"/>Torna all'elenco
          </button>
        )}
        <div className="te-detail-kicker">
          <span className="mono">#{p.id}</span>
          {p.category && <><span aria-hidden="true">·</span><span>{CATEGORY_LABEL[p.category] || p.category}</span></>}
          {p.zone && <><span aria-hidden="true">·</span><span>{p.zone}</span></>}
        </div>
        <h2 className="te-detail-title">{p.title}</h2>
        <div style={{ display:'flex', gap:8, flexWrap:'wrap' }}>
          <SeverityBadge value={p.severity} large/>
          <StatusBadge status={p.status} large/>
        </div>
        <dl className="te-dl" style={{ marginTop:4 }}>
          <div><dt>Aperta il</dt><dd>{fmtDateTime(p.created_at)}</dd></div>
          <div><dt>Ultimo evento</dt><dd title={lastEvent ? fmtDateTime(lastEvent.sampling_time || lastEvent.transmission_time) : undefined}>{lastEvent ? timeAgo(lastEvent.sampling_time || lastEvent.transmission_time, now) : '—'}</dd></div>
          <div><dt>Eventi collegati</dt><dd>{events.length}</dd></div>
          {p.lat != null && <div><dt>Coordinate</dt><dd className="mono" style={{ fontSize:12 }}>{p.lat.toFixed(5)}, {p.lon.toFixed(5)}</dd></div>}
        </dl>
        {hasCitizen && !closed && transitions.length > 0 && (
          <div className="te-field">
            <label htmlFor={`citizen-note-${p.id}`} className="te-label">Nota per i cittadini <span style={{ fontWeight:400, color:'var(--text-3)' }}>(facoltativa)</span></label>
            <textarea id={`citizen-note-${p.id}`} className="te-textarea" rows={2} maxLength={500} value={note} onChange={e => setNote(e.target.value)}
              placeholder="Es. Intervento programmato per domani mattina" aria-describedby={`citizen-note-${p.id}-hint`}/>
            <span id={`citizen-note-${p.id}-hint`} className="te-hint">La vedono nell'app i cittadini che hanno segnalato il problema, insieme al prossimo cambio di stato. Niente note interne.</span>
          </div>
        )}
      </div>

      {(!closed || menuItems.length > 0) && (
        <div className="te-detail-actions">
          {primary
            ? <Btn variant="primary" onClick={() => changeStatus(primary)} loading={updating === primary} disabled={!!updating} icon={PrimaryIcon && <PrimaryIcon size={16}/>}>{L[primary]}</Btn>
            : <span style={{ flex:1 }}/>}
          {escalation && !closed && <Btn variant="danger" onClick={() => setEsc(true)} icon={<ArrowUpRight size={16}/>}>Escalation</Btn>}
          {menuItems.length > 0 && <OverflowMenu label="Altre azioni sulla pratica" items={menuItems}/>}
        </div>
      )}

      <Tabs label="Sezioni della pratica" idPrefix={`pr-${p.id}`} value={tab} onChange={setTab} tabs={[
        { key:'eventi', label:'Eventi', badge:<span className="te-count">{events.length}</span> },
        showActuators && { key:'attivazioni', label:'Attivazioni', badge: activeActuators
            ? <span className="te-count" style={{ background:'var(--red-light)', color:'var(--red)' }}>{activeActuators} {activeActuators === 1 ? 'attiva' : 'attive'}</span>
            : <span className="te-count">{p.actuators?.length || 0}</span> },
        { key:'audit', label:'Registro' },
      ].filter(Boolean)}/>

      <div className="te-detail-body" role="tabpanel" id={`pr-${p.id}-panel`} aria-labelledby={`pr-${p.id}-tab-${tab}`} tabIndex={0}>
        {tab === 'eventi' ? (
          !events.length
            ? <EmptyState title="Nessun evento" text="Gli eventi dei sensori collegati a questa pratica compariranno qui."/>
            : events.map(ev => <EventCard key={ev.id} ev={ev}/>)
        ) : tab === 'attivazioni' ? (
          !p.actuators?.length
            ? <EmptyState icon={Siren} title="Nessuna attivazione" text="Nessuna sirena o LED è stato attivato per questa pratica."/>
            : p.actuators.map((a, i) => (
              <div key={i} className="te-event" style={a.resolved ? undefined : { borderColor:'var(--red-mid)', background:'var(--red-light)' }}>
                <div className="te-event-head">
                  <span className="te-event-icon" style={{ background: a.resolved ? 'var(--bg-3)' : 'var(--bg-2)', color: a.resolved ? 'var(--text-3)' : 'var(--red)' }}><Siren size={16} aria-hidden="true"/></span>
                  <div style={{ flex:1, minWidth:0 }}>
                    <div style={{ fontSize:14, fontWeight:600 }}>{alarmLabel(a.alarm_type)}</div>
                    <div style={{ fontSize:12, color:'var(--text-3)' }}><span className="mono">{a.device_id}</span></div>
                  </div>
                  <Ts iso={a.timestamp}/>
                </div>
                <div style={{ display:'flex', gap:6, flexWrap:'wrap', fontSize:13 }}>
                  <span className="te-chip" style={{ background:'var(--bg-2)', color:'var(--text-2)' }}>Sirena {a.sirena_active ? 'accesa' : 'spenta'}</span>
                  <span className="te-chip" style={{ background:'var(--bg-2)', color:'var(--text-2)' }}>LED polizia {a.led_police_active ? 'acceso' : 'spento'}</span>
                  <span className="te-chip" style={a.resolved ? { background:'var(--green-light)', color:'var(--green)' } : { background:'var(--bg-2)', color:'var(--red)' }}>{a.resolved ? 'Riarmato' : 'Ancora attivo'}</span>
                </div>
              </div>
            ))
        ) : (
          <AuditTrail practiceId={p.id}/>
        )}
      </div>
      {showEsc && <EscalationModal practice={p} onClose={() => setEsc(false)}/>}
      {dialog}
    </div>
  )
}

const PRIORITY_LABEL = { low:'Bassa', medium:'Media', high:'Alta' }

function sourceOf(d, mac = '') {
  if (d?.report_code) return { icon:MessageSquare, label:'Cittadino' }
  if (/bin|basket/i.test(mac)) return { icon:Trash, label:'Cestino' }
  if (/cam/i.test(mac)) return { icon:Camera, label:'Telecamera IA' }
  if (!d) return { icon:Activity, label:'Sensore' }
  if (d.person_count != null || d.frame_url) return { icon:Camera, label:'Telecamera IA' }
  if (d.decibel != null || d.noise_db != null) return { icon:Mic, label:'Microfono' }
  if (d.fill_level_pct != null || d.fill_cm != null || d.tilt_angle != null || d.weight_kg != null) return { icon:Trash, label:'Cestino' }
  if (d.lux_value != null || d.lux_ldr != null || d.fault_code) return { icon:Lightbulb, label:'Lampione' }
  if (d.humidity_pct != null || d.pm25 != null || d.temperature_c != null) return { icon:Sprout, label:'Sensore ambiente' }
  return { icon:Activity, label:'Sensore' }
}

function metricsOf(d) {
  if (!d) return []
  const r = []
  const add = (k, v, warn = false) => r.push([k, v, warn])
  if (d.priority)               add('Priorità', PRIORITY_LABEL[d.priority] || d.priority, d.priority === 'high')
  if (d.person_count != null)   add('Persone', d.person_count, d.person_count > 2)
  if (d.confidence != null)     add('Confidenza', `${(d.confidence * 100).toFixed(0)}%`, d.confidence > 0.9)
  if (d.decibel != null)        add('Decibel', `${d.decibel} dB`, d.decibel > 85)
  if (d.noise_db != null)       add('Rumore (KY-038)', `${d.noise_db} dB`, d.noise_db > 85)
  if (d.fill_level_pct != null) add('Riempimento', `${d.fill_level_pct}%`, d.fill_level_pct > 85)
  if (d.fill_cm != null)        add('Distanza (VL53L0X)', `${d.fill_cm} cm`, d.fill_cm < 8)
  if (d.tilt_angle != null)     add('Inclinazione', `${d.tilt_angle}°`, d.tilt_angle > 45)
  if (d.weight_kg != null)      add('Peso', `${d.weight_kg} kg`)
  if (d.battery_pct != null)    add('Batteria', `${d.battery_pct}%`, d.battery_pct < 20)
  if (d.lux_value != null)      add('Luminosità', `${d.lux_value} lux`)
  if (d.lux_ldr != null)        add('Luce (LDR)', d.lux_ldr)
  if (d.fault_code)             add('Guasto', d.fault_code, true)
  if (d.humidity_pct != null)   add('Umidità', `${d.humidity_pct}%`, d.humidity_pct > 80)
  if (d.temperature_c != null)  add('Temperatura', `${d.temperature_c}°C`, d.temperature_c > 35)
  if (d.pm25 != null)           add('PM2.5', `${d.pm25} µg/m³`, d.pm25 > 25)
  if (d.pm10 != null)           add('PM10', `${d.pm10} µg/m³`, d.pm10 > 50)
  return r
}

function EventCard({ ev }) {
  const d = ev.detail
  const src = sourceOf(d, ev.mac_address)
  const title = (d?.alert_type && DANGER_LABELS[d.alert_type]) || TYPE_LABEL[ev.type] || String(ev.type || 'Evento').replace(/_/g, ' ')
  const danger = !!(d?.alert_type && DANGER_LABELS[d.alert_type]) || ev.type === 'alert' || ev.type === 'assistance'
  const tone = danger ? 'crit' : (ev.type === 'motion' || ev.type === 'full') ? 'med' : null
  const metrics = metricsOf(d)
  return (
    <article className="te-event">
      <div className="te-event-head">
        <span className="te-event-icon" style={tone ? { background:`var(--sev-${tone}-bg)`, color:`var(--sev-${tone})` } : { background:'var(--bg-3)', color:'var(--text-2)' }}>
          <src.icon size={16} aria-hidden="true"/>
        </span>
        <div style={{ flex:1, minWidth:0 }}>
          <div style={{ fontSize:14, fontWeight:600 }}>{title}</div>
          <div style={{ fontSize:12, color:'var(--text-3)', overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap' }}>{src.label} · <span className="mono">{d?.report_code || ev.mac_address}</span></div>
        </div>
        <Ts iso={ev.sampling_time || ev.transmission_time}/>
      </div>
      {ev.val_number != null && !metrics.length && <div style={{ fontSize:13, color:'var(--text-2)' }}>Valore rilevato: <strong>{ev.val_number}</strong></div>}
      {metrics.length > 0 && (
        <dl className="te-metrics">
          {metrics.map(([k, v, warn]) => (
            <div key={k} className="te-metric"><dt className="te-metric-k">{k}</dt><dd className={`te-metric-v${warn ? ' te-metric-v--warn' : ''}`} style={{ margin:0 }}>{v}</dd></div>
          ))}
        </dl>
      )}
      {d?.description && <p style={{ fontSize:13, color:'var(--text-2)', margin:0, whiteSpace:'pre-wrap', overflowWrap:'anywhere' }}>{d.description}</p>}
      {d?.photo_url && (
        <a href={apiUrl(d.photo_url)} target="_blank" rel="noreferrer" aria-label="Apri la foto della segnalazione in una nuova scheda">
          <img src={apiUrl(d.photo_url)} alt={`Foto della segnalazione ${d.report_code}`} loading="lazy" style={{ width:'100%', maxHeight:180, objectFit:'cover', borderRadius:'var(--r-sm)', border:'1px solid var(--border)', display:'block' }}/>
        </a>
      )}
      {d?.frame_url && (
        <a href={d.frame_url} target="_blank" rel="noreferrer" aria-label="Apri lo snapshot dell'evento in una nuova scheda">
          <img src={d.frame_url} alt={`Snapshot: ${title}`} loading="lazy" style={{ width:'100%', maxHeight:180, objectFit:'cover', borderRadius:'var(--r-sm)', border:'1px solid var(--border)', display:'block' }}/>
        </a>
      )}
      {ev.video?.video_url && (
        <a href={ev.video.video_url} target="_blank" rel="noreferrer" className="te-btn te-btn--secondary te-btn--sm" style={{ alignSelf:'flex-start' }}>
          <Video size={15} aria-hidden="true"/>Apri clip video
        </a>
      )}
    </article>
  )
}

