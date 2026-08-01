import {Composition} from 'remotion';
import {Note1Douyin30s} from './Note1Douyin30s';

export const Root = () => (
  <Composition
    id="NOTE1Douyin30s"
    component={Note1Douyin30s}
    durationInFrames={900}
    fps={30}
    width={1080}
    height={1920}
  />
);
