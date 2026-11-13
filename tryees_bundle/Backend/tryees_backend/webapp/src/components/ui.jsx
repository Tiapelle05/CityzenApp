import React, { useState, useEffect, useRef, useCallback, useId } from 'react'
import {
  AlertTriangle, AlertCircle, Circle, Check, RefreshCw, ChevronDown, LogOut, Repeat,
  Shield, Leaf, Wrench, Box, SlidersHorizontal, Inbox, X, MoreHorizontal,
} from 'lucide-react'
import { LogoIcon } from './Logo.jsx'
import { fetchParks } from '../lib/api'

// Nome del parco: arriva da /parks; questo è solo il valore di riserva finché non risponde.
const PARK_FALLBACK = 'Parco Robinson · Legnano'
let _parkLabel = PARK_FALLBACK
export const getParkLabel = () => _parkLabel
export function useParkLabel() {
  const [label, setLabel] = useState(_parkLabel)
  useEffect(() => {
    let on = true
    fetchParks().then(parks => {
      const p = parks?.[0]
      if (!p?.name) return
      _parkLabel = [p.name, p.city].filter(Boolean).join(' · ')
      if (on) setLabel(_parkLabel)
    }).catch(() => {})
    return () => { on = false }
  }, [])
  return label
}

// ── Numeri e date ─────────────────────────────────────────────
export const fmt1 = v => (v == null || Number.isNaN(+v)) ? '—'
  : Number(v).toLocaleString('it-IT', { minimumFractionDigits: 1, maximumFractionDigits: 1 })

export function timeAgo(iso, now = Date.now()) {
  if (!iso) return '—'
  const s = Math.max(0, Math.round((now - new Date(iso).getTime()) / 1000))
  if (s < 45) return 'ora'
  const m = Math.round(s / 60)
  if (m < 60) return `${m} min fa`
  const h = Math.round(m / 60)
  if (h < 24) return `${h} h fa`
  const d = Math.round(h / 24)
  return d === 1 ? 'ieri' : `${d} giorni fa`
}
export const fmtDateTime = iso => iso ? new Date(iso).toLocaleString('it-IT', { day:'2-digit', month:'2-digit', year:'numeric', hour:'2-digit', minute:'2-digit' }) : '—'
export const fmtTime = iso => iso ? new Date(iso).toLocaleTimeString('it-IT', { hour:'2-digit', minute:'2-digit', second:'2-digit' }) : '—'

/** Forza un re-render periodico (per i tempi relativi "2 min fa"). */
export function useNow(intervalMs = 30000) {
  const [now, setNow] = useState(Date.now())
  useEffect(() => { const id = setInterval(() => setNow(Date.now()), intervalMs); return () => clearInterval(id) }, [intervalMs])
  return now
}

// ── Severità ──────────────────────────────────────────────────
export const sevLevel = v => v >= 7 ? 'crit' : v >= 4 ? 'med' : 'low'
export const sevColor = v => `var(--sev-${sevLevel(v)})`
export const sevLabel = v => v >= 7 ? 'Critica' : v >= 4 ? 'Media' : 'Bassa'
const SEV_ICON = { crit: AlertTriangle, med: AlertCircle, low: Circle }

/** compact: solo icona + valore (liste). Altrimenti "Critica 8,4". */
export function SeverityBadge({ value = 0, compact = false, large = false }) {
  const lv = sevLevel(value || 0)
  const Icon = SEV_ICON[lv]
  const text = compact ? fmt1(value) : `${sevLabel(value)} · ${fmt1(value)}`
  return (
    <span className={`te-chip${large ? ' te-chip--lg' : ''}`} title={`Severità ${sevLabel(value).toLowerCase()} ${fmt1(value)} su 10`}
      style={{ background:`var(--sev-${lv}-bg)`, color:`var(--sev-${lv})`, fontWeight:700, flexShrink:0 }}>
      <Icon size={large ? 14 : 12} strokeWidth={2.5} aria-hidden="true"/>
      {compact && <span className="sr-only">Severità {sevLabel(value).toLowerCase()} </span>}
      {text}{large && <span style={{ fontWeight:500, opacity:.85 }}> / 10</span>}
    </span>
  )
}

// ── Stato pratica ─────────────────────────────────────────────
export const STATUS_META = {
  open:        { l:'Aperta',    c:'var(--st-open)',     bg:'var(--st-open-bg)',     mark:'ring' },
  in_progress: { l:'In carico', c:'var(--st-progress)', bg:'var(--st-progress-bg)', mark:'dot' },
  resolved:    { l:'Risolta',   c:'var(--st-resolved)', bg:'var(--st-resolved-bg)', mark:'check' },
  closed:      { l:'Chiusa',    c:'var(--st-closed)',   bg:'var(--st-closed-bg)',   mark:'square' },
}
function StatusMark({ mark }) {
  if (mark === 'check')  return <Check size={13} strokeWidth={3} aria-hidden="true"/>
  if (mark === 'square') return <span aria-hidden="true" style={{ width:8, height:8, borderRadius:2, background:'currentColor', opacity:.6, display:'inline-block' }}/>
  return <span aria-hidden="true" className={`te-dot${mark === 'ring' ? ' te-dot--ring' : ''}`} style={{ background:'currentColor' }}/>
}
/** plain: solo pallino + testo (liste). Altrimenti chip con sfondo. */
export function StatusBadge({ status, plain = false, large = false }) {
  const m = STATUS_META[status] || STATUS_META.open
  return (
    <span className={plain ? undefined : `te-chip${large ? ' te-chip--lg' : ''}`}
      style={plain
        ? { display:'inline-flex', alignItems:'center', gap:5, color:m.c, fontWeight:600, whiteSpace:'nowrap' }
        : { background:m.bg, color:m.c }}>
      <StatusMark mark={m.mark}/>{m.l}
    </span>
  )
}

// ── Categoria pratica ─────────────────────────────────────────
export const CATEGORY_LABEL = { security:'Sicurezza', basket:'Rifiuti', soil:'Terreno', light:'Illuminazione', other:'Altro' }

// ── Pericoli e allarmi ────────────────────────────────────────
export const DANGER_LABELS = {
  arma: 'Arma rilevata', arma_da_fuoco: 'Arma da fuoco rilevata', coltello: 'Coltello rilevato',
  granata: 'Granata rilevata', esplosione: 'Esplosione rilevata', rissa: 'Rissa in corso', persona_a_terra: 'Persona a terra',
  vandalismo: 'Vandalismo in corso', fuoco_fumo: 'Fuoco o fumo rilevato',
  assembramento: 'Assembramento sospetto', segnale_aiuto: 'Segnale di aiuto',
  vetro_rotto: 'Vetro rotto', urla: 'Urla rilevate',
}
/** "TELECAMERA_ARMA" -> "Arma rilevata", "VANDALISMO" -> "Vandalismo sul cestino" */
export function alarmLabel(type) {
  const t = String(type || '')
  if (t.startsWith('TELECAMERA_')) {
    const k = t.slice('TELECAMERA_'.length).toLowerCase()
    return DANGER_LABELS[k] || `Allarme telecamera: ${k.replace(/_/g, ' ')}`
  }
  return { VANDALISMO:'Vandalismo sul cestino', AFFOLLAMENTO:'Affollamento' }[t] || t.replace(/_/g, ' ').toLowerCase()
}

// ── Tipo evento ───────────────────────────────────────────────
export const TYPE_LABEL = {
  alert:'Allerta', assistance:'Richiesta di aiuto', motion:'Movimento',
  full:'Cestino pieno', battery:'Batteria', weight:'Peso',
  light:'Anomalia luce', light_on:'Luce accesa', is_dark:'Zona buia',
  humidity:'Umidità', eco:'Eco', citizen:'Segnalazione cittadino',
}
export function Ts({ iso, full }) {
  if (!iso) return <span style={{ color:'var(--text-4)', fontSize:12 }}>—</span>
  return <time dateTime={iso} style={{ fontSize:12, color:'var(--text-3)', whiteSpace:'nowrap' }}>{full ? fmtDateTime(iso) : fmtTime(iso)}</time>
}

// ── Connessione in tempo reale ────────────────────────────────
const WS_META = {
  connected:    { c:'var(--green)',  dot:'#2F9E5B', l:'In tempo reale' },
  connecting:   { c:'var(--yellow)', dot:'#D48A12', l:'Connessione…' },
  disconnected: { c:'var(--red)',    dot:'var(--red)', l:'Offline' },
}
export function WsDot({ status }) {
  const m = WS_META[status] || WS_META.disconnected
  return (
    <span role="status" style={{ display:'inline-flex', alignItems:'center', gap:8, fontSize:13, fontWeight:500, color:m.c, whiteSpace:'nowrap' }}>
      <span aria-hidden="true" className="te-dot" style={{ background:m.dot, boxShadow: status==='connected' ? '0 0 0 3px #DDF0E3' : 'none', animation: status==='connecting' ? 'pulse 1.2s infinite' : 'none' }}/>
      <span className="te-hide-sm">{m.l}</span>
      <span className="sr-only">{status === 'connected' ? '' : m.l}</span>
    </span>
  )
}

export function Spinner({ size = 18, label = 'Caricamento' }) {
  return <span role="status" aria-label={label} style={{ display:'inline-block', width:size, height:size, border:'2px solid var(--border-2)', borderTopColor:'var(--accent)', borderRadius:'50%', animation:'spin .7s linear infinite', flexShrink:0 }} />
}

// ── Pulsanti ──────────────────────────────────────────────────
const VARIANT = { default:'secondary', cyan:'secondary', primary:'primary', danger:'danger', 'danger-solid':'danger-solid', success:'success', warning:'warning', ghost:'ghost', secondary:'secondary', link:'link' }
export function Btn({ children, onClick, variant = 'default', disabled, size = 'md', icon, loading, type = 'button', full, title, ariaLabel, style, className = '', ...rest }) {
  const v = VARIANT[variant] || 'secondary'
  const cls = ['te-btn', `te-btn--${v}`, size === 'sm' && 'te-btn--sm', size === 'lg' && 'te-btn--lg', full && 'te-btn--full', loading && 'te-btn--loading', className].filter(Boolean).join(' ')
  return (
    <button type={type} className={cls} onClick={onClick} disabled={disabled || loading} title={title} aria-label={ariaLabel} aria-busy={loading || undefined} style={style} {...rest}>
      {loading
        ? <span aria-hidden="true" style={{ width:14, height:14, borderRadius:'50%', border:'2px solid rgba(255,255,255,.4)', borderTopColor:'#fff', animation:'spin .7s linear infinite' }}/>
        : icon && <span aria-hidden="true" style={{ display:'inline-flex' }}>{icon}</span>}
      {children}
    </button>
  )
}

export const IconButton = React.forwardRef(function IconButton({ icon: Icon, label, onClick, pressed, plain, disabled, size = 16, className = '', ...rest }, ref) {
  return (
    <button ref={ref} type="button" className={`te-icon-btn${plain ? ' te-icon-btn--plain' : ''} ${className}`} onClick={onClick}
      aria-label={label} title={label} aria-pressed={pressed} disabled={disabled} {...rest}>
      <Icon size={size} aria-hidden="true"/>
    </button>
  )
})

// ── KPI ───────────────────────────────────────────────────────
export function KpiCard({ label, value, sub, color = 'var(--text-1)', subColor }) {
  return (
    <div className="te-kpi">
      <div className="te-kpi-label">{label}</div>
      <div className="te-kpi-row">
        <span className="te-kpi-value" style={{ color }}>{value}</span>
        {sub && <span className="te-kpi-sub" style={subColor ? { color:subColor, fontWeight:600 } : undefined}>{sub}</span>}
      </div>
    </div>
  )
}

export function StatCard({ icon:Icon, iconBg = 'var(--bg-3)', iconColor = 'var(--text-2)', label, value, valueColor = 'var(--text-1)', delta, deltaPositive = true, caption, pulse }) {
  return (
    <div className="te-card" style={{ padding:'16px 18px', flex:1, minWidth:0 }}>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', gap:8, marginBottom:10 }}>
        <span style={{ fontSize:13, fontWeight:500, color:'var(--text-3)' }}>{label}</span>
        <div style={{ position:'relative', width:34, height:34, borderRadius:'var(--r-sm)', background:iconBg, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0 }}>
          <Icon size={17} color={iconColor} strokeWidth={2} aria-hidden="true"/>
          {pulse && <span aria-hidden="true" style={{ position:'absolute', top:-3, right:-3, width:10, height:10, borderRadius:'50%', background:'var(--red)', animation:'pulse 1.4s infinite', border:'2px solid var(--bg-2)' }}/>}
        </div>
      </div>
      <div className="tnum" style={{ fontSize:26, fontWeight:700, lineHeight:1.15, color:valueColor, marginBottom:(delta!=null||caption)?6:0 }}>{value}</div>
      {(delta != null || caption) && (
        <div style={{ display:'flex', alignItems:'center', gap:6, flexWrap:'wrap' }}>
          {delta != null && <span style={{ fontSize:13, fontWeight:600, color: deltaPositive ? 'var(--green)' : 'var(--red)' }}>{delta}</span>}
          {caption && <span style={{ fontSize:12, color:'var(--text-3)' }}>{caption}</span>}
        </div>
      )}
    </div>
  )
}

export function MiniBarChart({ data, color = 'var(--accent)' }) {
  const max = Math.max(...data.map(d => d.value), 1)
  return (
    <div style={{ display:'flex', alignItems:'flex-end', gap:10, height:132, padding:'0 4px' }} role="img" aria-label={data.map(d => `${d.label}: ${d.value}`).join(', ')}>
      {data.map(d => (
        <div key={d.label} style={{ flex:1, display:'flex', flexDirection:'column', alignItems:'center', gap:6, minWidth:0 }}>
          <span className="tnum" style={{ fontSize:12, fontWeight:600, color:'var(--text-2)' }}>{d.value}</span>
          <div style={{ width:'100%', maxWidth:36, height:Math.max(4, (d.value / max) * 84), background:color, borderRadius:6, transition:'height .3s ease' }}/>
          <span style={{ fontSize:12, color:'var(--text-3)', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis', maxWidth:'100%' }}>{d.label}</span>
        </div>
      ))}
    </div>
  )
}

export function SectionTitle({ children, action, as: Tag = 'h2' }) {
  return (
    <div className="te-section-title">
      <Tag>{children}</Tag>
      {action && <div>{action}</div>}
    </div>
  )
}

// ── Stati vuoto / errore / caricamento ────────────────────────
export function EmptyState({ icon: Icon = Inbox, title, text, action, tone }) {
  const toneStyle = tone === 'ok' ? { background:'var(--green-light)', color:'var(--green)' } : undefined
  return (
    <div className="te-state">
      <span className="te-state-icon" style={toneStyle}><Icon size={22} aria-hidden="true"/></span>
      {title && <div className="te-state-title">{title}</div>}
      {text && <div className="te-state-text">{text}</div>}
      {action}
    </div>
  )
}
export function ErrorState({ title = 'Impossibile caricare i dati', text = 'Il server non risponde. Controlla la connessione e riprova.', onRetry }) {
  return (
    <div className="te-state" role="alert">
      <span className="te-state-icon" style={{ background:'var(--red-light)', color:'var(--red)' }}><AlertCircle size={22} aria-hidden="true"/></span>
      <div className="te-state-title">{title}</div>
      <div className="te-state-text">{text}</div>
      {onRetry && <Btn variant="primary" size="sm" onClick={onRetry} icon={<RefreshCw size={14}/>}>Riprova</Btn>}
    </div>
  )
}
export function SkeletonRows({ n = 5 }) {
  return (
    <div aria-busy="true" aria-label="Caricamento in corso">
      {Array.from({ length:n }, (_, i) => (
        <div key={i} style={{ padding:'14px 16px', display:'flex', flexDirection:'column', gap:8, borderBottom:'1px solid var(--bg-4)' }}>
          <div className="te-skel" style={{ height:14, width:`${70 - (i % 3) * 8}%` }}/>
          <div className="te-skel" style={{ height:10, width:`${46 - (i % 2) * 6}%` }}/>
        </div>
      ))}
    </div>
  )
}

// ── Controllo segmentato ──────────────────────────────────────
export function Segmented({ label, options, value, onChange, style }) {
  return (
    <div role="group" aria-label={label} className="te-seg" style={style}>
      {options.map(([v, l]) => (
        <button key={v} type="button" aria-pressed={value === v} onClick={() => onChange(v)}>{l}</button>
      ))}
    </div>
  )
}

// ── Tab con navigazione da tastiera ───────────────────────────
export function Tabs({ label, tabs, value, onChange, idPrefix }) {
  const refs = useRef({})
  function onKey(e, i) {
    if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return
    const next = tabs[(i + (e.key === 'ArrowRight' ? 1 : tabs.length - 1)) % tabs.length]
    onChange(next.key); refs.current[next.key]?.focus()
  }
  return (
    <div role="tablist" aria-label={label} className="te-tabs">
      {tabs.map((t, i) => (
        <button key={t.key} ref={el => { refs.current[t.key] = el }} type="button" role="tab" className="te-tab"
          id={`${idPrefix}-tab-${t.key}`} aria-controls={`${idPrefix}-panel`} aria-selected={value === t.key}
          tabIndex={value === t.key ? 0 : -1} onClick={() => onChange(t.key)} onKeyDown={e => onKey(e, i)}>
          {t.label}{t.badge}
        </button>
      ))}
    </div>
  )
}

// ── Menu a tendina (overflow, utente) ─────────────────────────
function useDismiss(open, setOpen, wrapRef, triggerRef) {
  useEffect(() => {
    if (!open) return
    const onDown = e => { if (!wrapRef.current?.contains(e.target)) setOpen(false) }
    const onKey = e => { if (e.key === 'Escape') { setOpen(false); triggerRef.current?.focus() } }
    document.addEventListener('mousedown', onDown); document.addEventListener('touchstart', onDown)
    document.addEventListener('keydown', onKey)
    return () => { document.removeEventListener('mousedown', onDown); document.removeEventListener('touchstart', onDown); document.removeEventListener('keydown', onKey) }
  }, [open, setOpen, wrapRef, triggerRef])
}

export function MenuButton({ label, trigger, items, up = false, header }) {
  const [open, setOpen] = useState(false)
  const wrapRef = useRef(null), triggerRef = useRef(null), menuRef = useRef(null)
  const menuId = useId()
  useDismiss(open, setOpen, wrapRef, triggerRef)
  useEffect(() => { if (open) menuRef.current?.querySelector('[role="menuitem"]')?.focus() }, [open])
  function onMenuKey(e) {
    if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return
    e.preventDefault()
    const els = [...menuRef.current.querySelectorAll('[role="menuitem"]')]
    const i = els.indexOf(document.activeElement)
    els[(i + (e.key === 'ArrowDown' ? 1 : els.length - 1)) % els.length]?.focus()
  }
  return (
    <div className="te-menu-wrap" ref={wrapRef}>
      {trigger({ ref: triggerRef, onClick: () => setOpen(o => !o), 'aria-haspopup': 'menu', 'aria-expanded': open, 'aria-controls': open ? menuId : undefined, label })}
      {open && (
        <div id={menuId} role="menu" aria-label={label} ref={menuRef} className={`te-menu${up ? ' te-menu--up' : ''}`} onKeyDown={onMenuKey}>
          {header && <div className="te-menu-label">{header}</div>}
          {items.filter(Boolean).map((it, i) => it === 'sep'
            ? <div key={i} className="te-menu-sep" role="separator"/>
            : (
              <button key={it.label} type="button" role="menuitem" disabled={it.disabled}
                className={`te-menu-item${it.danger ? ' te-menu-item--danger' : ''}`}
                onClick={() => { setOpen(false); triggerRef.current?.focus(); it.onClick?.() }}>
                {it.icon && <it.icon size={16} aria-hidden="true"/>}{it.label}
              </button>
            ))}
        </div>
      )}
    </div>
  )
}

export function OverflowMenu({ label = 'Altre azioni', items, up }) {
  return (
    <MenuButton label={label} items={items} up={up} trigger={({ ref, label: l, ...p }) => (
      <IconButton ref={ref} icon={MoreHorizontal} label={l} size={18} {...p}/>
    )}/>
  )
}

// ── Ruoli ─────────────────────────────────────────────────────
export const ROLE_META = {
  police:      { label:'Polizia Locale', short:'PL', icon:Shield,            c:'var(--role-police)',      bg:'var(--role-police-bg)' },
  eco:         { label:'Operatore Eco',  short:'EC', icon:Leaf,              c:'var(--role-eco)',         bg:'var(--role-eco-bg)' },
  maintenance: { label:'Manutenzione',   short:'MN', icon:Wrench,            c:'var(--role-maintenance)', bg:'var(--role-maintenance-bg)' },
  modellino:   { label:'Modellino',      short:'MD', icon:Box,               c:'var(--role-modellino)',   bg:'var(--role-modellino-bg)' },
  admin:       { label:'Amministrazione',short:'AD', icon:SlidersHorizontal, c:'var(--role-admin)',       bg:'var(--role-admin-bg)' },
}
export function RoleChip({ role }) {
  const m = ROLE_META[role]; if (!m) return null
  return (
    <span style={{ display:'inline-flex', alignItems:'center', gap:6, padding:'4px 10px 4px 8px', borderRadius:999, background:m.bg, color:m.c, fontSize:13, fontWeight:600, whiteSpace:'nowrap', flexShrink:0 }}>
      <m.icon size={15} aria-hidden="true"/>{m.label}
    </span>
  )
}

export function UserMenu({ username, role, onSwitchRole, onLogout }) {
  const m = ROLE_META[role] || ROLE_META.admin
  const initials = (username || '?').slice(0, 2).toUpperCase()
  return (
    <MenuButton label={`Menu utente ${username || ''}`} header={username ? <>Connesso come <strong>{username}</strong></> : null}
      items={[
        onSwitchRole && { label:'Cambia profilo', icon:Repeat, onClick:onSwitchRole },
        onSwitchRole && 'sep',
        { label:'Esci', icon:LogOut, onClick:onLogout },
      ]}
      trigger={({ ref, label, ...p }) => (
        <button ref={ref} type="button" className="te-user-btn" aria-label={label} {...p}>
          <span className="te-avatar" style={{ background:m.c }} aria-hidden="true">{initials}</span>
          <span className="te-hide-sm">{username}</span>
          <ChevronDown size={14} aria-hidden="true"/>
        </button>
      )}/>
  )
}

// ── Barra superiore condivisa ─────────────────────────────────
export function TopBar({ role, username, onSwitchRole, onLogout, children, title }) {
  const park = useParkLabel()
  return (
    <header className="te-topbar">
      <div className="te-topbar-brand">
        <LogoIcon size={30}/>
        <span className="te-topbar-name te-hide-sm" style={{ color:'var(--text-1)' }}>Treeyes</span>
      </div>
      <span className="te-topbar-sep te-hide-sm" aria-hidden="true"/>
      {title ? <h1 style={{ fontSize:16, fontWeight:700, whiteSpace:'nowrap', color:'var(--text-1)' }}>{title}</h1> : <RoleChip role={role}/>}
      <span className="te-topbar-park te-hide-md">{park}</span>
      <div className="te-topbar-actions">
        {children}
        <UserMenu username={username} role={role} onSwitchRole={onSwitchRole} onLogout={onLogout}/>
      </div>
    </header>
  )
}

/** Aggiorna ora + orario dell'ultimo aggiornamento. */
export function RefreshControl({ onRefresh, lastUpdated }) {
  const [spin, setSpin] = useState(false)
  const go = useCallback(async () => {
    setSpin(true)
    try { await onRefresh() } finally { setTimeout(() => setSpin(false), 400) }
  }, [onRefresh])
  return (
    <>
      {lastUpdated && <span className="te-updated te-hide-md">Aggiornato alle {new Date(lastUpdated).toLocaleTimeString('it-IT', { hour:'2-digit', minute:'2-digit' })}</span>}
      <button type="button" className="te-icon-btn" onClick={go} aria-label="Aggiorna ora" title="Aggiorna ora" disabled={spin}>
        <RefreshCw size={16} className={spin ? 'te-spin' : undefined} aria-hidden="true"/>
      </button>
    </>
  )
}

/** Banner quando la connessione in tempo reale cade. */
export function OfflineBanner({ status, lastUpdated, onRetry }) {
  if (status !== 'disconnected') return null
  return (
    <div className="te-banner te-banner--danger" role="status">
      <AlertCircle size={18} aria-hidden="true" style={{ flexShrink:0 }}/>
      <span style={{ flex:1 }}>
        <strong>Connessione in tempo reale interrotta.</strong>{' '}
        {lastUpdated ? `I dati mostrati risalgono alle ${new Date(lastUpdated).toLocaleTimeString('it-IT', { hour:'2-digit', minute:'2-digit' })}. ` : ''}
        Nuovo tentativo in corso…
      </span>
      {onRetry && <Btn variant="danger" size="sm" onClick={onRetry}>Aggiorna ora</Btn>}
    </div>
  )
}

// ── Dialog ────────────────────────────────────────────────────
/** Dialog modale accessibile: focus iniziale, Esc per chiudere, focus trap, ripristino focus. */
export function Modal({ open, onClose, labelledBy, describedBy, wide, children, initialFocusRef }) {
  const ref = useRef(null)
  const onCloseRef = useRef(onClose)
  onCloseRef.current = onClose
  useEffect(() => {
    if (!open) return
    const prev = document.activeElement
    const t = setTimeout(() => {
      (initialFocusRef?.current || ref.current?.querySelector('button, [href], input, select, textarea'))?.focus()
    }, 0)
    function onKey(e) {
      if (e.key === 'Escape') { e.stopPropagation(); onCloseRef.current?.() }
      if (e.key !== 'Tab' || !ref.current) return
      const f = [...ref.current.querySelectorAll('button:not(:disabled), [href], input:not(:disabled), select, textarea, [tabindex]:not([tabindex="-1"])')]
      if (!f.length) return
      const first = f[0], last = f[f.length - 1]
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus() }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus() }
    }
    document.addEventListener('keydown', onKey)
    return () => { clearTimeout(t); document.removeEventListener('keydown', onKey); prev?.focus?.() }
  }, [open, initialFocusRef])
  if (!open) return null
  return (
    <div className="te-overlay" onMouseDown={e => { if (e.target === e.currentTarget) onCloseRef.current?.() }}>
      <div ref={ref} role="dialog" aria-modal="true" aria-labelledby={labelledBy} aria-describedby={describedBy} className={`te-dialog${wide ? ' te-dialog--wide' : ''}`}>
        {children}
      </div>
    </div>
  )
}

export function DialogHeader({ id, title, icon: Icon, tone, onClose, children }) {
  const toneStyle = tone === 'danger' ? { background:'var(--red-light)', color:'var(--red)' } : { background:'var(--bg-3)', color:'var(--text-2)' }
  return (
    <div className="te-dialog-head">
      {Icon && <span style={{ width:40, height:40, borderRadius:'var(--r-md)', flexShrink:0, display:'inline-flex', alignItems:'center', justifyContent:'center', ...toneStyle }}><Icon size={20} aria-hidden="true"/></span>}
      <div style={{ flex:1, minWidth:0 }}>
        <h2 id={id} className="te-dialog-title">{title}</h2>
        {children}
      </div>
      {onClose && <IconButton icon={X} label="Chiudi" plain onClick={onClose} size={18}/>}
    </div>
  )
}

export function ConfirmDialog({ open, title, message, confirmLabel = 'Conferma', cancelLabel = 'Annulla', tone = 'primary', icon, busy, onConfirm, onCancel }) {
  const titleId = useId(), descId = useId()
  const cancelRef = useRef(null)
  return (
    <Modal open={open} onClose={busy ? undefined : onCancel} labelledBy={titleId} describedBy={descId} initialFocusRef={tone === 'danger' ? cancelRef : undefined}>
      <DialogHeader id={titleId} title={title} icon={icon} tone={tone}>
        <p id={descId} style={{ marginTop:6, color:'var(--text-2)' }}>{message}</p>
      </DialogHeader>
      <div className="te-dialog-foot">
        <button ref={cancelRef} type="button" className="te-btn te-btn--secondary" onClick={onCancel} disabled={busy}>{cancelLabel}</button>
        <Btn variant={tone === 'danger' ? 'danger-solid' : 'primary'} onClick={onConfirm} loading={busy}>{confirmLabel}</Btn>
      </div>
    </Modal>
  )
}

/**
 * Sostituto di window.confirm: const [dialog, ask] = useConfirm()
 * if (await ask({ title, message, confirmLabel, tone })) { ... }  — e renderizza {dialog}.
 */
export function useConfirm() {
  const [state, setState] = useState(null)
  const ask = useCallback(opts => new Promise(resolve => setState({ ...opts, resolve })), [])
  const close = v => { state?.resolve(v); setState(null) }
  const dialog = (
    <ConfirmDialog open={!!state} title={state?.title} message={state?.message} confirmLabel={state?.confirmLabel}
      tone={state?.tone} icon={state?.icon} onConfirm={() => close(true)} onCancel={() => close(false)}/>
  )
  return [dialog, ask]
}
