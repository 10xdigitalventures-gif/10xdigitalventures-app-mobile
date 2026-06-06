import React from 'react'
import Svg, { Path, Circle, Line, Polyline, Polygon, Rect } from 'react-native-svg'
import { colors } from '@/lib/theme'

const stroke = (c) => c || colors.textPrimary

// --- ticks ---
export const TickSingle = ({ size = 14, color }) => (
  <Svg width={size} height={size * 11 / 16} viewBox="0 0 16 11" fill="none">
    <Path d="M1 5.5L5.5 10L15 1" stroke={stroke(color)} strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" />
  </Svg>
)
export const TickDouble = ({ size = 17, color }) => (
  <Svg width={size} height={size * 11 / 20} viewBox="0 0 20 11" fill="none">
    <Path d="M1 5.5L5 9.5L13 1" stroke={stroke(color)} strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" />
    <Path d="M7 5.5L11 9.5L19 1" stroke={stroke(color)} strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" />
  </Svg>
)

// --- tabs / nav ---
export const ChatIcon = ({ size = 24, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
  </Svg>
)
export const PhoneIcon = ({ size = 24, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
  </Svg>
)
export const VideoIcon = ({ size = 24, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Polygon points="23 7 16 12 23 17 23 7" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Rect x={1} y={5} width={15} height={14} rx={2} stroke={stroke(color)} strokeWidth={2}/>
  </Svg>
)
export const GroupIcon = ({ size = 24, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Circle cx={9} cy={7} r={4} stroke={stroke(color)} strokeWidth={2}/>
    <Path d="M23 21v-2a4 4 0 0 0-3-3.87" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Path d="M16 3.13a4 4 0 0 1 0 7.75" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
  </Svg>
)
export const SettingsIcon = ({ size = 24, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Circle cx={12} cy={12} r={3} stroke={stroke(color)} strokeWidth={2}/>
    <Path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
  </Svg>
)

// --- chat-screen actions ---
export const AttachIcon = ({ size = 22, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
  </Svg>
)
export const SendIcon = ({ size = 22, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Line x1={22} y1={2} x2={11} y2={13} stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Polygon points="22 2 15 22 11 13 2 9 22 2" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
  </Svg>
)
export const SmileIcon = ({ size = 22, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Circle cx={12} cy={12} r={10} stroke={stroke(color)} strokeWidth={2}/>
    <Path d="M8 14s1.5 2 4 2 4-2 4-2" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Line x1={9} y1={9} x2={9.01} y2={9} stroke={stroke(color)} strokeWidth={2} strokeLinecap="round"/>
    <Line x1={15} y1={9} x2={15.01} y2={9} stroke={stroke(color)} strokeWidth={2} strokeLinecap="round"/>
  </Svg>
)
export const BackIcon = ({ size = 26, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Polyline points="15 18 9 12 15 6" stroke={stroke(color)} strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round"/>
  </Svg>
)
export const FileIcon = ({ size = 18, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Polyline points="14 2 14 8 20 8" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
  </Svg>
)
export const SearchIcon = ({ size = 22, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Circle cx={11} cy={11} r={8} stroke={stroke(color)} strokeWidth={2}/>
    <Line x1={21} y1={21} x2={16.65} y2={16.65} stroke={stroke(color)} strokeWidth={2} strokeLinecap="round"/>
  </Svg>
)
export const PlusIcon = ({ size = 22, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Line x1={12} y1={5} x2={12} y2={19} stroke={stroke(color)} strokeWidth={2.4} strokeLinecap="round"/>
    <Line x1={5} y1={12} x2={19} y2={12} stroke={stroke(color)} strokeWidth={2.4} strokeLinecap="round"/>
  </Svg>
)
export const LogoutIcon = ({ size = 20, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Polyline points="16 17 21 12 16 7" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Line x1={21} y1={12} x2={9} y2={12} stroke={stroke(color)} strokeWidth={2} strokeLinecap="round"/>
  </Svg>
)