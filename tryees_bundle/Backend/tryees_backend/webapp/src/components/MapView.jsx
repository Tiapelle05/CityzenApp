import React, { useEffect, useRef, useState } from 'react'
import { L, createParkMap, severityIcon, escHtml, TILE_LAYERS } from '../lib/map'
import { Segmented, fmt1, sevLabel } from './ui.jsx'

/** Mappa delle pratiche (Polizia, Eco): marker per severità, selezione, legenda, cambio sfondo. */
export default function MapView({ practices, selected, onSelect }) {
  const el = useRef(null), api = useRef(null), mks = useRef({}), fitted = useRef(false)
  const onSelectRef = useRef(onSelect)
  onSelectRef.current = onSelect
  const [tileMode, setTileMode] = useState('street')

  useEffect(() => {
    api.current = createParkMap(el.current)
    return () => { api.current.map.remove(); api.current = null; mks.current = {} }
  }, [])

  useEffect(() => { api.current?.setTiles(tileMode) }, [tileMode])

  useEffect(() => {
    const map = api.current?.map; if (!map) return
    Object.values(mks.current).forEach(m => m.remove()); mks.current = {}
    practices.filter(p => p.lat && p.lon && p.status !== 'closed').forEach(p => {
      const isSel = selected?.id === p.id
      const tip = `<strong>#${p.id}</strong> ${escHtml(p.title)}<br><span style="color:#5E6660">Severità ${escHtml(sevLabel(p.severity || 0).toLowerCase())} ${escHtml(fmt1(p.severity))} · ${escHtml(p.zone || '')}</span>`
      mks.current[p.id] = L.marker([p.lat, p.lon], { icon: severityIcon(p.severity, isSel), zIndexOffset: isSel ? 1000 : Math.round((p.severity || 0) * 10), keyboard: true, title: `#${p.id} ${p.title}` })
        .addTo(map)
        .bindTooltip(tip, { className:'map-tip', direction:'top', offset:[0,-10] })
        .on('click', () => onSelectRef.current(p.id))
    })
    // Al primo caricamento inquadra tutti i segnaposto
    const pts = Object.values(mks.current).map(m => m.getLatLng())
    if (!fitted.current && pts.length) {
      fitted.current = true
      if (!selected) map.fitBounds(L.latLngBounds(pts).pad(0.25), { maxZoom:18 })
    }
  }, [practices, selected])

  useEffect(() => {
    const map = api.current?.map
    if (map && selected?.lat) map.setView([selected.lat, selected.lon], Math.max(map.getZoom(), 18), { animate:true, duration:.5 })
  }, [selected?.id, selected?.lat, selected?.lon])

  return (
    <div style={{ width:'100%', height:'100%', position:'relative' }}>
      <div ref={el} style={{ width:'100%', height:'100%' }} aria-label="Mappa del parco con le pratiche attive" role="region"/>
      <div className="te-map-float" style={{ top:12, left:12 }}>
        <Segmented label="Tipo di mappa" value={tileMode} onChange={setTileMode}
          options={Object.entries(TILE_LAYERS).map(([k, c]) => [k, c.label])}
          style={{ background:'var(--bg-2)', boxShadow:'var(--shadow-sm)' }}/>
      </div>
      <div className="te-map-float te-map-panel te-legend" style={{ left:12, bottom:12 }}>
        <strong>Severità</strong>
        <span className="te-legend-item"><span className="te-mark te-mark--crit" aria-hidden="true"/>Critica ≥ 7</span>
        <span className="te-legend-item"><span className="te-mark te-mark--med" aria-hidden="true"/>Media ≥ 4</span>
        <span className="te-legend-item"><span className="te-mark te-mark--low" aria-hidden="true"/>Bassa</span>
      </div>
    </div>
  )
}
