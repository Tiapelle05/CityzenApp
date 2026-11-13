import React, { useState, useEffect, useCallback, useRef, useMemo, useId } from 'react'
import {
  Camera, Radar, Trash2, Thermometer, Droplets, Wind, Sprout, RotateCcw, BellRing, Shield, Activity,
  Video, Play, Footprints, Swords, HandHelping, Users, AlertTriangle, CheckCircle2, FlaskConical,
} from 'lucide-react'
import {
  apiUrl, miniTestTrigger, miniReset, fetchMiniSettings, updateMiniSettings, fetchMiniState,
  fetchEnvHistory, resetMiniAlarm, fetchMiniAlarms, fetchMiniVideos,
} from '../lib/api'
import {
  Spinner, Btn, StatCard, TopBar, Tabs, WsDot, Modal, DialogHeader, EmptyState, ErrorState,
  useConfirm, fmt1, fmtDateTime, alarmLabel, DANGER_LABELS,
} from './ui.jsx'
import { toast, ToastContainer } from './Shared.jsx'
import SoundButton, { triggerSound } from './SoundButton.jsx'
import { since } from './devices.jsx'

// ── I cinque dispositivi del modellino e dove stanno sulla mappa ─────────
const SLOTS = [
  { key:'cam_a',  label:'Telecamera A', sub:'Zona A', zone:'a', kind:'camera', icon:Camera, pos:{ left:'19%', top:'9%' },
    desc:"Riconosce armi, risse e richieste di aiuto nella zona A." },
  { key:'cam_b',  label:'Telecamera B', sub:'Zona B', zone:'b', kind:'camera', icon:Camera, pos:{ left:'81%', top:'9%' },
    desc:"Riconosce armi, risse e richieste di aiuto nella zona B." },
  { key:'node_a', label:'Varco A', sub:'Passaggi · sirena', zone:'a', kind:'node', icon:Radar, pos:{ left:'15%', top:'47%' },
    desc:"Conta i passaggi e comanda sirena e lampeggiante della zona A." },
  { key:'node_b', label:'Varco B', sub:'Passaggi · clima', zone:'b', kind:'node', icon:Radar, pos:{ left:'85%', top:'47%' },
    desc:"Conta i passaggi, comanda la sirena della zona B e misura temperatura, umidità, polveri e umidità del terreno." },
  { key:'bin',    label:'Cestino', sub:'Riempimento · urti', kind:'bin', icon:Trash2, pos:{ left:'50%', top:'90%' },
    desc:"Misura il riempimento e rileva urti o ribaltamenti." },
]
const NODE_TYPES = ['mini_node', 'mini_ambiente', 'mini_varchi']

function sensorFor(slot, sensors) {
  const inZone = s => new RegExp(`zona ${slot.zone}\\b`, 'i').test(s.zone || '')
  if (slot.kind === 'bin') return sensors.find(s => s.type === 'mini_bin')
  if (slot.kind === 'camera') return sensors.find(s => s.type === 'camera' && inZone(s))
  return sensors.find(s => NODE_TYPES.includes(s.type) && inZone(s))
}

// ── Letture: etichetta e formato per ogni valore inviato dal backend ─────
const pct = v => `${Math.round(v)} %`
const READING = {
  temperatura_c:     ['Temperatura', v => `${fmt1(v)} °C`],
  umidita_pct:       ["Umidità dell'aria", pct],
  umidita_suolo_pct: ['Umidità del terreno', pct],
  pm25:              ['Polveri PM2.5', v => `${fmt1(v)} µg/m³`],
  pm10:              ['Polveri PM10', v => `${fmt1(v)} µg/m³`],
  riempimento_pct:   ['Riempimento', pct],
  inclinazione_deg:  ['Inclinazione', v => `${Math.round(v)}°`],
  ultimo_varco:      ['Ultimo passaggio', v => ({ ingresso:'Ingresso', uscita:'Uscita' }[v] || String(v))],
  ultimo_evento:     ['Ultimo passaggio', v => ({ ingresso:'Ingresso', uscita:'Uscita' }[v] || String(v))],
  ultimo_alert:      ['Ultimo rilevamento', v => DANGER_LABELS[v] || String(v).replace(/_/g, ' ')],
  confidenza:        ['Confidenza', v => pct(v * 100)],
}
const readingRows = reading => Object.entries(reading || {})
  .filter(([, v]) => v != null)
  .map(([k, v]) => { const m = READING[k]; return m ? [m[0], m[1](v)] : [k.replace(/_/g, ' '), String(v)] })

// ── Simulazioni disponibili per ogni dispositivo ─────────────────────────
function actionsFor(slot) {
  if (slot.kind === 'camera') {
    const cam = alert_type => ({ kind:'camera_alert', zone:slot.zone, alert_type })
    return [
      { label:'Simula arma rilevata', icon:Swords, variant:'danger', payload:cam('oggetto_pericoloso') },
      { label:'Simula richiesta di aiuto', icon:HandHelping, payload:cam('segnale_aiuto') },
      { label:'Simula rissa', icon:Users, payload:cam('aggressione') },
    ]
  }
  if (slot.kind === 'node') return [
    { label:'Simula un passaggio', icon:Footprints, payload:{ kind:'ultrasonic', zone:slot.zone } },
    slot.zone === 'b' && { label:'Invia una lettura ambiente', icon:Thermometer, payload:{ kind:'environment' } },
  ].filter(Boolean)
  return [
    { label:'Simula cestino pieno (95 %)', icon:Trash2, payload:{ kind:'bin', fill_level_pct:95, tilt_angle_deg:2 } },
    { label:'Simula cestino svuotato (10 %)', icon:CheckCircle2, payload:{ kind:'bin', fill_level_pct:10, tilt_angle_deg:2 } },
    { label:'Simula ribaltamento (55°)', icon:AlertTriangle, variant:'danger', payload:{ kind:'bin', fill_level_pct:10, tilt_angle_deg:55 } },
  ]
}

// ── Soglie configurabili (stesse chiavi del backend) ─────────────────────
const FIELDS = [
  { key:'bin_full_pct', label:'Cestino pieno', unit:'%', min:1, max:100, hint:'Oltre questo riempimento il cestino viene segnalato come pieno.' },
  { key:'vandal_tilt_deg', label:'Allarme vandalismo', unit:'gradi', min:5, max:90, hint:"Inclinazione del cestino oltre la quale scatta l'allarme." },
  { key:'crowd_threshold', label:'Affollamento', unit:'passaggi', min:1, max:500, int:true, hint:"Passaggi in una zona nell'ultima ora oltre i quali scatta la segnalazione." },
  { key:'presence_light_seconds', label:'Durata delle luci', unit:'secondi', min:1, max:3600, int:true, hint:'Per quanto restano accese le luci dopo un passaggio.' },
]
const toForm = values => Object.fromEntries(FIELDS.map(f => [f.key, String(values?.[f.key] ?? '')]))
const fieldError = (f, raw) => {
  const n = Number(raw)
  if (raw === '' || Number.isNaN(n)) return 'Inserisci un numero.'
  if (n < f.min || n > f.max) return `Valore tra ${f.min} e ${f.max}.`
  if (f.int && !Number.isInteger(n)) return 'Serve un numero intero.'
  return null
}

const TABS = [
  { key:'stato', label:'Stato' },
  { key:'ambiente', label:'Ambiente' },
  { key:'allarmi', label:'Allarmi e video' },
  { key:'impostazioni', label:'Impostazioni' },
]
const POLL_MS = 3000, SSE_RETRY_MS = 30000, AUX_MS = 10000

export default function ModellinoDashboard({ onLogout, onSwitchRole, username, role = 'modellino' }) {
  const canControl = !!onSwitchRole            // simulazioni, soglie e azzeramento: solo amministratori
  const [dialog, ask] = useConfirm()
  const [tab, setTab] = useState('stato')
  const [state, setState] = useState(null)
  const [error, setError] = useState(false)
  const [live, setLive] = useState(false)
  const [selKey, setSelKey] = useState('node_a')
  const [busy, setBusy] = useState(null)
  const [history, setHistory] = useState(null)
  const [videos, setVideos] = useState(null)
  const [env, setEnv] = useState(null)
  const [clip, setClip] = useState(null)
  const seen = useRef(null)                     // id degli allarmi già notificati (null = primo caricamento)

  // ── Stato in tempo reale ────────────────────────────────────────────────
  const onState = useCallback(data => {
    if (!data) return
    const ids = new Set((data.active_alarms || []).map(a => a.id))
    if (seen.current) {
      const fresh = (data.active_alarms || []).filter(a => !seen.current.has(a.id))
      if (fresh.length) {
        triggerSound('alert')
        toast(fresh.map(a => alarmLabel(a.alarm_type)).filter((v, i, arr) => arr.indexOf(v) === i).join(', '), 'alert', { title: fresh.length === 1 ? 'Nuovo allarme' : `${fresh.length} nuovi allarmi` })
      }
    }
    seen.current = ids
    setState(data); setError(false)
  }, [])
  const loadState = useCallback(() => fetchMiniState().then(onState).catch(() => setError(true)), [onState])

  // Streaming; se cade si passa agli aggiornamenti periodici e si riprova a riconnettersi
  useEffect(() => {
    let es = null, poll = null, retry = null, dead = false
    const startPoll = () => { if (!poll) { loadState(); poll = setInterval(loadState, POLL_MS) } }
    const stopPoll = () => { clearInterval(poll); poll = null }
    const connect = () => {
      if (dead) return
      try { es = new EventSource(apiUrl('/mini/stream')) } catch { startPoll(); return }
      es.onopen = () => { setLive(true); stopPoll() }
      es.onmessage = e => { try { onState(JSON.parse(e.data)) } catch {} }
      es.onerror = () => { es.close(); setLive(false); startPoll(); clearTimeout(retry); retry = setTimeout(connect, SSE_RETRY_MS) }
    }
    connect()
    return () => { dead = true; es?.close(); stopPoll(); clearTimeout(retry) }
  }, [onState, loadState])

  // ── Storico allarmi, clip, andamento ambiente ───────────────────────────
  const loadAux = useCallback(() => {
    fetchMiniAlarms(30).then(setHistory).catch(() => setHistory(h => h || []))
    fetchMiniVideos(12).then(setVideos).catch(() => setVideos(v => v || []))
    fetchEnvHistory(40).then(setEnv).catch(() => setEnv(e => e || []))
  }, [])
  useEffect(() => { loadAux(); const id = setInterval(loadAux, AUX_MS); return () => clearInterval(id) }, [loadAux])

  // ── Dati derivati ───────────────────────────────────────────────────────
  const sensors = state?.sensors || []
  const alarms = state?.active_alarms || []
  const slots = useMemo(() => SLOTS.map(sl => {
    const sensor = sensorFor(sl, sensors)
    return { ...sl, sensor, alarms: sensor ? alarms.filter(a => a.device_id === sensor.device_id) : [] }
  }), [sensors, alarms])
  const deviceName = id => slots.find(s => s.sensor?.device_id === id)?.label || id
  const sel = slots.find(s => s.key === selKey) || slots[0]
  const online = sensors.filter(s => s.is_online).length
  const climate = slots.find(s => s.key === 'node_b')?.sensor?.reading
  const binR = slots.find(s => s.key === 'bin')?.sensor?.reading

  // ── Azioni ──────────────────────────────────────────────────────────────
  async function simulate(a) {
    setBusy(a.label)
    try { await miniTestTrigger(a.payload); toast('Simulazione inviata al modellino.', 'success'); setTimeout(() => { loadState(); loadAux() }, 500) }
    catch (e) { toast(e.message, 'danger', { title:'Simulazione non riuscita' }) }
    finally { setBusy(null) }
  }
  async function rearm(list) {
    if (!list.length) return
    setBusy('rearm')
    const res = await Promise.allSettled(list.map(a => resetMiniAlarm(a.id)))
    const failed = res.filter(r => r.status === 'rejected').length
    if (failed) toast(`${failed} ${failed === 1 ? 'allarme non è stato riarmato' : 'allarmi non sono stati riarmati'}. Riprova.`, 'danger', { title:'Riarmo incompleto' })
    else toast(list.length === 1 ? 'Allarme riarmato: sirena spenta.' : 'Allarmi riarmati: sirene spente.', 'success')
    await loadState(); loadAux(); setBusy(null)
  }

  return (
    <div className="te-app">
      <TopBar role={role} username={username} onSwitchRole={onSwitchRole} onLogout={onLogout}>
        {live ? <WsDot status="connected"/> : <span className="te-hide-sm" style={{ fontSize:13, color:'var(--text-3)', whiteSpace:'nowrap' }}>Aggiornamento ogni 3 s</span>}
        <SoundButton/>
      </TopBar>

      {alarms.length > 0 && (
        <div className="te-banner te-banner--danger" role="alert">
          <BellRing size={18} aria-hidden="true" style={{ flexShrink:0, animation:'pulse 1.4s infinite' }}/>
          <span style={{ flex:1 }}>
            <strong>{alarms.length === 1 ? 'Un allarme attivo' : `${alarms.length} allarmi attivi`}.</strong>{' '}
            {[...new Set(alarms.map(a => `${alarmLabel(a.alarm_type)} (${deviceName(a.device_id)})`))].join(' · ')}
          </span>
          <Btn variant="danger" size="sm" onClick={() => rearm(alarms)} loading={busy === 'rearm'} disabled={!!busy}>Riarma e spegni le sirene</Btn>
        </div>
      )}

      <Tabs label="Sezioni del modellino" idPrefix="mini" value={tab} onChange={setTab} tabs={TABS.map(t => t.key === 'allarmi' && alarms.length
        ? { ...t, badge:<span className="te-count" style={{ background:'var(--red-light)', color:'var(--red)' }}>{alarms.length}</span> } : t)}/>

      <main className="te-content" role="tabpanel" id="mini-panel" aria-labelledby={`mini-tab-${tab}`}>
        {!state && !error ? <div style={{ display:'flex', justifyContent:'center', padding:80 }}><Spinner size={24}/></div>
          : !state ? <ErrorState title="Modellino non raggiungibile" text="Il server non risponde. Nuovo tentativo automatico in corso." onRetry={loadState}/>
          : tab === 'stato' ? (
            <div className="te-stack" style={{ maxWidth:1180 }}>
              <div className="te-grid-4">
                <StatCard icon={Shield} iconBg={alarms.length ? 'var(--red-light)' : 'var(--green-light)'} iconColor={alarms.length ? 'var(--red)' : 'var(--green)'}
                  label="Sicurezza" value={alarms.length ? `${alarms.length} ${alarms.length === 1 ? 'allarme' : 'allarmi'}` : 'Tranquillo'}
                  valueColor={alarms.length ? 'var(--red)' : 'var(--text-1)'} pulse={alarms.length > 0}/>
                <StatCard icon={Thermometer} label="Temperatura" value={climate?.temperatura_c != null ? `${fmt1(climate.temperatura_c)} °C` : '—'}
                  caption={climate?.umidita_pct != null ? `Umidità dell'aria ${pct(climate.umidita_pct)}` : 'Nessuna lettura'}/>
                <StatCard icon={Trash2} label="Cestino" value={binR?.riempimento_pct != null ? pct(binR.riempimento_pct) : '—'}
                  caption={binR?.inclinazione_deg != null ? `Inclinazione ${Math.round(binR.inclinazione_deg)}°` : 'Nessuna lettura'}/>
                <StatCard icon={Activity} label="Dispositivi online" value={`${online}/${sensors.length}`}
                  delta={online < sensors.length ? `${sensors.length - online} offline` : 'Tutti connessi'} deltaPositive={online === sensors.length}/>
              </div>

              <div className="te-grid-2 te-grid-2--main-side" style={{ alignItems:'start' }}>
                <section className="te-card te-card--pad" aria-label="Mappa del modellino">
                  <div className="te-card-title">Mappa del modellino</div>
                  <div className="te-card-sub" style={{ marginBottom:16 }}>Scegli un dispositivo per vederne le letture{canControl ? ' e provare una simulazione' : ''}.</div>
                  <MiniMap slots={slots} selKey={sel.key} onSelect={setSelKey}/>
                </section>
                <DevicePanel slot={sel} canControl={canControl} busy={busy} onSimulate={simulate} onRearm={rearm}/>
              </div>
            </div>
          ) : tab === 'ambiente' ? (
            <EnvPanel env={env}/>
          ) : tab === 'allarmi' ? (
            <div className="te-stack" style={{ maxWidth:1180 }}>
              <section className="te-card" style={{ overflow:'hidden' }} aria-label="Storico allarmi">
                <div style={{ padding:'16px 20px 12px' }} className="te-card-title">Storico allarmi</div>
                {history === null ? <div style={{ padding:24 }}><Spinner/></div>
                  : !history.length ? <EmptyState icon={Shield} tone="ok" title="Nessun allarme registrato" text="Gli allarmi del modellino compariranno qui."/>
                  : (
                    <div className="te-table-wrap">
                      <table className="te-table">
                        <caption className="sr-only">Storico degli allarmi del modellino</caption>
                        <thead><tr>{['Data e ora', 'Allarme', 'Dispositivo', 'Stato'].map(h => <th key={h} scope="col">{h}</th>)}</tr></thead>
                        <tbody>
                          {history.map(a => (
                            <tr key={a.id}>
                              <td style={{ whiteSpace:'nowrap', color:'var(--text-2)' }}>{fmtDateTime(a.timestamp)}</td>
                              <td style={{ fontWeight:600 }}>{alarmLabel(a.alarm_type)}</td>
                              <td>{deviceName(a.device_id)}</td>
                              <td>{a.resolved
                                ? <span style={{ color:'var(--green)', fontWeight:600 }}>Riarmato</span>
                                : <span style={{ display:'inline-flex', alignItems:'center', gap:10 }}><span style={{ color:'var(--red)', fontWeight:600 }}>Attivo</span><Btn size="sm" variant="danger" disabled={!!busy} onClick={() => rearm([a])}>Riarma</Btn></span>}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  )}
              </section>

              <section className="te-card te-card--pad" aria-label="Clip registrate">
                <div className="te-card-title">Clip registrate</div>
                <div className="te-card-sub" style={{ marginBottom:16 }}>Video salvati quando scatta un allarme.</div>
                {videos === null ? <Spinner/>
                  : !videos.length ? <EmptyState icon={Video} title="Nessuna clip registrata"/>
                  : (
                    <div className="te-clip-grid">
                      {videos.map(v => (
                        <button key={v.id} type="button" className="te-clip" onClick={() => setClip(v)} aria-label={`Guarda la clip: ${alarmLabel(v.trigger_event)}, ${fmtDateTime(v.timestamp)}`}>
                          <span className="te-clip-thumb"><Play size={30} aria-hidden="true"/></span>
                          <span className="te-clip-body">
                            <strong>{v.trigger_event ? alarmLabel(v.trigger_event) : 'Clip'}</strong>
                            <span style={{ color:'var(--text-3)' }}>{deviceName(v.device_id)} · {fmtDateTime(v.timestamp)}</span>
                          </span>
                        </button>
                      ))}
                    </div>
                  )}
              </section>
            </div>
          ) : (
            <SettingsPanel canControl={canControl} ask={ask} onReset={() => { seen.current = new Set(); loadState(); loadAux() }}/>
          )}
      </main>

      {clip && <ClipDialog clip={clip} deviceName={deviceName} onClose={() => setClip(null)}/>}
      {dialog}
      <ToastContainer/>
    </div>
  )
}

// ── Mappa schematica ─────────────────────────────────────────────────────
function MiniMap({ slots, selKey, onSelect }) {
  return (
    <div className="te-mini-map">
      <svg viewBox="0 0 900 560" aria-hidden="true">
        <rect x="120" y="50" width="660" height="380" rx="24" fill="var(--sev-low-bg)" stroke="var(--border-2)" strokeWidth="2"/>
        {['M170 240 Q290 140 320 240 Q290 320 170 240', 'M730 240 Q610 140 580 240 Q610 320 730 240'].map(d => (
          <path key={d} d={d} fill="none" stroke="var(--bg-2)" strokeWidth="14" strokeLinecap="round"/>
        ))}
        <line x1="450" y1="60" x2="450" y2="420" stroke="var(--border-3)" strokeWidth="1.5" strokeDasharray="5,5"/>
        <text x="285" y="88" textAnchor="middle" fontSize="17" fontWeight="700" fill="var(--text-3)">Zona A</text>
        <text x="615" y="88" textAnchor="middle" fontSize="17" fontWeight="700" fill="var(--text-3)">Zona B</text>
        <circle cx="450" cy="240" r="34" fill="var(--bg-2)" stroke="var(--border-3)" strokeWidth="2"/>
        <circle cx="450" cy="240" r="22" fill="var(--st-open-bg)"/>
        <text x="450" y="296" textAnchor="middle" fontSize="12" fontWeight="600" fill="var(--text-3)">Fontana</text>
      </svg>
      {slots.map(s => {
        const alarm = s.alarms.length > 0, offline = !s.sensor?.is_online
        return (
          <button key={s.key} type="button" className="te-mini-dev" style={s.pos} onClick={() => onSelect(s.key)}
            aria-pressed={selKey === s.key} data-alarm={alarm} data-offline={!alarm && offline}
            aria-label={`${s.label}${alarm ? ', allarme attivo' : offline ? ', offline' : ', online'}`}>
            <span className="te-mini-dev-top"><s.icon size={16} aria-hidden="true"/>{s.label}</span>
            <small>{alarm ? 'Allarme attivo' : offline ? 'Offline' : s.sub}</small>
          </button>
        )
      })}
    </div>
  )
}

// ── Dettaglio del dispositivo selezionato ────────────────────────────────
function DevicePanel({ slot, canControl, busy, onSimulate, onRearm }) {
  const s = slot.sensor
  const rows = readingRows(s?.reading)
  const alarm = slot.alarms.length > 0
  const chip = alarm ? { l:'Allarme attivo', bg:'var(--red-light)', c:'var(--red)' }
    : s?.is_online ? { l:'Online', bg:'var(--green-light)', c:'var(--green)' }
    : { l:'Offline', bg:'var(--bg-3)', c:'var(--text-3)' }
  return (
    <section className="te-card te-card--pad" aria-label={`Dettaglio ${slot.label}`} style={{ display:'flex', flexDirection:'column', gap:16 }}>
      <div style={{ display:'flex', alignItems:'flex-start', gap:12 }}>
        <span style={{ width:40, height:40, borderRadius:'var(--r-md)', background:'var(--bg-3)', color:'var(--text-2)', display:'inline-flex', alignItems:'center', justifyContent:'center', flexShrink:0 }}><slot.icon size={20} aria-hidden="true"/></span>
        <div style={{ flex:1, minWidth:0 }}>
          <h2 style={{ fontSize:16, fontWeight:700 }}>{slot.label}</h2>
          <div style={{ fontSize:13, color:'var(--text-3)' }}>{slot.desc}</div>
        </div>
        <span className="te-chip" style={{ background:chip.bg, color:chip.c, fontWeight:700, flexShrink:0 }}>{chip.l}</span>
      </div>

      {!s ? <p style={{ fontSize:13, color:'var(--text-3)' }}>Questo dispositivo non è registrato nel sistema.</p> : (
        <>
          {alarm && (
            <div style={{ display:'flex', flexDirection:'column', gap:8 }}>
              {slot.alarms.map(a => (
                <div key={a.id} style={{ display:'flex', alignItems:'center', gap:10, padding:'10px 12px', background:'var(--red-light)', border:'1px solid var(--red-mid)', borderRadius:'var(--r-md)' }}>
                  <div style={{ flex:1, minWidth:0 }}>
                    <div style={{ fontSize:14, fontWeight:700, color:'var(--red)' }}>{alarmLabel(a.alarm_type)}</div>
                    <div style={{ fontSize:12, color:'var(--text-2)' }}>{fmtDateTime(a.timestamp)}{a.sirena_active ? ' · sirena accesa' : ''}</div>
                  </div>
                  <Btn size="sm" variant="danger" disabled={!!busy} onClick={() => onRearm([a])}>Riarma</Btn>
                </div>
              ))}
            </div>
          )}

          <div>
            <h3 style={{ fontSize:13, fontWeight:600, color:'var(--text-3)', marginBottom:8 }}>Ultime letture</h3>
            {rows.length ? (
              <dl className="te-metrics" style={{ gridTemplateColumns:'repeat(auto-fill, minmax(130px, 1fr))' }}>
                {rows.map(([k, v]) => <div key={k} className="te-metric"><dt className="te-metric-k">{k}</dt><dd className="te-metric-v" style={{ margin:0 }}>{v}</dd></div>)}
              </dl>
            ) : <p style={{ fontSize:13, color:'var(--text-3)' }}>Nessuna lettura ricevuta.</p>}
            <p style={{ fontSize:12, color:'var(--text-3)', marginTop:8 }}>
              {s.minutes_since == null ? 'Non ha mai trasmesso.' : s.minutes_since < 1 ? 'Ultimo contatto: adesso.' : `Ultimo contatto: ${since(s.minutes_since)} fa.`}
            </p>
          </div>

          {canControl && (
            <div style={{ paddingTop:16, borderTop:'1px solid var(--border)', display:'flex', flexDirection:'column', gap:8 }}>
              <h3 style={{ fontSize:13, fontWeight:600, color:'var(--text-3)', display:'flex', alignItems:'center', gap:6 }}><FlaskConical size={14} aria-hidden="true"/>Simulazioni</h3>
              {actionsFor(slot).map(a => (
                <Btn key={a.label} variant={a.variant || 'secondary'} size="sm" icon={<a.icon size={15}/>} loading={busy === a.label} disabled={!!busy}
                  onClick={() => onSimulate(a)} style={{ justifyContent:'flex-start' }}>{a.label}</Btn>
              ))}
              {slot.kind === 'camera' && <p style={{ fontSize:12, color:'var(--text-3)' }}>L'allarme della telecamera accende le sirene di entrambi i varchi: lo vedrai comparire su Varco A e Varco B.</p>}
            </div>
          )}
        </>
      )}
    </section>
  )
}

// ── Andamento ambiente ───────────────────────────────────────────────────
const hhmm = iso => iso ? new Date(iso).toLocaleTimeString('it-IT', { hour:'2-digit', minute:'2-digit' }) : ''
const METRICS = [
  { key:'temperature_c', label:'Temperatura', unit:'°C', icon:Thermometer, color:'var(--sev-med-mark)' },
  { key:'humidity_pct', label:"Umidità dell'aria", unit:'%', icon:Droplets, color:'var(--st-open)', digits:0 },
  { key:'soil_humidity_pct', label:'Umidità del terreno', unit:'%', icon:Sprout, color:'var(--brand-green)', digits:0 },
  { key:'pm25', label:'Polveri PM2.5', unit:'µg/m³', icon:Wind, color:'var(--accent)' },
]

function EnvPanel({ env }) {
  if (env === null) return <div style={{ display:'flex', justifyContent:'center', padding:80 }}><Spinner size={24}/></div>
  if (!env.length) return <div className="te-card" style={{ maxWidth:560 }}><EmptyState icon={Thermometer} title="Nessuna lettura ambientale" text="I grafici compariranno quando il Varco B avrà inviato le prime misure."/></div>
  return (
    <div className="te-stack" style={{ maxWidth:1180 }}>
      <p style={{ fontSize:13, color:'var(--text-3)' }}>Ultime {env.length} letture del Varco B, dalle {hhmm(env[0].timestamp)} alle {hhmm(env[env.length - 1].timestamp)}.</p>
      <div className="te-grid-2">
        {METRICS.map(m => <MetricChart key={m.key} {...m} points={env.map(r => ({ t:r.timestamp, v:r[m.key] }))}/>)}
      </div>
    </div>
  )
}

/** Un grafico per misura: scala propria, ultimo valore, minimo e massimo. Solo dati reali. */
function MetricChart({ label, unit, icon:Icon, color, points, digits = 1 }) {
  const pts = points.filter(p => p.v != null)
  const f = v => Number(v).toLocaleString('it-IT', { maximumFractionDigits:digits })
  const head = (
    <div style={{ display:'flex', alignItems:'center', gap:8, color:'var(--text-3)', fontSize:13, fontWeight:500 }}><Icon size={16} aria-hidden="true"/>{label}</div>
  )
  if (pts.length < 2) return <div className="te-card te-card--pad">{head}<p style={{ fontSize:13, color:'var(--text-3)', padding:'24px 0 8px' }}>Dati non ancora sufficienti per il grafico.</p></div>
  const vals = pts.map(p => p.v), min = Math.min(...vals), max = Math.max(...vals), range = (max - min) || 1
  const d = pts.map((p, i) => `${i ? 'L' : 'M'}${((i / (pts.length - 1)) * 100).toFixed(2)},${(92 - ((p.v - min) / range) * 84).toFixed(2)}`).join(' ')
  const last = pts[pts.length - 1]
  return (
    <div className="te-card te-card--pad">
      {head}
      <div className="tnum" style={{ fontSize:26, fontWeight:700, lineHeight:1.2, margin:'4px 0 10px' }}>{f(last.v)} <span style={{ fontSize:14, fontWeight:500, color:'var(--text-3)' }}>{unit}</span></div>
      <svg viewBox="0 0 100 100" preserveAspectRatio="none" style={{ width:'100%', height:110, display:'block' }} role="img"
        aria-label={`${label}: ultimo valore ${f(last.v)} ${unit}, minimo ${f(min)}, massimo ${f(max)}`}>
        {[8, 50, 92].map(y => <line key={y} x1="0" y1={y} x2="100" y2={y} stroke="var(--bg-4)" strokeWidth="1" vectorEffect="non-scaling-stroke"/>)}
        <path d={d} fill="none" stroke={color} strokeWidth="2.5" vectorEffect="non-scaling-stroke" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
      <div style={{ display:'flex', justifyContent:'space-between', gap:8, marginTop:8, fontSize:12, color:'var(--text-3)' }}>
        <span>{hhmm(pts[0].t)}</span>
        <span>min {f(min)} · max {f(max)} {unit}</span>
        <span>{hhmm(last.t)}</span>
      </div>
    </div>
  )
}

// ── Impostazioni: soglie e azzeramento dati ──────────────────────────────
function SettingsPanel({ canControl, ask, onReset }) {
  const [saved, setSaved] = useState(null)       // { values, defaults } dal server
  const [form, setForm] = useState(null)
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(null)

  // Caricate una volta sola: gli aggiornamenti periodici non devono sovrascrivere ciò che si sta scrivendo
  const load = useCallback(() => {
    setError(null)
    fetchMiniSettings().then(s => { setSaved(s); setForm(toForm(s.values)) }).catch(e => setError(e.message))
  }, [])
  useEffect(load, [load])

  if (error) return <ErrorState title="Impostazioni non disponibili" text={error} onRetry={load}/>
  if (!form) return <div style={{ display:'flex', justifyContent:'center', padding:80 }}><Spinner size={24}/></div>

  const errors = Object.fromEntries(FIELDS.map(f => [f.key, fieldError(f, form[f.key])]))
  const invalid = Object.values(errors).some(Boolean)
  const dirty = FIELDS.some(f => Number(form[f.key]) !== Number(saved.values[f.key]))
  const isDefault = FIELDS.every(f => Number(form[f.key]) === Number(saved.defaults[f.key]))

  async function save(e) {
    e.preventDefault()
    if (invalid || !dirty) return
    setBusy('save')
    try {
      const s = await updateMiniSettings(Object.fromEntries(FIELDS.map(f => [f.key, Number(form[f.key])])))
      setSaved(s); setForm(toForm(s.values)); toast('Soglie salvate.', 'success')
    } catch (err) { toast(err.message, 'danger', { title:'Soglie non salvate' }) }
    finally { setBusy(null) }
  }
  async function reset() {
    if (!(await ask({ title:'Azzerare i dati del modellino?', message:"Verranno cancellati letture, allarmi e pratiche generati dal modellino. I dispositivi restano registrati. L'operazione non è annullabile.", confirmLabel:'Azzera i dati', tone:'danger', icon:RotateCcw }))) return
    setBusy('reset')
    try { await miniReset(); toast('Dati del modellino azzerati.', 'success'); onReset() }
    catch (err) { toast(err.message, 'danger', { title:'Azzeramento non riuscito' }) }
    finally { setBusy(null) }
  }

  return (
    <div className="te-stack" style={{ maxWidth:720 }}>
      <form onSubmit={save} noValidate className="te-card te-card--pad" style={{ display:'flex', flexDirection:'column', gap:16 }}>
        <div>
          <h2 className="te-card-title">Soglie</h2>
          <p className="te-card-sub">Valori oltre i quali il sistema reagisce da solo.{!canControl && ' Solo un amministratore può modificarli.'}</p>
        </div>
        <div style={{ display:'grid', gridTemplateColumns:'repeat(auto-fit, minmax(240px, 1fr))', gap:16 }}>
          {FIELDS.map(f => (
            <div key={f.key} className="te-field">
              <label htmlFor={`set-${f.key}`} className="te-label">{f.label} <span style={{ fontWeight:400, color:'var(--text-3)' }}>({f.unit})</span></label>
              <input id={`set-${f.key}`} className="te-input" type="number" inputMode="decimal" min={f.min} max={f.max} step={f.int ? 1 : 'any'} disabled={!canControl}
                value={form[f.key]} onChange={e => setForm(v => ({ ...v, [f.key]: e.target.value }))}
                aria-invalid={!!errors[f.key] || undefined} aria-describedby={`set-${f.key}-hint`}/>
              <span id={`set-${f.key}-hint`} className={errors[f.key] ? 'te-field-error' : 'te-hint'}>{errors[f.key] || `${f.hint} Predefinito: ${saved.defaults[f.key]}.`}</span>
            </div>
          ))}
        </div>
        {canControl && (
          <div style={{ display:'flex', gap:8, flexWrap:'wrap' }}>
            <Btn type="submit" variant="primary" loading={busy === 'save'} disabled={!dirty || invalid || !!busy}>Salva soglie</Btn>
            <Btn variant="secondary" disabled={isDefault || !!busy} onClick={() => setForm(toForm(saved.defaults))}>Ripristina i valori predefiniti</Btn>
          </div>
        )}
      </form>

      {canControl && (
        <section className="te-card te-card--pad" style={{ display:'flex', alignItems:'center', gap:16, flexWrap:'wrap' }} aria-label="Azzeramento dati">
          <div style={{ flex:1, minWidth:220 }}>
            <h2 className="te-card-title">Azzera i dati del modellino</h2>
            <p className="te-card-sub">Cancella letture, allarmi e pratiche generati dal modellino, per ripartire da una situazione pulita.</p>
          </div>
          <Btn variant="danger" icon={<RotateCcw size={16}/>} loading={busy === 'reset'} disabled={!!busy} onClick={reset}>Azzera i dati</Btn>
        </section>
      )}
    </div>
  )
}

// ── Riproduzione clip ────────────────────────────────────────────────────
function ClipDialog({ clip, deviceName, onClose }) {
  const titleId = useId()
  return (
    <Modal open onClose={onClose} labelledBy={titleId} wide>
      <DialogHeader id={titleId} icon={Video} onClose={onClose} title={clip.trigger_event ? alarmLabel(clip.trigger_event) : 'Clip'}>
        <p style={{ marginTop:4, color:'var(--text-3)', fontSize:13 }}>{deviceName(clip.device_id)} · {fmtDateTime(clip.timestamp)}</p>
      </DialogHeader>
      <div className="te-dialog-body" style={{ paddingBottom:20 }}>
        <video controls autoPlay src={apiUrl(`/${clip.video_path}`)} style={{ width:'100%', maxHeight:'60vh', borderRadius:'var(--r-md)', background:'#000', display:'block' }}>
          Il browser non riesce a riprodurre questo video.
        </video>
      </div>
    </Modal>
  )
}
