import React, { useState, useEffect, useRef } from 'react'
import { Volume2, VolumeX } from 'lucide-react'
import { isMuted, toggleMute, alertEl, notifyEl, playAudioEl } from '../lib/sound.js'

// Gestisce il pulsante audio E la coda dei suoni da WebSocket.
// I browser bloccano l'audio finché l'utente non interagisce: il primo clic sblocca, i successivi attivano/disattivano.

let _pendingPlay = null  // suono in attesa di unlock
let _playFn = null       // funzione per triggerare play dall'esterno

export function triggerSound(type = 'alert') {
  if (_playFn) _playFn(type)
  else _pendingPlay = type
}

export default function SoundButton() {
  const [muted,    setMuted]    = useState(isMuted())
  const [unlocked, setUnlocked] = useState(false)
  const unlockedRef = useRef(false)

  function doPlay(type) {
    if (muted || isMuted()) return
    const el = type === 'alert' ? alertEl : notifyEl
    playAudioEl(el, type === 'alert' ? 0.7 : 0.5)
  }

  useEffect(() => {
    _playFn = (type) => {
      if (unlockedRef.current) doPlay(type)
      else _pendingPlay = type
    }
    return () => { _playFn = null }
  }, [muted])

  function handleClick() {
    if (!unlockedRef.current) {
      // Primo clic: sblocca soltanto l'audio (non cambia lo stato muto)
      unlockedRef.current = true
      setUnlocked(true)
      if (!muted) playAudioEl(notifyEl, 0.5)
      if (_pendingPlay && !muted) setTimeout(() => { doPlay(_pendingPlay); _pendingPlay = null }, 300)
    } else {
      const nowMuted = toggleMute()
      setMuted(nowMuted)
      if (!nowMuted) playAudioEl(notifyEl, 0.5)
    }
  }

  const needsUnlock = !unlocked && !muted
  const label = muted ? 'Avvisi sonori disattivati: clicca per attivarli'
    : needsUnlock ? 'Attiva gli avvisi sonori (il browser richiede un clic)'
    : 'Avvisi sonori attivi: clicca per disattivarli'
  const Icon = muted ? VolumeX : Volume2

  return (
    <button type="button" onClick={handleClick} aria-label={label} title={label} aria-pressed={unlocked ? !muted : undefined}
      className={needsUnlock ? 'te-btn te-btn--warning te-btn--sm' : 'te-icon-btn'}
      style={needsUnlock ? { minHeight:36 } : { color: muted ? 'var(--text-4)' : 'var(--text-2)' }}>
      <Icon size={16} aria-hidden="true"/>
      {needsUnlock && <span className="te-hide-md">Attiva audio</span>}
    </button>
  )
}
