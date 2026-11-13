import React, { useState, useEffect, useRef, useCallback, useMemo } from 'react'
import { List, Map as MapIcon } from 'lucide-react'
import { fetchPractices, fetchPractice, updateStatus as apiUpdate, createWs } from '../lib/api'
import { WsDot, TopBar, RefreshControl, OfflineBanner, KpiCard } from './ui.jsx'
import { toast, ToastContainer } from './Shared.jsx'
import SoundButton, { triggerSound } from './SoundButton.jsx'
import PracticeList from './PracticeList.jsx'
import PracticeDetail from './PracticeDetail.jsx'
import MapView from './MapView.jsx'

// Cestini + sensori di umidità del terreno
const CATEGORIES = ['basket', 'soil']
const CATEGORY_PARAM = CATEGORIES.join(',')
const ECO_TRANS = { open:['in_progress','resolved','closed'], in_progress:['resolved','closed'], resolved:['closed'], closed:[] }
const BASKET_LABELS = { resolved:'Segna come svuotato' }
const isActive = p => p.status === 'open' || p.status === 'in_progress'
const matches = (p, f) => (!f.status || p.status === f.status) && (!f.min_severity || (p.severity || 0) >= Number(f.min_severity))

export default function EcoDashboard({ onLogout, onSwitchRole, username, role = 'eco' }) {
  const [practices,setPractices]=useState([])
  const [selected,setSelected]=useState(null)
  const [loading,setLoading]=useState(true)
  const [error,setError]=useState(null)
  const [detailL,setDL]=useState(false)
  const [wsStatus,setWsStatus]=useState('connecting')
  const [filter,setFilter]=useState({status:'',min_severity:''})
  const [lastUpdated,setLastUpdated]=useState(null)
  const [view,setView]=useState('list')
  const wsRef=useRef(null); const selReq=useRef(0)

  const load=useCallback(async()=>{
    try{const res=await fetchPractices({limit:100,category:CATEGORY_PARAM});setPractices(res.filter(p=>CATEGORIES.includes(p.category)));setError(null);setLastUpdated(Date.now())}
    catch(e){setError(e.message)}
    finally{setLoading(false)}
  },[])
  const select=useCallback(async id=>{
    const req=++selReq.current; setDL(true)
    try{const p=await fetchPractice(id);if(req===selReq.current)setSelected(p)}
    catch(e){if(req===selReq.current)toast(e.message,'danger',{title:`Impossibile aprire la pratica #${id}`})}
    finally{if(req===selReq.current)setDL(false)}
  },[])
  const closeDetail=useCallback(()=>{selReq.current++;setSelected(null);setDL(false)},[])
  const updateStatus=useCallback(async(id,status,note)=>{
    await apiUpdate(id,status,note)
    setPractices(ps=>ps.map(p=>p.id===id?{...p,status,updated_at:new Date().toISOString()}:p));setSelected(s=>s?.id===id?{...s,status}:s)
  },[])

  const handleWs=useCallback(msg=>{
    if(msg.type==='practice_created'){
      if(!CATEGORIES.includes(msg.data.category)) return
      setPractices(ps=>ps.find(x=>x.id===msg.data.id)?ps:[{...msg.data,event_count:1},...ps]); setLastUpdated(Date.now())
      toast(msg.data.title,'info',{title:msg.data.category==='basket'?'Nuovo cestino da gestire':'Nuova segnalazione dal terreno',action:{label:'Apri',onClick:()=>select(msg.data.id)}})
      triggerSound('notify')
    }
    if(msg.type==='practice_updated'){
      const{practice_id,new_event,status,severity}=msg.data
      setPractices(ps=>ps.map(p=>p.id!==practice_id?p:{...p,...(status?{status}:{}),...(severity!==undefined?{severity}:{}),event_count:new_event?(p.event_count||0)+1:p.event_count,updated_at:new Date().toISOString()}))
      setSelected(s=>s?.id!==practice_id?s:{...s,...(status?{status}:{}),...(severity!==undefined?{severity}:{}),...(new_event?{events:[...(s.events||[]),new_event]}:{})})
      setLastUpdated(Date.now())
    }
  },[select])

  useEffect(()=>{load()},[load])
  useEffect(()=>{wsRef.current=createWs(handleWs,setWsStatus);return()=>wsRef.current?.close()},[handleWs])

  const active=useMemo(()=>practices.filter(isActive),[practices])
  const shown=useMemo(()=>practices.filter(p=>matches(p,filter)),[practices,filter])
  const activeBaskets=active.filter(p=>p.category==='basket').length
  const activeSoil=active.length-activeBaskets
  const hasSelection=!!(selected||detailL)

  return(
    <div className="te-app">
      <TopBar role={role} username={username} onSwitchRole={onSwitchRole} onLogout={onLogout}>
        <WsDot status={wsStatus}/>
        <span className="te-topbar-sep te-hide-sm" aria-hidden="true"/>
        <RefreshControl onRefresh={load} lastUpdated={lastUpdated}/>
        <SoundButton/>
      </TopBar>
      <OfflineBanner status={wsStatus} lastUpdated={lastUpdated} onRetry={load}/>

      <section aria-label="Riepilogo segnalazioni" className="te-kpis">
        <KpiCard label="Da gestire" value={active.length} sub={`su ${practices.length} segnalazioni`} color={active.length?'var(--yellow)':'var(--green)'}/>
        <KpiCard label="Cestini da svuotare" value={activeBaskets}/>
        <KpiCard label="Terreno da controllare" value={activeSoil}/>
      </section>

      <div className="te-workspace" data-view={view} data-has-selection={hasSelection} style={{'--list-w':'340px','--detail-w':'380px'}}>
        <section className="te-pane te-pane-list" aria-label="Elenco segnalazioni">
          <PracticeList title="Segnalazioni" practices={shown} loading={loading} error={error} onRetry={()=>{setLoading(true);load()}}
            selected={selected} filter={filter} setFilter={setFilter} onSelect={select} showCategory/>
        </section>
        <section className="te-pane te-pane-map" aria-label="Mappa delle segnalazioni da gestire">
          <MapView practices={active} selected={selected} onSelect={select}/>
        </section>
        <aside className="te-pane te-pane-detail" aria-label="Dettaglio segnalazione">
          <PracticeDetail practice={selected} loading={detailL} onUpdateStatus={updateStatus} onClose={closeDetail} canDelete={!!onSwitchRole}
            escalation={false} showActuators={false} transitions={ECO_TRANS} labels={selected?.category==='basket'?BASKET_LABELS:undefined}
            emptyText="Scegli una segnalazione dall'elenco o sulla mappa per vederne i dettagli e aggiornarne lo stato."
            onDeleted={id=>{setPractices(ps=>ps.filter(p=>p.id!==id));closeDetail()}}/>
        </aside>
      </div>

      {!hasSelection && (
        <nav className="te-bottomnav" aria-label="Vista">
          <button type="button" aria-current={view==='list'?'page':undefined} onClick={()=>setView('list')}><List size={22} aria-hidden="true"/>Segnalazioni</button>
          <button type="button" aria-current={view==='map'?'page':undefined} onClick={()=>setView('map')}><MapIcon size={22} aria-hidden="true"/>Mappa</button>
        </nav>
      )}
      <ToastContainer/>
    </div>
  )
}
