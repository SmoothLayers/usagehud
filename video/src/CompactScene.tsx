import React from 'react';
import {AbsoluteFill, interpolate} from 'remotion';
import {COLOR, FONT, PROVIDERS, Provider} from './theme';
import {Bar, Caption, useFrame, useSpringAt} from './shared';

// A digital twin of compact mode: one strip per provider, stacked, then
// rearranged side by side.
const V_W = 1180;
const V_X = (1920 - V_W) / 2;
const V_Y0 = 250;
const STRIP_H = 132;
const V_GAP = 22;
const H_W = 596;
const H_GAP = 26;
const H_X0 = (1920 - (H_W * 3 + H_GAP * 2)) / 2;
const H_Y = 470;

const T = {flip: 84};

const Strip: React.FC<{p: Provider; index: number; flip: number}> = ({p, index, flip}) => {
  const rise = useSpringAt(6 + index * 6, {damping: 15, stiffness: 110});
  const fill = useSpringAt(16 + index * 6, {damping: 22, stiffness: 60});

  const x = interpolate(flip, [0, 1], [V_X, H_X0 + index * (H_W + H_GAP)]);
  const y = interpolate(flip, [0, 1], [V_Y0 + index * (STRIP_H + V_GAP), H_Y]);
  const w = interpolate(flip, [0, 1], [V_W, H_W]);
  const big = interpolate(flip, [0, 1], [48, 40]);

  return (
    <div
      style={{
        position: 'absolute',
        left: x,
        top: y,
        width: w,
        height: STRIP_H,
        borderRadius: 26,
        background: '#121416',
        border: `1.5px solid ${p.accent}55`,
        boxShadow: `0 0 0 1px rgba(0,0,0,0.6), 0 18px 40px rgba(0,0,0,0.45), 0 0 30px ${p.accent}14`,
        padding: '22px 30px 20px',
        boxSizing: 'border-box',
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'space-between',
        opacity: rise,
        transform: `translateY(${(1 - rise) * 24}px)`,
      }}
    >
      <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'baseline'}}>
        <span style={{fontFamily: FONT.mono, fontSize: 24, fontWeight: 700, letterSpacing: '0.14em', color: p.accent}}>{p.name.toUpperCase()}</span>
        <span style={{display: 'flex', alignItems: 'baseline', gap: 8}}>
          <span style={{fontFamily: FONT.sans, fontSize: big, fontWeight: 800, letterSpacing: '-0.03em', color: COLOR.text, lineHeight: 1}}>{p.session}</span>
          <span style={{fontFamily: FONT.mono, fontSize: 20, fontWeight: 700, color: p.accent}}>%</span>
          <span style={{fontFamily: FONT.mono, fontSize: 15, fontWeight: 600, letterSpacing: '0.18em', color: COLOR.muted}}>LEFT</span>
        </span>
      </div>
      <Bar fraction={(p.session / 100) * fill} accent={p.accent} height={8} gradient />
      <div style={{display: 'flex', justifyContent: 'space-between', fontFamily: FONT.mono, fontSize: 17, fontWeight: 600, letterSpacing: '0.08em', color: COLOR.muted}}>
        <span>
          {p.sessionWindow.toUpperCase()} · RESET {p.sessionResetClock}
        </span>
        <span>{p.week === null ? 'NO WEEK' : `WEEK ${p.week}%`}</span>
      </div>
    </div>
  );
};

// The app labels Claude "A" in the rail (Anthropic), the others by name.
const RAIL_LABEL: Record<string, string> = {codex: 'C', claude: 'A', kimi: 'K'};
/** Seconds until each provider's next poll at the start of the scene. */
const RAIL_SECONDS = [161, 252, 65];
const countdown = (total: number) => {
  const t = Math.max(0, total);
  const pad = (n: number) => String(n).padStart(2, '0');
  return t === 0 ? 'NOW' : `${pad(Math.floor(t / 60))}:${pad(t % 60)}`;
};

export const CompactScene: React.FC = () => {
  const frame = useFrame();
  const flip = useSpringAt(T.flip, {damping: 17, stiffness: 80});
  const rail = useSpringAt(2, {damping: 16});
  const railY = interpolate(flip, [0, 1], [V_Y0 - 64, H_Y - 64]);
  const railX = interpolate(flip, [0, 1], [V_X, H_X0]);
  const railW = interpolate(flip, [0, 1], [V_W, H_W * 3 + H_GAP * 2]);

  return (
    <AbsoluteFill style={{background: COLOR.ground}}>
      <div style={{position: 'absolute', inset: 0, background: 'radial-gradient(70% 60% at 50% 50%, rgba(255,255,255,0.035), transparent 70%)'}} />

      {/* Refresh rail, as the app draws it above the strips: POLL, then each
          provider's initial and the countdown to its next refresh. */}
      <div style={{position: 'absolute', left: railX, top: railY, width: railW, display: 'flex', justifyContent: 'space-between', alignItems: 'center', opacity: rail}}>
        <div style={{display: 'flex', gap: 14, paddingLeft: 12, fontFamily: FONT.mono, fontSize: 17, fontWeight: 700, letterSpacing: '0.08em', color: COLOR.muted}}>
          <span>POLL</span>
          {PROVIDERS.map((p, i) => (
            <React.Fragment key={p.id}>
              {i > 0 && <span>·</span>}
              <span style={{display: 'flex', gap: 6}}>
                <span style={{color: p.accent}}>{RAIL_LABEL[p.id]}</span>
                <span style={{color: 'rgba(255,255,255,0.72)', fontVariantNumeric: 'tabular-nums'}}>{countdown(RAIL_SECONDS[i] - Math.floor(frame / 30))}</span>
              </span>
            </React.Fragment>
          ))}
        </div>
        <svg width={30} height={30} viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,0.85)" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round">
          <path d="M21 12a9 9 0 1 1-3-6.7" />
          <path d="M21 3v6h-6" />
        </svg>
      </div>

      {PROVIDERS.map((p, i) => (
        <Strip key={p.id} p={p} index={i} flip={flip} />
      ))}

      <Caption eyebrow="COMPACT MODE" title="Stack them, or line them up." start={22} />
    </AbsoluteFill>
  );
};
