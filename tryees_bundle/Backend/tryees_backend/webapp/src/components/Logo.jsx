import React from 'react'

/**
 * Logo iconico ufficiale di Treeyes:
 * Scudo bicolore con albero tecnologico e occhio sentinella per il monitoraggio IoT del parco.
 */
export function LogoIcon({ size = 34, white = false, className = '', style = {} }) {
  const width = size
  const height = Math.round(size * (405 / 358))

  return (
    <img
      src="/Logo-transparent.png"
      alt="Treeyes"
      width={width}
      height={height}
      className={className}
      style={{
        width: `${width}px`,
        height: `${height}px`,
        objectFit: 'contain',
        flexShrink: 0,
        display: 'inline-block',
        verticalAlign: 'middle',
        filter: white
          ? 'drop-shadow(0 2px 8px rgba(0,0,0,0.35))'
          : 'drop-shadow(0 1px 3px rgba(0,0,0,0.08))',
        ...style
      }}
    />
  )
}

export function LogoFull({ size = 'md', white = false, style = {} }) {
  const sizes = {
    sm: { icon: 24, text: 15, sub: 11 },
    md: { icon: 34, text: 19, sub: 12 },
    lg: { icon: 44, text: 23, sub: 13 }
  }
  const s = sizes[size] || sizes.md

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: Math.round(s.icon * 0.4), ...style }}>
      <LogoIcon size={s.icon} white={white} />
      <div>
        <div
          style={{
            fontSize: s.text,
            fontWeight: 700,
            color: white ? '#FFFFFF' : 'var(--text-1)',
            lineHeight: 1.1,
            letterSpacing: '-0.01em'
          }}
        >
          Tree<span style={{ color: white ? '#66C82B' : '#5CB825' }}>yes</span>
        </div>
        <div
          style={{
            fontSize: s.sub,
            fontWeight: 500,
            color: white ? '#A9B5AC' : 'var(--text-3)',
            lineHeight: 1.2,
            marginTop: 2
          }}
        >
          Smart Park OS
        </div>
      </div>
    </div>
  )
}

export default LogoFull
