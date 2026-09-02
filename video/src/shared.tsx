import React from 'react';
import {interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {COLOR, FONT, GLYPH, ProviderId} from './theme';

/**
 * Every scene is timed in "beats" of 1/30 s, whatever the composition's
 * frame rate. Rendering at 60 fps then just samples the same motion twice
 * as often, so timings never have to be re-tuned per rate.
 */
export const BEAT_FPS = 30;

/** The current time in beats (fractional at higher frame rates). */
export const useFrame = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return (frame * BEAT_FPS) / fps;
};

/** A spring that starts at beat `start` and sits at 0 before it. */
export const useSpringAt = (
  start: number,
  config: {damping?: number; stiffness?: number; mass?: number} = {},
  durationInFrames?: number,
) => {
  const frame = useFrame();
  return spring({
    frame: frame - start,
    fps: BEAT_FPS,
    config: {damping: 14, stiffness: 120, mass: 1, ...config},
    durationInFrames,
  });
};

export const easeOut = (t: number) => 1 - Math.pow(1 - Math.max(0, Math.min(1, t)), 3);

/** Counts a figure up from zero after beat `start`, over `frames` beats. */
export const useCount = (target: number, start: number, frames = 28) => {
  const frame = useFrame();
  return Math.round(target * easeOut((frame - start) / frames));
};

export const Glyph: React.FC<{id: ProviderId; size: number; color?: string}> = ({id, size, color = '#fff'}) => (
  <svg width={size} height={size} viewBox="0 0 24 24" style={{display: 'block'}}>
    <path d={GLYPH[id]} fill={color} />
  </svg>
);

/** The macOS arrow pointer, tip at (x, y). */
export const Cursor: React.FC<{x: number; y: number; scale?: number; opacity?: number}> = ({
  x,
  y,
  scale = 1.6,
  opacity = 1,
}) => (
  <svg
    width={24 * scale}
    height={30 * scale}
    viewBox="0 0 24 30"
    style={{position: 'absolute', left: x, top: y, opacity, filter: 'drop-shadow(0 2px 4px rgba(0,0,0,.45))'}}
  >
    <path
      d="M2 2 L2 23 L7.6 18.2 L11.4 27 L15 25.4 L11.3 16.9 L18.8 16.9 Z"
      fill="#000"
      stroke="#fff"
      strokeWidth={1.8}
      strokeLinejoin="round"
    />
  </svg>
);

/** Scene caption, bottom-left: an eyebrow and a line, rising in at `start`. */
export const Caption: React.FC<{eyebrow: string; title: string; start: number; light?: boolean}> = ({
  eyebrow,
  title,
  start,
  light,
}) => {
  const p = useSpringAt(start, {damping: 18, stiffness: 90});
  const color = light ? '#fff' : COLOR.text;
  return (
    <div
      style={{
        position: 'absolute',
        left: 96,
        bottom: 84,
        opacity: p,
        transform: `translateY(${(1 - p) * 24}px)`,
      }}
    >
      <div
        style={{
          fontFamily: FONT.mono,
          fontSize: 20,
          fontWeight: 600,
          letterSpacing: '0.22em',
          color: light ? 'rgba(255,255,255,0.7)' : COLOR.muted,
          marginBottom: 14,
        }}
      >
        {eyebrow}
      </div>
      <div
        style={{
          fontFamily: FONT.sans,
          fontSize: 54,
          fontWeight: 700,
          letterSpacing: '-0.02em',
          color,
          textShadow: light ? '0 2px 24px rgba(0,0,0,.5)' : undefined,
        }}
      >
        {title}
      </div>
    </div>
  );
};

/** Fades a scene in over its first frames and out over its last. */
export const Fade: React.FC<{duration: number; edge?: number; children: React.ReactNode}> = ({
  duration,
  edge = 12,
  children,
}) => {
  const frame = useFrame();
  const opacity = interpolate(frame, [0, edge, duration - edge, duration], [0, 1, 1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  return <div style={{position: 'absolute', inset: 0, opacity}}>{children}</div>;
};

/** A meter with a glow under its fill. */
export const Bar: React.FC<{
  fraction: number;
  accent: string;
  height: number;
  gradient?: boolean;
  track?: string;
}> = ({fraction, accent, height, gradient, track = 'rgba(255,255,255,0.1)'}) => (
  <div style={{position: 'relative', height, borderRadius: height, background: track, overflow: 'hidden'}}>
    <div
      style={{
        position: 'absolute',
        inset: 0,
        width: `${Math.max(0, Math.min(100, fraction * 100))}%`,
        borderRadius: height,
        background: gradient
          ? `linear-gradient(90deg, ${accent}, ${accent}66)`
          : accent,
        boxShadow: `0 0 ${height * 2}px ${accent}80`,
      }}
    />
  </div>
);
