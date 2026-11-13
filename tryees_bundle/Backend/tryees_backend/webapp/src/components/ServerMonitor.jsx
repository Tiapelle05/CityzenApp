import React, { useState, useEffect, useCallback, useRef } from 'react'
import { Cpu, MemoryStick, HardDrive, Film, CheckCircle2, AlertTriangle, AlertCircle, Trash2 } from 'lucide-react'
import { fetchServerStatus, runVideoCleanup } from '../lib/api'
import { Spinner, Btn, ErrorState, useConfirm, fmtTime, fmtDateTime } from './ui.jsx'
import { toast } from './Shared.jsx'

const POLL_MS = 5000
const WINDOW_S = 30 * 60          // storia della CPU conservata dal backend (app/services/server_monitor.py)
const WARN_PCT = 75, CRIT_PCT = 90

// Il riempimento del misuratore porta la gravità; la traccia è un passo più chiaro della stessa tinta
const LEVELS = {
  ok:   { fill:'var(--accent)',       track:'var(--accent-dim)', bg:'var(--accent-light)', c:'var(--accent)' },
  warn: { fill:'var(--sev-med-mark)', track:'var(--yellow-mid)', bg:'var(--yellow-light)', c:'var(--yellow)', border:'var(--yellow-mid)', label:'Elevato', icon:AlertTriangle },
  crit: { fill:'var(--red)',          track:'var(--red-mid)',    bg:'var(--red-light)',    c:'var(--red)',    border:'var(--red-mid)',    label:'Critico', icon:AlertCircle },
}
const levelOf = v => v == null ? 'ok' : v >= CRIT_PCT ? 'crit' : v >= WARN_PCT ? 'warn' : 'ok'

// ── Numeri e durate ───────────────────────────────────────────
const fmtPct = v => v == null ? '—' : `${Math.round(v)}%`
const fmtNum = (v, digits = 1) => Number(v).toLocaleString('it-IT', { maximumFractionDigits:digits })
const hhmm = t => new Date(t * 1000).toLocaleTimeString('it-IT', { hour:'2-digit', minute:'2-digit' })
const hhmmss = t => new Date(t * 1000).toLocaleTimeString('it-IT', { hour:'2-digit', minute:'2-digit', second:'2-digit' })
const cap = s => s.charAt(0).toUpperCase() + s.slice(1)
const nDeleted = n => n === 1 ? '1 file eliminato' : `${fmtNum(n, 0)} file eliminati`

function fmtBytes(n) {
  if (n == null) return '—'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  let v = n, i = 0
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
  return `${fmtNum(v, v >= 100 || i === 0 ? 0 : 1)} ${units[i]}`
}
/** 3600 -> "un'ora", 300 -> "5 minuti", 30 -> "30 secondi" */
function fmtSpan(seconds) {
  if (seconds % 3600 === 0) { const h = seconds / 3600; return h === 1 ? "un'ora" : `${h} ore` }
  if (seconds % 60 === 0) { const m = seconds / 60; return m === 1 ? 'un minuto' : `${m} minuti` }
  return `${seconds} secondi`
}
function fmtElapsed(ms) {
  const m = Math.floor(ms / 60000)
  if (m < 1) return 'meno di un minuto'
  if (m < 60) return `${m} min`
  const h = Math.floor(m / 60)
  return h < 48 ? `${h} h` : `${Math.floor(h / 24)} giorni`
}
function timeUntil(iso, now) {
  const s = Math.round((new Date(iso).getTime() - now) / 1000)
  if (s <= 0) return 'a momenti'
  return s < 60 ? 'tra meno di un minuto' : `tra ${Math.round(s / 60)} min`
}

/** Stato del server, riletto ogni 5 s finché la scheda del browser è in primo piano. */
function useServerStatus() {
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)
  const load = useCallback(() => fetchServerStatus().then(d => { setData(d); setError(null) }).catch(e => setError(e.message)), [])
  useEffect(() => {
    load()
    const id = setInterval(() => { if (!document.hidden) load() }, POLL_MS)
    return () => clearInterval(id)
  }, [load])
  return { data, error, reload: load }
}

export default function ServerMonitor() {
  const { data, error, reload } = useServerStatus()
  const [dialog, ask] = useConfirm()
  const [cleaning, setCleaning] = useState(false)

  if (!data) {
    return error
      ? <ErrorState title="Stato del server non disponibile" text={error} onRetry={reload}/>
      : <div style={{ display:'flex', justifyContent:'center', padding:48 }}><Spinner/></div>
  }

  const { cpu, memory, disk, uploads, retention, history } = data
  const now = new Date(data.timestamp).getTime()   // orologio del server: i tempi relativi non dipendono da quello del browser
  const maxAge = fmtSpan(retention.retention_minutes * 60)

  async function cleanup() {
    if (!(await ask({ title:'Eliminare ora le clip scadute?', message:`Le clip video più vecchie di ${maxAge} vengono eliminate subito, senza aspettare il prossimo controllo automatico. L'operazione non è annullabile.`, confirmLabel:'Elimina clip', tone:'danger', icon:Trash2 }))) return
    setCleaning(true)
    try {
      const r = await runVideoCleanup()
      if (r.errors) toast(`${r.errors} file non sono stati eliminati: controlla i permessi della cartella uploads/videos.`, 'warning')
      toast(r.deleted_files ? `${nDeleted(r.deleted_files)}, ${fmtBytes(r.freed_bytes)} liberati.` : 'Nessuna clip scaduta da eliminare.', 'success')
      await reload()
    } catch (e) { toast(e.message, 'danger', { title:'Pulizia non riuscita' }) }
    finally { setCleaning(false) }
  }

  return (
    <div className="te-stack" style={{ maxWidth:1120 }}>
      <StatusBanner data={data} now={now} error={error} onRetry={reload}/>

      {!cpu && (
        <p role="status" style={{ padding:'10px 16px', background:'var(--yellow-light)', border:'1px solid var(--yellow-mid)', borderRadius:'var(--r-md)', fontSize:13, color:'var(--text-2)' }}>
          CPU e memoria non sono disponibili: sul server manca il pacchetto <code>psutil</code>. Ricostruisci l'immagine del backend con <code>docker compose up -d --build backend</code>.
        </p>
      )}

      <div className="te-grid-4">
        <Tile icon={Cpu} label="CPU" value={fmtPct(cpu?.percent)} percent={cpu?.percent}
          caption={!cpu ? 'Non disponibile' : cpu.percent == null ? 'Prima lettura in corso…' : `${cpu.cores} core${cpu.load_avg ? ` · carico medio ${fmtNum(cpu.load_avg[0], 2)}` : ''}`}/>
        <Tile icon={MemoryStick} label="Memoria" value={fmtPct(memory?.percent)} percent={memory?.percent}
          caption={memory ? `${fmtBytes(memory.used)} di ${fmtBytes(memory.total)}` : 'Non disponibile'}/>
        <Tile icon={HardDrive} label="Disco" value={fmtPct(disk.percent)} percent={disk.percent}
          caption={`${fmtBytes(disk.free)} liberi di ${fmtBytes(disk.total)}`}/>
        <Tile icon={Film} label="Clip video su disco" value={fmtBytes(uploads.videos.bytes)}
          caption={uploads.videos.files ? `${fmtNum(uploads.videos.files, 0)} file · il più vecchio ha ${fmtElapsed(now - new Date(uploads.videos.oldest_at).getTime())}` : 'Nessun file'}/>
      </div>

      {cpu && <CpuCard cpu={cpu} samples={history.samples}/>}

      <div className="te-grid-2" style={{ alignItems:'start' }}>
        <StorageCard disk={disk} uploads={uploads} retention={retention}/>
        <RetentionCard retention={retention} startedAt={data.started_at} now={now} busy={cleaning} onCleanup={cleanup}/>
      </div>
      <PracticeRetentionCard practices={retention.practices}/>
      {dialog}
    </div>
  )
}

// ── Esito complessivo ─────────────────────────────────────────
function StatusBanner({ data, now, error, onRetry }) {
  const metrics = [['CPU', data.cpu?.percent], ['memoria', data.memory?.percent], ['disco', data.disk.percent]]
  const issues = metrics.filter(([, v]) => levelOf(v) !== 'ok')
  const level = issues.some(([, v]) => levelOf(v) === 'crit') ? 'crit' : issues.length ? 'warn' : 'ok'
  const m = level === 'ok'
    ? { icon:CheckCircle2, c:'var(--green)', bg:'var(--green-light)', border:'var(--green-mid)' }
    : LEVELS[level]
  const title = { ok:'Server in salute', warn:'Risorse sotto pressione', crit:'Risorse quasi esaurite' }[level]
  return (
    <div role="status" style={{ display:'flex', alignItems:'center', gap:12, padding:'12px 16px', background:m.bg, border:`1px solid ${m.border}`, borderRadius:'var(--r-md)', flexWrap:'wrap' }}>
      <m.icon size={20} color={m.c} aria-hidden="true"/>
      <span style={{ fontSize:15, fontWeight:700, color:m.c }}>{title}</span>
      <span style={{ fontSize:13, color:'var(--text-2)' }}>
        {issues.length ? issues.map(([name, v]) => `${name} ${fmtPct(v)}`).join(' · ') : data.boot_time ? `In funzione da ${fmtElapsed(now - new Date(data.boot_time).getTime())}` : ''}
      </span>
      {error ? (
        <>
          <span style={{ fontSize:13, color:'var(--text-2)', marginLeft:'auto' }}>Aggiornamento non riuscito: dati delle {fmtTime(data.timestamp)}</span>
          <Btn size="sm" variant="secondary" onClick={onRetry}>Riprova</Btn>
        </>
      ) : <span style={{ fontSize:13, color:'var(--text-3)', marginLeft:'auto' }}>Aggiornato alle {fmtTime(data.timestamp)}</span>}
    </div>
  )
}

// ── Riquadri: valore, misuratore, dettaglio ───────────────────
/** Senza percent (clip video) o con percent null (misura non disponibile) il misuratore non compare. */
function Tile({ icon:Icon, label, value, percent, caption }) {
  const lv = LEVELS[levelOf(percent)]
  return (
    <div className="te-card" style={{ padding:'16px 18px', minWidth:0 }}>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', gap:8, marginBottom:10 }}>
        <span style={{ fontSize:13, fontWeight:500, color:'var(--text-3)' }}>{label}</span>
        <span style={{ width:34, height:34, borderRadius:'var(--r-sm)', background:lv.bg, color:lv.c, display:'inline-flex', alignItems:'center', justifyContent:'center', flexShrink:0 }}>
          <Icon size={17} strokeWidth={2} aria-hidden="true"/>
        </span>
      </div>
      <div style={{ fontSize:26, fontWeight:700, lineHeight:1.15 }}>{value}</div>
      {percent != null && (
        <div role="meter" aria-label={label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(percent)}
          style={{ height:8, marginTop:10, borderRadius:4, background:lv.track, overflow:'hidden' }}>
          <div style={{ width:`${Math.min(100, percent)}%`, minWidth:percent > 0 ? 4 : 0, height:'100%', borderRadius:4, background:lv.fill, transition:'width .4s ease' }}/>
        </div>
      )}
      <div style={{ display:'flex', alignItems:'center', gap:6, flexWrap:'wrap', marginTop:8, fontSize:12, color:'var(--text-3)' }}>
        {lv.label && <span className="te-chip" style={{ background:lv.bg, color:lv.c }}><lv.icon size={12} strokeWidth={2.5} aria-hidden="true"/>{lv.label}</span>}
        <span>{caption}</span>
      </div>
    </div>
  )
}

// ── CPU: andamento e dettaglio per core ───────────────────────
function CpuCard({ cpu, samples }) {
  const values = samples.map(s => s[1])
  const peak = samples.reduce((a, s) => (!a || s[1] > a[1] ? s : a), null)
  return (
    <section className="te-card te-card--pad" aria-labelledby="cpu-title">
      <div style={{ display:'flex', justifyContent:'space-between', alignItems:'baseline', gap:12, flexWrap:'wrap', marginBottom:12 }}>
        <div>
          <h2 id="cpu-title" className="te-card-title">Utilizzo della CPU</h2>
          <div className="te-card-sub">Ultimi 30 minuti, una lettura ogni 5 secondi</div>
        </div>
        {samples.length > 1 && (
          <div style={{ fontSize:13, color:'var(--text-3)' }}>
            Media <strong style={{ color:'var(--text-1)' }}>{fmtPct(values.reduce((a, b) => a + b, 0) / values.length)}</strong>
            {' · '}Picco <strong style={{ color:'var(--text-1)' }}>{fmtPct(peak[1])}</strong> alle {hhmm(peak[0])}
          </div>
        )}
      </div>
      {samples.length > 1
        ? <CpuChart samples={samples}/>
        : <p style={{ fontSize:13, color:'var(--text-3)', padding:'32px 0' }}>Raccolta delle prime letture in corso…</p>}

      {cpu.per_core.length > 0 && (
        <>
          <h3 style={{ fontSize:13, fontWeight:600, color:'var(--text-2)', margin:'20px 0 10px' }}>Adesso, per core</h3>
          <ul style={{ listStyle:'none', display:'grid', gridTemplateColumns:'repeat(auto-fill, minmax(170px, 1fr))', gap:'8px 24px' }}>
            {cpu.per_core.map((v, i) => (
              <li key={i} style={{ display:'flex', alignItems:'center', gap:8, fontSize:12, color:'var(--text-3)' }}>
                <span style={{ width:46, flexShrink:0 }}>Core {i + 1}</span>
                <span aria-hidden="true" style={{ flex:1, height:6, borderRadius:3, background:'var(--accent-dim)', overflow:'hidden' }}>
                  <span style={{ display:'block', width:`${Math.min(100, v)}%`, height:'100%', borderRadius:3, background:'var(--accent)', transition:'width .4s ease' }}/>
                </span>
                <span className="tnum" style={{ width:34, flexShrink:0, textAlign:'right', fontWeight:500, color:'var(--text-1)' }}>{fmtPct(v)}</span>
              </li>
            ))}
          </ul>
        </>
      )}
    </section>
  )
}

/**
 * Area su asse fisso 0–100% e finestra fissa di 30 minuti che termina all'ultima lettura:
 * appena avviato il backend la curva occupa solo il bordo destro e cresce verso sinistra.
 * Il cursore (o le frecce da tastiera) aggancia la lettura più vicina.
 */
function CpuChart({ samples }) {
  const ref = useRef(null)
  const [hover, setHover] = useState(null)
  const end = samples[samples.length - 1][0], start = end - WINDOW_S
  const pts = samples.filter(s => s[0] >= start)
  const x = t => ((t - start) / WINDOW_S) * 100
  const y = v => 100 - Math.max(0, Math.min(100, v))
  const line = pts.map(([t, v], i) => `${i ? 'L' : 'M'}${x(t).toFixed(2)},${y(v).toFixed(2)}`).join(' ')
  const sel = hover != null && hover < pts.length ? pts[hover] : null
  const last = pts[pts.length - 1]

  function pick(e) {
    const r = ref.current.getBoundingClientRect()
    const t = start + ((e.clientX - r.left) / r.width) * WINDOW_S
    let best = 0
    pts.forEach((p, i) => { if (Math.abs(p[0] - t) < Math.abs(pts[best][0] - t)) best = i })
    setHover(best)
  }
  function onKey(e) {
    const step = { ArrowLeft:-1, ArrowRight:1 }[e.key]
    if (!step) return
    e.preventDefault()
    setHover(h => Math.max(0, Math.min(pts.length - 1, (h ?? pts.length - 1) + step * (e.shiftKey ? 12 : 1))))
  }
  const dot = { position:'absolute', width:12, height:12, borderRadius:'50%', background:'var(--accent)', border:'2px solid var(--bg-2)', transform:'translate(-50%, -50%)', pointerEvents:'none' }

  // Media per minuto: la stessa serie in forma di tabella, per chi non vede il grafico
  const byMinute = new Map()
  pts.forEach(([t, v]) => { const k = Math.floor(t / 60) * 60, b = byMinute.get(k) || [0, 0]; byMinute.set(k, [b[0] + v, b[1] + 1]) })

  return (
    <>
      <div ref={ref} tabIndex={0} role="group" aria-label="Andamento dell'utilizzo della CPU negli ultimi 30 minuti. Frecce sinistra e destra per leggere le singole letture."
        onPointerMove={pick} onPointerLeave={() => setHover(null)} onFocus={() => setHover(h => h ?? pts.length - 1)} onBlur={() => setHover(null)} onKeyDown={onKey}
        style={{ position:'relative', height:180, margin:'8px 8px 0 44px', cursor:'crosshair', touchAction:'pan-y' }}>
        <svg viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true" style={{ position:'absolute', inset:0, width:'100%', height:'100%', overflow:'visible' }}>
          {[0, 25, 50, 75, 100].map(v => <line key={v} x1="0" x2="100" y1={y(v)} y2={y(v)} stroke={v ? 'var(--bg-4)' : 'var(--border-2)'} strokeWidth="1" vectorEffect="non-scaling-stroke"/>)}
          <path d={`${line} L${x(last[0]).toFixed(2)},100 L${x(pts[0][0]).toFixed(2)},100 Z`} fill="var(--accent)" fillOpacity=".1"/>
          <path d={line} fill="none" stroke="var(--accent)" strokeWidth="2" vectorEffect="non-scaling-stroke" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
        {[0, 50, 100].map(v => (
          <span key={v} aria-hidden="true" className="tnum" style={{ position:'absolute', right:'100%', top:`${y(v)}%`, transform:'translateY(-50%)', paddingRight:8, fontSize:12, color:'var(--text-3)', whiteSpace:'nowrap' }}>{v}%</span>
        ))}
        <span style={{ ...dot, left:`${x(last[0])}%`, top:`${y(last[1])}%` }}/>
        {sel && (
          <>
            <span style={{ position:'absolute', top:0, bottom:0, left:`${x(sel[0])}%`, width:1, background:'var(--border-3)', pointerEvents:'none' }}/>
            <span style={{ ...dot, left:`${x(sel[0])}%`, top:`${y(sel[1])}%` }}/>
            <div role="status" style={{ position:'absolute', top:4, left:`${x(sel[0])}%`, transform:`translateX(${x(sel[0]) > 75 ? 'calc(-100% - 10px)' : '10px'})`, padding:'6px 10px', background:'var(--bg-2)', border:'1px solid var(--border)', borderRadius:'var(--r-sm)', boxShadow:'var(--shadow-md)', fontSize:13, whiteSpace:'nowrap', pointerEvents:'none' }}>
              <strong>{fmtPct(sel[1])}</strong> <span style={{ color:'var(--text-3)' }}>alle {hhmmss(sel[0])}</span>
            </div>
          </>
        )}
      </div>
      <div aria-hidden="true" className="tnum" style={{ display:'flex', justifyContent:'space-between', margin:'6px 8px 0 44px', fontSize:12, color:'var(--text-3)' }}>
        <span>{hhmm(start)}</span><span>{hhmm(start + WINDOW_S / 2)}</span><span>{hhmm(end)}</span>
      </div>
      <table className="sr-only">
        <caption>Utilizzo medio della CPU, minuto per minuto</caption>
        <thead><tr><th scope="col">Ora</th><th scope="col">CPU</th></tr></thead>
        <tbody>{[...byMinute].map(([t, [sum, n]]) => <tr key={t}><td>{hhmm(t)}</td><td>{fmtPct(sum / n)}</td></tr>)}</tbody>
      </table>
    </>
  )
}

// ── Spazio su disco ───────────────────────────────────────────
function StorageCard({ disk, uploads, retention }) {
  const keep = retention.enabled ? cap(fmtSpan(retention.retention_minutes * 60)) : 'Senza scadenza'
  const rows = [
    ['Clip video', uploads.videos, keep],
    ['Snapshot delle telecamere', uploads.snapshots, 'Senza scadenza'],
    ['Clip dimostrativa del modellino', uploads.mock_videos, 'Senza scadenza'],
  ]
  return (
    <section className="te-card" style={{ overflow:'hidden' }} aria-labelledby="storage-title">
      <div style={{ padding:'20px 20px 16px' }}>
        <h2 id="storage-title" className="te-card-title">Spazio su disco</h2>
        <div className="te-card-sub" style={{ marginBottom:14 }}>Il disco su cui il server salva clip e snapshot</div>
        <dl className="te-dl" style={{ gridTemplateColumns:'repeat(3, minmax(0, 1fr))' }}>
          <div><dt>Capacità</dt><dd>{fmtBytes(disk.total)}</dd></div>
          <div><dt>Occupato</dt><dd>{fmtBytes(disk.used)}</dd></div>
          <div><dt>Libero</dt><dd>{fmtBytes(disk.free)}</dd></div>
        </dl>
      </div>
      <div className="te-table-wrap">
        <table className="te-table">
          <caption className="sr-only">Spazio occupato dalle cartelle di upload</caption>
          <thead><tr><th scope="col">Cartella</th><th scope="col" style={{ textAlign:'right' }}>File</th><th scope="col" style={{ textAlign:'right' }}>Dimensione</th><th scope="col">Conservazione</th></tr></thead>
          <tbody>
            {rows.map(([name, u, kept]) => (
              <tr key={name}>
                <td>{name}</td>
                <td className="tnum" style={{ textAlign:'right' }}>{fmtNum(u.files, 0)}</td>
                <td className="tnum" style={{ textAlign:'right', fontWeight:600 }}>{fmtBytes(u.bytes)}</td>
                <td style={{ color:'var(--text-3)' }}>{kept}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  )
}

// ── Cancellazione automatica delle clip ───────────────────────
function RetentionCard({ retention, startedAt, now, busy, onCleanup }) {
  const { enabled, last_run: last, totals } = retention
  const outcome = !last ? 'Non ancora eseguito'
    : `Alle ${fmtTime(last.at)} · ${last.deleted_files ? `${nDeleted(last.deleted_files)}, ${fmtBytes(last.freed_bytes)} liberati` : 'nessuna clip scaduta'}${last.errors ? ` · ${last.errors} non eliminati` : ''}`
  return (
    <section className="te-card te-card--pad" aria-labelledby="retention-title">
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', gap:8, marginBottom:6 }}>
        <h2 id="retention-title" className="te-card-title">Cancellazione automatica delle clip</h2>
        {enabled
          ? <span className="te-chip" style={{ background:'var(--green-light)', color:'var(--green)' }}><CheckCircle2 size={12} strokeWidth={2.5} aria-hidden="true"/>Attiva</span>
          : <span className="te-chip" style={{ background:'var(--bg-4)', color:'var(--text-3)' }}>Disattivata</span>}
      </div>
      {enabled ? (
        <>
          <p style={{ fontSize:13, color:'var(--text-2)', marginBottom:16 }}>
            Le clip video più vecchie di <strong style={{ color:'var(--text-1)' }}>{fmtSpan(retention.retention_minutes * 60)}</strong> vengono eliminate insieme alla loro anteprima. Controllo ogni {fmtSpan(retention.interval_seconds)}.
          </p>
          <dl className="te-dl" style={{ marginBottom:16 }}>
            <div><dt>Ultimo controllo</dt><dd>{outcome}</dd></div>
            <div><dt>Prossimo controllo</dt><dd>{retention.next_run_at ? cap(timeUntil(retention.next_run_at, now)) : '—'}</dd></div>
            <div><dt>Eliminati dall'avvio del backend</dt><dd>{fmtNum(totals.deleted_files, 0)} file · {fmtBytes(totals.freed_bytes)}</dd></div>
            <div><dt>Backend avviato</dt><dd>{fmtDateTime(startedAt)}</dd></div>
          </dl>
          <Btn variant="secondary" icon={<Trash2 size={15}/>} loading={busy} onClick={onCleanup}>Elimina ora le clip scadute</Btn>
        </>
      ) : (
        <p style={{ fontSize:13, color:'var(--text-2)' }}>
          Le clip restano sul disco finché non vengono rimosse a mano. Per attivarla imposta <code>VIDEO_RETENTION_MINUTES</code> nel file <code>.env</code> del backend e riavvialo.
        </p>
      )}
    </section>
  )
}

// ── Cancellazione automatica delle segnalazioni ───────────────
function PracticeRetentionCard({ practices }) {
  const { enabled, last_run: last, totals } = practices
  return (
    <section className="te-card te-card--pad" aria-labelledby="practice-retention-title">
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', gap:8, marginBottom:6 }}>
        <h2 id="practice-retention-title" className="te-card-title">Cancellazione automatica delle segnalazioni</h2>
        {enabled
          ? <span className="te-chip" style={{ background:'var(--green-light)', color:'var(--green)' }}><CheckCircle2 size={12} strokeWidth={2.5} aria-hidden="true"/>Attiva</span>
          : <span className="te-chip" style={{ background:'var(--bg-4)', color:'var(--text-3)' }}>Disattivata</span>}
      </div>
      {enabled ? (
        <>
          <p style={{ fontSize:13, color:'var(--text-2)', marginBottom:16 }}>
            Le segnalazioni vengono eliminate dal database insieme ai loro eventi, in qualunque stato si trovino:{' '}
            {practices.retention_hours > 0
              ? <>quelle con dati di telecamere o microfoni dopo <strong style={{ color:'var(--text-1)' }}>{fmtSpan(practices.retention_hours * 3600)}</strong></>
              : <>quelle con dati di telecamere o microfoni mai</>},{' '}
            {practices.retention_days_non_security > 0
              ? <>le altre (cestini, suolo, cittadini) dopo <strong style={{ color:'var(--text-1)' }}>{practices.retention_days_non_security === 1 ? 'un giorno' : `${practices.retention_days_non_security} giorni`}</strong>.</>
              : <>le altre (cestini, suolo, cittadini) mai.</>}
          </p>
          <dl className="te-dl">
            <div><dt>Ultimo controllo</dt><dd>{!last ? 'Non ancora eseguito' : `Alle ${fmtTime(last.at)} · ${last.deleted_practices ? `${fmtNum(last.deleted_practices, 0)} segnalazioni e ${fmtNum(last.deleted_events, 0)} eventi eliminati` : 'nessuna segnalazione scaduta'}`}</dd></div>
            <div><dt>Eliminati dall'avvio del backend</dt><dd>{fmtNum(totals.deleted_practices, 0)} segnalazioni · {fmtNum(totals.deleted_events, 0)} eventi</dd></div>
          </dl>
        </>
      ) : (
        <p style={{ fontSize:13, color:'var(--text-2)' }}>
          Segnalazioni ed eventi restano nel database senza scadenza. Per attivarla imposta <code>PRACTICE_RETENTION_HOURS</code> o <code>PRACTICE_RETENTION_DAYS_NON_SECURITY</code> nel file <code>.env</code> del backend e riavvialo.
        </p>
      )}
    </section>
  )
}
