import React, { useState, useEffect, useId } from 'react'
import { AlertTriangle, CheckCircle2, Info, XCircle, X, ArrowUpRight, Copy, Printer, Check, Archive, RefreshCw, PlusCircle, Activity } from 'lucide-react'
import { fetchAudit, escalate } from '../lib/api'
import { Spinner, Btn, Modal, DialogHeader, EmptyState, ErrorState, IconButton, getParkLabel, fmt1, STATUS_META } from './ui.jsx'

// ── Toast ─────────────────────────────────────────────────────
let _add = null
let _seq = 0
/**
 * toast('Messaggio', 'success' | 'danger' | 'warning' | 'info', { title, action: { label, onClick }, duration })
 * Gli errori restano visibili più a lungo e si possono chiudere a mano.
 */
export function toast(msg, type = 'info', opts = {}) { _add?.({ msg, type, id: ++_seq, ...opts }) }

const TOAST_META = {
  danger:  { icon: XCircle,       c: 'var(--red)',    bg: 'var(--red-light)' },
  success: { icon: CheckCircle2,  c: 'var(--green)',  bg: 'var(--green-light)' },
  info:    { icon: Info,          c: 'var(--accent)', bg: 'var(--accent-light)' },
  warning: { icon: AlertTriangle, c: 'var(--yellow)', bg: 'var(--yellow-light)' },
  alert:   { icon: AlertTriangle, c: 'var(--red)',    bg: 'var(--red-light)' },
}

export function ToastContainer() {
  const [ts, setTs] = useState([])
  useEffect(() => {
    _add = t => {
      setTs(s => [...s, t].slice(-3))
      const ms = t.duration ?? (t.type === 'danger' || t.type === 'alert' ? 9000 : 4500)
      setTimeout(() => setTs(s => s.filter(x => x.id !== t.id)), ms)
    }
    return () => { _add = null }
  }, [])
  const dismiss = id => setTs(s => s.filter(x => x.id !== id))
  return (
    <div className="te-toasts" aria-live="polite">
      {ts.map(t => {
        const m = TOAST_META[t.type] || TOAST_META.info
        const urgent = t.type === 'danger' || t.type === 'alert'
        return (
          <div key={t.id} className={`te-toast${urgent ? ' te-toast--danger' : ''}`} role={urgent ? 'alert' : 'status'}>
            <span className="te-toast-icon" style={{ background: m.bg, color: m.c }}><m.icon size={16} aria-hidden="true"/></span>
            <div className="te-toast-msg">
              {t.title && <div style={{ fontWeight: 700 }}>{t.title}</div>}
              <div style={t.title ? { fontSize: 13, color: 'var(--text-2)' } : undefined}>{t.msg}</div>
            </div>
            {t.action && <Btn size="sm" variant="secondary" onClick={() => { t.action.onClick(); dismiss(t.id) }}>{t.action.label}</Btn>}
            <IconButton icon={X} label="Chiudi notifica" plain size={16} onClick={() => dismiss(t.id)} style={{ width: 30, height: 30 }}/>
          </div>
        )
      })}
    </div>
  )
}

// ── Registro attività (audit) ─────────────────────────────────
const AM = {
  status_change: { icon: RefreshCw,    label: 'Cambio di stato', c: 'var(--accent)' },
  escalation:    { icon: ArrowUpRight, label: 'Escalation',      c: 'var(--red)' },
  archived:      { icon: Archive,      label: 'Archiviata',      c: 'var(--text-3)' },
  created:       { icon: PlusCircle,   label: 'Creata',          c: 'var(--green)' },
  event_added:   { icon: Activity,     label: 'Nuovo evento',    c: 'var(--text-3)' },
}
const statusWord = s => STATUS_META[s]?.l || s
/** "open → in_progress" diventa "Aperta → In carico" */
const humanDetail = d => typeof d === 'string' ? d.replace(/\b(open|in_progress|resolved|closed)\b/g, statusWord) : d

export function AuditTrail({ practiceId }) {
  const [log, setLog] = useState([])
  const [loading, setL] = useState(true)
  const [error, setError] = useState(false)
  const load = () => {
    if (!practiceId) return
    setL(true); setError(false)
    fetchAudit(practiceId).then(setLog).catch(() => setError(true)).finally(() => setL(false))
  }
  useEffect(load, [practiceId])
  if (loading) return <div style={{ display: 'flex', justifyContent: 'center', padding: 24 }}><Spinner/></div>
  if (error) return <ErrorState title="Registro non disponibile" text="Non è stato possibile caricare le attività di questa pratica." onRetry={load}/>
  if (!log.length) return <EmptyState title="Nessuna attività registrata" text="Cambi di stato, escalation e archiviazioni compariranno qui."/>
  return (
    <ol style={{ listStyle: 'none', display: 'flex', flexDirection: 'column' }}>
      {log.map((r, i) => {
        const m = AM[r.action] || { icon: Activity, label: String(r.action).replace(/_/g, ' '), c: 'var(--text-3)' }
        const last = i === log.length - 1
        return (
          <li key={r.id} style={{ display: 'flex', gap: 12, paddingBottom: last ? 0 : 14 }}>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', flexShrink: 0 }}>
              <span style={{ width: 28, height: 28, borderRadius: 'var(--r-sm)', background: 'var(--bg-3)', color: m.c, display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}><m.icon size={14} aria-hidden="true"/></span>
              {!last && <span aria-hidden="true" style={{ width: 1, flex: 1, background: 'var(--border)', marginTop: 4 }}/>}
            </div>
            <div style={{ flex: 1, minWidth: 0, paddingTop: 3 }}>
              <div style={{ display: 'flex', gap: 8, alignItems: 'baseline', flexWrap: 'wrap' }}>
                <span style={{ fontSize: 14, fontWeight: 600 }}>{m.label}</span>
                <time dateTime={r.created_at} style={{ fontSize: 12, color: 'var(--text-3)' }}>{new Date(r.created_at).toLocaleString('it-IT', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' })}</time>
              </div>
              <div style={{ fontSize: 13, color: 'var(--text-2)' }}>
                <span style={{ fontWeight: 600 }}>{r.actor}</span>{r.detail ? ` · ${humanDetail(r.detail)}` : ''}
              </div>
            </div>
          </li>
        )
      })}
    </ol>
  )
}

// ── Escalation ────────────────────────────────────────────────
export function EscalationModal({ practice, onClose }) {
  const [data, setData]     = useState(null)
  const [loading, setL]     = useState(false)
  const [copied, setCopied] = useState(false)
  const titleId = useId()

  async function doEscalate() {
    setL(true)
    try { const r = await escalate(practice.id); setData(r); toast('Escalation registrata nel registro di audit.', 'success') }
    catch (e) { toast(e.message || 'Escalation non riuscita.', 'danger') }
    finally { setL(false) }
  }

  function buildReport(d) {
    const sep = '═'.repeat(48)
    const practiceId = d.id || d.practice_id || ''
    const eventsList = (d.events || []).map(e => `  ${new Date(e.sampling_time || e.transmission_time).toLocaleTimeString('it-IT')}  ${(e.type || '').toUpperCase().padEnd(16)} ${e.mac_address}`)
    return [sep, '  TREEYES — REPORT ESCALATION OPERATIVO', `  ${getParkLabel()}`, sep,
      `ID Pratica   : #${practiceId}`, `Titolo       : ${d.title}`,
      `Zona         : ${d.zone || 'N/D'}`, `Severità     : ${fmt1(d.severity)}/10`,
      `Stato        : ${statusWord(d.status)}`,
      `Coordinate   : ${d.lat?.toFixed(6)}, ${d.lon?.toFixed(6)}`,
      `Apertura     : ${new Date(d.created_at).toLocaleString('it-IT')}`,
      `Escalation   : ${new Date(d.escalated_at).toLocaleString('it-IT')}`,
      `Operatore    : ${d.escalated_by}`, `N° eventi    : ${d.event_count}`, '',
      '── CRONOLOGIA ─────────────────────────────────────────',
      ...eventsList,
      sep,
    ].join('\n')
  }

  async function copy() {
    try { await navigator.clipboard.writeText(buildReport(data)); setCopied(true); setTimeout(() => setCopied(false), 2000) }
    catch { toast('Copia non riuscita: seleziona il testo e copialo a mano.', 'warning') }
  }
  function doPrint() {
    const w = window.open('', '_blank')
    if (!w) { toast('Il browser ha bloccato la finestra di stampa.', 'warning'); return }
    const pre = w.document.createElement('pre')
    pre.style.cssText = 'font-family:monospace;font-size:13px;padding:32px;line-height:1.7'
    pre.textContent = buildReport(data)          // textContent: niente HTML iniettato dai titoli
    w.document.body.appendChild(pre); w.document.close(); w.print()
  }

  return (
    <Modal open onClose={loading ? undefined : onClose} labelledBy={titleId} wide>
      <DialogHeader id={titleId} icon={ArrowUpRight} tone="danger" onClose={onClose}
        title={data ? `Escalation registrata · #${practice.id}` : `Escalation della pratica #${practice.id}`}>
        <p style={{ marginTop: 4, color: 'var(--text-3)', fontSize: 13 }}>{practice.title}</p>
      </DialogHeader>
      <div className="te-dialog-body">
        {!data ? (
          <>
            <p style={{ marginBottom: 16 }}>Registra una <strong style={{ color: 'var(--text-1)' }}>richiesta formale di intervento</strong> nel registro di audit e genera il report operativo da inoltrare.</p>
            <dl className="te-dl" style={{ padding: 12, background: 'var(--bg-3)', borderRadius: 'var(--r-md)' }}>
              <div><dt>Pratica</dt><dd className="mono">#{practice.id}</dd></div>
              <div><dt>Zona</dt><dd>{practice.zone || 'N/D'}</dd></div>
              <div><dt>Severità</dt><dd>{fmt1(practice.severity)} / 10</dd></div>
              <div><dt>Stato</dt><dd>{statusWord(practice.status)}</dd></div>
            </dl>
          </>
        ) : (
          <pre className="mono" style={{ padding: 14, background: 'var(--bg-3)', border: '1px solid var(--border)', borderRadius: 'var(--r-md)', fontSize: 12, color: 'var(--text-1)', whiteSpace: 'pre-wrap', lineHeight: 1.6, maxHeight: 320, overflow: 'auto' }}>{buildReport(data)}</pre>
        )}
      </div>
      <div className="te-dialog-foot">
        {!data ? (
          <>
            <Btn variant="secondary" onClick={onClose} disabled={loading}>Annulla</Btn>
            <Btn variant="danger-solid" onClick={doEscalate} loading={loading}>{loading ? 'Registrazione…' : 'Conferma escalation'}</Btn>
          </>
        ) : (
          <>
            <Btn variant="secondary" onClick={copy} icon={copied ? <Check size={16}/> : <Copy size={16}/>}>{copied ? 'Copiato' : 'Copia report'}</Btn>
            <Btn variant="secondary" onClick={doPrint} icon={<Printer size={16}/>}>Stampa</Btn>
            <Btn variant="primary" onClick={onClose}>Fatto</Btn>
          </>
        )}
      </div>
    </Modal>
  )
}
