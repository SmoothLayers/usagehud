import {Composition} from 'remotion';
import {Main, DURATION, FPS} from './Main';

export const RemotionRoot = () => (
  <>
    <Composition
      id="UsageHUD"
      component={Main}
      durationInFrames={DURATION}
      fps={FPS}
      width={1920}
      height={1080}
    />
    <Composition
      id="UsageHUDSquare"
      component={Main}
      durationInFrames={DURATION}
      fps={FPS}
      width={1080}
      height={1080}
    />
  </>
);
