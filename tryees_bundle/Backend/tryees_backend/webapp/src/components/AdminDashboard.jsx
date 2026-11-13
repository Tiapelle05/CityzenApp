import React, { useState, useEffect, useCallback } from 'react'
import { fetchSLA, fetchDeviceHealth, fetchAccessLog, fetchOnboardingKeys, registerDevice, revokeKey, setup2FA, confirm2FA, status2FA, disable2FA, deleteDevice, fetchOverview, fetchPowerLatest, fetchPowerDaily, fetchParks } from '../lib/api'
import { Spinner, Btn, SectionTitle, StatCard, MiniBarChart, UserMenu, EmptyState, ErrorState, useConfirm, fmt1, fmtDateTime } from './ui.jsx'
import { toast, ToastContainer } from './Shared.jsx'
import { LogoIcon } from './Logo.jsx'
import { Home, Activity, Key, Shield, History, Server, Cpu, AlertTriangle, CheckCircle2, Zap, Lock, LockOpen, Trash2, Copy, CircleCheck, CircleX, LogOut, Repeat, ClipboardList, Megaphone, Lightbulb } from 'lucide-react'
import AdminPractices from './AdminPractices.jsx'
import AdminNotices from './AdminNotices.jsx'
import AdminSuggestions from './AdminSuggestions.jsx'
import ServerMonitor from './ServerMonitor.jsx'
import { TYPE, typeOf, since, DeviceStatus } from './devices.jsx'

const TABS=[['overview','Panoramica',Home],['practices','Pratiche',ClipboardList],['notices','Avvisi',Megaphone],['suggestions','Suggerimenti',Lightbulb],['devices','Dispositivi',Server],['power','Energia',Zap],['server','Server',Cpu],['onboarding','Registrazione',Key],['security','Sicurezza',Shield],['log','Accessi',History]]
const ACTION_LABEL={login_success:'Accesso',login_failed:'Accesso fallito','2fa_enabled':'Verifica in due passaggi attivata','2fa_disabled':'Verifica in due passaggi disattivata','2fa_verified':'Codice di verifica corretto','2fa_failed':'Codice di verifica errato'}
const actionLabel=a=>ACTION_LABEL[a]||String(a||'').replace(/_/g,' ')
const Loading=()=> <div style={{display:'flex',justifyContent:'center',padding:48}}><Spinner/></div>

/** Carica dati con stato di caricamento/errore e funzione "riprova". */
function useLoad(fn, deps=[]){
  const [data,setData]=useState(null);const [loading,setL]=useState(true);const [error,setError]=useState(null)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const load=useCallback(()=>{setL(true);setError(null);return fn().then(setData).catch(e=>setError(e.message)).finally(()=>setL(false))},deps)
  useEffect(()=>{load()},[load])
  return {data,setData,loading,error,reload:load}
}

export default function AdminDashboard({ onLogout, onSwitchRole, username, role='admin' }) {
  // La sezione aperta sopravvive al refresh della pagina (App.jsx la azzera al logout)
  const [tab,setTabState]=useState(()=>{try{const t=sessionStorage.getItem('te_admin_tab');return TABS.some(x=>x[0]===t)?t:'overview'}catch{return 'overview'}})
  const setTab=t=>{setTabState(t);try{sessionStorage.setItem('te_admin_tab',t)}catch{}}
  const tabLabel = TABS.find(t=>t[0]===tab)?.[1] || ''
  return(
    <div className="te-sidebar-layout">
      <nav className="te-sidebar" aria-label="Sezioni amministrazione">
        <div className="te-sidebar-brand" style={{display:'flex',alignItems:'center',gap:10,padding:'4px 8px 20px'}}>
          <LogoIcon size={32}/>
          <div>
            <div style={{fontSize:15,fontWeight:700,color:'var(--text-1)',lineHeight:1.2}}>Treeyes</div>
            <div style={{fontSize:12,fontWeight:500,color:'var(--text-3)',lineHeight:1.2}}>Amministrazione</div>
          </div>
        </div>
        {TABS.map(([k,l,Icon])=>(
          <button key={k} type="button" className="te-nav-item" aria-current={tab===k?'page':undefined} onClick={()=>setTab(k)}>
            <Icon size={18} aria-hidden="true"/>{l}
          </button>
        ))}
        <div style={{flex:1}}/>
        <div className="te-sidebar-foot">
          {onSwitchRole && (
            <button key="switch-role" type="button" className="te-nav-item" onClick={onSwitchRole} title="Cambia profilo">
              <Repeat size={18} aria-hidden="true"/>
              <span>Cambia profilo</span>
            </button>
          )}
          <button key="logout" type="button" className="te-nav-item" onClick={onLogout} style={{color:'var(--red)'}} title="Esci dall'applicazione">
            <LogOut size={18} aria-hidden="true"/>
            <span>Esci</span>
          </button>
        </div>
      </nav>

      <div className="te-main">
        <header className="te-topbar" style={{minHeight:64}}>
          <div className="te-topbar-brand te-only-mobile">
            <LogoIcon size={28}/>
            <span className="te-topbar-name" style={{color:'var(--text-1)'}}>Treeyes</span>
            <span className="te-topbar-sep" aria-hidden="true"/>
          </div>
          <h1 className="te-page-title">{tabLabel}</h1>
          <div className="te-topbar-actions">
            <UserMenu username={username} role={role} onSwitchRole={onSwitchRole} onLogout={onLogout}/>
          </div>
        </header>
        <main className="te-content">
          {tab==='overview'   && <OverviewPanel onNavigate={setTab}/>}
          {tab==='practices'  && <AdminPractices/>}
          {tab==='notices'    && <AdminNotices/>}
          {tab==='suggestions'&& <AdminSuggestions/>}
          {tab==='devices'    && <DevicesPanel/>}
          {tab==='power'      && <PowerPanel/>}
          {tab==='server'     && <ServerMonitor/>}
          {tab==='onboarding' && <OnboardingPanel/>}
          {tab==='security'   && <SecurityPanel/>}
          {tab==='log'        && <AccessLogPanel/>}
        </main>
      </div>
      <ToastContainer/>
    </div>
  )
}

function OverviewPanel({ onNavigate }){
  const {data,loading,error,reload}=useLoad(()=>Promise.all([fetchSLA(), fetchOverview(), fetchAccessLog().catch(()=>[])]))
  if(loading) return <Loading/>
  if(error||!data) return <ErrorState title="Panoramica non disponibile" text={error} onRetry={reload}/>
  const [sla,severity,logAll]=data
  const log=(logAll||[]).slice(0,6)
  const SL = { open:'Aperte', in_progress:'In carico', resolved:'Risolte', closed:'Chiuse' }
  const barData = ['open','in_progress','resolved','closed'].map(s=>(severity||[]).find(r=>r.status===s)).filter(Boolean).map(r=>({label:SL[r.status]||r.status, value:r.count}))
  const failed=sla.security.failed_logins_24h
  const ok=sla.status==='ok'
  const devIssues=[sla.devices.offline>0&&`${sla.devices.offline} offline`,sla.devices.faulty>0&&`${sla.devices.faulty} guasti`].filter(Boolean).join(' · ')

  return(
    <div className="te-stack" style={{maxWidth:1120}}>
      <div role="status" style={{display:'flex',alignItems:'center',gap:12,padding:'12px 16px',background:ok?'var(--green-light)':'var(--yellow-light)',border:`1px solid ${ok?'var(--green-mid)':'var(--yellow-mid)'}`,borderRadius:'var(--r-md)',flexWrap:'wrap'}}>
        {ok?<CheckCircle2 size={20} color="var(--green)" aria-hidden="true"/>:<AlertTriangle size={20} color="var(--yellow)" aria-hidden="true"/>}
        <span style={{fontSize:15,fontWeight:700,color:ok?'var(--green)':'var(--yellow)'}}>{ok?'Sistema operativo':'Sistema degradato'}</span>
        {!ok&&<span style={{fontSize:13,color:'var(--text-2)'}}>Più del 30% dei dispositivi non trasmette.</span>}
        <span style={{fontSize:13,color:'var(--text-3)',marginLeft:'auto'}}>Aggiornato il {fmtDateTime(sla.timestamp)}</span>
        <Btn size="sm" variant="secondary" onClick={reload}>Aggiorna</Btn>
      </div>
      <div className="te-grid-4">
        <StatCard icon={AlertTriangle} iconBg="var(--red-light)" iconColor="var(--red)"
          label="Pratiche aperte" value={sla.practices.open}
          delta={sla.practices.critical>0?`${sla.practices.critical} critiche`:'Nessuna critica'} deltaPositive={sla.practices.critical===0}/>
        <StatCard icon={Server} iconBg="var(--blue-light)" iconColor="var(--blue)"
          label="Dispositivi online" value={`${sla.devices.online}/${sla.devices.total}`}
          delta={devIssues||'Tutti connessi'} deltaPositive={!devIssues}/>
        <StatCard icon={Activity} iconBg="var(--accent-light)" iconColor="var(--accent)"
          label="Eventi nelle 24 h" value={sla.events.last_24h}
          delta={`${sla.events.last_hour} nell'ultima ora`} deltaPositive/>
        <StatCard icon={Shield} iconBg={failed>5?'var(--red-light)':'var(--green-light)'} iconColor={failed>5?'var(--red)':'var(--green)'}
          label="Accessi falliti 24 h" value={failed}
          delta={failed>5?'Sopra la soglia':'Nella norma'} deltaPositive={failed<=5}/>
      </div>

      <div className="te-grid-2 te-grid-2--main-side">
        <div className="te-card te-card--pad">
          <div className="te-card-title">Pratiche per stato</div>
          <div className="te-card-sub" style={{marginBottom:12}}>{barData.reduce((a,b)=>a+b.value,0)} in totale</div>
          {barData.length===0 ? <p style={{fontSize:13,color:'var(--text-3)',padding:'20px 0'}}>Nessuna pratica registrata.</p> : <MiniBarChart data={barData}/>}
        </div>
        <div className="te-card te-card--pad">
          <div style={{display:'flex',justifyContent:'space-between',alignItems:'baseline',marginBottom:14}}>
            <div className="te-card-title">Accessi recenti</div>
            <Btn variant="link" size="sm" onClick={()=>onNavigate('log')}>Vedi tutti</Btn>
          </div>
          {log.length===0 ? <p style={{fontSize:13,color:'var(--text-3)'}}>Nessun accesso registrato.</p> : (
            <ul style={{listStyle:'none',display:'flex',flexDirection:'column',gap:12}}>
              {log.map(r=>(
                <li key={r.id} style={{display:'flex',alignItems:'center',gap:10}}>
                  <span aria-hidden="true" className="te-avatar" style={{width:32,height:32,background:r.success?'var(--green-light)':'var(--red-light)',color:r.success?'var(--green)':'var(--red)'}}>{(r.username||'?')[0].toUpperCase()}</span>
                  <div style={{flex:1,minWidth:0}}>
                    <div style={{fontSize:14,fontWeight:600,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}}>{r.username}</div>
                    <div style={{fontSize:12,color:'var(--text-3)'}}>{actionLabel(r.action)}</div>
                  </div>
                  <time dateTime={r.created_at} style={{fontSize:12,color:'var(--text-3)',whiteSpace:'nowrap'}}>{new Date(r.created_at).toLocaleTimeString('it-IT',{hour:'2-digit',minute:'2-digit'})}</time>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>

      {sla.devices.offline_list?.length>0 && <OfflineDevices list={sla.devices.offline_list}/>}
    </div>
  )
}

function OfflineDevices({ list }){
  return (
    <div className="te-card te-card--pad">
      <div className="te-card-title" style={{marginBottom:12}}>Dispositivi offline</div>
      <ul style={{listStyle:'none',display:'flex',flexDirection:'column',gap:8}}>
        {list.map(d=>(
          <li key={d.mac_address} style={{display:'flex',alignItems:'center',gap:12,padding:'10px 12px',background:'var(--yellow-light)',border:'1px solid var(--yellow-mid)',borderRadius:'var(--r-md)'}}>
            <div style={{flex:1,minWidth:0}}>
              <div className="mono" style={{fontSize:13,fontWeight:500}}>{d.mac_address}</div>
              <div style={{fontSize:12,color:'var(--text-3)'}}>{typeOf(d.type).l} · {d.zone}</div>
            </div>
            <div style={{fontSize:13,color:'var(--yellow)',fontWeight:600,whiteSpace:'nowrap'}}>{d.minutes_since!=null?`visto ${since(d.minutes_since)} fa`:'mai visto'}</div>
          </li>
        ))}
      </ul>
    </div>
  )
}

function PowerPanel(){
  const {data:rows,loading,error,reload}=useLoad(fetchPowerLatest)
  const [selected,setSelected]=useState(null)
  const [daily,setDaily]=useState(null)
  useEffect(()=>{
    if(!selected) return
    setDaily(null)
    fetchPowerDaily(selected,7).then(d=>setDaily(d.map(r=>({label:r.date.slice(5),value:r.kwh})))).catch(()=>setDaily([]))
  },[selected])

  if(loading) return <Loading/>
  if(error) return <ErrorState title="Consumi non disponibili" text={error} onRetry={reload}/>
  if(!rows?.length) return (
    <div className="te-card" style={{maxWidth:560}}>
      <EmptyState icon={Zap} title="Nessun dato di consumo" text="Serve un sensore di corrente in linea (INA219/INA226 o presa smart per il server) che pubblichi un evento con power_w, e facoltativamente voltage e current_ma."/>
    </div>
  )
  const totalW = rows.reduce((a,r)=>a+(r.power_w||0),0)

  return(
    <div className="te-stack" style={{maxWidth:1120}}>
      <div style={{maxWidth:320}}>
        <StatCard icon={Zap} iconBg="var(--yellow-light)" iconColor="var(--yellow)" label="Potenza totale ora" value={`${fmt1(totalW)} W`} delta={`${rows.length} dispositivi monitorati`} deltaPositive/>
      </div>
      <div className="te-card" style={{overflow:'hidden'}}>
        <div style={{padding:'16px 20px 12px'}} className="te-card-title">Consumo per dispositivo</div>
        <div className="te-table-wrap">
          <table className="te-table">
            <caption className="sr-only">Consumo elettrico per dispositivo</caption>
            <thead><tr>{['Dispositivo','Zona','Tensione','Corrente','Potenza','Aggiornato',''].map(h=><th key={h} scope="col">{h}</th>)}</tr></thead>
            <tbody>
              {rows.map(r=>(
                <tr key={r.mac_address} aria-selected={selected===r.mac_address}>
                  <td className="mono">{r.mac_address}</td>
                  <td>{r.zone||'—'}</td>
                  <td className="tnum">{r.voltage!=null?`${fmt1(r.voltage)} V`:'—'}</td>
                  <td className="tnum">{r.current_ma!=null?`${r.current_ma.toFixed(0)} mA`:'—'}</td>
                  <td className="tnum" style={{fontWeight:600}}>{r.power_w!=null?`${fmt1(r.power_w)} W`:'—'}</td>
                  <td style={{color:'var(--text-3)'}}>{r.timestamp?new Date(r.timestamp).toLocaleTimeString('it-IT'):'—'}</td>
                  <td><Btn size="sm" variant="link" onClick={()=>setSelected(r.mac_address)} ariaLabel={`Mostra i kWh giornalieri di ${r.mac_address}`}>kWh giornalieri</Btn></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {selected && (
        <div className="te-card te-card--pad">
          <div className="te-card-title">kWh giornalieri · <span className="mono" style={{fontWeight:500}}>{selected}</span></div>
          <div className="te-card-sub" style={{marginBottom:12}}>Ultimi 7 giorni</div>
          {daily===null ? <Spinner/> : daily.length===0 || daily.every(d=>d.value===0) ? (
            <p style={{fontSize:13,color:'var(--text-3)',padding:'12px 0'}}>Dati insufficienti per calcolare i kWh: servono almeno due letture nello stesso giorno.</p>
          ) : <MiniBarChart data={daily} color="var(--sev-med-mark)"/>}
        </div>
      )}
    </div>
  )
}

function DevicesPanel(){
  const {data:devices,loading,error,reload}=useLoad(fetchDeviceHealth)
  const [busy,setBusy]=useState(null)
  const [dialog,ask]=useConfirm()
  async function remove(mac){
    if(!(await ask({title:`Eliminare il dispositivo ${mac}?`,message:'Verranno cancellati anche tutti i suoi eventi e allarmi. L\'operazione non è annullabile.',confirmLabel:'Elimina dispositivo',tone:'danger',icon:Trash2})))return
    setBusy(mac)
    try{ await deleteDevice(mac); toast('Dispositivo eliminato.','success'); reload() }
    catch(e){ toast(e.message,'danger',{title:'Eliminazione non riuscita'}) }
    finally{ setBusy(null) }
  }
  if(loading) return <Loading/>
  if(error) return <ErrorState title="Elenco dispositivi non disponibile" text={error} onRetry={reload}/>
  if(!devices?.length) return <div className="te-card"><EmptyState icon={Server} title="Nessun dispositivo registrato" text="Registra il primo dispositivo dalla sezione Registrazione."/></div>
  return(
    <div className="te-card" style={{maxWidth:1120,overflow:'hidden'}}>
      <div className="te-table-wrap">
        <table className="te-table">
          <caption className="sr-only">Dispositivi registrati</caption>
          <thead><tr>{['ID dispositivo','Tipo','Zona','Stato','Ultimo contatto','Eventi 24 h',''].map(h=><th key={h} scope="col">{h||<span className="sr-only">Azioni</span>}</th>)}</tr></thead>
          <tbody>
            {devices.map(d=>(
              <tr key={d.mac_address}>
                <td className="mono">{d.mac_address}</td>
                <td>{typeOf(d.type).l}</td>
                <td>{d.zone}</td>
                <td><DeviceStatus status={(d.status||'ok')==='ok'&&!d.is_online?'offline':d.status}/></td>
                <td style={{color:'var(--text-3)'}}>{d.minutes_since!=null?`${since(d.minutes_since)} fa`:'mai'}</td>
                <td className="tnum" style={{fontWeight:600}}>{d.events_24h}</td>
                <td><Btn size="sm" variant="danger" loading={busy===d.mac_address} disabled={!!busy} onClick={()=>remove(d.mac_address)} ariaLabel={`Elimina ${d.mac_address}`} icon={<Trash2 size={14}/>}>Elimina</Btn></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {dialog}
    </div>
  )
}

function OnboardingPanel(){
  const {data:keys,setData:setKeys,loading,error,reload}=useLoad(fetchOnboardingKeys)
  const [saving,setSaving]=useState(false)
  const [form,setForm]=useState({mac_address:'',device_type:'camera',zone:'',lat:45.6035,lon:8.9382,park_id:1,label:''});const [result,setResult]=useState(null)
  const [touched,setTouched]=useState(false)
  const [dialog,ask]=useConfirm()
  const [parks,setParks]=useState([])
  const set=(k,v)=>setForm(f=>({...f,[k]:v}))
  useEffect(()=>{fetchParks().then(ps=>{setParks(ps||[]);if(ps?.length)setForm(f=>ps.some(p=>p.id===f.park_id)?f:{...f,park_id:ps[0].id})}).catch(()=>{})},[])
  // Nessun vincolo sul formato: è l'identificativo con cui il dispositivo si presenta al sistema
  const missing=!form.mac_address.trim()||!form.label.trim()||!form.zone.trim()
  async function register(e){
    e.preventDefault(); setTouched(true)
    if(missing) return
    setSaving(true)
    try{const r=await registerDevice({...form,mac_address:form.mac_address.trim(),lat:parseFloat(form.lat),lon:parseFloat(form.lon),park_id:parseInt(form.park_id)});setResult(r);reload();toast('Dispositivo registrato.','success');setTouched(false)}
    catch(err){toast(err.message,'danger',{title:'Registrazione non riuscita'})}
    finally{setSaving(false)}
  }
  async function revoke(k){
    if(!(await ask({title:`Revocare la chiave «${k.label}»?`,message:'Il dispositivo associato non potrà più inviare dati finché non ne riceve una nuova.',confirmLabel:'Revoca chiave',tone:'danger',icon:Key})))return
    try{await revokeKey(k.id);setKeys(ks=>ks.map(x=>x.id===k.id?{...x,active:false}:x));toast('Chiave revocata.','success')}
    catch(err){toast(err.message,'danger',{title:'Revoca non riuscita'})}
  }
  async function copyKey(){ try{await navigator.clipboard.writeText(result.api_key);toast('Chiave copiata negli appunti.','success')}catch{toast('Copia non riuscita: seleziona la chiave e copiala a mano.','warning')} }
  const err=(cond)=>touched&&cond
  return(
    <div className="te-grid-2 te-grid-2--main-side" style={{maxWidth:1080,alignItems:'start'}}>
      <section className="te-card te-card--pad" aria-labelledby="onb-title">
        <SectionTitle as="h2"><span id="onb-title">Registra un nuovo dispositivo</span></SectionTitle>
        <form onSubmit={register} noValidate>
          <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(200px,1fr))',gap:14,marginBottom:16}}>
            <div className="te-field">
              <label htmlFor="onb-mac" className="te-label">ID dispositivo</label>
              <input id="onb-mac" className="te-input mono" value={form.mac_address} onChange={e=>set('mac_address',e.target.value)} placeholder="Es. cam_ingresso_01" aria-invalid={err(!form.mac_address.trim())||undefined} aria-describedby="onb-mac-hint"/>
              <span id="onb-mac-hint" className={err(!form.mac_address.trim())?'te-field-error':'te-hint'}>{err(!form.mac_address.trim())?'Campo obbligatorio.':'Il nome con cui il dispositivo si identifica quando invia i dati.'}</span>
            </div>
            <div className="te-field">
              <label htmlFor="onb-label" className="te-label">Nome</label>
              <input id="onb-label" className="te-input" value={form.label} onChange={e=>set('label',e.target.value)} placeholder="Es. Telecamera ingresso sud" aria-invalid={err(!form.label.trim())||undefined}/>
              {err(!form.label.trim())&&<span className="te-field-error">Campo obbligatorio.</span>}
            </div>
            <div className="te-field">
              <label htmlFor="onb-zone" className="te-label">Zona</label>
              <input id="onb-zone" className="te-input" value={form.zone} onChange={e=>set('zone',e.target.value)} placeholder="Es. Ingresso Sud" aria-invalid={err(!form.zone.trim())||undefined}/>
              {err(!form.zone.trim())&&<span className="te-field-error">Campo obbligatorio.</span>}
            </div>
            <div className="te-field">
              <label htmlFor="onb-type" className="te-label">Tipo di dispositivo</label>
              <select id="onb-type" className="te-select" value={form.device_type} onChange={e=>set('device_type',e.target.value)}>
                {Object.keys(TYPE).map(t=><option key={t} value={t}>{TYPE[t].l}</option>)}
              </select>
            </div>
            {parks.length>1&&(
              <div className="te-field">
                <label htmlFor="onb-park" className="te-label">Parco</label>
                <select id="onb-park" className="te-select" value={form.park_id} onChange={e=>set('park_id',Number(e.target.value))}>
                  {parks.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}
                </select>
              </div>
            )}
            <div className="te-field">
              <label htmlFor="onb-lat" className="te-label">Latitudine</label>
              <input id="onb-lat" className="te-input" type="number" step="0.000001" value={form.lat} onChange={e=>set('lat',e.target.value)}/>
            </div>
            <div className="te-field">
              <label htmlFor="onb-lon" className="te-label">Longitudine</label>
              <input id="onb-lon" className="te-input" type="number" step="0.000001" value={form.lon} onChange={e=>set('lon',e.target.value)}/>
            </div>
          </div>
          <Btn type="submit" variant="primary" loading={saving}>{saving?'Registrazione…':'Registra dispositivo'}</Btn>
        </form>
        {result&&(
          <div role="status" style={{marginTop:16,padding:14,background:'var(--green-light)',border:'1px solid var(--green-mid)',borderRadius:'var(--r-md)',display:'flex',flexDirection:'column',gap:8}}>
            <div style={{display:'flex',alignItems:'center',gap:8,fontWeight:700,color:'var(--green)'}}><CheckCircle2 size={18} aria-hidden="true"/>Dispositivo registrato</div>
            <div style={{fontSize:13,color:'var(--text-2)'}}>Topic MQTT: <code>{result.mqtt_topic}</code></div>
            {result.warning&&<div style={{display:'flex',gap:8,fontSize:13,fontWeight:600,color:'var(--yellow)'}}><AlertTriangle size={16} aria-hidden="true" style={{flexShrink:0}}/>{result.warning}</div>}
            <div style={{display:'flex',gap:8,alignItems:'center'}}>
              <code style={{flex:1,padding:'8px 10px',background:'var(--bg-2)',borderRadius:'var(--r-sm)',wordBreak:'break-all',border:'1px solid var(--border)'}}>{result.api_key}</code>
              <Btn size="sm" variant="secondary" onClick={copyKey} icon={<Copy size={14}/>}>Copia</Btn>
            </div>
          </div>
        )}
      </section>

      <section className="te-card te-card--pad" aria-labelledby="keys-title">
        <SectionTitle as="h2"><span id="keys-title">Chiavi API</span></SectionTitle>
        {loading?<Spinner/>:error?<ErrorState title="Chiavi non disponibili" text={error} onRetry={reload}/>:!keys?.length?<p style={{fontSize:13,color:'var(--text-3)'}}>Nessuna chiave emessa.</p>
          :<ul style={{listStyle:'none',display:'flex',flexDirection:'column',gap:8}}>
            {keys.map(k=>(
              <li key={k.id} style={{padding:'10px 12px',border:'1px solid var(--border)',borderRadius:'var(--r-md)',background:k.active?'var(--bg-2)':'var(--bg-3)'}}>
                <div style={{display:'flex',alignItems:'center',gap:8}}>
                  <span style={{fontSize:14,fontWeight:600,flex:1,minWidth:0,overflow:'hidden',textOverflow:'ellipsis'}}>{k.label}</span>
                  {k.active
                    ? <Btn size="sm" variant="danger" onClick={()=>revoke(k)} ariaLabel={`Revoca la chiave ${k.label}`}>Revoca</Btn>
                    : <span className="te-chip" style={{background:'var(--bg-4)',color:'var(--text-3)'}}>Revocata</span>}
                </div>
                <div className="mono" style={{fontSize:12,color:'var(--text-3)',marginTop:2}}>{k.key_preview} · {k.device_mac||'—'}</div>
              </li>
            ))}
          </ul>}
      </section>
      {dialog}
    </div>
  )
}

function SecurityPanel(){
  const {data:status,setData:setStatus,loading,error,reload}=useLoad(status2FA)
  const [code,setCode]=useState('');const [setupData,setSetupData]=useState(null);const [saving,setSaving]=useState(false)
  const [dialog,ask]=useConfirm()
  async function doSetup(){setSaving(true);try{setSetupData(await setup2FA())}catch(e){toast(e.message,'danger')}finally{setSaving(false)}}
  async function doConfirm(e){e.preventDefault();setSaving(true);try{await confirm2FA(code);setStatus({enabled:true});setSetupData(null);setCode('');toast('Verifica in due passaggi attivata.','success')}catch(err){toast(err.message,'danger',{title:'Codice non valido'})}finally{setSaving(false)}}
  async function doDisable(e){
    e.preventDefault()
    if(!(await ask({title:'Disattivare la verifica in due passaggi?',message:'L\'account sarà protetto solo dalla password.',confirmLabel:'Disattiva',tone:'danger',icon:LockOpen})))return
    setSaving(true);try{await disable2FA(code);setStatus({enabled:false});setCode('');toast('Verifica in due passaggi disattivata.','success')}catch(err){toast(err.message,'danger',{title:'Codice non valido'})}finally{setSaving(false)}
  }
  const onCode=e=>setCode(e.target.value.replace(/\D/g,'').slice(0,6))
  if(loading)return <Loading/>
  if(error)return <ErrorState title="Stato della sicurezza non disponibile" text={error} onRetry={reload}/>
  const on=status?.enabled
  return(
    <div className="te-stack" style={{maxWidth:520}}>
      <div className="te-card" style={{padding:'16px 18px',display:'flex',alignItems:'center',gap:14,borderColor:on?'var(--green-mid)':undefined}}>
        <span style={{width:40,height:40,borderRadius:'var(--r-md)',background:on?'var(--green-light)':'var(--bg-3)',color:on?'var(--green)':'var(--text-3)',display:'inline-flex',alignItems:'center',justifyContent:'center',flexShrink:0}}>
          {on?<Lock size={20} aria-hidden="true"/>:<LockOpen size={20} aria-hidden="true"/>}
        </span>
        <div>
          <div style={{fontSize:15,fontWeight:700}}>Verifica in due passaggi {on?'attiva':'non attiva'}</div>
          <div style={{fontSize:13,color:'var(--text-2)',marginTop:2}}>{on?'Il tuo account è protetto da un codice temporaneo (TOTP).':'Attivala per proteggere l\'account anche se la password venisse scoperta.'}</div>
        </div>
      </div>
      {!on&&!setupData&&<div><Btn variant="primary" onClick={doSetup} loading={saving}>Attiva la verifica in due passaggi</Btn></div>}
      {setupData&&(
        <form onSubmit={doConfirm} className="te-card te-card--pad" style={{display:'flex',flexDirection:'column',gap:12}}>
          <ol style={{paddingLeft:20,display:'flex',flexDirection:'column',gap:8,fontSize:14,color:'var(--text-2)'}}>
            <li>Apri un'app di autenticazione (Google Authenticator, Authy…).</li>
            <li>Aggiungi un account con questa chiave segreta:
              <code style={{display:'block',marginTop:6,padding:'10px 12px',background:'var(--bg-3)',borderRadius:'var(--r-sm)',letterSpacing:'.12em',color:'var(--text-1)',wordBreak:'break-all',border:'1px solid var(--border)'}}>{setupData.secret}</code>
            </li>
            <li>Inserisci il codice a 6 cifre mostrato dall'app.</li>
          </ol>
          <div className="te-field">
            <label htmlFor="totp-confirm" className="te-label">Codice di verifica</label>
            <input id="totp-confirm" className="te-input mono" inputMode="numeric" autoComplete="one-time-code" value={code} onChange={onCode} placeholder="000000" style={{fontSize:22,letterSpacing:'.4em',textAlign:'center'}}/>
          </div>
          <Btn type="submit" variant="primary" loading={saving} disabled={code.length!==6}>Conferma e attiva</Btn>
        </form>
      )}
      {on&&(
        <form onSubmit={doDisable} className="te-card te-card--pad" style={{display:'flex',flexDirection:'column',gap:12}}>
          <h2 style={{fontSize:15,fontWeight:700}}>Disattiva la verifica in due passaggi</h2>
          <div className="te-field">
            <label htmlFor="totp-disable" className="te-label">Codice attuale dell'app</label>
            <input id="totp-disable" className="te-input mono" inputMode="numeric" autoComplete="one-time-code" value={code} onChange={onCode} placeholder="000000" style={{letterSpacing:'.3em'}}/>
          </div>
          <Btn type="submit" variant="danger" loading={saving} disabled={code.length!==6}>Disattiva</Btn>
        </form>
      )}
      {dialog}
    </div>
  )
}

function AccessLogPanel(){
  const {data:log,loading,error,reload}=useLoad(fetchAccessLog)
  if(loading)return <Loading/>
  if(error)return <ErrorState title="Registro accessi non disponibile" text={error} onRetry={reload}/>
  if(!log?.length)return <div className="te-card"><EmptyState icon={History} title="Nessun accesso registrato"/></div>
  return(
    <div className="te-card" style={{maxWidth:960,overflow:'hidden'}}>
      <div className="te-table-wrap">
        <table className="te-table">
          <caption className="sr-only">Registro degli accessi</caption>
          <thead><tr>{['Data e ora','Utente','Azione','Indirizzo IP','Esito'].map(h=><th key={h} scope="col">{h}</th>)}</tr></thead>
          <tbody>
            {log.map(r=>(
              <tr key={r.id}>
                <td style={{whiteSpace:'nowrap',color:'var(--text-2)'}}>{new Date(r.created_at).toLocaleString('it-IT')}</td>
                <td style={{fontWeight:600}}>{r.username}</td>
                <td>{actionLabel(r.action)}</td>
                <td className="mono" style={{color:'var(--text-3)'}}>{r.ip||'—'}</td>
                <td>{r.success
                  ? <span style={{display:'inline-flex',alignItems:'center',gap:6,color:'var(--green)',fontWeight:600}}><CircleCheck size={16} aria-hidden="true"/>Riuscito</span>
                  : <span style={{display:'inline-flex',alignItems:'center',gap:6,color:'var(--red)',fontWeight:600}}><CircleX size={16} aria-hidden="true"/>Fallito</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
