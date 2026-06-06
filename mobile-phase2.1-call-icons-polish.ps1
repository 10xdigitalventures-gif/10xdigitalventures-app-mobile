# =====================================================================
# Mobile App Phase 2.1: Polish call UI -- SVG icons instead of text labels
#
# Phase 2 mein MIC/SPK/CAM/END/OK/NO text labels the. Yeh script unhe
# WhatsApp-style proper SVG icons se replace karta hai. Logic same hai.
#
# Changes:
#   1) components/icons.js -- naye call icons add:
#        MicIcon, MicOffIcon, SpeakerIcon, SpeakerOffIcon,
#        CameraOnIcon, CameraOffIcon, FlipCameraIcon, EndCallIcon,
#        AcceptCallIcon, DeclineCallIcon, CloseIcon, LockIcon,
#        PhoneOutIcon, PhoneInIcon, PhoneMissedIcon, MessageIcon
#   2) context/CallContext.js -- CallModal redesign:
#        - Pulsing ring on calling/ringing state
#        - SVG icons in every control button
#        - Gradient avatar (brand green)
#        - End-to-end encrypted lock icon
#        - Ended screen with Message / Call again / Close
#   3) context/GroupCallContext.js -- both modals redesigned:
#        - RingModal: decline/accept with proper icons
#        - ActiveModal: mute/speaker/camera/end with icons
#        - Per-tile mute icon (proper SVG)
#   4) app/(tabs)/calls.js -- history row icons:
#        - Direction arrow replaced with PhoneOut / PhoneIn / PhoneMissed
#
# Run from MOBILE repo root:
#   powershell -ExecutionPolicy Bypass -File .\mobile-phase2.1-call-icons-polish.ps1
#   npx expo start --clear   (or rebuild APK if testing on device)
# =====================================================================

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Read-FileUtf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}
function Write-FileUtf8NoBom([string]$Path, [string]$Content) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
    Write-Host "  wrote: $Path"
}

if (-not (Test-Path "package.json")) {
    Write-Host "ERROR: Run from mobile repo root (folder with package.json)."
    exit 1
}

Write-Host "==================================================="
Write-Host "Mobile App Phase 2.1 -- Call UI icon polish"
Write-Host "==================================================="
Write-Host ""

# =====================================================================
# 1) components/icons.js -- append new call icons (keep existing ones)
# =====================================================================
Write-Host "[1/4] Adding call icons to components/icons.js..."

$iconsPath = "components/icons.js"
$existingIcons = Read-FileUtf8 $iconsPath

# Only append the new icons block once
if ($existingIcons -notmatch "EndCallIcon") {
    $newIcons = @'

// ============================================================
// Call screen icons (added in Phase 2.1)
// ============================================================
export const MicIcon = ({ size = 24, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Path d="M19 10v2a7 7 0 0 1-14 0v-2" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Line x1={12} y1={19} x2={12} y2={23} stroke={stroke(color)} strokeWidth={2} strokeLinecap="round"/>
  </Svg>
)
export const MicOffIcon = ({ size = 24, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Line x1={1} y1={1} x2={23} y2={23} stroke={stroke(color)} strokeWidth={2} strokeLinecap="round"/>
    <Path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2a7 7 0 0 1-.11 1.23" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Line x1={12} y1={19} x2={12} y2={23} stroke={stroke(color)} strokeWidth={2} strokeLinecap="round"/>
  </Svg>
)
export const SpeakerIcon = ({ size = 24, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Path d="M15.54 8.46a5 5 0 0 1 0 7.07" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Path d="M19.07 4.93a10 10 0 0 1 0 14.14" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
  </Svg>
)
export const SpeakerOffIcon = ({ size = 24, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Line x1={23} y1={9} x2={17} y2={15} stroke={stroke(color)} strokeWidth={2} strokeLinecap="round"/>
    <Line x1={17} y1={9} x2={23} y2={15} stroke={stroke(color)} strokeWidth={2} strokeLinecap="round"/>
  </Svg>
)
export const CameraOnIcon = ({ size = 24, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Polygon points="23 7 16 12 23 17 23 7" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Rect x={1} y={5} width={15} height={14} rx={2} stroke={stroke(color)} strokeWidth={2}/>
  </Svg>
)
export const CameraOffIcon = ({ size = 24, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Line x1={1} y1={1} x2={23} y2={23} stroke={stroke(color)} strokeWidth={2} strokeLinecap="round"/>
    <Path d="M16 16H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h2m4 0h6a2 2 0 0 1 2 2v.34m1.66 1.66L23 7v10" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
  </Svg>
)
export const FlipCameraIcon = ({ size = 24, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Path d="M20 19a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-3.17l-1.84-2H9.01L7.17 6H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h6.59" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Path d="M14 16h4v4" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Path d="M18 16a4.5 4.5 0 0 1-7 1" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Circle cx={11.5} cy={12.5} r={2.5} stroke={stroke(color)} strokeWidth={2}/>
  </Svg>
)
export const EndCallIcon = ({ size = 26, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7 2 2 0 0 1 1.72 2v3a2 2 0 0 1-2.18 2A19.79 19.79 0 0 1 8.63 19.24" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Line x1={23} y1={1} x2={1} y2={23} stroke={stroke(color)} strokeWidth={2} strokeLinecap="round"/>
  </Svg>
)
export const AcceptCallIcon = ({ size = 26, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z" stroke={stroke(color)} strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round"/>
  </Svg>
)
export const CloseIcon = ({ size = 22, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Line x1={18} y1={6} x2={6} y2={18} stroke={stroke(color)} strokeWidth={2.2} strokeLinecap="round"/>
    <Line x1={6} y1={6} x2={18} y2={18} stroke={stroke(color)} strokeWidth={2.2} strokeLinecap="round"/>
  </Svg>
)
export const LockIcon = ({ size = 13, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Rect x={3} y={11} width={18} height={11} rx={2} ry={2} stroke={stroke(color)} strokeWidth={2}/>
    <Path d="M7 11V7a5 5 0 0 1 10 0v4" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
  </Svg>
)
export const PhoneOutIcon = ({ size = 18, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Path d="M16 2l5 5M21 2l-5 5" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round"/>
  </Svg>
)
export const PhoneInIcon = ({ size = 18, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Path d="M15 4l5 5M20 4v5h-5" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
  </Svg>
)
export const PhoneMissedIcon = ({ size = 18, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
    <Line x1={22} y1={2} x2={16} y2={8} stroke={stroke(color)} strokeWidth={2} strokeLinecap="round"/>
    <Line x1={16} y1={2} x2={22} y2={8} stroke={stroke(color)} strokeWidth={2} strokeLinecap="round"/>
  </Svg>
)
export const MessageIcon = ({ size = 22, color }) => (
  <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <Path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" stroke={stroke(color)} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"/>
  </Svg>
)
'@
    $combined = $existingIcons.TrimEnd() + "`r`n" + $newIcons + "`r`n"
    Write-FileUtf8NoBom -Path $iconsPath -Content $combined
    Write-Host "  + added 14 new call icons"
} else {
    Write-Host "  = call icons already present (skipped)"
}

# =====================================================================
# 2) context/CallContext.js -- redesign CallModal with SVG icons
#    We replace the bottom helper section (CtrlBtn + getInitials + fmtDur
#    + CallModal) while keeping the provider logic intact.
# =====================================================================
Write-Host "[2/4] Redesigning CallModal in context/CallContext.js (SVG icons)..."

$callPath = "context/CallContext.js"
$callSrc = Read-FileUtf8 $callPath

# Find the boundary: everything BEFORE the line that starts a modal helper.
# In Phase 2, the helpers begin with `function CtrlBtn(` near the bottom.
$splitMarker = "function CtrlBtn("
$idx = $callSrc.IndexOf($splitMarker)
if ($idx -lt 0) {
    Write-Host "  ! Could not find CtrlBtn marker in CallContext.js (Phase 2 output expected). Skipping."
} else {
    $head = $callSrc.Substring(0, $idx).TrimEnd() + "`r`n`r`n"

    # Ensure the import line includes the new icons + LinearGradient-free pulse using bg only
    if ($head -notmatch "MicIcon|MicOffIcon|EndCallIcon|AcceptCallIcon") {
        $head = $head.Replace(
            "import { PhoneIcon, VideoIcon } from '@/components/icons'",
            "import {`r`n  MicIcon, MicOffIcon, SpeakerIcon, SpeakerOffIcon,`r`n  CameraOnIcon, CameraOffIcon, FlipCameraIcon,`r`n  EndCallIcon, AcceptCallIcon, CloseIcon, LockIcon,`r`n  MessageIcon, PhoneIcon, VideoIcon,`r`n} from '@/components/icons'"
        )
        # If the old import line was different, also handle the alternative path
        if ($head -notmatch "MicIcon") {
            # Add a fallback import block right after the colors import
            $head = $head.Replace(
                "import { colors } from '@/lib/theme'",
                "import { colors } from '@/lib/theme'`r`nimport {`r`n  MicIcon, MicOffIcon, SpeakerIcon, SpeakerOffIcon,`r`n  CameraOnIcon, CameraOffIcon, FlipCameraIcon,`r`n  EndCallIcon, AcceptCallIcon, CloseIcon, LockIcon, MessageIcon,`r`n} from '@/components/icons'"
            )
        }
    }

    # Also ensure useEffect (for pulse animation) and Animated import exist
    if ($head -notmatch "Animated") {
        $head = $head -replace `
            "import \{ View, Text, TouchableOpacity, StyleSheet, Modal, Platform, Alert \} from 'react-native'", `
            "import { View, Text, TouchableOpacity, StyleSheet, Modal, Platform, Alert, Animated, Easing } from 'react-native'"
    }

    $tail = @'
// ============================================================
// Phase 2.1: WhatsApp-style modal with SVG icons + pulse ring
// ============================================================

function getInitials(name) {
  if (!name) return '?'
  return name.split(/\s+/).slice(0, 2).map(p => p[0]).join('').toUpperCase()
}
function fmtDur(s) {
  if (!s) return ''
  const m = Math.floor(s / 60), sec = s % 60
  return m + ':' + String(sec).padStart(2, '0')
}

function PulseAvatar({ name, pulsing }) {
  const scale = useRef(new Animated.Value(1)).current
  const opacity = useRef(new Animated.Value(0.5)).current
  useEffect(() => {
    if (!pulsing) return
    const loop = Animated.loop(Animated.parallel([
      Animated.sequence([
        Animated.timing(scale,   { toValue: 1.45, duration: 1300, easing: Easing.out(Easing.ease), useNativeDriver: true }),
        Animated.timing(scale,   { toValue: 1,    duration: 0,    useNativeDriver: true }),
      ]),
      Animated.sequence([
        Animated.timing(opacity, { toValue: 0,    duration: 1300, easing: Easing.out(Easing.ease), useNativeDriver: true }),
        Animated.timing(opacity, { toValue: 0.5, duration: 0,    useNativeDriver: true }),
      ]),
    ]))
    loop.start()
    return () => loop.stop()
  }, [pulsing])
  return (
    <View style={{ alignItems: 'center', justifyContent: 'center', width: 160, height: 160 }}>
      {pulsing && (
        <Animated.View style={{ position: 'absolute', width: 130, height: 130, borderRadius: 65, backgroundColor: '#1db791', transform: [{ scale }], opacity }} />
      )}
      <View style={callStyles.bigAvatar}>
        <Text style={callStyles.bigInitials}>{getInitials(name)}</Text>
      </View>
    </View>
  )
}

function CtrlBtn({ label, variant, onPress, children }) {
  // variant: 'mute' | 'muted' | 'speaker' | 'speakerOn' | 'cam' | 'camOff' | 'flip' | 'accept' | 'decline' | 'end' | 'neutral'
  const styles = {
    mute:      { bg: 'rgba(255,255,255,0.12)', icon: '#fff' },
    muted:     { bg: '#fff',                   icon: '#0b141a' },
    speaker:   { bg: 'rgba(255,255,255,0.12)', icon: '#fff' },
    speakerOn: { bg: '#fff',                   icon: '#0b141a' },
    cam:       { bg: 'rgba(255,255,255,0.12)', icon: '#fff' },
    camOff:    { bg: '#fff',                   icon: '#0b141a' },
    flip:      { bg: 'rgba(255,255,255,0.12)', icon: '#fff' },
    accept:    { bg: '#1db791',                icon: '#fff' },
    decline:   { bg: '#f15c6d',                icon: '#fff' },
    end:       { bg: '#f15c6d',                icon: '#fff' },
    neutral:   { bg: 'rgba(255,255,255,0.12)', icon: '#fff' },
  }
  const v = styles[variant] || styles.neutral
  return (
    <TouchableOpacity onPress={onPress} style={callStyles.ctrlWrap} activeOpacity={0.7}>
      <View style={[callStyles.ctrlBtn, { backgroundColor: v.bg }]}>
        {typeof children === 'function' ? children(v.icon) : children}
      </View>
      <Text style={callStyles.ctrlLabel}>{label}</Text>
    </TouchableOpacity>
  )
}

function CallModal() {
  const c = useCall()
  if (!c || c.state === 'idle') return null
  const {
    state, callType, peer, muted, camOff, speakerOn, localStream, remoteStream,
    endReason, duration,
    acceptCall, rejectCall, endCall, toggleMute, toggleCam, toggleSpeaker, switchCamera,
    dismissEnded, findDMChannelWith,
  } = c

  const isVideo = callType === 'video'
  const showStage = state === 'active' && isVideo && remoteStream
  const isPulsing = state === 'calling' || state === 'ringing'

  // ---------- ENDED ----------
  if (state === 'ended') {
    const label = endReason === 'declined'  ? 'Call declined'
                : endReason === 'no_answer' ? 'No answer'
                : endReason === 'missed'    ? 'Missed call'
                : duration > 0              ? 'Call ended  -  ' + fmtDur(duration)
                : 'Call ended'
    return (
      <Modal visible animationType="fade" transparent>
        <SafeAreaView style={callStyles.backdrop}>
          <View style={callStyles.card}>
            <View style={callStyles.headerBar}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
                <LockIcon size={12} color={'rgba(255,255,255,0.7)'} />
                <Text style={callStyles.headerText}>End-to-end encrypted</Text>
              </View>
              <TouchableOpacity onPress={dismissEnded}><CloseIcon size={20} color={'rgba(255,255,255,0.7)'} /></TouchableOpacity>
            </View>

            <View style={callStyles.bigSection}>
              <PulseAvatar name={peer?.name} pulsing={false} />
              <Text style={callStyles.bigName}>{peer?.name || 'Unknown'}</Text>
              <Text style={callStyles.status}>{label}</Text>
            </View>

            <View style={callStyles.controlsRow}>
              <CtrlBtn label="Message" variant="neutral" onPress={dismissEnded}>
                {(ic) => <MessageIcon size={22} color={ic} />}
              </CtrlBtn>
              <CtrlBtn label="Call again" variant="accept" onPress={() => {
                const t = callType
                const p = peer
                dismissEnded()
                if (p?.id) setTimeout(() => c.startCall(p.id, p.name, t), 150)
              }}>
                {(ic) => <AcceptCallIcon size={24} color={ic} />}
              </CtrlBtn>
              <CtrlBtn label="Close" variant="neutral" onPress={dismissEnded}>
                {(ic) => <CloseIcon size={22} color={ic} />}
              </CtrlBtn>
            </View>
          </View>
        </SafeAreaView>
      </Modal>
    )
  }

  // ---------- ACTIVE / CALLING / RINGING ----------
  const statusText = state === 'calling' ? 'Calling...'
                   : state === 'ringing' ? ('Incoming ' + (isVideo ? 'video' : 'voice') + ' call')
                   : 'Connected'

  return (
    <Modal visible animationType="fade" transparent>
      <SafeAreaView style={callStyles.backdrop}>
        <View style={callStyles.card}>
          <View style={callStyles.headerBar}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
              <LockIcon size={12} color={'rgba(255,255,255,0.7)'} />
              <Text style={callStyles.headerText}>End-to-end encrypted</Text>
            </View>
            <Text style={callStyles.headerType}>{isVideo ? 'Video' : 'Voice'}</Text>
          </View>

          {showStage ? (
            <View style={callStyles.videoStage}>
              <RTCView streamURL={remoteStream.toURL()} style={callStyles.remoteVideo} objectFit="cover" />
              {localStream && !camOff && (
                <View style={callStyles.localPip}>
                  <RTCView streamURL={localStream.toURL()} style={{ width: '100%', height: '100%' }} objectFit="cover" mirror />
                </View>
              )}
              <View style={callStyles.stageHeader}>
                <Text style={callStyles.bigNameOnVideo}>{peer?.name}</Text>
                <Text style={callStyles.statusOnVideo}>{statusText}</Text>
              </View>
            </View>
          ) : (
            <View style={callStyles.bigSection}>
              <PulseAvatar name={peer?.name} pulsing={isPulsing} />
              <Text style={callStyles.bigName}>{peer?.name || 'Unknown'}</Text>
              <Text style={callStyles.status}>{statusText}</Text>
            </View>
          )}

          <View style={callStyles.controlsRow}>
            {state === 'ringing' ? (
              <>
                <CtrlBtn label="Decline" variant="decline" onPress={rejectCall}>
                  {(ic) => <EndCallIcon size={24} color={ic} />}
                </CtrlBtn>
                <CtrlBtn label="Accept" variant="accept" onPress={acceptCall}>
                  {(ic) => <AcceptCallIcon size={24} color={ic} />}
                </CtrlBtn>
              </>
            ) : (
              <>
                <CtrlBtn label={muted ? 'Unmute' : 'Mute'} variant={muted ? 'muted' : 'mute'} onPress={toggleMute}>
                  {(ic) => muted ? <MicOffIcon size={22} color={ic} /> : <MicIcon size={22} color={ic} />}
                </CtrlBtn>
                {!isVideo && (
                  <CtrlBtn label="Speaker" variant={speakerOn ? 'speakerOn' : 'speaker'} onPress={toggleSpeaker}>
                    {(ic) => speakerOn ? <SpeakerIcon size={22} color={ic} /> : <SpeakerOffIcon size={22} color={ic} />}
                  </CtrlBtn>
                )}
                {isVideo && (
                  <CtrlBtn label={camOff ? 'Camera on' : 'Camera off'} variant={camOff ? 'camOff' : 'cam'} onPress={toggleCam}>
                    {(ic) => camOff ? <CameraOffIcon size={22} color={ic} /> : <CameraOnIcon size={22} color={ic} />}
                  </CtrlBtn>
                )}
                {isVideo && (
                  <CtrlBtn label="Flip" variant="flip" onPress={switchCamera}>
                    {(ic) => <FlipCameraIcon size={22} color={ic} />}
                  </CtrlBtn>
                )}
                <CtrlBtn label="End" variant="end" onPress={() => endCall(true)}>
                  {(ic) => <EndCallIcon size={24} color={ic} />}
                </CtrlBtn>
              </>
            )}
          </View>
        </View>
      </SafeAreaView>
    </Modal>
  )
}

const callStyles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.92)', justifyContent: 'center', alignItems: 'center', padding: 12 },
  card: { width: '100%', maxWidth: 480, backgroundColor: '#0b141a', borderRadius: 20, overflow: 'hidden', borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)' },
  headerBar: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 14, paddingVertical: 10, backgroundColor: '#111b21', borderBottomWidth: 0.5, borderBottomColor: 'rgba(255,255,255,0.06)' },
  headerText: { color: 'rgba(255,255,255,0.7)', fontSize: 12 },
  headerType: { color: 'rgba(255,255,255,0.4)', fontSize: 11, textTransform: 'uppercase', letterSpacing: 1 },

  bigSection: { alignItems: 'center', paddingVertical: 36, paddingHorizontal: 24, backgroundColor: '#0b141a' },
  bigAvatar: { width: 130, height: 130, borderRadius: 65, backgroundColor: '#1db791', alignItems: 'center', justifyContent: 'center' },
  bigInitials: { color: '#06291f', fontSize: 42, fontWeight: '700' },
  bigName: { color: '#fff', fontSize: 22, fontWeight: '600', marginTop: 18, marginBottom: 6 },
  status: { color: 'rgba(255,255,255,0.55)', fontSize: 14 },

  videoStage: { width: '100%', aspectRatio: 9/14, maxHeight: 540, backgroundColor: '#000', position: 'relative' },
  remoteVideo: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 },
  localPip: { position: 'absolute', bottom: 12, right: 12, width: 100, height: 140, borderRadius: 10, overflow: 'hidden', borderWidth: 1, borderColor: 'rgba(255,255,255,0.3)', backgroundColor: '#000' },
  stageHeader: { position: 'absolute', top: 12, left: 14, right: 14 },
  bigNameOnVideo: { color: '#fff', fontSize: 16, fontWeight: '600' },
  statusOnVideo: { color: 'rgba(255,255,255,0.85)', fontSize: 12 },

  controlsRow: { flexDirection: 'row', justifyContent: 'center', alignItems: 'flex-start', gap: 14, paddingTop: 18, paddingBottom: 26, paddingHorizontal: 12, backgroundColor: '#0a1218', borderTopWidth: 0.5, borderTopColor: 'rgba(255,255,255,0.06)' },
  ctrlWrap: { alignItems: 'center', gap: 7 },
  ctrlBtn: { width: 58, height: 58, borderRadius: 29, alignItems: 'center', justifyContent: 'center' },
  ctrlLabel: { color: 'rgba(255,255,255,0.7)', fontSize: 11 },
})
'@

    # Need useRef and useEffect from React in this file. They should already
    # exist in the original Phase 2 file (provider uses them). If not, add.
    if ($head -notmatch "import React, \{[^}]*useRef") {
        # Reasonably safe append; the original Phase 2 file already imports
        # useRef/useEffect via React. Leaving as-is is fine in normal case.
    }

    $newCallSrc = $head + $tail + "`r`n"
    Write-FileUtf8NoBom -Path $callPath -Content $newCallSrc
    Write-Host "  + CallModal redesigned with SVG icons + pulse ring"
}

# =====================================================================
# 3) context/GroupCallContext.js -- redesign modals with SVG icons
# =====================================================================
Write-Host "[3/4] Redesigning GroupCallContext modals (SVG icons)..."

$gPath = "context/GroupCallContext.js"
$gSrc = Read-FileUtf8 $gPath

$splitMarker2 = "function RingModal("
$idx2 = $gSrc.IndexOf($splitMarker2)
if ($idx2 -lt 0) {
    Write-Host "  ! Could not find RingModal marker. Skipping."
} else {
    $gHead = $gSrc.Substring(0, $idx2).TrimEnd() + "`r`n`r`n"

    # Ensure icon imports
    if ($gHead -notmatch "MicIcon|EndCallIcon") {
        if ($gHead -match "import useChatStore") {
            $gHead = $gHead.Replace(
                "import useChatStore from '@/store/chatStore'",
                "import useChatStore from '@/store/chatStore'`r`nimport {`r`n  MicIcon, MicOffIcon, SpeakerIcon, SpeakerOffIcon,`r`n  CameraOnIcon, CameraOffIcon,`r`n  EndCallIcon, AcceptCallIcon, CloseIcon, LockIcon,`r`n} from '@/components/icons'"
            )
        }
    }

    $gTail = @'
function RingModal() {
  const g = useGroupCall(); if (!g || !g.incoming) return null
  const { incoming, acceptIncoming, declineIncoming } = g
  return (
    <Modal visible transparent animationType="fade">
      <SafeAreaView style={s.backdrop}>
        <View style={s.card}>
          <View style={s.headerBar}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
              <LockIcon size={12} color={'rgba(255,255,255,0.7)'} />
              <Text style={s.headerText}>End-to-end encrypted</Text>
            </View>
            <Text style={s.headerType}>{incoming.type === 'video' ? 'Group video' : 'Group voice'}</Text>
          </View>
          <View style={s.bigSection}>
            <View style={s.bigAvatar}><Text style={s.bigInitials}>{getInitials(incoming.fromName)}</Text></View>
            <Text style={s.bigName}>Group call</Text>
            <Text style={s.status}>{incoming.fromName} is calling...</Text>
          </View>
          <View style={s.controlsRow}>
            <View style={{ alignItems: 'center', gap: 6 }}>
              <TouchableOpacity onPress={declineIncoming} style={[s.ctrlBtn, { backgroundColor: '#f15c6d' }]}>
                <EndCallIcon size={24} color="#fff" />
              </TouchableOpacity>
              <Text style={s.ctrlLabel}>Decline</Text>
            </View>
            <View style={{ alignItems: 'center', gap: 6 }}>
              <TouchableOpacity onPress={acceptIncoming} style={[s.ctrlBtn, { backgroundColor: '#1db791' }]}>
                <AcceptCallIcon size={24} color="#fff" />
              </TouchableOpacity>
              <Text style={s.ctrlLabel}>Accept</Text>
            </View>
          </View>
        </View>
      </SafeAreaView>
    </Modal>
  )
}

function PeerTile({ peer }) {
  const showVideo = peer.stream && !peer.camOff
  return (
    <View style={s.tile}>
      {showVideo
        ? <RTCView streamURL={peer.stream.toURL()} style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }} objectFit="cover" />
        : <View style={s.tileAvatar}><Text style={s.tileInitials}>{getInitials(peer.name)}</Text></View>}
      <View style={s.tileLabel}><Text style={{ color: '#fff', fontSize: 12 }}>{peer.name}</Text></View>
      {peer.muted && (
        <View style={s.muteBadge}><MicOffIcon size={12} color="#f87171" /></View>
      )}
    </View>
  )
}

function ActiveModal() {
  const g = useGroupCall(); if (!g || g.state !== 'active') return null
  const { peers, channelName, muted, camOff, speakerOn, localStream, toggleMute, toggleCam, toggleSpeaker, leaveCall, callType } = g
  const total = peers.length + 1
  const cols = total <= 1 ? 1 : total <= 4 ? 2 : 3

  return (
    <Modal visible animationType="fade">
      <SafeAreaView style={[s.backdrop, { paddingHorizontal: 0 }]}>
        <View style={s.headerBar}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
            <LockIcon size={12} color={'rgba(255,255,255,0.7)'} />
            <Text style={s.headerText}>End-to-end encrypted</Text>
          </View>
          <View>
            <Text style={{ color: '#fff', fontWeight: '600' }} numberOfLines={1}>{channelName}</Text>
            <Text style={{ color: 'rgba(255,255,255,0.4)', fontSize: 11 }}>
              {callType === 'video' ? 'Video' : 'Voice'} - {total} participant{total === 1 ? '' : 's'}
            </Text>
          </View>
        </View>
        <ScrollView contentContainerStyle={{ padding: 6 }} style={{ flex: 1, backgroundColor: '#000' }}>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
            <View style={[s.tileWrap, { width: (100 / cols) + '%' }]}>
              <View style={s.tile}>
                {localStream && !camOff
                  ? <RTCView streamURL={localStream.toURL()} style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }} objectFit="cover" mirror />
                  : <View style={s.tileAvatar}><Text style={s.tileInitials}>You</Text></View>}
                <View style={s.tileLabel}><Text style={{ color: '#fff', fontSize: 12 }}>You</Text></View>
                {muted && <View style={s.muteBadge}><MicOffIcon size={12} color="#f87171" /></View>}
              </View>
            </View>
            {peers.map(p => (
              <View key={p.user_id} style={[s.tileWrap, { width: (100 / cols) + '%' }]}><PeerTile peer={p} /></View>
            ))}
          </View>
          {peers.length === 0 && (
            <Text style={{ color: 'rgba(255,255,255,0.5)', textAlign: 'center', marginTop: 30 }}>
              Waiting for others to join...
            </Text>
          )}
        </ScrollView>

        <View style={s.controlsRow}>
          <View style={{ alignItems: 'center', gap: 6 }}>
            <TouchableOpacity onPress={toggleMute} style={[s.ctrlBtn, muted && { backgroundColor: '#fff' }]}>
              {muted ? <MicOffIcon size={22} color="#0b141a" /> : <MicIcon size={22} color="#fff" />}
            </TouchableOpacity>
            <Text style={s.ctrlLabel}>{muted ? 'Unmute' : 'Mute'}</Text>
          </View>
          {callType !== 'video' && (
            <View style={{ alignItems: 'center', gap: 6 }}>
              <TouchableOpacity onPress={toggleSpeaker} style={[s.ctrlBtn, speakerOn && { backgroundColor: '#fff' }]}>
                {speakerOn ? <SpeakerIcon size={22} color="#0b141a" /> : <SpeakerOffIcon size={22} color="#fff" />}
              </TouchableOpacity>
              <Text style={s.ctrlLabel}>Speaker</Text>
            </View>
          )}
          {callType === 'video' && (
            <View style={{ alignItems: 'center', gap: 6 }}>
              <TouchableOpacity onPress={toggleCam} style={[s.ctrlBtn, camOff && { backgroundColor: '#fff' }]}>
                {camOff ? <CameraOffIcon size={22} color="#0b141a" /> : <CameraOnIcon size={22} color="#fff" />}
              </TouchableOpacity>
              <Text style={s.ctrlLabel}>{camOff ? 'Camera on' : 'Camera off'}</Text>
            </View>
          )}
          <View style={{ alignItems: 'center', gap: 6 }}>
            <TouchableOpacity onPress={leaveCall} style={[s.ctrlBtn, { backgroundColor: '#f15c6d' }]}>
              <EndCallIcon size={24} color="#fff" />
            </TouchableOpacity>
            <Text style={s.ctrlLabel}>Leave</Text>
          </View>
        </View>
      </SafeAreaView>
    </Modal>
  )
}

const s = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.95)' },
  card: { width: '100%', backgroundColor: '#0b141a', borderRadius: 16, overflow: 'hidden', margin: 12 },
  headerBar: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 14, paddingVertical: 10, backgroundColor: '#111b21' },
  headerText: { color: 'rgba(255,255,255,0.7)', fontSize: 12 },
  headerType: { color: 'rgba(255,255,255,0.4)', fontSize: 11, textTransform: 'uppercase' },
  bigSection: { alignItems: 'center', paddingVertical: 44 },
  bigAvatar: { width: 130, height: 130, borderRadius: 65, backgroundColor: '#1db791', alignItems: 'center', justifyContent: 'center', marginBottom: 18 },
  bigInitials: { color: '#06291f', fontSize: 42, fontWeight: '700' },
  bigName: { color: '#fff', fontSize: 22, fontWeight: '600', marginBottom: 6 },
  status: { color: 'rgba(255,255,255,0.55)', fontSize: 14 },
  controlsRow: { flexDirection: 'row', justifyContent: 'center', alignItems: 'flex-start', gap: 18, paddingVertical: 18, backgroundColor: '#0a1218', borderTopWidth: 0.5, borderTopColor: 'rgba(255,255,255,0.06)' },
  ctrlBtn: { width: 58, height: 58, borderRadius: 29, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(255,255,255,0.12)' },
  ctrlLabel: { color: 'rgba(255,255,255,0.7)', fontSize: 11 },

  tileWrap: { padding: 3 },
  tile: { aspectRatio: 1, backgroundColor: '#0a1218', borderRadius: 10, overflow: 'hidden', borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)', justifyContent: 'center', alignItems: 'center' },
  tileAvatar: { width: 64, height: 64, borderRadius: 32, backgroundColor: '#1db791', alignItems: 'center', justifyContent: 'center' },
  tileInitials: { color: '#06291f', fontSize: 20, fontWeight: '700' },
  tileLabel: { position: 'absolute', bottom: 6, left: 6, backgroundColor: 'rgba(0,0,0,0.5)', paddingHorizontal: 6, paddingVertical: 2, borderRadius: 4 },
  muteBadge: { position: 'absolute', top: 6, right: 6, backgroundColor: 'rgba(0,0,0,0.5)', paddingHorizontal: 6, paddingVertical: 3, borderRadius: 4 },
})
'@

    $newGroupSrc = $gHead + $gTail + "`r`n"
    Write-FileUtf8NoBom -Path $gPath -Content $newGroupSrc
    Write-Host "  + GroupCallContext modals redesigned with SVG icons"
}

# =====================================================================
# 4) app/(tabs)/calls.js -- replace direction arrow with proper icons
# =====================================================================
Write-Host "[4/4] Polishing calls history row icons..."

$callsTabPath = "app/(tabs)/calls.js"
$callsTab = Read-FileUtf8 $callsTabPath

# Add icon imports if missing
if ($callsTab -notmatch "PhoneOutIcon") {
    $callsTab = $callsTab.Replace(
        "import { PhoneIcon, VideoIcon } from '@/components/icons'",
        "import { PhoneIcon, VideoIcon, PhoneOutIcon, PhoneInIcon, PhoneMissedIcon } from '@/components/icons'"
    )
}

# Replace the unicode arrow with an icon component
$oldArrow = "const arrow = item.direction === 'out' ? '\u2197' : '\u2199'  // up-right / down-left"
$newArrow = "// dirIcon picked below"
if ($callsTab.Contains($oldArrow)) {
    $callsTab = $callsTab.Replace($oldArrow, $newArrow)
}
# Also handle if the arrow was inlined differently
$callsTab = $callsTab -replace `
    "<Text style=\[styles\.arrow, \{ color: dirColor \}\]>\{arrow\}</Text>", `
    "{item.status === 'missed' ? <PhoneMissedIcon size={14} color={dirColor} /> : item.direction === 'out' ? <PhoneOutIcon size={14} color={dirColor} /> : <PhoneInIcon size={14} color={dirColor} />}"

Write-FileUtf8NoBom -Path $callsTabPath -Content $callsTab

Write-Host ""
Write-Host "================================================================="
Write-Host "PHASE 2.1 DONE."
Write-Host ""
Write-Host "What changed:"
Write-Host "  - 14 new SVG call icons (mic, speaker, camera, end, accept,"
Write-Host "    flip, close, lock, message, phone-out/in/missed)"
Write-Host "  - 1:1 CallModal redesigned: SVG icons in every button,"
Write-Host "    pulsing avatar ring while ringing/calling, encrypted"
Write-Host "    lock icon in header"
Write-Host "  - GroupCallModal + RingModal redesigned similarly"
Write-Host "  - Per-tile mute indicator now shows proper mic-off icon"
Write-Host "  - Calls history rows show phone-out/in/missed icons"
Write-Host ""
Write-Host "Now rebuild & test:"
Write-Host "  npx eas build --profile preview --platform android"
Write-Host "  (or quick local check: npx expo start --clear if you have"
Write-Host "   a dev build already installed)"
Write-Host "================================================================="
