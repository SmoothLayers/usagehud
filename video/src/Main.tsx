import React from 'react';
import {AbsoluteFill, Sequence, useVideoConfig} from 'remotion';
import {COLOR} from './theme';
import {BEAT_FPS, Fade} from './shared';
import {TitleScene, OutroScene} from './TitleScene';
import {NotchScene} from './NotchScene';
import {ThemesScene} from './ThemesScene';
import {HudScene} from './HudScene';
import {CompactScene} from './CompactScene';

export const FPS = 60;
// Scene lengths are authored in beats (1/30 s); frames scale with the rate.
const R = FPS / BEAT_FPS;

// Scenes overlap by the fade length so one dissolves into the next.
const FADE = 12;
const SCENES = [
  {id: 'title', length: 84, node: <TitleScene />},
  {id: 'notch', length: 280, node: <NotchScene />},
  {id: 'themes', length: 210, node: <ThemesScene />},
  {id: 'hud', length: 190, node: <HudScene />},
  {id: 'compact', length: 190, node: <CompactScene />},
  {id: 'outro', length: 96, node: <OutroScene />},
];

let cursor = 0;
const PLACED = SCENES.map((scene) => {
  const from = cursor;
  cursor += scene.length - FADE;
  return {...scene, from};
});

export const DURATION = Math.round((PLACED[PLACED.length - 1].from + PLACED[PLACED.length - 1].length) * R);

export const Main: React.FC = () => {
  const {width, height} = useVideoConfig();
  // The scenes are composed for 1920x1080; other frames letterbox it.
  const scale = Math.min(width / 1920, height / 1080);
  return (
    <AbsoluteFill style={{background: COLOR.ground}}>
      <div
        style={{
          position: 'absolute',
          width: 1920,
          height: 1080,
          left: (width - 1920 * scale) / 2,
          top: (height - 1080 * scale) / 2,
          transform: `scale(${scale})`,
          transformOrigin: '0 0',
        }}
      >
        {PLACED.map((scene) => (
          <Sequence key={scene.id} from={Math.round(scene.from * R)} durationInFrames={Math.round(scene.length * R)} name={scene.id}>
            <Fade duration={scene.length} edge={FADE}>
              {scene.node}
            </Fade>
          </Sequence>
        ))}
      </div>
    </AbsoluteFill>
  );
};
