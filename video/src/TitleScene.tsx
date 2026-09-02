import React from 'react';
import {AbsoluteFill, Img, interpolate, staticFile} from 'remotion';
import {COLOR, FONT, PROVIDERS} from './theme';
import {useFrame, useSpringAt} from './shared';

/** The real app icon, from assets/UsageHUD-AppIcon.png. */
export const AppIcon: React.FC<{size: number}> = ({size}) => (
  <Img
    src={staticFile('app-icon.png')}
    style={{width: size, height: size, borderRadius: size * 0.22, display: 'block', boxShadow: `0 0 ${size * 0.4}px rgba(80,140,255,0.25)`}}
  />
);

export const TitleScene: React.FC = () => {
  const frame = useFrame();
  const wordmark = useSpringAt(4, {damping: 16, stiffness: 100});
  const tagline = useSpringAt(16, {damping: 18, stiffness: 90});
  const dots = useSpringAt(26, {damping: 12, stiffness: 140});

  return (
    <AbsoluteFill style={{background: COLOR.ground, justifyContent: 'center', alignItems: 'center'}}>
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background:
            'radial-gradient(60% 50% at 50% 55%, rgba(46,242,169,0.08), transparent 70%), radial-gradient(40% 40% at 70% 40%, rgba(255,138,74,0.07), transparent 70%)',
        }}
      />
      <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 28}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 26, opacity: wordmark, transform: `scale(${0.92 + 0.08 * wordmark})`}}>
          <AppIcon size={118} />
          <div style={{fontFamily: FONT.mono, fontSize: 84, fontWeight: 700, letterSpacing: '0.16em', color: COLOR.text}}>USAGE HUD</div>
        </div>
        <div
          style={{
            fontFamily: FONT.sans,
            fontSize: 34,
            fontWeight: 500,
            color: COLOR.muted,
            opacity: tagline,
            transform: `translateY(${(1 - tagline) * 16}px)`,
          }}
        >
          Your AI limits, always in view.
        </div>
        {/* No roster: the provider set keeps growing, so the card names the idea, not the list. */}
        <div style={{display: 'flex', alignItems: 'center', gap: 18, marginTop: 10, opacity: dots, transform: `translateY(${(1 - dots) * 10}px)`}}>
          <div style={{display: 'flex', gap: 10}}>
            {PROVIDERS.map((p, i) => {
              const pulse = 0.85 + 0.15 * Math.sin((frame + i * 9) / 9);
              return (
                <div
                  key={p.id}
                  style={{width: 12, height: 12, borderRadius: 6, background: p.accent, boxShadow: `0 0 ${14 * pulse}px ${p.accent}`, transform: `scale(${pulse})`}}
                />
              );
            })}
          </div>
          <div style={{fontFamily: FONT.mono, fontSize: 22, fontWeight: 500, letterSpacing: '0.16em', color: COLOR.muted}}>EVERY PROVIDER · ONE HUD</div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const OutroScene: React.FC = () => {
  const a = useSpringAt(2, {damping: 16, stiffness: 100});
  const b = useSpringAt(12, {damping: 18, stiffness: 90});
  return (
    <AbsoluteFill style={{background: COLOR.ground, justifyContent: 'center', alignItems: 'center'}}>
      <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 22}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 24, opacity: a, transform: `scale(${0.94 + 0.06 * a})`}}>
          <AppIcon size={98} />
          <div style={{fontFamily: FONT.mono, fontSize: 72, fontWeight: 700, letterSpacing: '0.16em', color: COLOR.text}}>USAGE HUD</div>
        </div>
        <div style={{fontFamily: FONT.sans, fontSize: 30, color: COLOR.muted, opacity: b}}>
          Every provider's limits, one glance away.
        </div>
        <div
          style={{
            marginTop: 26,
            padding: '16px 30px',
            borderRadius: 16,
            border: `1px solid ${COLOR.line}`,
            background: COLOR.panel,
            fontFamily: FONT.mono,
            fontSize: 26,
            fontWeight: 600,
            color: '#2EF2A9',
            opacity: b,
            transform: `translateY(${(1 - b) * 12}px)`,
          }}
        >
          github.com/SmoothLayers/usagehud
        </div>
        <div style={{fontFamily: FONT.mono, fontSize: 18, letterSpacing: '0.14em', color: COLOR.dim, opacity: b}}>FREE · MACOS 14+ · APPLE SILICON</div>
      </div>
    </AbsoluteFill>
  );
};
