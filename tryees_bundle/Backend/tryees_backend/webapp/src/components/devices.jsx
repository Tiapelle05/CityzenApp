// Etichette, icone e stato dei dispositivi: condivisi da Manutenzione e Amministrazione.
import React from 'react'
import { Cpu, Camera, Mic, Trash, Lightbulb, Sprout, Server } from 'lucide-react'

export const ST = {
  ok:           { l:'Operativo',     c:'var(--green)',  hex:'#2B6E47' },
  guasto:       { l:'Guasto',        c:'var(--red)',    hex:'#B42318' },
  manutenzione: { l:'In manutenzione', c:'var(--yellow)', hex:'#B06A00' },
  offline:      { l:'Offline',       c:'var(--text-3)', hex:'#6E766F' },
}
export const TYPE = {
  camera:{ l:'Telecamera', icon:Camera }, microphone:{ l:'Microfono', icon:Mic }, basket:{ l:'Cestino', icon:Trash },
  light:{ l:'Lampione', icon:Lightbulb }, soil_sensor:{ l:'Sensore suolo', icon:Sprout }, server:{ l:'Server', icon:Server },
  mini_node:{ l:'Nodo modellino', icon:Cpu }, mini_ambiente:{ l:'Nodo ambiente', icon:Cpu }, mini_varchi:{ l:'Nodo varchi', icon:Cpu },
  mini_bin:{ l:'Cestino modellino', icon:Trash }, mini_display:{ l:'Display modellino', icon:Cpu },
}
export const typeOf = t => TYPE[t] || { l:String(t || 'Dispositivo').replace(/_/g,' '), icon:Cpu }
export const stOf = s => ST[s || 'ok'] || ST.ok

/** Minuti -> "12 min" / "3 h" / "9 giorni" */
export const since = m => m < 60 ? `${m} min` : m < 1440 ? `${Math.round(m / 60)} h` : Math.round(m / 1440) === 1 ? '1 giorno' : `${Math.round(m / 1440)} giorni`

export function DeviceStatus({ status }) {
  const m = stOf(status)
  return <span style={{ display:'inline-flex', alignItems:'center', gap:6, color:m.c, fontSize:13, fontWeight:600, whiteSpace:'nowrap' }}><span className="te-dot" style={{ background:m.hex }} aria-hidden="true"/>{m.l}</span>
}
