import React from 'react';
import {
  AbsoluteFill,
  Audio,
  Img,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

const ink = '#091b35';
const accent = '#3373f2';
const screens = {
  home: 'screens/01-home.png',
  review: 'screens/02-review.png',
  editor: 'screens/03-editor.png',
  group: 'screens/04-group.png',
  history: 'screens/05-history.png',
};

type PhoneProps = {screen: string; zoom?: number; x?: number; y?: number};

const Phone = ({screen, zoom = 1, x = 0, y = 0}: PhoneProps) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const enter = spring({frame, fps, config: {damping: 22, stiffness: 105}});
  const opacity = interpolate(enter, [0, 0.2], [0, 1]);
  const lift = interpolate(enter, [0, 1], [44, 0]);
  return (
    <div
      style={{
        width: 745,
        height: 1620,
        borderRadius: 74,
        overflow: 'hidden',
        background: '#eef0ff',
        border: '13px solid #13233e',
        boxShadow: '0 54px 100px rgba(7, 18, 48, .24)',
        opacity,
        transform: `translate(${x}px, ${y + lift}px) scale(${zoom})`,
      }}
    >
      <Img src={staticFile(screen)} style={{width: '100%', height: '100%', objectFit: 'cover'}} />
    </div>
  );
};

const Caption = ({children, compact = false}: {children: React.ReactNode; compact?: boolean}) => (
  <div
    style={{
      position: 'absolute',
      left: 66,
      right: 66,
      bottom: 220,
      color: 'white',
      fontFamily: 'PingFang SC, -apple-system, sans-serif',
      fontWeight: 700,
      fontSize: compact ? 47 : 54,
      lineHeight: 1.3,
      letterSpacing: -1.5,
      textAlign: 'center',
      textShadow: '0 3px 18px rgba(0,0,0,.42)',
    }}
  >
    {children}
  </div>
);

const Progress = () => {
  const frame = useCurrentFrame();
  return <div style={{position: 'absolute', top: 0, left: 0, height: 8, background: accent, width: `${(frame / 900) * 100}%`}} />;
};

const Scene = ({
  screen,
  caption,
  title,
  compact,
  zoom,
}: {
  screen: string;
  caption: React.ReactNode;
  title?: string;
  compact?: boolean;
  zoom?: number;
}) => (
  <AbsoluteFill style={{background: 'linear-gradient(150deg, #e9efff 0%, #f8f9ff 48%, #dce8ff 100%)', overflow: 'hidden'}}>
    <div style={{position: 'absolute', width: 780, height: 780, borderRadius: 999, background: '#aac8ff', opacity: 0.36, filter: 'blur(10px)', top: -250, right: -310}} />
    {title ? <div style={{position: 'absolute', top: 140, left: 66, right: 66, color: ink, fontSize: 38, fontWeight: 700, textAlign: 'center', letterSpacing: 2}}>{title}</div> : null}
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', paddingTop: title ? 120 : 0}}>
      <Phone screen={screen} zoom={zoom} />
    </AbsoluteFill>
    <Caption compact={compact}>{caption}</Caption>
  </AbsoluteFill>
);

export const Note1Douyin30s = () => (
  <AbsoluteFill style={{background: ink}}>
    <Audio src={staticFile('audio/narration.m4a')} />
    <Sequence from={0} durationInFrames={120}>
      <Scene screen={screens.home} zoom={0.93} caption={<>我一直找不到一款适合自己的备忘录，<br />所以用 AI 做了一个，它叫 <span style={{color: '#a9c8ff'}}>NOTE1</span>。</>} />
    </Sequence>
    <Sequence from={120} durationInFrames={180}>
      <Scene screen={screens.home} title="灵感来了，打开就记" zoom={0.9} caption={<>文字、照片和文件，<br />都能直接保存。</>} />
    </Sequence>
    <Sequence from={300} durationInFrames={180}>
      <Scene screen={screens.review} title="有空时，再进入卡片回看" zoom={0.88} compact caption={<>上下切换，左右完成，<br />点开继续写。</>} />
    </Sequence>
    <Sequence from={480} durationInFrames={120}>
      <Scene screen={screens.editor} title="让想法继续展开" zoom={0.9} caption={<>同一方向的内容，<br />还可以放进灵感组。</>} />
    </Sequence>
    <Sequence from={600} durationInFrames={120}>
      <Scene screen={screens.group} title="不是信息流" zoom={0.88} compact caption={<>有点像刷短视频，<br />但刷到的都是自己曾经记下来的想法。</>} />
    </Sequence>
    <Sequence from={720} durationInFrames={180}>
      <Scene screen={screens.history} title="NOTE1 正在测试" zoom={0.88} compact caption={<>如果你也需要这样的工具，<br />或者有什么建议，评论区告诉我。</>} />
    </Sequence>
    <Progress />
  </AbsoluteFill>
);
