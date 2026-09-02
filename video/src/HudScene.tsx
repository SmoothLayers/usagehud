import React from 'react';
import {AbsoluteFill, interpolate} from 'remotion';
import {COLOR, FONT, PROVIDERS, Provider} from './theme';
import {Bar, Caption, useCount, useSpringAt} from './shared';
import {AppIcon} from './TitleScene';

// A digital twin of the regular HUD window: header, one card per provider.
const PANEL_W = 1500;

const IconButton: React.FC<{children: React.ReactNode}> = ({children}) => (
  <div
    style={{
      width: 44,
      height: 44,
      borderRadius: 22,
      background: 'rgba(255,255,255,0.06)',
      display: 'grid',
      placeItems: 'center',
      color: 'rgba(255,255,255,0.8)',
    }}
  >
    {children}
  </div>
);

const Card: React.FC<{p: Provider; start: number}> = ({p, start}) => {
  const rise = useSpringAt(start, {damping: 16, stiffness: 110});
  const fill = useSpringAt(start + 10, {damping: 22, stiffness: 60});
  const value = useCount(p.session, start + 8, 36);
  return (
    <div
      style={{
        position: 'relative',
        flex: 1,
        borderRadius: 24,
        background: COLOR.card,
        border: `1px solid ${COLOR.line}`,
        padding: '30px 34px 30px 38px',
        overflow: 'hidden',
        opacity: rise,
        transform: `translateY(${(1 - rise) * 26}px)`,
      }}
    >
      <div style={{position: 'absolute', left: 0, top: 24, bottom: 24, width: 5, borderRadius: 3, background: p.accent, boxShadow: `0 0 12px ${p.accent}80`}} />
      <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'baseline'}}>
        <span style={{fontFamily: FONT.mono, fontSize: 26, fontWeight: 700, letterSpacing: '0.12em', color: p.accent}}>{p.name.toUpperCase()}</span>
        <span style={{fontFamily: FONT.mono, fontSize: 18, fontWeight: 600, letterSpacing: '0.08em', color: COLOR.muted}}>{p.plan.toUpperCase()}</span>
      </div>
      <div style={{display: 'flex', alignItems: 'baseline', gap: 10, marginTop: 26}}>
        <span style={{fontFamily: FONT.sans, fontSize: 104, fontWeight: 800, letterSpacing: '-0.04em', lineHeight: 1, color: COLOR.text, fontVariantNumeric: 'tabular-nums'}}>{value}</span>
        <span style={{fontFamily: FONT.mono, fontSize: 44, fontWeight: 700, color: p.accent}}>%</span>
        <span style={{fontFamily: FONT.mono, fontSize: 18, fontWeight: 600, letterSpacing: '0.18em', color: COLOR.muted}}>LEFT</span>
      </div>
      <div style={{marginTop: 26}}>
        <Bar fraction={(p.session / 100) * fill} accent={p.accent} height={7} />
      </div>
      <div style={{display: 'flex', justifyContent: 'space-between', marginTop: 18, fontFamily: FONT.mono, fontSize: 20, color: COLOR.muted}}>
        <span>{p.sessionWindow}</span>
        <span>Resets in {p.sessionReset}</span>
      </div>
      <div style={{height: 1, background: COLOR.line, margin: '22px 0'}} />
      <div style={{display: 'flex', justifyContent: 'space-between', fontFamily: FONT.mono, fontSize: 20}}>
        <span style={{letterSpacing: '0.14em', color: COLOR.muted, fontWeight: 600}}>WEEK</span>
        <span style={{fontWeight: 700, color: COLOR.text}}>{p.week === null ? 'no window' : `${p.week}% left`}</span>
      </div>
    </div>
  );
};

export const HudScene: React.FC = () => {
  const panel = useSpringAt(0, {damping: 15, stiffness: 100});
  return (
    <AbsoluteFill style={{background: COLOR.ground, justifyContent: 'center', alignItems: 'center'}}>
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background: 'radial-gradient(70% 60% at 50% 50%, rgba(255,255,255,0.035), transparent 70%)',
        }}
      />
      <div
        style={{
          width: PANEL_W,
          borderRadius: 34,
          background: COLOR.panel,
          border: `1px solid ${COLOR.line}`,
          boxShadow: '0 40px 90px rgba(0,0,0,0.6)',
          padding: '30px 30px 34px',
          opacity: panel,
          transform: `translateY(${(1 - panel) * 40 - 40}px) scale(${0.94 + 0.06 * panel})`,
        }}
      >
        <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '4px 10px 26px'}}>
          <div style={{display: 'flex', alignItems: 'center', gap: 16}}>
            <AppIcon size={40} />
            <span style={{fontFamily: FONT.mono, fontSize: 26, fontWeight: 700, letterSpacing: '0.18em', color: COLOR.text}}>USAGE HUD</span>
            <div style={{width: 10, height: 10, borderRadius: 5, background: '#2EF2A9', boxShadow: '0 0 10px #2EF2A9'}} />
          </div>
          <div style={{display: 'flex', gap: 14}}>
            <IconButton>
              <svg width={20} height={20} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round">
                <path d="M21 12a9 9 0 1 1-3-6.7" />
                <path d="M21 3v6h-6" />
              </svg>
            </IconButton>
            <IconButton>
              <svg width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round">
                <path d="M4 14h6v6M20 10h-6V4M14 10l7-7M3 21l7-7" />
              </svg>
            </IconButton>
            <IconButton>
              <svg width={18} height={18} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round">
                <path d="M6 6l12 12M18 6L6 18" />
              </svg>
            </IconButton>
          </div>
        </div>
        <div style={{display: 'flex', gap: 22}}>
          {PROVIDERS.map((p, i) => (
            <Card key={p.id} p={p} start={8 + i * 6} />
          ))}
        </div>
      </div>
      <Caption eyebrow="THE HUD" title="Every window, every reset, at a glance." start={26} />
    </AbsoluteFill>
  );
};

export const interpolateClamp = (v: number, a: [number, number], b: [number, number]) =>
  interpolate(v, a, b, {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
