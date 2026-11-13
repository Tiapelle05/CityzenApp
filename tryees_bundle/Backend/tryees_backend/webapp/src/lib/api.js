const BASE = import.meta.env.VITE_API_URL || ''
const WS_BASE = import.meta.env.VITE_WS_URL || `${window.location.protocol === 'https:' ? 'wss' : 'ws'}://${window.location.host}`
let _token = localStorage.getItem('te_token') || null
/** URL assoluto di una risorsa del backend (stream, video): rispetta VITE_API_URL. */
export const apiUrl = path => `${BASE}${path}`
export const getToken   = () => _token
export const setToken   = t => { _token = t; localStorage.setItem('te_token', t) }
/** expired: true quando è il server a rifiutare il token (la pagina di accesso lo spiega all'utente). */
export const clearToken = (expired = false) => { _token = null; localStorage.removeItem('te_token'); window.dispatchEvent(new CustomEvent('te:logout', { detail: { expired } })) }

const NETWORK_MSG = 'Impossibile contattare il server. Controlla la connessione e riprova.'

/** Trasforma una risposta d'errore in un messaggio comprensibile, senza dettagli tecnici. */
async function errorFrom(res) {
  let detail = null
  try { const body = await res.json(); detail = body?.detail } catch {}
  let msg
  if (typeof detail === 'string' && res.status < 500) msg = detail
  else if (Array.isArray(detail) && res.status === 422) msg = 'Alcuni dati inseriti non sono validi. Controlla i campi e riprova.'
  else if (res.status === 403) msg = 'Non hai i permessi per questa operazione.'
  else if (res.status === 404) msg = 'Elemento non trovato: potrebbe essere stato rimosso.'
  else if (res.status === 429) msg = 'Troppe richieste. Attendi qualche secondo e riprova.'
  else if (res.status >= 500) msg = 'Il server ha avuto un problema. Riprova tra poco.'
  else msg = 'Operazione non riuscita. Riprova.'
  const err = new Error(msg)
  err.status = res.status
  return err
}

async function req(method, path, body) {
  let res
  try {
    res = await fetch(`${BASE}${path}`, {
      method,
      headers: { 'Content-Type': 'application/json', ...(_token ? { Authorization: `Bearer ${_token}` } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    })
  } catch {
    const err = new Error(NETWORK_MSG); err.status = 0; throw err
  }
  if (res.status === 401) { clearToken(true); const err = new Error('Sessione scaduta: accedi di nuovo.'); err.status = 401; err.code = 'AUTH'; throw err }
  if (!res.ok) throw await errorFrom(res)
  return res.json()
}

export async function login(username, password) {
  const f = new FormData()
  f.append('username', username); f.append('password', password)
  let res
  try { res = await fetch(`${BASE}/auth/login/access-token`, { method: 'POST', body: f }) }
  catch { throw new Error(NETWORK_MSG) }
  if (!res.ok) {
    if (res.status === 400 || res.status === 401) throw new Error('Nome utente o password non corretti.')
    throw await errorFrom(res)
  }
  const data = await res.json(); setToken(data.access_token); return data
}

export const fetchPractices = (p = {}) => {
  const q = new URLSearchParams()
  if (p.status) q.set('status', p.status)
  if (p.min_severity) q.set('min_severity', p.min_severity)
  if (p.category) q.set('category', p.category)
  q.set('limit', p.limit || 100)
  q.set('skip', p.skip || 0)
  return req('GET', `/practices/?${q}`)
}
export const fetchPractice = id     => req('GET',   `/practices/${id}`)
// note: testo facoltativo mostrato nell'app ai cittadini che hanno segnalato il problema
export const updateStatus  = (id,s,note) => req('PATCH', `/practices/${id}/status`, note ? { status: s, citizen_note: note } : { status: s })
export const fetchOverview = (category) => req('GET', `/practices/overview/severity${category ? `?category=${encodeURIComponent(category)}` : ''}`)
export const fetchAudit    = id     => req('GET',   `/practices/${id}/audit`)
export const escalate      = id     => req('POST',  `/practices/${id}/escalate`)

/** WebSocket con riconnessione automatica; il token viaggia in query (i browser non permettono header custom). */
export function createWs(onMessage, onStatus) {
  let ws, dead = false, timer
  function connect() {
    onStatus('connecting')
    const qs = _token ? `?token=${encodeURIComponent(_token)}` : ''
    ws = new WebSocket(`${WS_BASE}/practices/ws${qs}`)
    ws.onopen    = () => { onStatus('connected'); ws._ping = setInterval(() => ws.readyState === 1 && ws.send('ping'), 25000) }
    ws.onmessage = e => { try { onMessage(JSON.parse(e.data)) } catch {} }
    ws.onclose   = ev => {
      clearInterval(ws._ping); onStatus('disconnected')
      if (ev.code === 1008) { if (_token) clearToken(true); return }   // token non valido: niente retry
      if (!dead) timer = setTimeout(connect, 3000)
    }
    ws.onerror   = () => ws.close()
  }
  connect()
  return { close() { dead = true; clearTimeout(timer); ws?.close() } }
}

export const fetchMe      = ()         => req('GET',   '/auth/me')
export const fetchAllDevices = ()      => req('GET',   '/devices/')
export const updateDeviceStatus = (mac,body) => req('PATCH', `/devices/${mac}/status`, body)
export const deleteDevice = mac              => req('DELETE', `/devices/${mac}`)
export const addMaintenance = (mac,body)     => req('POST',  `/devices/${mac}/maintenance`, body)
export const fetchMaintenance = mac          => req('GET',   `/devices/${mac}/maintenance`)
export const deletePractice  = id => req('DELETE', `/practices/${id}`)

// I parchi cambiano raramente: una sola richiesta per sessione, condivisa tra le mappe.
let _parksPromise = null
export const fetchParks = () => {
  if (!_parksPromise) _parksPromise = req('GET', '/parks/').catch(e => { _parksPromise = null; throw e })
  return _parksPromise
}
// Avvisi del parco mostrati nell'app dei cittadini
export const fetchNotices  = (parkId, includeExpired=false) => req('GET', `/parks/${parkId}/notices${includeExpired ? '?include_expired=true' : ''}`)
export const createNotice  = (parkId, body)     => req('POST',   `/parks/${parkId}/notices`, body)
export const updateNotice  = (parkId, id, body) => req('PATCH',  `/parks/${parkId}/notices/${id}`, body)
export const deleteNotice  = (parkId, id)       => req('DELETE', `/parks/${parkId}/notices/${id}`)

// Suggerimenti e feedback dei cittadini (solo admin). note: testo mostrato nell'app
export const fetchCitizenReports = (p = {}) => {
  const q = new URLSearchParams(Object.entries(p).filter(([, v]) => v != null && v !== '')).toString()
  return req('GET', `/citizen-reports/${q ? `?${q}` : ''}`)
}
export const updateCitizenReport = (id, status, note) => req('PATCH', `/citizen-reports/${id}/status`, note ? { status, citizen_note: note } : { status })

export const fetchSLA           = ()       => req('GET',  '/sla/')
export const fetchDeviceHealth  = ()       => req('GET',  '/sla/devices')
export const fetchServerStatus   = ()       => req('GET',  '/sla/server')
export const runVideoCleanup    = ()       => req('POST', '/sla/server/cleanup')
export const fetchAccessLog     = ()       => req('GET',  '/sla/access-log')
export const fetchOnboardingKeys= ()       => req('GET',  '/onboarding/keys')
export const registerDevice     = b        => req('POST', '/onboarding/register', b)
export const revokeKey          = id       => req('DELETE',`/onboarding/keys/${id}`)
export const setup2FA           = ()       => req('POST', '/auth/2fa/setup')
export const confirm2FA         = code     => req('POST', '/auth/2fa/confirm', { code })
export const verify2FA          = code     => req('POST', '/auth/2fa/verify',  { code })
export const status2FA          = ()       => req('GET',  '/auth/2fa/status')
export const disable2FA         = code     => req('POST', '/auth/2fa/disable', { code })

export const miniTestTrigger    = b        => req('POST', '/mini/test-trigger', b)
export const miniReset          = ()       => req('POST', '/mini/reset')
export const fetchMiniSettings  = ()       => req('GET', '/mini/settings')
export const updateMiniSettings = b        => req('PUT', '/mini/settings', b)
export const fetchMiniState     = ()       => req('GET', '/mini/state')
export const fetchEnvHistory    = (limit=20) => req('GET', `/mini/env-history?limit=${limit}`)
export const resetMiniAlarm     = id       => req('POST', `/mini/alarms/${id}/reset`)
export const fetchMiniAlarms    = (limit=30) => req('GET', `/mini/alarms?limit=${limit}`)
export const fetchMiniVideos    = (limit=20) => req('GET', `/mini/videos?limit=${limit}`)
export const fetchPowerLatest   = ()       => req('GET', '/power/latest')
export const fetchPowerDaily    = (mac,days=7) => req('GET', `/power/daily?mac=${encodeURIComponent(mac)}&days=${days}`)
