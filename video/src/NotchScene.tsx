import React from 'react';
import {AbsoluteFill, interpolate} from 'remotion';
import {FONT, PROVIDERS, Provider} from './theme';
import {Caption, Cursor, Glyph, easeOut, useFrame, useSpringAt} from './shared';

// A digital twin of notch mode with the Segmented tray theme, drawn at 1.6x
// the app's point sizes so it reads on a phone.
const S = 1.6;
const MENU_H = 37 * S;
const NOTCH_W = 200 * S + 12;
const TRAY_W = 270 * S;
const TRAY_CONTENT_H = 80 * S;
const TILE_W = 58 * S;
const TILE_GAP = 4 * S;
const RING = 40 * S;
const PAD = 14 * S;
const SEGMENTS = 28;

// Timeline (frames, local to the scene).
const T = {
  cursorIn: 4,
  peek: 30,
  open: 46,
  tiles: 54,
  cursorToClaude: 150,
  detail: 172,
};

const segmentDash = (lit: number) =>
  lit > 0 ? `${Array.from({length: lit}, () => '0.7 0.3').join(' ')} 0 ${SEGMENTS}` : `0 ${SEGMENTS}`;
const edgeDash = (lit: number) => (lit > 0 ? `${'0 1 '.repeat(lit - 1)}0.7 0.3 0 ${SEGMENTS}` : `0 ${SEGMENTS}`);

const SegmentedRing: React.FC<{p: Provider; lit: number; focus: number}> = ({p, lit, focus}) => {
  const r = RING / 2 - 2.5 * S;
  return (
    <div style={{position: 'relative', width: RING, height: RING}}>
      <div
        style={{
          position: 'absolute',
          inset: -6,
          borderRadius: '50%',
          background: p.accent,
          filter: 'blur(14px)',
          opacity: 0.28 * focus,
        }}
      />
      <svg width={RING} height={RING} viewBox={`0 0 ${RING} ${RING}`} style={{position: 'absolute', inset: 0, overflow: 'visible'}}>
        <g transform={`rotate(-90 ${RING / 2} ${RING / 2})`}>
          <circle cx={RING / 2} cy={RING / 2} r={r} pathLength={SEGMENTS} fill="none" stroke="rgba(255,255,255,0.11)" strokeWidth={3 * S} strokeDasharray="0.7 0.3" />
          <circle
            cx={RING / 2}
            cy={RING / 2}
            r={r}
            pathLength={SEGMENTS}
            fill="none"
            stroke={p.accent}
            strokeWidth={3 * S}
            strokeDasharray={segmentDash(lit)}
            style={{filter: `drop-shadow(0 0 3px ${p.accent}99)`}}
          />
          <circle cx={RING / 2} cy={RING / 2} r={r} pathLength={SEGMENTS} fill="none" stroke="#fff" strokeWidth={3 * S} strokeDasharray={edgeDash(lit)} />
        </g>
      </svg>
      <div style={{position: 'absolute', inset: 0, display: 'grid', placeItems: 'center'}}>
        <Glyph id={p.id} size={13 * S} color="rgba(255,255,255,0.92)" />
      </div>
    </div>
  );
};

const CellBar: React.FC<{fraction: number; accent: string; start: number}> = ({fraction, accent, start}) => {
  const frame = useFrame();
  const N = 20;
  const lit = Math.round(fraction * N);
  const shown = Math.floor((frame - start) * 0.9);
  return (
    <div style={{display: 'flex', gap: 1.5 * S}}>
      {Array.from({length: N}, (_, k) => {
        const on = k < lit && k < shown;
        const edge = on && k === lit - 1;
        return (
          <div
            key={k}
            style={{
              flex: 1,
              height: 4 * S,
              borderRadius: 1.5,
              background: on ? (edge ? '#fff' : accent) : 'rgba(255,255,255,0.1)',
              boxShadow: on ? `0 0 5px ${accent}99` : undefined,
            }}
          />
        );
      })}
    </div>
  );
};

const Mono: React.FC<{size: number; weight?: number; color?: string; tracking?: string; children: React.ReactNode; style?: React.CSSProperties}> = ({
  size,
  weight = 500,
  color = '#fff',
  tracking,
  children,
  style,
}) => (
  <span style={{fontFamily: FONT.mono, fontSize: size, fontWeight: weight, color, letterSpacing: tracking, whiteSpace: 'nowrap', ...style}}>{children}</span>
);

export const NotchScene: React.FC = () => {
  const frame = useFrame();

  // Camera: settle into the notch as the cursor arrives, and be fully still
  // before the tray opens — a scale that is still creeping re-rasterizes the
  // rings every frame, which reads as shaking.
  const zoom = 1 + 0.42 * easeOut(frame / 40);

  // Cursor path.
  const arrive = useSpringAt(T.cursorIn, {damping: 20, stiffness: 60});
  const toClaude = useSpringAt(T.cursorToClaude, {damping: 18, stiffness: 80});
  const claudeTileCenterY = MENU_H + 10 * S + RING / 2;
  const cursorX = 960 + (1 - arrive) * 60;
  const cursorY = interpolate(arrive, [0, 1], [720, MENU_H * 0.55]) + toClaude * (claudeTileCenterY - MENU_H * 0.55);

  // Peek, then open.
  const peek = useSpringAt(T.peek, {damping: 10, stiffness: 160});
  const open = useSpringAt(T.open, {damping: 13, stiffness: 110});
  const trayW = interpolate(open, [0, 1], [NOTCH_W + 14 * S * peek, TRAY_W]);
  const trayH = MENU_H + interpolate(open, [0, 1], [5 * S * peek, TRAY_CONTENT_H]);
  const contentOpacity = interpolate(open, [0.35, 0.8], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const sheenX = interpolate(frame, [T.open + 6, T.open + 30], [-0.6, 1.6], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});

  // Detail for Claude.
  const detail = useSpringAt(T.detail, {damping: 15, stiffness: 100});

  const rowWidth = PROVIDERS.length * TILE_W + (PROVIDERS.length - 1) * TILE_GAP;
  const rowX0 = (TRAY_W - rowWidth) / 2;
  const focusIndex = 1;
  const claude = PROVIDERS[focusIndex];

  return (
    <AbsoluteFill style={{background: '#0d1020', overflow: 'hidden'}}>
      {/* Desktop */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background:
            'radial-gradient(110% 80% at 12% 112%, #d8794c 0%, rgba(216,121,76,0) 55%), radial-gradient(80% 70% at 88% 105%, #6a3f9e 0%, rgba(106,63,158,0) 62%), linear-gradient(160deg, #1a2140 0%, #2a2450 52%, #3b2a4a 100%)',
          transform: `scale(${zoom})`,
          transformOrigin: '50% 0%',
        }}
      >
        {/* Menu bar */}
        <div
          style={{
            position: 'absolute',
            inset: '0 0 auto 0',
            height: MENU_H,
            background: 'rgba(8,8,12,0.28)',
            backdropFilter: 'blur(20px)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            // The camera zooms about the top centre, so the menu items slide
            // inward with it to stay inside the frame.
            padding: `0 ${28 + ((zoom - 1) * 960) / zoom}px`,
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

        {/* Notch housing */}
        <div style={{position: 'absolute', top: 0, left: '50%', transform: 'translateX(-50%)', width: NOTCH_W, height: MENU_H, background: '#000', borderRadius: '0 0 18px 18px'}} />

        {/* Tray shadow + body */}
        <div
          style={{
            position: 'absolute',
            top: 0,
            left: '50%',
            width: trayW,
            height: trayH,
            transform: `translateX(-50%)`,
            background: '#000',
            borderRadius: `0 0 ${interpolate(open, [0, 1], [18, 26 * S])}px ${interpolate(open, [0, 1], [18, 26 * S])}px`,
            boxShadow: `0 1px 0 rgba(255,255,255,${0.14 * open}) inset, 0 -1px 0 rgba(255,255,255,${0.06 * open}) inset, 0 2px 3px rgba(0,0,0,${0.35 * open}), 0 12px 24px rgba(0,0,0,${0.42 * Math.max(open, peek * 0.5)})`,
            overflow: 'hidden',
          }}
        >
          {/* Peek hairline */}
          <div
            style={{
              position: 'absolute',
              bottom: 3,
              left: '50%',
              transform: 'translateX(-50%)',
              width: NOTCH_W * 0.28,
              height: 2.5,
              borderRadius: 2,
              background: `linear-gradient(90deg, ${PROVIDERS.map((p) => p.accent).join(',')})`,
              boxShadow: '0 0 6px rgba(255,255,255,0.35)',
              opacity: peek * (1 - open),
            }}
          />

          {/* Sheen */}
          <div
            style={{
              position: 'absolute',
              top: MENU_H,
              bottom: 0,
              left: `${sheenX * 100}%`,
              width: '45%',
              background: 'linear-gradient(90deg, transparent, rgba(255,255,255,0.07) 45%, rgba(255,255,255,0.12) 50%, rgba(255,255,255,0.07) 55%, transparent)',
              transform: 'skewX(-18deg)',
              opacity: contentOpacity,
            }}
          />

          {/* Content */}
          <div style={{position: 'absolute', top: MENU_H, left: 0, width: TRAY_W, height: TRAY_CONTENT_H, opacity: contentOpacity}}>
            {/* Floor light */}
            <div style={{position: 'absolute', inset: 0, background: 'radial-gradient(ellipse 60% 70% at 50% 42%, rgba(255,255,255,0.075), transparent)'}} />

            {PROVIDERS.map((p, i) => {
              // Near-critically damped: one soft overshoot, then still.
              const tileIn = useSpringAt(T.tiles + i * 4, {damping: 17, stiffness: 140});
              const litStart = T.tiles + 8 + i * 4;
              const target = Math.round((p.session / 100) * SEGMENTS);
              const lit = Math.max(0, Math.min(target, Math.floor((frame - litStart) * 0.8)));
              const count = Math.round(p.session * easeOut((frame - litStart) / 30));
              const isFocus = i === focusIndex;
              const rowX = rowX0 + i * (TILE_W + TILE_GAP);
              const x = isFocus ? interpolate(detail, [0, 1], [rowX, PAD]) : rowX;
              const collapse = isFocus ? 0 : detail;
              return (
                <div
                  key={p.id}
                  style={{
                    position: 'absolute',
                    left: x,
                    top: 10 * S,
                    width: TILE_W,
                    display: 'flex',
                    flexDirection: 'column',
                    alignItems: 'center',
                    gap: 4 * S,
                    opacity: tileIn * (1 - collapse),
                    transform: `translateY(${(1 - tileIn) * -16}px) scale(${(0.55 + 0.45 * tileIn) * (1 - 0.5 * collapse)})`,
                  }}
                >
                  <SegmentedRing p={p} lit={lit} focus={isFocus ? detail : 0} />
                  <div style={{display: 'flex', alignItems: 'baseline', gap: 3 * S, opacity: interpolate(frame - litStart, [0, 10], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>
                    <Mono size={11 * S} weight={600} color={`rgba(255,255,255,${isFocus ? 0.95 : 0.88})`}>
                      {count}
                    </Mono>
                    <Mono size={7 * S} color="rgba(255,255,255,0.4)">
                      %
                    </Mono>
                    {p.live && (
                      <div
                        style={{
                          width: 3.5 * S,
                          height: 3.5 * S,
                          borderRadius: '50%',
                          background: p.accent,
                          boxShadow: `0 0 ${(4 + 3 * Math.sin(frame / 8)) * S}px ${p.accent}`,
                          transform: `scale(${0.9 + 0.2 * Math.sin(frame / 8)})`,
                          marginLeft: 2,
                        }}
                      />
                    )}
                  </div>
                </div>
              );
            })}

            {/* Detail rows */}
            <div
              style={{
                position: 'absolute',
                left: PAD + TILE_W + 12 * S,
                right: PAD,
                top: 12 * S,
                display: 'flex',
                flexDirection: 'column',
                gap: 10 * S,
                opacity: detail,
                transform: `translateX(${(1 - detail) * 14 * S}px)`,
                filter: `blur(${(1 - detail) * 5}px)`,
              }}
            >
              {[
                {title: 'SESSION', pct: claude.session, reset: `${claude.sessionReset} left`},
                {title: 'WEEK', pct: claude.week ?? 0, reset: `${claude.weekReset} left`},
              ].map((row, k) => (
                <div key={row.title} style={{display: 'flex', flexDirection: 'column', gap: 5 * S}}>
                  <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'baseline'}}>
                    <Mono size={6.5 * S} color="rgba(255,255,255,0.42)" tracking="0.16em">
                      {row.title}
                    </Mono>
                    <span>
                      <Mono size={8.5 * S} weight={600} color="rgba(255,255,255,0.9)">
                        {row.pct}%
                      </Mono>
                      <Mono size={8.5 * S} color="rgba(255,255,255,0.35)">
                        {' · '}
                      </Mono>
                      <Mono size={8.5 * S} color="rgba(255,255,255,0.55)">
                        {row.reset}
                      </Mono>
                    </span>
                  </div>
                  <CellBar fraction={row.pct / 100} accent={claude.accent} start={T.detail + 4 + k * 6} />
                </div>
              ))}
            </div>
          </div>
        </div>

        <Cursor x={cursorX} y={cursorY} scale={1.15} />
      </div>

      <Caption eyebrow="NOTCH MODE" title="Point at the notch. Your limits drop down." start={70} light />
    </AbsoluteFill>
  );
};
