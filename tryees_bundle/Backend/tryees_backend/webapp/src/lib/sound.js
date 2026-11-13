// Suoni di avviso: due elementi audio condivisi, caricati da public/.
const make = file => {
  const el = new Audio(`${import.meta.env.BASE_URL}${file}`)
  el.preload = 'auto'
  return el
}
export const alertEl  = make('alert.wav')
export const notifyEl = make('notify.wav')

export function playAudioEl(el, vol = 0.7) {
  try {
    el.volume = vol
    el.currentTime = 0
    el.play().catch(e => console.warn('audio:', e))
  } catch {}
}

export function isMuted() {
  try { return sessionStorage.getItem('te_muted') === '1' } catch { return false }
}
export function toggleMute() {
  const m = isMuted()
  try { sessionStorage.setItem('te_muted', m ? '0' : '1') } catch {}
  return !m
}
