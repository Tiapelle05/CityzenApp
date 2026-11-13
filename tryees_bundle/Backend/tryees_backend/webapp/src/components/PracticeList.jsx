import React from 'react'
import { ShieldCheck, SearchX } from 'lucide-react'
import { SeverityBadge, StatusBadge, Segmented, EmptyState, ErrorState, SkeletonRows, Btn, timeAgo, useNow, fmtDateTime, CATEGORY_LABEL } from './ui.jsx'

const STATUSES = [['', 'Tutte'], ['open', 'Aperte'], ['in_progress', 'In carico'], ['resolved', 'Risolte'], ['closed', 'Chiuse']]

export default function PracticeList({ practices, loading, error, onRetry, selected, flash, filter, setFilter, onSelect, onLoadMore, hasMore, loadingMore, title = 'Pratiche', headExtra, showCategory }) {
  const now = useNow(30000)
  const filtered = !!(filter.status || filter.min_severity)
  return (
    <>
      <div className="te-list-head">
        <div style={{ display:'flex', alignItems:'baseline', justifyContent:'space-between', gap:8 }}>
          <h2 style={{ fontSize:16, fontWeight:700 }}>{title}</h2>
          {!loading && !error && <span style={{ fontSize:13, color:'var(--text-3)' }}>{practices.length}{hasMore ? '+' : ''} {practices.length === 1 ? 'risultato' : 'risultati'}</span>}
        </div>
        <Segmented label="Filtra per stato" options={STATUSES} value={filter.status} onChange={v => setFilter(f => ({ ...f, status: v }))}/>
        <label style={{ display:'flex', alignItems:'center', justifyContent:'space-between', gap:12, fontSize:13, color:'var(--text-2)' }}>
          Severità minima
          <select className="te-select te-select--sm" style={{ width:'auto' }} value={filter.min_severity} onChange={e => setFilter(f => ({ ...f, min_severity: e.target.value }))}>
            <option value="">Qualsiasi</option>
            <option value="4">Media o superiore (≥ 4)</option>
            <option value="7">Solo critiche (≥ 7)</option>
          </select>
        </label>
        {headExtra}
      </div>

      <div className="te-list-body">
        {loading ? <SkeletonRows n={6}/>
          : error ? <ErrorState title="Impossibile caricare le pratiche" text={error} onRetry={onRetry}/>
          : practices.length === 0 ? (
            filtered
              ? <EmptyState icon={SearchX} title="Nessuna pratica con questi filtri" text="Prova a includere altri stati o una severità più bassa."
                  action={<Btn size="sm" variant="secondary" onClick={() => setFilter({ status:'', min_severity:'' })}>Rimuovi filtri</Btn>}/>
              : <EmptyState icon={ShieldCheck} tone="ok" title="Nessuna pratica" text="Il parco è tranquillo. Le nuove segnalazioni dei sensori compariranno qui in automatico."/>
          ) : (
            <ul style={{ listStyle:'none' }} aria-label="Elenco pratiche">
              {practices.map(p => (
                <li key={p.id}>
                  <Row p={p} now={now} showCategory={showCategory} active={selected?.id === p.id} flashing={flash?.has(p.id)} onClick={() => onSelect(p.id)}/>
                </li>
              ))}
            </ul>
          )}
      </div>

      {!loading && !error && practices.length > 0 && (
        <div className="te-list-foot">
          <span>{hasMore ? `Prime ${practices.length} pratiche` : `${practices.length} ${practices.length === 1 ? 'pratica' : 'pratiche'}`}</span>
          {hasMore && <Btn size="sm" variant="secondary" onClick={onLoadMore} loading={loadingMore}>{loadingMore ? 'Caricamento…' : 'Carica altre'}</Btn>}
        </div>
      )}
    </>
  )
}

function Row({ p, now, active, flashing, onClick, showCategory }) {
  const n = p.event_count || 0
  return (
    <button type="button" className={`te-row${flashing ? ' te-row--flash' : ''}`} aria-current={active || undefined} onClick={onClick}>
      <span className="te-row-top">
        <span className="te-row-title">{p.title}</span>
        <SeverityBadge value={p.severity || 0} compact/>
      </span>
      <span className="te-row-meta">
        <span className="mono">#{p.id}</span><span aria-hidden="true">·</span>
        {showCategory && p.category && <><span>{CATEGORY_LABEL[p.category] || p.category}</span><span aria-hidden="true">·</span></>}
        <StatusBadge status={p.status} plain/><span aria-hidden="true">·</span>
        <span>{n} {n === 1 ? 'evento' : 'eventi'}</span>
        <span className="te-grow"/>
        <time dateTime={p.updated_at} title={fmtDateTime(p.updated_at)} style={{ whiteSpace:'nowrap' }}>{timeAgo(p.updated_at, now)}</time>
      </span>
    </button>
  )
}
