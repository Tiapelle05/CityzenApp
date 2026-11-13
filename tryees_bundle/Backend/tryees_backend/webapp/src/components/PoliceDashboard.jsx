import React, { useState, useEffect, useRef, useCallback } from 'react'
import { List, Map as MapIcon } from 'lucide-react'
import { fetchPractices, fetchPractice, fetchOverview, updateStatus as apiUpdate, createWs } from '../lib/api'
import { WsDot, TopBar, RefreshControl, OfflineBanner, fmt1 } from './ui.jsx'
import { toast, ToastContainer } from './Shared.jsx'
import SoundButton, { triggerSound } from './SoundButton.jsx'
import Overview from './Overview.jsx'
import PracticeList from './PracticeList.jsx'
import PracticeDetail from './PracticeDetail.jsx'
import MapView from './MapView.jsx'

const PAGE_SIZE = 50
const CATEGORY = 'security'

const matches = (p, f) => (!f.status || p.status === f.status) && (!f.min_severity || (p.severity || 0) >= Number(f.min_severity))

export default function PoliceDashboard({ onLogout, onSwitchRole, username, role = 'police' }) {
  const [practices,setPractices]=useState([])
  const [hasMore,setHasMore]=useState(false)
  const [loadingMore,setLoadingMore]=useState(false)
  const [overview,setOverview]=useState([])
  const [selected,setSelected]=useState(null)
  const [loading,setLoading]=useState(true)
  const [error,setError]=useState(null)
  const [detailL,setDL]=useState(false)
  const [wsStatus,setWsStatus]=useState('connecting')
  const [filter,setFilter]=useState({status:'',min_severity:''})
  const [flash,setFlash]=useState(new Set())
  const [lastUpdated,setLastUpdated]=useState(null)
  const [view,setView]=useState('list')           // solo smartphone: 'list' | 'map'
  const wsRef=useRef(null); const selReq=useRef(0)
  const filterRef=useRef(filter); filterRef.current=filter

  const addFlash=id=>{setFlash(s=>new Set(s).add(id));setTimeout(()=>setFlash(s=>{const n=new Set(s);n.delete(id);return n}),900)}
  const params=(skip)=>{const p={limit:PAGE_SIZE,skip,category:CATEGORY};if(filter.status)p.status=filter.status;if(filter.min_severity)p.min_severity=filter.min_severity;return p}

  const load=useCallback(async()=>{
    try{const res=await fetchPractices(params(0));setPractices(res.filter(p=>p.category===CATEGORY));setHasMore(res.length===PAGE_SIZE);setError(null);setLastUpdated(Date.now())}
    catch(e){setError(e.message)}
    finally{setLoading(false)}
  // eslint-disable-next-line react-hooks/exhaustive-deps
  },[filter])

  const loadMore=useCallback(async()=>{
    setLoadingMore(true)
    try{const res=await fetchPractices(params(practices.length));setPractices(ps=>[...ps,...res.filter(r=>!ps.some(p=>p.id===r.id))]);setHasMore(res.length===PAGE_SIZE)}
    catch(e){toast(e.message,'danger',{title:'Impossibile caricare altre pratiche'})}
    finally{setLoadingMore(false)}
  // eslint-disable-next-line react-hooks/exhaustive-deps
  },[practices.length,filter])

  const loadOv=useCallback(async()=>{try{setOverview(await fetchOverview(CATEGORY))}catch{}},[])
  const reload=useCallback(()=>Promise.all([load(),loadOv()]),[load,loadOv])

  const select=useCallback(async id=>{
    const req=++selReq.current
    setDL(true)
    try{const p=await fetchPractice(id);if(req===selReq.current)setSelected(p)}
    catch(e){if(req===selReq.current)toast(e.message,'danger',{title:`Impossibile aprire la pratica #${id}`})}
    finally{if(req===selReq.current)setDL(false)}
  },[])
  const closeDetail=useCallback(()=>{selReq.current++;setSelected(null);setDL(false)},[])

  const updateStatus=useCallback(async(id,status,note)=>{
    await apiUpdate(id,status,note)
    setPractices(ps=>ps.map(p=>p.id===id?{...p,status,updated_at:new Date().toISOString()}:p).filter(p=>matches(p,filterRef.current)));setSelected(s=>s?.id===id?{...s,status}:s);addFlash(id);loadOv()
  },[loadOv])

  const handleWs=useCallback(msg=>{
    if(msg.type==='practice_created'){
      if(msg.data.category!==CATEGORY) return
      if(matches(msg.data,filterRef.current)) setPractices(ps=>ps.find(x=>x.id===msg.data.id)?ps:[{...msg.data,event_count:1},...ps])
      addFlash(msg.data.id); loadOv(); setLastUpdated(Date.now())
      const critical=(msg.data.severity||0)>=7
      toast(`${msg.data.title} · severità ${fmt1(msg.data.severity)}`, critical?'alert':'info', { title: critical?'Nuova pratica critica':'Nuova pratica', action:{ label:'Apri', onClick:()=>select(msg.data.id) } })
      triggerSound(critical?'alert':'notify')
    }
    if(msg.type==='practice_updated'){
      const{practice_id,new_event,status,severity}=msg.data
      setPractices(ps=>ps.map(p=>p.id!==practice_id?p:{...p,...(status?{status}:{}),...(severity!==undefined?{severity}:{}),event_count:new_event?(p.event_count||0)+1:p.event_count,updated_at:new Date().toISOString()}).filter(p=>matches(p,filterRef.current)))
      addFlash(practice_id); setLastUpdated(Date.now())
      setSelected(s=>s?.id!==practice_id?s:{...s,...(status?{status}:{}),...(severity!==undefined?{severity}:{}),...(new_event?{events:[...(s.events||[]),new_event]}:{})})
      if(status) loadOv()
    }
  },[loadOv,select])

  useEffect(()=>{setLoading(true);load()},[load])
  useEffect(()=>{loadOv()},[loadOv])
  useEffect(()=>{wsRef.current=createWs(handleWs,setWsStatus);return()=>wsRef.current?.close()},[handleWs])

  const hasSelection=!!(selected||detailL)

  return(
    <div className="te-app">
      <TopBar role={role} username={username} onSwitchRole={onSwitchRole} onLogout={onLogout}>
        <WsDot status={wsStatus}/>
        <span className="te-topbar-sep te-hide-sm" aria-hidden="true"/>
        <RefreshControl onRefresh={reload} lastUpdated={lastUpdated}/>
        <SoundButton/>
      </TopBar>
      <OfflineBanner status={wsStatus} lastUpdated={lastUpdated} onRetry={reload}/>
      <Overview data={overview}/>

      <div className="te-workspace" data-view={view} data-has-selection={hasSelection}>
        <section className="te-pane te-pane-list" aria-label="Elenco pratiche">
          <PracticeList practices={practices} loading={loading} error={error} onRetry={()=>{setLoading(true);load()}}
            selected={selected} flash={flash} filter={filter} setFilter={setFilter}
            onSelect={select} onLoadMore={loadMore} hasMore={hasMore} loadingMore={loadingMore}/>
        </section>
        <section className="te-pane te-pane-map" aria-label="Mappa">
          <MapView practices={practices} selected={selected} onSelect={select}/>
        </section>
        <aside className="te-pane te-pane-detail" aria-label="Dettaglio pratica">
          <PracticeDetail practice={selected} loading={detailL} onUpdateStatus={updateStatus} onClose={closeDetail} canDelete={!!onSwitchRole}
            onDeleted={id=>{setPractices(ps=>ps.filter(p=>p.id!==id));closeDetail();loadOv()}}/>
        </aside>
      </div>

      {!hasSelection && (
        <nav className="te-bottomnav" aria-label="Vista">
          <button type="button" aria-current={view==='list'?'page':undefined} onClick={()=>setView('list')}><List size={22} aria-hidden="true"/>Pratiche</button>
          <button type="button" aria-current={view==='map'?'page':undefined} onClick={()=>setView('map')}><MapIcon size={22} aria-hidden="true"/>Mappa</button>
        </nav>
      )}
      <ToastContainer/>
    </div>
  )
}
