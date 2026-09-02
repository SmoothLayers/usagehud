import React from 'react';
import {AbsoluteFill, interpolate} from 'remotion';
import {COLOR, FONT, PROVIDERS, Provider} from './theme';
import {Caption, Glyph, useFrame, useSpringAt} from './shared';

// Three of the six tray themes, in the same open tray: the shape reshapes to
// each theme's real dimensions while the content crosses over.
const S = 1.6;
const MENU_H = 37 * S;
const NOTCH_W = 200 * S + 12;
const ZOOM = 1.42;

interface Theme {
  id: 'instrument' | 'capsule' | 'concentric';
  label: string;
  width: number;
  height: number;
}

// Dimensions from NotchTheme.swift, in points.
const THEMES: Theme[] = [
  {id: 'instrument', label: 'INSTRUMENT', width: 270, height: 90},
  {id: 'capsule', label: 'CAPSULE', width: 312, height: 56},
  {id: 'concentric', label: 'CONCENTRIC', width: 260, height: 88},
];
const HOLD = 66;
const switchAt = (i: number) => i * HOLD;

const Mono: React.FC<{size: number; weight?: number; color?: string; tracking?: string; children: React.ReactNode}> = ({size, weight = 500, color = '#fff', tracking, children}) => (
  <span style={{fontFamily: FONT.mono, fontSize: size, fontWeight: weight, color, letterSpacing: tracking, whiteSpace: 'nowrap'}}>{children}</span>
);

// ---- Instrument ----------------------------------------------------------

const InstrumentTile: React.FC<{p: Provider; fill: number}> = ({p, fill}) => {
  const RING = 40 * S;
  const r = RING / 2 - 3.5 * S;
  const pct = p.session * fill;
  const a = (pct / 100) * 2 * Math.PI - Math.PI / 2;
  const tip = {x: RING / 2 + r * Math.cos(a), y: RING / 2 + r * Math.sin(a)};
  return (
    <div style={{width: 58 * S, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 * S}}>
      <div style={{position: 'relative', width: RING, height: RING}}>
        <svg width={RING} height={RING} viewBox={`0 0 ${RING} ${RING}`} style={{position: 'absolute', inset: 0, overflow: 'visible'}}>
          <circle cx={RING / 2} cy={RING / 2} r={RING / 2 - 0.75 * S} fill="none" stroke="rgba(255,255,255,0.22)" strokeWidth={1.5 * S} strokeDasharray={`${0.5 * S} ${2.6 * S}`} />
          <circle cx={RING / 2} cy={RING / 2} r={r} fill="none" stroke="rgba(255,255,255,0.1)" strokeWidth={1 * S} />
          <circle cx={RING / 2} cy={RING / 2} r={r} pathLength={100} fill="none" stroke={p.accent} strokeWidth={3 * S} strokeLinecap="round" strokeDasharray={`${pct} 100`} transform={`rotate(-90 ${RING / 2} ${RING / 2})`} style={{filter: 'blur(4px)', opacity: 0.45}} />
          <circle cx={RING / 2} cy={RING / 2} r={r} pathLength={100} fill="none" stroke={p.accent} strokeWidth={1.5 * S} strokeLinecap="round" strokeDasharray={`${pct} 100`} transform={`rotate(-90 ${RING / 2} ${RING / 2})`} />
          {pct < 100 && <circle cx={tip.x} cy={tip.y} r={1.3 * S} fill="#fff" style={{filter: `drop-shadow(0 0 4px ${p.accent})`}} />}
        </svg>
        <div style={{position: 'absolute', inset: 0, display: 'grid', placeItems: 'center'}}>
          <Glyph id={p.id} size={14 * S} color="rgba(255,255,255,0.92)" />
        </div>
      </div>
      <div style={{display: 'flex', alignItems: 'baseline', gap: 1}}>
        <Mono size={11 * S} color="rgba(255,255,255,0.85)">{Math.round(pct)}</Mono>
        <Mono size={7 * S} color="rgba(255,255,255,0.4)">%</Mono>
      </div>
      <Mono size={6.5 * S} color="rgba(255,255,255,0.42)" tracking="0.16em">{p.name.toUpperCase()}</Mono>
    </div>
  );
};

const Instrument: React.FC<{fill: number}> = ({fill}) => (
  <div style={{display: 'flex', justifyContent: 'center', gap: 4 * S, padding: `${10 * S}px ${14 * S}px`}}>
    {PROVIDERS.map((p) => (
      <InstrumentTile key={p.id} p={p} fill={fill} />
    ))}
  </div>
);

// ---- Capsule -------------------------------------------------------------

const Capsule: React.FC<{fill: number}> = ({fill}) => (
  <div style={{display: 'flex', gap: 6 * S, padding: `${10 * S}px ${12 * S}px`}}>
    {PROVIDERS.map((p) => (
      <div
        key={p.id}
        style={{
          flex: 1,
          height: 34 * S,
          borderRadius: 17 * S,
          background: 'rgba(255,255,255,0.065)',
          boxShadow: '0 1px 0 rgba(255,255,255,0.12) inset, 0 0 0 1px rgba(255,255,255,0.04) inset',
          display: 'flex',
          alignItems: 'center',
          gap: 7 * S,
          padding: `0 ${9 * S}px`,
        }}
      >
        <div
          style={{
            width: 22 * S,
            height: 22 * S,
            borderRadius: '50%',
            background: `radial-gradient(circle at 50% 30%, ${p.accent}6b, ${p.accent}24)`,
            boxShadow: `0 0 0 1px ${p.accent}4d inset`,
            display: 'grid',
            placeItems: 'center',
            flex: 'none',
          }}
        >
          <Glyph id={p.id} size={11 * S} />
        </div>
        <div style={{display: 'flex', flexDirection: 'column', gap: 3 * S}}>
          <span style={{fontFamily: FONT.sans, fontSize: 12 * S, fontWeight: 700, color: 'rgba(255,255,255,0.94)', lineHeight: 1}}>{Math.round(p.session * fill)}%</span>
          <div style={{width: 34 * S, height: 2 * S, borderRadius: 2, background: 'rgba(255,255,255,0.1)', overflow: 'hidden'}}>
            <div style={{width: `${p.session * fill}%`, height: '100%', background: p.accent, boxShadow: `0 0 6px ${p.accent}`}} />
          </div>
        </div>
      </div>
    ))}
  </div>
);

// ---- Concentric ----------------------------------------------------------

const Concentric: React.FC<{fill: number}> = ({fill}) => {
  const G = 66 * S;
  return (
    <div style={{display: 'flex', alignItems: 'center', gap: 12 * S, padding: `${10 * S}px ${14 * S}px`}}>
      <div style={{position: 'relative', width: G, height: G, flex: 'none'}}>
        <svg width={G} height={G} viewBox={`0 0 ${G} ${G}`} style={{overflow: 'visible'}}>
          {PROVIDERS.map((p, i) => {
            const r = G / 2 - (2 + i * 6) * S;
            return (
              <g key={p.id} transform={`rotate(135 ${G / 2} ${G / 2})`}>
                <circle cx={G / 2} cy={G / 2} r={r} pathLength={100} fill="none" stroke="rgba(255,255,255,0.09)" strokeWidth={3.5 * S} strokeLinecap="round" strokeDasharray="75 100" />
                <circle cx={G / 2} cy={G / 2} r={r} pathLength={100} fill="none" stroke={p.accent} strokeWidth={3.5 * S} strokeLinecap="round" strokeDasharray={`${0.75 * p.session * fill} 100`} style={{filter: `drop-shadow(0 0 3px ${p.accent}80)`}} />
              </g>
            );
          })}
        </svg>
        <div style={{position: 'absolute', inset: 0, display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 3 * S}}>
          {PROVIDERS.map((p) => (
            <div key={p.id} style={{width: 4 * S, height: 4 * S, borderRadius: '50%', background: p.accent, boxShadow: `0 0 4px ${p.accent}`}} />
          ))}
        </div>
      </div>
      <div style={{width: 150 * S, display: 'flex', flexDirection: 'column', gap: 3 * S}}>
        {PROVIDERS.map((p) => (
          <div key={p.id} style={{display: 'flex', alignItems: 'center', gap: 6 * S, height: 17 * S, padding: `0 ${7 * S}px`}}>
            <div style={{width: 5 * S, height: 5 * S, borderRadius: '50%', background: p.accent, boxShadow: `0 0 6px ${p.accent}`}} />
            <span style={{fontFamily: FONT.sans, fontSize: 9.5 * S, fontWeight: 700, color: 'rgba(255,255,255,0.9)'}}>{p.name}</span>
            <span style={{flex: 1}} />
            <span style={{fontFamily: FONT.sans, fontSize: 10 * S, fontWeight: 700, color: 'rgba(255,255,255,0.94)', fontVariantNumeric: 'tabular-nums'}}>{Math.round(p.session * fill)}%</span>
            <div style={{width: 30 * S, height: 3 * S, borderRadius: 2, background: 'rgba(255,255,255,0.1)', overflow: 'hidden'}}>
              <div style={{width: `${p.session * fill}%`, height: '100%', background: p.accent}} />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

// ---- Scene ---------------------------------------------------------------

export const ThemesScene: React.FC = () => {
  const frame = useFrame();
  const current = Math.min(THEMES.length - 1, Math.floor(frame / HOLD));
  const theme = THEMES[current];

  // The shape springs to each theme's dimensions.
  const morph = useSpringAt(switchAt(current), {damping: 15, stiffness: 110});
  const prev = THEMES[Math.max(0, current - 1)];
  const trayW = (current === 0 ? theme.width : interpolate(morph, [0, 1], [prev.width, theme.width])) * S;
  const trayH = MENU_H + (current === 0 ? theme.height : interpolate(morph, [0, 1], [prev.height, theme.height])) * S;

  // Content crosses over: out fast, in a beat later with the meters filling.
  const local = frame - switchAt(current);
  const contentIn = interpolate(local, [4, 16], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const fill = useSpringAt(switchAt(current) + 6, {damping: 20, stiffness: 70});
  const labelIn = useSpringAt(switchAt(current) + 6, {damping: 14, stiffness: 120});

  const content = theme.id === 'instrument' ? <Instrument fill={fill} /> : theme.id === 'capsule' ? <Capsule fill={fill} /> : <Concentric fill={fill} />;

  return (
    <AbsoluteFill style={{background: '#0d1020', overflow: 'hidden'}}>
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background:
            'radial-gradient(110% 80% at 12% 112%, #d8794c 0%, rgba(216,121,76,0) 55%), radial-gradient(80% 70% at 88% 105%, #6a3f9e 0%, rgba(106,63,158,0) 62%), linear-gradient(160deg, #1a2140 0%, #2a2450 52%, #3b2a4a 100%)',
          transform: `scale(${ZOOM})`,
          transformOrigin: '50% 0%',
        }}
      >
        <div
          style={{
            position: 'absolute',
            inset: '0 0 auto 0',
            height: MENU_H,
            background: 'rgba(8,8,12,0.28)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            padding: `0 ${28 + ((ZOOM - 1) * 960) / ZOOM}px`,
            color: 'rgba(255,255,255,0.88)',
            fontFamily: FONT.sans,
            fontSize: 21,
            fontWeight: 600,
          }}
        >
          <div style={{display: 'flex', gap: 28, alignItems: 'center'}}>
            <svg width={20} height={20} viewBox="0 0 24 24" fill="currentColor">
              <path d="M16.4 12.7c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9-1.7 0-3.3 1-4.2 2.6-1.8 3.1-.5 7.8 1.3 10.3.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8s2 .8 3.4.8 2.3-1.3 3.1-2.5c1-1.4 1.4-2.8 1.4-2.9 0 0-2.7-1-2.7-4.2zM13.9 5c.7-.9 1.2-2 1-3.2-1 0-2.3.7-3 1.6-.7.8-1.2 2-1.1 3.1 1.2.1 2.4-.6 3.1-1.5z" />
            </svg>
            <b>Finder</b>
            <span style={{fontWeight: 500}}>File</span>
            <span style={{fontWeight: 500}}>Edit</span>
            <span style={{fontWeight: 500}}>View</span>
            <span style={{fontWeight: 500}}>Go</span>
          </div>
          <div style={{display: 'flex', gap: 24, fontWeight: 500}}>
            <span>100%</span>
            <span>Tue 4:49 PM</span>
          </div>
        </div>

        <div style={{position: 'absolute', top: 0, left: '50%', transform: 'translateX(-50%)', width: NOTCH_W, height: MENU_H, background: '#000', borderRadius: '0 0 18px 18px'}} />

        <div
          style={{
            position: 'absolute',
            top: 0,
            left: '50%',
            width: trayW,
            height: trayH,
            transform: 'translateX(-50%)',
            background: '#000',
            borderRadius: `0 0 ${26 * S}px ${26 * S}px`,
            boxShadow: '0 1px 0 rgba(255,255,255,0.14) inset, 0 -1px 0 rgba(255,255,255,0.06) inset, 0 2px 3px rgba(0,0,0,0.35), 0 12px 24px rgba(0,0,0,0.42)',
            overflow: 'hidden',
          }}
        >
          <div
            key={theme.id}
            style={{
              position: 'absolute',
              top: MENU_H,
              left: 0,
              width: theme.width * S,
              opacity: contentIn,
              filter: `blur(${(1 - contentIn) * 6}px)`,
              transform: `translateY(${(1 - contentIn) * -6}px)`,
            }}
          >
            <div style={{position: 'absolute', inset: 0, background: 'radial-gradient(ellipse 60% 70% at 50% 42%, rgba(255,255,255,0.075), transparent)'}} />
            {content}
          </div>
        </div>

        {/* Theme label, hanging under the tray. */}
        <div
          key={`label-${theme.id}`}
          style={{
            position: 'absolute',
            top: trayH + 26,
            left: '50%',
            transform: `translateX(-50%) translateY(${(1 - labelIn) * 8}px)`,
            opacity: labelIn,
            padding: '8px 16px',
            borderRadius: 999,
            background: 'rgba(0,0,0,0.55)',
            border: '1px solid rgba(255,255,255,0.12)',
            fontFamily: FONT.mono,
            fontSize: 13,
            fontWeight: 600,
            letterSpacing: '0.2em',
            color: 'rgba(255,255,255,0.85)',
          }}
        >
          {theme.label}
          <span style={{color: COLOR.dim, marginLeft: 10}}>
            {current + 1}/{THEMES.length}
          </span>
        </div>
      </div>

      <Caption eyebrow="TRAY THEMES" title="Six looks for the tray. Pick yours in Settings." start={10} light />
    </AbsoluteFill>
  );
};
