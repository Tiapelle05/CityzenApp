import React, { useState, useEffect, useCallback, useRef, useMemo } from 'react'
import { List, Map as MapIcon, ArrowLeft, MousePointerClick, Wrench, History, SearchX, Info } from 'lucide-react'
import { fetchAllDevices, updateDeviceStatus, addMaintenance, fetchMaintenance } from '../lib/api'
import { L, createParkMap, dotIcon, escHtml } from '../lib/map'
import { Spinner, Btn, TopBar, RefreshControl, KpiCard, Segmented, EmptyState, ErrorState, SkeletonRows, fmtDateTime } from './ui.jsx'
import { toast, ToastContainer } from './Shared.jsx'
import { ST, typeOf, stOf, since, DeviceStatus } from './devices.jsx'

// Stati impostabili a mano: "offline" lo rileva il sistema quando il dispositivo smette di trasmettere
const MANUAL = ['ok', 'guasto', 'manutenzione']
const REFRESH_MS = 30000
/** "status: ok → guasto" (registro del backend) diventa "Stato: Operativo → Guasto" */
const humanAction = a => String(a || '').replace(/^status:\s*(\S+)\s*→\s*(\S+)$/, (_, o, n) => `Stato: ${ST[o]?.l || 'Operativo'} → ${ST[n]?.l || n}`)

export default function MaintenanceDashboard({ onLogout, onSwitchRole, username, role = 'maintenance' }) {
  const [devices,setDevices]=useState([]); const [loading,setL]=useState(true); const [error,setError]=useState(null)
  const [filter,setFilter]=useState('all'); const [lastUpdated,setLastUpdated]=useState(null)
  const [query,setQuery]=useState(''); const [typeFilter,setTypeFilter]=useState('')
  const [selected,setSelected]=useState(null); const [mlog,setMlog]=useState([]); const [mlogL,setML]=useState(false)
  const [newStatus,setNewStatus]=useState('ok'); const [statusNotes,setStatusNotes]=useState('')
  const [newAction,setNewAction]=useState(''); const [logNotes,setLogNotes]=useState('')
  const [saving,setSaving]=useState(null); const [view,setView]=useState('list')
  const mapEl=useRef(null); const mapApi=useRef(null); const markers=useRef({}); const fitted=useRef(false); const logReq=useRef(0)

  const load=useCallback(async()=>{
    try{
      const list=await fetchAllDevices()
      setDevices(list);setError(null);setLastUpdated(Date.now())
      setSelected(s=>s?(list.find(d=>d.mac_address===s.mac_address)||s):s)   // tiene allineato il dettaglio aperto
    }
    catch(e){setError(e.message)}
    finally{setL(false)}
  },[])
  useEffect(()=>{load();const id=setInterval(load,REFRESH_MS);return()=>clearInterval(id)},[load])

  const types=useMemo(()=>[...new Set(devices.map(d=>d.type))].sort((a,b)=>typeOf(a).l.localeCompare(typeOf(b).l)),[devices])
  const shown=useMemo(()=>{
    const q=query.trim().toLowerCase()
    return devices.filter(d=>(filter!=='faulty'||(d.status&&d.status!=='ok'))
      &&(!typeFilter||d.type===typeFilter)
      &&(!q||`${typeOf(d.type).l} ${d.zone||''} ${d.mac_address}`.toLowerCase().includes(q)))
  },[devices,filter,typeFilter,query])
  const searching=!!(query.trim()||typeFilter)
  const count=s=>devices.filter(d=>(d.status||'ok')===s).length
  const faultyCount=devices.length-count('ok')

  const selectDevice=useCallback(async d=>{
    const req=++logReq.current
    setSelected(d);setNewStatus(d.raw_status||'ok');setStatusNotes(d.notes||'');setNewAction('');setLogNotes('')
    setML(true);setMlog([])
    try{const rows=await fetchMaintenance(d.mac_address);if(req===logReq.current)setMlog(rows)}
    catch{if(req===logReq.current)setMlog([])}
    finally{if(req===logReq.current)setML(false)}
  },[])

  useEffect(()=>{
    mapApi.current=createParkMap(mapEl.current)
    return()=>{mapApi.current.map.remove();mapApi.current=null;markers.current={}}
  },[])
  useEffect(()=>{
    const map=mapApi.current?.map; if(!map)return
    Object.values(markers.current).forEach(m=>m.remove());markers.current={}
    shown.filter(d=>d.lat&&d.lon).forEach(d=>{
      const m=stOf(d.status), isSel=selected?.mac_address===d.mac_address
      markers.current[d.mac_address]=L.marker([d.lat,d.lon],{icon:dotIcon(m.hex,{selected:isSel,ring:(d.status||'ok')==='ok'}),zIndexOffset:isSel?1000:0,title:`${typeOf(d.type).l} ${d.mac_address}`})
        .addTo(map).bindTooltip(`<strong>${escHtml(typeOf(d.type).l)}</strong> · ${escHtml(d.zone)}<br><span style="font-family:var(--mono)">${escHtml(d.mac_address)}</span> · ${escHtml(m.l)}`,{className:'map-tip',direction:'top',offset:[0,-8]})
        .on('click',()=>selectDevice(d))
    })
    // Al primo caricamento inquadra tutti i dispositivi
    const pts=Object.values(markers.current).map(m=>m.getLatLng())
    if(!fitted.current&&pts.length){fitted.current=true;if(!selected)map.fitBounds(L.latLngBounds(pts).pad(0.15),{maxZoom:18})}
  },[shown,selected,selectDevice])
  useEffect(()=>{const map=mapApi.current?.map;if(map&&selected?.lat)map.setView([selected.lat,selected.lon],19,{animate:true})},[selected?.mac_address])

  async function saveStatus(e){
    e.preventDefault(); setSaving('status')
    try{
      const u=await updateDeviceStatus(selected.mac_address,{status:newStatus,notes:statusNotes})
      setDevices(ds=>ds.map(d=>d.mac_address===selected.mac_address?u:d));setSelected(u)
      setMlog(await fetchMaintenance(selected.mac_address).catch(()=>mlog))
      toast(`Stato aggiornato: ${stOf(u.status).l.toLowerCase()}.`,'success')
    }catch(err){toast(err.message,'danger',{title:'Stato non aggiornato'})}
    finally{setSaving(null)}
  }
  async function addLog(e){
    e.preventDefault(); if(!newAction.trim())return
    setSaving('log')
    try{
      await addMaintenance(selected.mac_address,{action:newAction.trim(),notes:logNotes||undefined})
      setMlog(await fetchMaintenance(selected.mac_address));setNewAction('');setLogNotes('')
      toast('Intervento registrato.','success')
    }catch(err){toast(err.message,'danger',{title:'Intervento non registrato'})}
    finally{setSaving(null)}
  }

  const close=()=>setSelected(null)
  const statusChanged=selected && (newStatus!==(selected.raw_status||'ok') || (statusNotes||'')!==(selected.notes||''))

  return(
    <div className="te-app">
      <TopBar role={role} username={username} onSwitchRole={onSwitchRole} onLogout={onLogout}>
        <RefreshControl onRefresh={load} lastUpdated={lastUpdated}/>
      </TopBar>

      <section aria-label="Riepilogo dispositivi" className="te-kpis">
        <KpiCard label="Dispositivi" value={devices.length}/>
        <KpiCard label="Operativi" value={count('ok')} color="var(--green)"/>
        <KpiCard label="Guasti" value={count('guasto')} color={count('guasto')?'var(--red)':'var(--text-1)'}/>
        <KpiCard label="In manutenzione" value={count('manutenzione')} color={count('manutenzione')?'var(--yellow)':'var(--text-1)'}/>
        <KpiCard label="Offline" value={count('offline')} color="var(--text-3)"/>
      </section>

      <div className="te-workspace" data-view={view} data-has-selection={!!selected} style={{'--list-w':'340px','--detail-w':'380px'}}>
        <section className="te-pane te-pane-list" aria-label="Elenco dispositivi">
          <div className="te-list-head">
            <div style={{display:'flex',alignItems:'baseline',justifyContent:'space-between',gap:8}}>
              <h2 style={{fontSize:16,fontWeight:700}}>Dispositivi</h2>
              {!loading&&!error&&<span style={{fontSize:13,color:'var(--text-3)'}}>{shown.length} {shown.length===1?'risultato':'risultati'}</span>}
            </div>
            <Segmented label="Filtra dispositivi" value={filter} onChange={setFilter} options={[['all','Tutti'],['faulty',`Non operativi${faultyCount?` · ${faultyCount}`:''}`]]}/>
            <div style={{display:'flex',gap:8}}>
              <input type="search" className="te-input" style={{flex:1,minWidth:0}} value={query} onChange={e=>setQuery(e.target.value)} placeholder="Cerca…" aria-label="Cerca dispositivo"/>
              <select className="te-select" style={{width:'auto',maxWidth:150}} value={typeFilter} onChange={e=>setTypeFilter(e.target.value)} aria-label="Filtra per tipo">
                <option value="">Tutti i tipi</option>
                {types.map(t=><option key={t} value={t}>{typeOf(t).l}</option>)}
              </select>
            </div>
          </div>
          <div className="te-list-body">
            {loading?<SkeletonRows n={7}/>
              :error?<ErrorState title="Impossibile caricare i dispositivi" text={error} onRetry={()=>{setL(true);load()}}/>
              :shown.length===0?(searching
                ?<EmptyState icon={SearchX} title="Nessun dispositivo trovato" text="Prova con un'altra ricerca o un altro tipo."
                    action={<Btn size="sm" variant="secondary" onClick={()=>{setQuery('');setTypeFilter('')}}>Rimuovi filtri</Btn>}/>
                :filter==='faulty'
                ?<EmptyState tone="ok" title="Tutti i dispositivi sono operativi" text="Non ci sono guasti, manutenzioni o dispositivi offline."/>
                :<EmptyState title="Nessun dispositivo registrato" text="I dispositivi registrati dall'amministratore compariranno qui."/>)
              :(
                <ul style={{listStyle:'none'}} aria-label="Dispositivi">
                  {shown.map(d=>{const t=typeOf(d.type);return(
                    <li key={d.mac_address}>
                      <button type="button" className="te-row" aria-current={selected?.mac_address===d.mac_address||undefined} onClick={()=>selectDevice(d)}>
                        <span className="te-row-top">
                          <t.icon size={16} aria-hidden="true" style={{color:'var(--text-3)',flexShrink:0,marginTop:2}}/>
                          <span className="te-row-title">{t.l} · {d.zone}</span>
                          <DeviceStatus status={d.status}/>
                        </span>
                        <span className="te-row-meta"><span className="mono">{d.mac_address}</span></span>
                      </button>
                    </li>)})}
                </ul>
              )}
          </div>
        </section>

        <section className="te-pane te-pane-map" aria-label="Mappa dei dispositivi">
          <div ref={mapEl} style={{width:'100%',height:'100%'}}/>
          <div className="te-map-float te-map-panel te-legend" style={{left:12,bottom:12}}>
            <strong>Stato</strong>
            {Object.entries(ST).map(([k,m])=>(
              <span key={k} className="te-legend-item"><span aria-hidden="true" className="te-dot" style={k==='ok'?{background:'#fff',border:`3px solid ${m.hex}`,width:10,height:10}:{background:m.hex}}/>{m.l}</span>
            ))}
          </div>
        </section>

        <aside className="te-pane te-pane-detail" aria-label="Dettaglio dispositivo">
          {!selected?(
            <EmptyState icon={MousePointerClick} title="Seleziona un dispositivo" text="Scegli un dispositivo dall'elenco o sulla mappa per aggiornarne lo stato e registrare un intervento."/>
          ):(
            <div style={{height:'100%',display:'flex',flexDirection:'column',overflow:'hidden'}}>
              <div className="te-detail-head">
                <button type="button" className="te-btn te-btn--link te-only-overlay" onClick={close} style={{alignSelf:'flex-start',marginLeft:-6,gap:4,fontSize:15}}><ArrowLeft size={18} aria-hidden="true"/>Torna all'elenco</button>
                <div className="te-detail-kicker"><span>{typeOf(selected.type).l}</span><span aria-hidden="true">·</span><span>{selected.zone}</span></div>
                <h2 className="te-detail-title mono" style={{fontSize:18}}>{selected.mac_address}</h2>
                <DeviceStatus status={selected.status}/>
                {selected.lat!=null&&selected.lon!=null&&<div className="mono" style={{fontSize:12,color:'var(--text-3)'}}>{selected.lat.toFixed(6)}, {selected.lon.toFixed(6)}</div>}
                {selected.notes&&<p style={{fontSize:13,color:'var(--text-2)',padding:'8px 10px',background:'var(--bg-3)',borderRadius:'var(--r-sm)'}}>{selected.notes}</p>}
              </div>
              <div className="te-detail-body" style={{gap:20}}>
                <form onSubmit={saveStatus} style={{display:'flex',flexDirection:'column',gap:10}}>
                  <h3 style={{fontSize:15,fontWeight:700,display:'flex',alignItems:'center',gap:8}}><Wrench size={16} aria-hidden="true"/>Aggiorna stato</h3>
                  <div className="te-field">
                    <label htmlFor="dev-status" className="te-label">Stato</label>
                    <select id="dev-status" className="te-select" value={newStatus} onChange={e=>setNewStatus(e.target.value)}>{MANUAL.map(k=><option key={k} value={k}>{ST[k].l}</option>)}</select>
                    {selected.status==='offline'&&<span className="te-hint" style={{display:'flex',gap:6,alignItems:'flex-start'}}><Info size={14} aria-hidden="true" style={{flexShrink:0,marginTop:2}}/>Risulta offline perché non trasmette{selected.minutes_since!=null?` da ${since(selected.minutes_since)}`:''}: tornerà operativo da solo appena riprende a inviare dati.</span>}
                  </div>
                  <div className="te-field">
                    <label htmlFor="dev-status-notes" className="te-label">Note sul dispositivo <span style={{fontWeight:400,color:'var(--text-3)'}}>(facoltative)</span></label>
                    <textarea id="dev-status-notes" className="te-textarea" rows={2} value={statusNotes} onChange={e=>setStatusNotes(e.target.value)} placeholder="Es. in attesa del pezzo di ricambio"/>
                  </div>
                  <Btn type="submit" variant="primary" loading={saving==='status'} disabled={!statusChanged||!!saving}>Salva stato</Btn>
                </form>

                <form onSubmit={addLog} style={{display:'flex',flexDirection:'column',gap:10,paddingTop:16,borderTop:'1px solid var(--border)'}}>
                  <h3 style={{fontSize:15,fontWeight:700}}>Registra intervento</h3>
                  <div className="te-field">
                    <label htmlFor="dev-action" className="te-label">Intervento eseguito</label>
                    <input id="dev-action" className="te-input" value={newAction} onChange={e=>setNewAction(e.target.value)} placeholder="Es. sostituito sensore VL53L0X"/>
                  </div>
                  <div className="te-field">
                    <label htmlFor="dev-log-notes" className="te-label">Note <span style={{fontWeight:400,color:'var(--text-3)'}}>(facoltative)</span></label>
                    <textarea id="dev-log-notes" className="te-textarea" rows={2} value={logNotes} onChange={e=>setLogNotes(e.target.value)}/>
                  </div>
                  <Btn type="submit" variant="secondary" loading={saving==='log'} disabled={!newAction.trim()||!!saving}>Registra intervento</Btn>
                </form>

                <section style={{paddingTop:16,borderTop:'1px solid var(--border)'}} aria-label="Storico interventi">
                  <h3 style={{fontSize:15,fontWeight:700,display:'flex',alignItems:'center',gap:8,marginBottom:10}}><History size={16} aria-hidden="true"/>Storico interventi</h3>
                  {mlogL?<Spinner size={16}/>:mlog.length===0
                    ?<p style={{fontSize:13,color:'var(--text-3)'}}>Nessun intervento registrato per questo dispositivo.</p>
                    :<ol style={{listStyle:'none',display:'flex',flexDirection:'column',gap:12}}>
                      {mlog.map(r=>(
                        <li key={r.id} style={{paddingBottom:12,borderBottom:'1px solid var(--bg-4)'}}>
                          <div style={{fontSize:14,fontWeight:600}}>{humanAction(r.action)}</div>
                          <div style={{fontSize:12,color:'var(--text-3)'}}>{fmtDateTime(r.created_at)} · {r.actor}</div>
                          {r.notes&&<div style={{fontSize:13,color:'var(--text-2)',marginTop:2}}>{r.notes}</div>}
                        </li>
                      ))}
                    </ol>}
                </section>
              </div>
            </div>
          )}
        </aside>
      </div>

      {!selected&&(
        <nav className="te-bottomnav" aria-label="Vista">
          <button type="button" aria-current={view==='list'?'page':undefined} onClick={()=>setView('list')}><List size={22} aria-hidden="true"/>Dispositivi</button>
          <button type="button" aria-current={view==='map'?'page':undefined} onClick={()=>setView('map')}><MapIcon size={22} aria-hidden="true"/>Mappa</button>
        </nav>
      )}
      <ToastContainer/>
    </div>
  )
}
