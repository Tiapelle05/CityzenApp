import React, { useState, useEffect, useRef, useCallback } from 'react'
import { fetchPractices, fetchPractice, updateStatus as apiUpdate, createWs } from '../lib/api'
import { CATEGORY_LABEL } from './ui.jsx'
import { toast } from './Shared.jsx'
import PracticeList from './PracticeList.jsx'
import PracticeDetail from './PracticeDetail.jsx'

/** Admin › Pratiche: tutte le categorie, con filtro, dettaglio ed eliminazione. */
export default function AdminPractices() {
  const [practices,setPractices]=useState([])
  const [loading,setLoading]=useState(true)
  const [error,setError]=useState(null)
  const [filter,setFilter]=useState({status:'',min_severity:''})
  const [category,setCategory]=useState('')
  const [selected,setSelected]=useState(null)
  const [detailL,setDL]=useState(false)
  const selReq=useRef(0); const selId=useRef(null); const loadRef=useRef(null)
  selId.current=selected?.id??null

  const load=useCallback(async()=>{
    try{setPractices(await fetchPractices({limit:200,status:filter.status,min_severity:filter.min_severity,category}));setError(null)}
    catch(e){setError(e.message)}
    finally{setLoading(false)}
  },[filter,category])
  loadRef.current=load
  useEffect(()=>{setLoading(true);load()},[load])

  const select=useCallback(async id=>{
    const req=++selReq.current; setDL(true)
    try{const p=await fetchPractice(id);if(req===selReq.current)setSelected(p)}
    catch(e){if(req===selReq.current)toast(e.message,'danger',{title:`Impossibile aprire la pratica #${id}`})}
    finally{if(req===selReq.current)setDL(false)}
  },[])
  const closeDetail=useCallback(()=>{selReq.current++;setSelected(null);setDL(false)},[])
  const updateStatus=useCallback(async(id,status,note)=>{
    await apiUpdate(id,status,note)
    setSelected(s=>s?.id===id?{...s,status}:s)
    loadRef.current()
  },[])

  // Aggiornamenti in tempo reale: ricarica l'elenco e la pratica aperta
  useEffect(()=>{
    const ws=createWs(msg=>{
      if(msg.type!=='practice_created'&&msg.type!=='practice_updated') return
      loadRef.current()
      const id=msg.data?.practice_id
      if(id&&id===selId.current) fetchPractice(id).then(p=>setSelected(s=>s?.id===id?p:s)).catch(()=>{})
    },()=>{})
    return()=>ws.close()
  },[])

  const hasSelection=!!(selected||detailL)
  return(
    <div className="te-card te-split" data-has-selection={hasSelection} style={{maxWidth:1120}}>
      <section className="te-pane te-pane-list" aria-label="Elenco pratiche">
        <PracticeList practices={practices} loading={loading} error={error} onRetry={()=>{setLoading(true);load()}}
          selected={selected} filter={filter} setFilter={setFilter} onSelect={select} showCategory
          headExtra={
            <label style={{display:'flex',alignItems:'center',justifyContent:'space-between',gap:12,fontSize:13,color:'var(--text-2)'}}>
              Categoria
              <select className="te-select te-select--sm" style={{width:'auto'}} value={category} onChange={e=>setCategory(e.target.value)}>
                <option value="">Tutte</option>
                {['security','basket','soil','other'].map(c=><option key={c} value={c}>{CATEGORY_LABEL[c]}</option>)}
              </select>
            </label>
          }/>
      </section>
      <aside className="te-pane" aria-label="Dettaglio pratica">
        <PracticeDetail practice={selected} loading={detailL} onUpdateStatus={updateStatus} onClose={closeDetail} canDelete
          escalation={selected?.category==='security'} showActuators={selected?.category==='security'}
          onDeleted={id=>{setPractices(ps=>ps.filter(p=>p.id!==id));closeDetail()}}/>
      </aside>
    </div>
  )
}
