// Inizializzazione Leaflet condivisa da tutte le dashboard con mappa.
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { fetchParks } from './api'

delete L.Icon.Default.prototype._getIconUrl

export { L }
export const DEFAULT_CENTER = [45.6035, 8.9382]

export const TILE_LAYERS = {
  // OpenStreetMap arriva nitido fino a zoom 19 (il parco è piccolo); `muted` lo desatura per non competere con i segnaposto
  street:    { label:'Mappa',     maxNative:19, muted:true, attribution:'© OpenStreetMap', url:'https://tile.openstreetmap.org/{z}/{x}/{y}.png' },
  satellite: { label:'Satellite', maxNative:19, attribution:'© Esri', url:'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', labels:'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}' },
}

/** Crea la mappa del parco: tile, zoom, centro dal primo parco, ridimensionamento automatico. */
export function createParkMap(el, { zoom = 17 } = {}) {
  const map = L.map(el, { zoomControl:false, attributionControl:false }).setView(DEFAULT_CENTER, zoom)
  L.control.zoom({ position:'topright', zoomInTitle:'Aumenta zoom', zoomOutTitle:'Riduci zoom' }).addTo(map)
  L.control.attribution({ position:'bottomright', prefix:false }).addTo(map)

  let layers = []
  function setTiles(mode) {
    layers.forEach(l => l.remove())
    const cfg = TILE_LAYERS[mode] || TILE_LAYERS.street
    layers = [cfg.url, cfg.labels].filter(Boolean).map(url => L.tileLayer(url, { maxZoom:20, maxNativeZoom:cfg.maxNative, attribution:cfg.attribution, className:cfg.muted ? 'te-tiles-muted' : '' }).addTo(map))
    layers.forEach(l => l.bringToBack())
  }
  setTiles('street')

  fetchParks().then(parks => {
    const p = parks?.[0]
    if (p?.lat && p?.lon && map._loaded) map.setView([p.lat, p.lon], zoom)
  }).catch(() => {})

  // La mappa vive in pannelli che cambiano dimensione (responsive, drawer): tienila allineata.
  const ro = typeof ResizeObserver !== 'undefined' ? new ResizeObserver(() => map.invalidateSize()) : null
  ro?.observe(el)
  map.on('unload', () => ro?.disconnect())

  return { map, setTiles }
}

export const escHtml = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]))

const SEV_HEX = { crit:'#B42318', med:'#B06A00', low:'#2B6E47' }
const lvl = v => v >= 7 ? 'crit' : v >= 4 ? 'med' : 'low'

/** Marker per severità: forma diversa oltre al colore (cerchio, rombo, anello). */
export function severityIcon(severity, selected = false) {
  const l = lvl(severity || 0), c = SEV_HEX[l]
  const s = selected ? 22 : 16
  const shape = l === 'crit'
    ? `<div style="position:absolute;inset:0;border-radius:50%;background:${c};border:3px solid #fff;box-shadow:0 1px 4px rgba(22,27,24,.4)"></div>`
    : l === 'med'
      ? `<div style="position:absolute;inset:2px;border-radius:3px;background:${c};border:3px solid #fff;transform:rotate(45deg);box-shadow:0 1px 4px rgba(22,27,24,.4)"></div>`
      : `<div style="position:absolute;inset:1px;border-radius:50%;background:#fff;border:4px solid ${c};box-shadow:0 1px 4px rgba(22,27,24,.4)"></div>`
  const halo = selected ? `<div style="position:absolute;inset:-8px;border-radius:50%;background:${c};opacity:.18;animation:ripple 1.6s infinite"></div>` : ''
  return L.divIcon({ className:'', html:`<div style="position:relative;width:${s}px;height:${s}px">${halo}${shape}</div>`, iconSize:[s,s], iconAnchor:[s/2,s/2] })
}

/** Marker semplice a pallino colorato (device, cestini). */
export function dotIcon(color, { size = 14, selected = false, ring = false } = {}) {
  const s = selected ? size + 6 : size
  const body = ring
    ? `background:#fff;border:4px solid ${color}`
    : `background:${color};border:3px solid #fff`
  const halo = selected ? `<div style="position:absolute;inset:-7px;border-radius:50%;background:${color};opacity:.18"></div>` : ''
  return L.divIcon({ className:'', html:`<div style="position:relative;width:${s}px;height:${s}px">${halo}<div style="position:absolute;inset:0;border-radius:50%;${body};box-shadow:0 1px 4px rgba(22,27,24,.4)"></div></div>`, iconSize:[s,s], iconAnchor:[s/2,s/2] })
}
