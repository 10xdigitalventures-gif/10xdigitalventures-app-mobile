# =====================================================================
# Mobile App Phase 2: WebRTC calls + Android SafeArea (gesture bar fix)
#
# REQUIRES:
#   - EAS account (eas login done)
#   - Phase 1 already run (theme + screens + tabs)
#
# WHAT THIS PHASE DELIVERS:
#   1) Root <SafeAreaProvider> wrap so insets propagate everywhere
#   2) Android edge-to-edge + nav bar transparent (no overlap with gestures)
#   3) react-native-webrtc, expo-av, expo-camera, react-native-incall-manager
#      added to package.json
#   4) lib/calls.js -- WebRTC permissions helper
#   5) context/CallContext.js -- 1:1 calls (audio + video) WhatsApp UI
#   6) context/GroupCallContext.js -- mesh up to 8 peers, grid UI
#   7) app/(tabs)/_layout.js -- providers + tabBar paddingBottom from insets
#   8) app/chat/[channelId].js -- header phone/video buttons wire up to
#      1:1 call (DM) or group call (channels)
#   9) app/(tabs)/calls.js -- "Call again" tap on history works
#
# IMPORTANT: Because this adds native modules, you cannot use Expo Go.
# You must build a Dev Build or APK with EAS:
#
#   npx expo install react-native-webrtc react-native-incall-manager
#   npx expo install react-native-safe-area-context expo-camera expo-av
#   npx eas build --profile preview --platform android
#
# Run from MOBILE repo root:
#   powershell -ExecutionPolicy Bypass -File .\mobile-phase2-webrtc-safearea.ps1
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
Write-Host "Mobile App Phase 2 -- WebRTC + SafeArea"
Write-Host "==================================================="
Write-Host ""

# =====================================================================
# 1) Patch app.json: edge-to-edge, permissions, plugins
# =====================================================================
Write-Host "[1/9] Patching app.json (edge-to-edge + permissions + plugins)..."

$appJsonPath = "app.json"
$appJsonText = Read-FileUtf8 $appJsonPath
$appJson = $appJsonText | ConvertFrom-Json

# Ensure android section
if (-not $appJson.expo.android) {
    $appJson.expo | Add-Member -NotePropertyName android -NotePropertyValue ([pscustomobject]@{})
}
# edgeToEdgeEnabled (Expo SDK 53+)
$appJson.expo.android | Add-Member -NotePropertyName edgeToEdgeEnabled -NotePropertyValue $true -Force
$appJson.expo.android | Add-Member -NotePropertyName softwareKeyboardLayoutMode -NotePropertyValue "pan" -Force

# Permissions: add CAMERA, RECORD_AUDIO, MODIFY_AUDIO_SETTINGS, BLUETOOTH_CONNECT
$existingPerms = @($appJson.expo.android.permissions)
$wantPerms = @(
  "READ_EXTERNAL_STORAGE","WRITE_EXTERNAL_STORAGE","CAMERA","RECORD_AUDIO",
  "MODIFY_AUDIO_SETTINGS","BLUETOOTH_CONNECT","WAKE_LOCK",
  "RECEIVE_BOOT_COMPLETED","VIBRATE","FOREGROUND_SERVICE"
)
$mergedPerms = ($existingPerms + $wantPerms) | Where-Object { $_ } | Select-Object -Unique
$appJson.expo.android | Add-Member -NotePropertyName permissions -NotePropertyValue $mergedPerms -Force

# Plugins: add expo-camera + react-native-webrtc (if missing)
$pluginsList = @()
if ($appJson.expo.plugins) { $pluginsList = @($appJson.expo.plugins) }
function HasPlugin($name) {
    foreach ($p in $pluginsList) {
        if ($p -is [string] -and $p -eq $name) { return $true }
        if ($p -is [System.Collections.IEnumerable] -and -not ($p -is [string])) {
            $first = @($p)[0]
            if ($first -eq $name) { return $true }
        }
    }
    return $false
}
if (-not (HasPlugin "expo-camera")) {
    $pluginsList += ,@("expo-camera", ([pscustomobject]@{ cameraPermission = "Allow 10x Chat to access your camera for video calls" }))
}
if (-not (HasPlugin "@config-plugins/react-native-webrtc")) {
    $pluginsList += ,@("@config-plugins/react-native-webrtc", ([pscustomobject]@{
        cameraPermission = "Allow 10x Chat to access your camera for video calls"
        microphonePermission = "Allow 10x Chat to access your microphone for calls"
    }))
}
$appJson.expo | Add-Member -NotePropertyName plugins -NotePropertyValue $pluginsList -Force

# Write back
$out = $appJson | ConvertTo-Json -Depth 32
Write-FileUtf8NoBom -Path $appJsonPath -Content $out

# =====================================================================
# 2) Add deps to package.json (npx expo install will pin compatible versions)
# =====================================================================
Write-Host "[2/9] Adding deps to package.json..."

$pkgPath = "package.json"
$pkgText = Read-FileUtf8 $pkgPath
$pkg = $pkgText | ConvertFrom-Json

# Use floating versions so `npx expo install` picks compatible ones later.
$newDeps = @{
    "react-native-webrtc" = "*"
    "react-native-incall-manager" = "*"
    "react-native-safe-area-context" = "*"
    "expo-camera" = "*"
    "expo-av" = "*"
    "@config-plugins/react-native-webrtc" = "*"
}
foreach ($k in $newDeps.Keys) {
    if (-not $pkg.dependencies.$k) {
        $pkg.dependencies | Add-Member -NotePropertyName $k -NotePropertyValue $newDeps[$k] -Force
    }
}
$pkgOut = $pkg | ConvertTo-Json -Depth 32
Write-FileUtf8NoBom -Path $pkgPath -Content $pkgOut

# =====================================================================
# 3) lib/permissions.js -- mic + camera permission helper
# =====================================================================
Write-Host "[3/9] Creating lib/permissions.js..."

$perms = @'
import { Platform, PermissionsAndroid } from 'react-native'

export async function requestCallPermissions(needVideo) {
  if (Platform.OS !== 'android') return true
  const list = [PermissionsAndroid.PERMISSIONS.RECORD_AUDIO]
  if (needVideo) list.push(PermissionsAndroid.PERMISSIONS.CAMERA)
  // Bluetooth connect is required on Android 12+ for audio routing
  if (PermissionsAndroid.PERMISSIONS.BLUETOOTH_CONNECT) {
    list.push(PermissionsAndroid.PERMISSIONS.BLUETOOTH_CONNECT)
  }
  try {
    const granted = await PermissionsAndroid.requestMultiple(list)
    return Object.values(granted).every(v => v === PermissionsAndroid.RESULTS.GRANTED)
  } catch (e) {
    console.warn('permission error', e)
    return false
  }
}
'@
Write-FileUtf8NoBom -Path "lib/permissions.js" -Content $perms

# =====================================================================
# 4) context/CallContext.js -- 1:1 calls (WhatsApp UI on mobile)
# =====================================================================
Write-Host "[4/9] Creating context/CallContext.js (1:1 WebRTC)..."

$callCtx = @'
import React, { createContext, useContext, useEffect, useRef, useState, useCallback } from 'react'
import { View, Text, TouchableOpacity, StyleSheet, Modal, Platform, Alert } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import {
  RTCPeerConnection, RTCSessionDescription, RTCIceCandidate,
  mediaDevices, RTCView,
} from 'react-native-webrtc'
import InCallManager from 'react-native-incall-manager'
import { getSocket } from '@/lib/socket'
import { requestCallPermissions } from '@/lib/permissions'
import useChatStore from '@/store/chatStore'
import { colors } from '@/lib/theme'
import { PhoneIcon, VideoIcon } from '@/components/icons'
import api from '@/lib/api'

const ICE = { iceServers: [{ urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'] }] }
const CallContext = createContext(null)
export const useCall = () => useContext(CallContext)

export function CallProvider({ children }) {
  const { user, channels } = useChatStore()
  const [state, setState] = useState('idle') // idle | calling | ringing | active | ended
  const [callType, setCallType] = useState('audio')
  const [peer, setPeer] = useState(null)
  const [muted, setMuted] = useState(false)
  const [camOff, setCamOff] = useState(false)
  const [speakerOn, setSpeakerOn] = useState(false)
  const [localStream, setLocalStream] = useState(null)
  const [remoteStream, setRemoteStream] = useState(null)
  const [endReason, setEndReason] = useState(null)
  const [duration, setDuration] = useState(0)

  const pcRef = useRef(null)
  const localStreamRef = useRef(null)
  const pendingOfferRef = useRef(null)
  const pendingIcesRef = useRef([])
  const peerRef = useRef(null)
  const callTypeRef = useRef('audio')
  const callerRef = useRef(false)
  const answeredRef = useRef(false)
  const declinedRef = useRef(false)
  const startTsRef = useRef(0)
  const loggedRef = useRef(false)
  const endTimerRef = useRef(null)

  useEffect(() => { peerRef.current = peer }, [peer])
  useEffect(() => { callTypeRef.current = callType }, [callType])

  // --- helpers ---
  const cleanup = useCallback(() => {
    try { pcRef.current?.close() } catch (e) {}
    pcRef.current = null
    if (localStreamRef.current) {
      localStreamRef.current.getTracks().forEach(t => t.stop())
      localStreamRef.current = null
    }
    setLocalStream(null); setRemoteStream(null)
    setMuted(false); setCamOff(false); setSpeakerOn(false)
    pendingOfferRef.current = null
    pendingIcesRef.current = []
    try { InCallManager.stop() } catch (e) {}
  }, [])

  const logCall = useCallback(() => {
    if (loggedRef.current || !peerRef.current) return null
    loggedRef.current = true
    const answered = answeredRef.current
    const dur = answered && startTsRef.current ? Math.round((Date.now() - startTsRef.current) / 1000) : 0
    const direction = callerRef.current ? 'out' : 'in'
    const status = answered ? 'answered' : (declinedRef.current ? 'declined' : (callerRef.current ? 'no_answer' : 'missed'))
    api.post('/calls', { peer_id: peerRef.current.id, peer_name: peerRef.current.name, type: callTypeRef.current, direction, status, duration: dur }).catch(() => {})
    return { duration: dur, status }
  }, [])

  const finish = useCallback(() => {
    const info = logCall()
    cleanup()
    let reason = 'completed'
    if (info) {
      if (info.status === 'declined') reason = 'declined'
      else if (info.status === 'no_answer') reason = 'no_answer'
      else if (info.status === 'missed') reason = 'missed'
    }
    setEndReason(reason); setDuration(info?.duration || 0); setState('ended')
    if (endTimerRef.current) clearTimeout(endTimerRef.current)
    endTimerRef.current = setTimeout(() => { setState('idle'); setPeer(null); setEndReason(null) }, 15000)
  }, [logCall, cleanup])

  const dismissEnded = useCallback(() => {
    if (endTimerRef.current) { clearTimeout(endTimerRef.current); endTimerRef.current = null }
    setState('idle'); setPeer(null); setEndReason(null)
  }, [])

  const endCall = useCallback(async (notify = true) => {
    if (notify && peerRef.current?.id) {
      const s = await getSocket(); s.emit('call:end', { to: peerRef.current.id })
    }
    finish()
  }, [finish])

  const getMedia = useCallback(async (type) => {
    const opts = type === 'video'
      ? { audio: true, video: { facingMode: 'user' } }
      : { audio: true, video: false }
    const stream = await mediaDevices.getUserMedia(opts)
    localStreamRef.current = stream
    setLocalStream(stream)
    return stream
  }, [])

  const createPeer = useCallback(async (targetId) => {
    const pc = new RTCPeerConnection(ICE)
    const sock = await getSocket()
    pc.addEventListener('icecandidate', (e) => {
      if (e.candidate) sock.emit('call:ice', { to: targetId, candidate: e.candidate })
    })
    pc.addEventListener('track', (e) => {
      if (e.streams && e.streams[0]) setRemoteStream(e.streams[0])
    })
    pc.addEventListener('connectionstatechange', () => {
      if (['failed','closed','disconnected'].includes(pc.connectionState)) finish()
    })
    pcRef.current = pc
    return pc
  }, [finish])

  const startCall = useCallback(async (targetId, targetName, type = 'audio') => {
    if (!targetId || state !== 'idle') return
    const ok = await requestCallPermissions(type === 'video')
    if (!ok) { Alert.alert('Permission denied', 'Microphone is required for calls'); return }
    callerRef.current = true; answeredRef.current = false; declinedRef.current = false; loggedRef.current = false; startTsRef.current = 0
    setPeer({ id: targetId, name: targetName }); setCallType(type); setState('calling')
    try {
      InCallManager.start({ media: type === 'video' ? 'video' : 'audio' })
      InCallManager.setKeepScreenOn(true)
      if (type !== 'video') InCallManager.setForceSpeakerphoneOn(false)
      const stream = await getMedia(type)
      const pc = await createPeer(targetId)
      stream.getTracks().forEach(t => pc.addTrack(t, stream))
      const offer = await pc.createOffer(); await pc.setLocalDescription(offer)
      const sock = await getSocket()
      sock.emit('call:offer', { to: targetId, fromName: user?.name, type, sdp: offer })
    } catch (e) {
      console.warn('startCall error', e); Alert.alert('Call failed', e?.message || 'Could not start call')
      endCall(false)
    }
  }, [state, user, getMedia, createPeer, endCall])

  const acceptCall = useCallback(async () => {
    const offer = pendingOfferRef.current
    if (!offer || !peer?.id) return
    const ok = await requestCallPermissions(callType === 'video')
    if (!ok) { Alert.alert('Permission denied'); finish(); return }
    answeredRef.current = true; startTsRef.current = Date.now(); setState('active')
    try {
      InCallManager.start({ media: callType === 'video' ? 'video' : 'audio' })
      InCallManager.setKeepScreenOn(true)
      const stream = await getMedia(callType)
      const pc = await createPeer(peer.id)
      stream.getTracks().forEach(t => pc.addTrack(t, stream))
      await pc.setRemoteDescription(new RTCSessionDescription(offer))
      for (const c of pendingIcesRef.current) { try { await pc.addIceCandidate(new RTCIceCandidate(c)) } catch (e) {} }
      pendingIcesRef.current = []
      const answer = await pc.createAnswer(); await pc.setLocalDescription(answer)
      const sock = await getSocket()
      sock.emit('call:answer', { to: peer.id, sdp: answer })
    } catch (e) {
      console.warn('acceptCall error', e); endCall()
    }
  }, [peer, callType, getMedia, createPeer, endCall, finish])

  const rejectCall = useCallback(async () => {
    declinedRef.current = true
    if (peer?.id) { const s = await getSocket(); s.emit('call:reject', { to: peer.id }) }
    finish()
  }, [peer, finish])

  const toggleMute = () => {
    const s = localStreamRef.current; if (!s) return
    s.getAudioTracks().forEach(t => { t.enabled = !t.enabled })
    setMuted(m => !m)
  }
  const toggleCam = () => {
    const s = localStreamRef.current; if (!s) return
    const tr = s.getVideoTracks(); if (!tr.length) return
    tr.forEach(t => { t.enabled = !t.enabled })
    setCamOff(c => !c)
  }
  const toggleSpeaker = () => {
    const next = !speakerOn
    try { InCallManager.setForceSpeakerphoneOn(next) } catch (e) {}
    setSpeakerOn(next)
  }
  const switchCamera = () => {
    const s = localStreamRef.current; if (!s) return
    const vt = s.getVideoTracks()[0]; if (vt && typeof vt._switchCamera === 'function') vt._switchCamera()
  }

  // ---- Socket wiring ----
  useEffect(() => {
    let sockRef = null
    let mounted = true
    const onOffer = ({ from, fromName, type, sdp }) => {
      if (!mounted) return
      if (pcRef.current || (state !== 'idle' && state !== 'ended')) {
        sockRef?.emit('call:reject', { to: from }); return
      }
      callerRef.current = false; answeredRef.current = false; declinedRef.current = false; loggedRef.current = false; startTsRef.current = 0
      pendingOfferRef.current = sdp
      setPeer({ id: from, name: fromName || 'Unknown' }); setCallType(type || 'audio'); setState('ringing')
      try { InCallManager.startRingtone('_BUNDLE_') } catch (e) {}
    }
    const onAnswer = async ({ sdp }) => {
      try { await pcRef.current?.setRemoteDescription(new RTCSessionDescription(sdp)); answeredRef.current = true; startTsRef.current = Date.now(); setState('active') } catch (e) {}
    }
    const onIce = async ({ candidate }) => {
      if (!candidate) return
      if (pcRef.current?.remoteDescription) {
        try { await pcRef.current.addIceCandidate(new RTCIceCandidate(candidate)) } catch (e) {}
      } else { pendingIcesRef.current.push(candidate) }
    }
    const onRejectOrEnd = () => { try { InCallManager.stopRingtone() } catch (e) {}; finish() }

    getSocket().then(s => {
      if (!mounted) return
      sockRef = s
      s.on('call:offer', onOffer); s.on('call:answer', onAnswer); s.on('call:ice', onIce)
      s.on('call:reject', onRejectOrEnd); s.on('call:end', onRejectOrEnd)
    })
    return () => {
      mounted = false
      if (sockRef) {
        sockRef.off('call:offer', onOffer); sockRef.off('call:answer', onAnswer); sockRef.off('call:ice', onIce)
        sockRef.off('call:reject', onRejectOrEnd); sockRef.off('call:end', onRejectOrEnd)
      }
      try { InCallManager.stopRingtone() } catch (e) {}
    }
  }, [state, finish])

  // Stop ringtone when state leaves 'ringing'
  useEffect(() => {
    if (state !== 'ringing') { try { InCallManager.stopRingtone() } catch (e) {} }
  }, [state])

  // ---- For openChat from ended screen ----
  const findDMChannelWith = useCallback((peerId) => {
    if (!peerId || !channels) return null
    const dm = channels.find(c => c.type === 'dm' && (c.peer_id === peerId || c.peer === peerId))
    return dm ? dm.id : null
  }, [channels])

  return (
    <CallContext.Provider value={{
      state, callType, peer, muted, camOff, speakerOn, localStream, remoteStream, endReason, duration,
      startCall, acceptCall, rejectCall, endCall, toggleMute, toggleCam, toggleSpeaker, switchCamera,
      dismissEnded, findDMChannelWith,
    }}>
      {children}
      <CallModal />
    </CallContext.Provider>
  )
}

// ============================================================
// WhatsApp-style modal (mobile)
// ============================================================
function CtrlBtn({ title, variant, onPress, children }) {
  const variants = {
    mute:     { bg: 'rgba(255,255,255,0.1)', icon: '#fff' },
    muted:    { bg: '#fff', icon: '#0b141a' },
    speaker:  { bg: 'rgba(255,255,255,0.1)', icon: '#fff' },
    speakerOn:{ bg: '#fff', icon: '#0b141a' },
    cam:      { bg: 'rgba(255,255,255,0.1)', icon: '#fff' },
    camOff:   { bg: '#fff', icon: '#0b141a' },
    flip:     { bg: 'rgba(255,255,255,0.1)', icon: '#fff' },
    accept:   { bg: '#1db791', icon: '#fff' },
    end:      { bg: '#f15c6d', icon: '#fff' },
    decline:  { bg: '#f15c6d', icon: '#fff' },
  }
  const v = variants[variant] || variants.mute
  return (
    <TouchableOpacity onPress={onPress} style={callStyles.ctrlWrap} activeOpacity={0.7}>
      <View style={[callStyles.ctrlBtn, { backgroundColor: v.bg }]}>{children(v.icon)}</View>
      <Text style={callStyles.ctrlLabel}>{title}</Text>
    </TouchableOpacity>
  )
}

function getInitials(name) {
  if (!name) return '?'
  return name.split(/\s+/).slice(0,2).map(p => p[0]).join('').toUpperCase()
}

function fmtDur(s) {
  if (!s) return ''
  const m = Math.floor(s/60), sec = s%60
  return m + ':' + String(sec).padStart(2,'0')
}

function CallModal() {
  const c = useCall()
  if (!c || c.state === 'idle') return null
  const { state, callType, peer, muted, camOff, speakerOn, localStream, remoteStream,
          endReason, duration,
          acceptCall, rejectCall, endCall, toggleMute, toggleCam, toggleSpeaker, switchCamera,
          dismissEnded } = c

  const isVideo = callType === 'video'
  const showStage = state === 'active' && isVideo && remoteStream

  // ---- Ended screen ----
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
              <Text style={callStyles.headerText}>End-to-end encrypted</Text>
              <TouchableOpacity onPress={dismissEnded}><Text style={callStyles.headerClose}>X</Text></TouchableOpacity>
            </View>
            <View style={callStyles.bigSection}>
              <View style={callStyles.bigAvatar}><Text style={callStyles.bigInitials}>{getInitials(peer?.name)}</Text></View>
              <Text style={callStyles.bigName}>{peer?.name || 'Unknown'}</Text>
              <Text style={callStyles.status}>{label}</Text>
            </View>
            <View style={callStyles.controlsRow}>
              <CtrlBtn title="Close" variant="end" onPress={dismissEnded}>
                {(c) => <Text style={{ color: c, fontSize: 22, fontWeight: '700' }}>X</Text>}
              </CtrlBtn>
            </View>
          </View>
        </SafeAreaView>
      </Modal>
    )
  }

  // ---- Active / ringing / calling screen ----
  const statusText = state === 'calling' ? 'Calling...'
                   : state === 'ringing' ? ('Incoming ' + (isVideo ? 'video' : 'voice') + ' call')
                   : 'Connected'

  return (
    <Modal visible animationType="fade" transparent>
      <SafeAreaView style={callStyles.backdrop}>
        <View style={callStyles.card}>
          <View style={callStyles.headerBar}>
            <Text style={callStyles.headerText}>End-to-end encrypted</Text>
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
              <View style={callStyles.bigAvatar}><Text style={callStyles.bigInitials}>{getInitials(peer?.name)}</Text></View>
              <Text style={callStyles.bigName}>{peer?.name || 'Unknown'}</Text>
              <Text style={callStyles.status}>{statusText}</Text>
            </View>
          )}

          <View style={callStyles.controlsRow}>
            {state === 'ringing' ? (
              <>
                <CtrlBtn title="Decline" variant="decline" onPress={rejectCall}>
                  {(c) => <Text style={{ color: c, fontSize: 24 }}>X</Text>}
                </CtrlBtn>
                <CtrlBtn title="Accept" variant="accept" onPress={acceptCall}>
                  {(c) => <Text style={{ color: c, fontSize: 22 }}>OK</Text>}
                </CtrlBtn>
              </>
            ) : (
              <>
                <CtrlBtn title={muted ? 'Unmute' : 'Mute'} variant={muted ? 'muted' : 'mute'} onPress={toggleMute}>
                  {(c) => <Text style={{ color: c, fontSize: 14, fontWeight: '700' }}>{muted ? 'OFF' : 'MIC'}</Text>}
                </CtrlBtn>
                {!isVideo && (
                  <CtrlBtn title="Speaker" variant={speakerOn ? 'speakerOn' : 'speaker'} onPress={toggleSpeaker}>
                    {(c) => <Text style={{ color: c, fontSize: 14, fontWeight: '700' }}>SPK</Text>}
                  </CtrlBtn>
                )}
                {isVideo && (
                  <CtrlBtn title={camOff ? 'Camera on' : 'Camera off'} variant={camOff ? 'camOff' : 'cam'} onPress={toggleCam}>
                    {(c) => <Text style={{ color: c, fontSize: 14, fontWeight: '700' }}>CAM</Text>}
                  </CtrlBtn>
                )}
                {isVideo && (
                  <CtrlBtn title="Flip" variant="flip" onPress={switchCamera}>
                    {(c) => <Text style={{ color: c, fontSize: 14, fontWeight: '700' }}>FLP</Text>}
                  </CtrlBtn>
                )}
                <CtrlBtn title="End" variant="end" onPress={() => endCall(true)}>
                  {(c) => <Text style={{ color: c, fontSize: 22, fontWeight: '700' }}>X</Text>}
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
  headerClose: { color: 'rgba(255,255,255,0.7)', fontSize: 16, paddingHorizontal: 6 },

  bigSection: { alignItems: 'center', paddingVertical: 48, paddingHorizontal: 24, backgroundColor: '#0b141a' },
  bigAvatar: { width: 130, height: 130, borderRadius: 65, backgroundColor: '#1db791', alignItems: 'center', justifyContent: 'center', marginBottom: 22 },
  bigInitials: { color: '#06291f', fontSize: 42, fontWeight: '700' },
  bigName: { color: '#fff', fontSize: 22, fontWeight: '600', marginBottom: 6 },
  status: { color: 'rgba(255,255,255,0.55)', fontSize: 14 },

  videoStage: { width: '100%', aspectRatio: 9/14, maxHeight: 520, backgroundColor: '#000', position: 'relative' },
  remoteVideo: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 },
  localPip: { position: 'absolute', bottom: 12, right: 12, width: 100, height: 140, borderRadius: 10, overflow: 'hidden', borderWidth: 1, borderColor: 'rgba(255,255,255,0.3)', backgroundColor: '#000' },
  stageHeader: { position: 'absolute', top: 12, left: 14, right: 14 },
  bigNameOnVideo: { color: '#fff', fontSize: 16, fontWeight: '600' },
  statusOnVideo: { color: 'rgba(255,255,255,0.85)', fontSize: 12 },

  controlsRow: { flexDirection: 'row', justifyContent: 'center', alignItems: 'flex-start', gap: 16, paddingTop: 18, paddingBottom: 26, paddingHorizontal: 12, backgroundColor: '#0a1218', borderTopWidth: 0.5, borderTopColor: 'rgba(255,255,255,0.06)' },
  ctrlWrap: { alignItems: 'center', gap: 7 },
  ctrlBtn: { width: 58, height: 58, borderRadius: 29, alignItems: 'center', justifyContent: 'center' },
  ctrlLabel: { color: 'rgba(255,255,255,0.7)', fontSize: 11 },
})
'@
Write-FileUtf8NoBom -Path "context/CallContext.js" -Content $callCtx

# =====================================================================
# 5) context/GroupCallContext.js -- group mesh + grid
# =====================================================================
Write-Host "[5/9] Creating context/GroupCallContext.js (group mesh)..."

$groupCtx = @'
import React, { createContext, useContext, useEffect, useRef, useState, useCallback } from 'react'
import { View, Text, TouchableOpacity, StyleSheet, Modal, ScrollView, Alert } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { RTCPeerConnection, RTCSessionDescription, RTCIceCandidate, mediaDevices, RTCView } from 'react-native-webrtc'
import InCallManager from 'react-native-incall-manager'
import { getSocket } from '@/lib/socket'
import { requestCallPermissions } from '@/lib/permissions'
import useChatStore from '@/store/chatStore'

const ICE = { iceServers: [{ urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'] }] }
const MAX_PEERS = 8

const GCtx = createContext(null)
export const useGroupCall = () => useContext(GCtx)

function getInitials(name) {
  if (!name) return '?'
  return name.split(/\s+/).slice(0,2).map(p => p[0]).join('').toUpperCase()
}

export function GroupCallProvider({ children }) {
  const { user, channels } = useChatStore()
  const [state, setState] = useState('idle')
  const [channelId, setChannelId] = useState(null)
  const [callType, setCallType] = useState('audio')
  const [incoming, setIncoming] = useState(null)
  const [peers, setPeers] = useState([])
  const [muted, setMuted] = useState(false)
  const [camOff, setCamOff] = useState(false)
  const [speakerOn, setSpeakerOn] = useState(false)
  const [localStream, setLocalStream] = useState(null)

  const localRef = useRef(null)
  const peersRef = useRef(new Map())
  const channelIdRef = useRef(null)
  const callTypeRef = useRef('audio')

  useEffect(() => { channelIdRef.current = channelId }, [channelId])
  useEffect(() => { callTypeRef.current = callType }, [callType])

  const upsertPeer = useCallback((uid, patch) => {
    setPeers(prev => {
      const i = prev.findIndex(p => p.user_id === uid)
      if (i === -1) return [...prev, { user_id: uid, name: 'User', stream: null, muted: false, camOff: false, ...patch }]
      const copy = [...prev]; copy[i] = { ...copy[i], ...patch }; return copy
    })
  }, [])
  const removePeer = useCallback((uid) => {
    setPeers(prev => prev.filter(p => p.user_id !== uid))
    const e = peersRef.current.get(uid)
    if (e) { try { e.pc.close() } catch {} ; peersRef.current.delete(uid) }
  }, [])

  const getMedia = useCallback(async (type) => {
    const opts = type === 'video' ? { audio: true, video: { facingMode: 'user' } } : { audio: true, video: false }
    const stream = await mediaDevices.getUserMedia(opts)
    localRef.current = stream; setLocalStream(stream)
    return stream
  }, [])

  const makePeer = useCallback(async (uid, name) => {
    const pc = new RTCPeerConnection(ICE)
    const sock = await getSocket()
    const cid = channelIdRef.current
    const local = localRef.current
    if (local) local.getTracks().forEach(t => pc.addTrack(t, local))
    pc.addEventListener('icecandidate', (e) => {
      if (e.candidate) sock.emit('gcall:ice', { channel_id: cid, to: uid, candidate: e.candidate })
    })
    pc.addEventListener('track', (e) => {
      const stream = e.streams[0]
      upsertPeer(uid, { stream, name })
    })
    pc.addEventListener('connectionstatechange', () => {
      if (['failed','closed'].includes(pc.connectionState)) removePeer(uid)
    })
    peersRef.current.set(uid, { pc })
    upsertPeer(uid, { name })
    return pc
  }, [upsertPeer, removePeer])

  const cleanup = useCallback(() => {
    peersRef.current.forEach(e => { try { e.pc.close() } catch {} })
    peersRef.current.clear()
    if (localRef.current) { localRef.current.getTracks().forEach(t => t.stop()); localRef.current = null }
    setLocalStream(null); setPeers([])
    setMuted(false); setCamOff(false); setSpeakerOn(false)
    try { InCallManager.stop() } catch {}
  }, [])

  const leaveCall = useCallback(async () => {
    const sock = await getSocket()
    if (channelIdRef.current) sock.emit('gcall:leave', { channel_id: channelIdRef.current })
    cleanup(); setState('idle'); setChannelId(null); setIncoming(null)
  }, [cleanup])

  const startCall = useCallback(async (cid, type = 'audio') => {
    if (!cid || state !== 'idle') return
    const ok = await requestCallPermissions(type === 'video')
    if (!ok) { Alert.alert('Permission denied'); return }
    setChannelId(cid); setCallType(type); setState('active')
    try {
      InCallManager.start({ media: type === 'video' ? 'video' : 'audio' })
      InCallManager.setKeepScreenOn(true)
      await getMedia(type)
      const sock = await getSocket()
      sock.emit('gcall:join', { channel_id: cid, name: user?.name || 'User', type })
    } catch (e) { console.warn(e); leaveCall() }
  }, [state, user, getMedia, leaveCall])

  const acceptIncoming = useCallback(async () => {
    if (!incoming) return
    const cid = incoming.channel_id; const type = incoming.type
    const ok = await requestCallPermissions(type === 'video')
    if (!ok) { Alert.alert('Permission denied'); setIncoming(null); return }
    try { InCallManager.stopRingtone() } catch {}
    setIncoming(null); setChannelId(cid); setCallType(type); setState('active')
    try {
      InCallManager.start({ media: type === 'video' ? 'video' : 'audio' })
      InCallManager.setKeepScreenOn(true)
      await getMedia(type)
      const sock = await getSocket()
      sock.emit('gcall:join', { channel_id: cid, name: user?.name || 'User', type })
    } catch (e) { console.warn(e); leaveCall() }
  }, [incoming, user, getMedia, leaveCall])

  const declineIncoming = () => { try { InCallManager.stopRingtone() } catch {} ; setIncoming(null) }

  const toggleMute = () => { const s = localRef.current; if (!s) return; s.getAudioTracks().forEach(t => t.enabled = !t.enabled); setMuted(m => !m) }
  const toggleCam = () => { const s = localRef.current; if (!s) return; const tr = s.getVideoTracks(); if (!tr.length) return; tr.forEach(t => t.enabled = !t.enabled); setCamOff(c => !c) }
  const toggleSpeaker = () => { const n = !speakerOn; try { InCallManager.setForceSpeakerphoneOn(n) } catch {} ; setSpeakerOn(n) }

  // Socket wiring
  useEffect(() => {
    let sockRef = null
    let mounted = true
    const onRing = ({ channel_id, from, fromName, type }) => {
      if (!mounted) return
      if (state === 'active' && channelIdRef.current === channel_id) return
      if (from === user?.id) return
      setIncoming({ channel_id, from, fromName, type })
      try { InCallManager.startRingtone('_BUNDLE_') } catch {}
    }
    const onPeers = async ({ channel_id, peers: list }) => {
      if (channel_id !== channelIdRef.current) return
      for (const p of list.slice(0, MAX_PEERS)) {
        if (peersRef.current.has(p.user_id)) continue
        const pc = await makePeer(p.user_id, p.name)
        try {
          const offer = await pc.createOffer(); await pc.setLocalDescription(offer)
          sockRef?.emit('gcall:offer', { channel_id, to: p.user_id, sdp: offer })
        } catch (e) {}
      }
    }
    const onJoined = ({ channel_id, user_id, name }) => { if (channel_id === channelIdRef.current) upsertPeer(user_id, { name }) }
    const onLeft   = ({ channel_id, user_id })       => { if (channel_id === channelIdRef.current) removePeer(user_id) }
    const onOffer  = async ({ channel_id, from, sdp }) => {
      if (channel_id !== channelIdRef.current) return
      let entry = peersRef.current.get(from); let pc = entry?.pc
      if (!pc) pc = await makePeer(from, 'User')
      try {
        await pc.setRemoteDescription(new RTCSessionDescription(sdp))
        const ans = await pc.createAnswer(); await pc.setLocalDescription(ans)
        sockRef?.emit('gcall:answer', { channel_id, to: from, sdp: ans })
      } catch {}
    }
    const onAnswer = async ({ channel_id, from, sdp }) => {
      if (channel_id !== channelIdRef.current) return
      const entry = peersRef.current.get(from); if (!entry) return
      try { await entry.pc.setRemoteDescription(new RTCSessionDescription(sdp)) } catch {}
    }
    const onIce = async ({ channel_id, from, candidate }) => {
      if (channel_id !== channelIdRef.current) return
      const entry = peersRef.current.get(from); if (!entry || !candidate) return
      try { await entry.pc.addIceCandidate(new RTCIceCandidate(candidate)) } catch {}
    }
    const onState = ({ channel_id, user_id, muted: m, camOff: c }) => {
      if (channel_id === channelIdRef.current) upsertPeer(user_id, { muted: !!m, camOff: !!c })
    }

    getSocket().then(s => {
      if (!mounted) return
      sockRef = s
      s.on('gcall:ring', onRing); s.on('gcall:peers', onPeers)
      s.on('gcall:joined', onJoined); s.on('gcall:left', onLeft)
      s.on('gcall:offer', onOffer); s.on('gcall:answer', onAnswer); s.on('gcall:ice', onIce)
      s.on('gcall:state', onState)
    })
    return () => {
      mounted = false
      if (sockRef) {
        sockRef.off('gcall:ring', onRing); sockRef.off('gcall:peers', onPeers)
        sockRef.off('gcall:joined', onJoined); sockRef.off('gcall:left', onLeft)
        sockRef.off('gcall:offer', onOffer); sockRef.off('gcall:answer', onAnswer); sockRef.off('gcall:ice', onIce)
        sockRef.off('gcall:state', onState)
      }
      try { InCallManager.stopRingtone() } catch {}
    }
  }, [state, user, makePeer, upsertPeer, removePeer])

  const channelName = channels?.find(c => c.id === channelId)?.name || 'Group call'

  return (
    <GCtx.Provider value={{ state, channelId, callType, peers, muted, camOff, speakerOn, localStream, channelName, incoming,
                            startCall, leaveCall, toggleMute, toggleCam, toggleSpeaker, acceptIncoming, declineIncoming }}>
      {children}
      <RingModal />
      <ActiveModal />
    </GCtx.Provider>
  )
}

function RingModal() {
  const g = useGroupCall(); if (!g || !g.incoming) return null
  const { incoming, acceptIncoming, declineIncoming } = g
  return (
    <Modal visible transparent animationType="fade">
      <SafeAreaView style={s.backdrop}>
        <View style={s.card}>
          <View style={s.headerBar}>
            <Text style={s.headerText}>End-to-end encrypted</Text>
            <Text style={s.headerType}>{incoming.type === 'video' ? 'Group video' : 'Group voice'}</Text>
          </View>
          <View style={s.bigSection}>
            <View style={s.bigAvatar}><Text style={s.bigInitials}>{getInitials(incoming.fromName)}</Text></View>
            <Text style={s.bigName}>Group call</Text>
            <Text style={s.status}>{incoming.fromName} is calling...</Text>
          </View>
          <View style={s.controlsRow}>
            <TouchableOpacity onPress={declineIncoming} style={[s.ctrlBtn, { backgroundColor: '#f15c6d' }]}>
              <Text style={{ color: '#fff', fontWeight: '700' }}>NO</Text>
            </TouchableOpacity>
            <TouchableOpacity onPress={acceptIncoming} style={[s.ctrlBtn, { backgroundColor: '#1db791' }]}>
              <Text style={{ color: '#fff', fontWeight: '700' }}>OK</Text>
            </TouchableOpacity>
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
      {peer.muted && <View style={s.muteBadge}><Text style={{ color: '#f87171', fontSize: 10 }}>MUTED</Text></View>}
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
          <Text style={s.headerText}>End-to-end encrypted</Text>
          <View>
            <Text style={{ color: '#fff', fontWeight: '600' }} numberOfLines={1}>{channelName}</Text>
            <Text style={{ color: 'rgba(255,255,255,0.4)', fontSize: 11 }}>{callType === 'video' ? 'Video' : 'Voice'} - {total} participant{total === 1 ? '' : 's'}</Text>
          </View>
        </View>
        <ScrollView contentContainerStyle={{ padding: 6 }} style={{ flex: 1, backgroundColor: '#000' }}>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
            {/* self */}
            <View style={[s.tileWrap, { width: (100 / cols) + '%' }]}>
              <View style={s.tile}>
                {localStream && !camOff
                  ? <RTCView streamURL={localStream.toURL()} style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }} objectFit="cover" mirror />
                  : <View style={s.tileAvatar}><Text style={s.tileInitials}>You</Text></View>}
                <View style={s.tileLabel}><Text style={{ color: '#fff', fontSize: 12 }}>You</Text></View>
                {muted && <View style={s.muteBadge}><Text style={{ color: '#f87171', fontSize: 10 }}>MUTED</Text></View>}
              </View>
            </View>
            {peers.map(p => (
              <View key={p.user_id} style={[s.tileWrap, { width: (100 / cols) + '%' }]}><PeerTile peer={p} /></View>
            ))}
          </View>
          {peers.length === 0 && <Text style={{ color: 'rgba(255,255,255,0.5)', textAlign: 'center', marginTop: 30 }}>Waiting for others to join...</Text>}
        </ScrollView>
        <View style={s.controlsRow}>
          <TouchableOpacity onPress={toggleMute} style={[s.ctrlBtn, muted && { backgroundColor: '#fff' }]}><Text style={{ color: muted ? '#0b141a' : '#fff', fontWeight: '700' }}>{muted ? 'OFF' : 'MIC'}</Text></TouchableOpacity>
          {callType !== 'video' && (
            <TouchableOpacity onPress={toggleSpeaker} style={[s.ctrlBtn, speakerOn && { backgroundColor: '#fff' }]}><Text style={{ color: speakerOn ? '#0b141a' : '#fff', fontWeight: '700' }}>SPK</Text></TouchableOpacity>
          )}
          {callType === 'video' && (
            <TouchableOpacity onPress={toggleCam} style={[s.ctrlBtn, camOff && { backgroundColor: '#fff' }]}><Text style={{ color: camOff ? '#0b141a' : '#fff', fontWeight: '700' }}>CAM</Text></TouchableOpacity>
          )}
          <TouchableOpacity onPress={leaveCall} style={[s.ctrlBtn, { backgroundColor: '#f15c6d' }]}><Text style={{ color: '#fff', fontWeight: '700' }}>END</Text></TouchableOpacity>
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
  bigSection: { alignItems: 'center', paddingVertical: 48 },
  bigAvatar: { width: 130, height: 130, borderRadius: 65, backgroundColor: '#1db791', alignItems: 'center', justifyContent: 'center', marginBottom: 22 },
  bigInitials: { color: '#06291f', fontSize: 42, fontWeight: '700' },
  bigName: { color: '#fff', fontSize: 22, fontWeight: '600', marginBottom: 6 },
  status: { color: 'rgba(255,255,255,0.55)', fontSize: 14 },
  controlsRow: { flexDirection: 'row', justifyContent: 'center', gap: 14, paddingVertical: 16, backgroundColor: '#0a1218', borderTopWidth: 0.5, borderTopColor: 'rgba(255,255,255,0.06)' },
  ctrlBtn: { width: 58, height: 58, borderRadius: 29, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(255,255,255,0.1)' },

  tileWrap: { padding: 3 },
  tile: { aspectRatio: 1, backgroundColor: '#0a1218', borderRadius: 10, overflow: 'hidden', borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)', justifyContent: 'center', alignItems: 'center' },
  tileAvatar: { width: 64, height: 64, borderRadius: 32, backgroundColor: '#1db791', alignItems: 'center', justifyContent: 'center' },
  tileInitials: { color: '#06291f', fontSize: 20, fontWeight: '700' },
  tileLabel: { position: 'absolute', bottom: 6, left: 6, backgroundColor: 'rgba(0,0,0,0.5)', paddingHorizontal: 6, paddingVertical: 2, borderRadius: 4 },
  muteBadge: { position: 'absolute', top: 6, right: 6, backgroundColor: 'rgba(0,0,0,0.5)', paddingHorizontal: 6, paddingVertical: 2, borderRadius: 4 },
})
'@
Write-FileUtf8NoBom -Path "context/GroupCallContext.js" -Content $groupCtx

# =====================================================================
# 6) app/_layout.js -- wrap with SafeAreaProvider + Call providers
# =====================================================================
Write-Host "[6/9] Rewriting app/_layout.js (SafeAreaProvider + Call providers)..."

$rootLayout = @'
import { useEffect } from 'react'
import { Stack } from 'expo-router'
import { StatusBar } from 'expo-status-bar'
import { GestureHandlerRootView } from 'react-native-gesture-handler'
import { SafeAreaProvider } from 'react-native-safe-area-context'
import { registerForPushNotifications } from '@/lib/notifications'
import { CallProvider } from '@/context/CallContext'
import { GroupCallProvider } from '@/context/GroupCallContext'

export default function RootLayout() {
  useEffect(() => {
    registerForPushNotifications()
  }, [])

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <CallProvider>
          <GroupCallProvider>
            <StatusBar style="light" />
            <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: '#0b141a' } }}>
              <Stack.Screen name="(auth)" />
              <Stack.Screen name="(tabs)" />
            </Stack>
          </GroupCallProvider>
        </CallProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  )
}
'@
Write-FileUtf8NoBom -Path "app/_layout.js" -Content $rootLayout

# =====================================================================
# 7) app/(tabs)/_layout.js -- tabBar padding from safe-area insets
#    (prevents overlap with Android gesture/nav bar)
# =====================================================================
Write-Host "[7/9] Patching app/(tabs)/_layout.js (tab bar + insets)..."

$tabsLay = Read-FileUtf8 "app/(tabs)/_layout.js"

# Inject useSafeAreaInsets import + computed padding if not already there
if ($tabsLay -notmatch "useSafeAreaInsets") {
    $tabsLay = $tabsLay.Replace(
        "import { Tabs } from 'expo-router'",
        "import { Tabs } from 'expo-router'`r`nimport { useSafeAreaInsets } from 'react-native-safe-area-context'"
    )
    # Inject `const insets = useSafeAreaInsets()` inside TabsLayout
    $tabsLay = $tabsLay.Replace(
        "export default function TabsLayout() {",
        "export default function TabsLayout() {`r`n  const insets = useSafeAreaInsets()"
    )
    # Replace static tabBarStyle paddingBottom with dynamic insets-based one
    $tabsLay = $tabsLay -replace `
        "tabBarStyle:\s*\{[^}]*\}", `
        "tabBarStyle: { backgroundColor: colors.bgSurface, borderTopColor: colors.bgDivider, borderTopWidth: 0.5, height: 60 + insets.bottom, paddingTop: 6, paddingBottom: Math.max(insets.bottom, 8) }"
}

Write-FileUtf8NoBom -Path "app/(tabs)/_layout.js" -Content $tabsLay

# =====================================================================
# 8) app/chat/[channelId].js -- wire header phone/video to call providers
# =====================================================================
Write-Host "[8/9] Wiring header call buttons in chat screen..."

$chatPath = "app/chat/[channelId].js"
$chat = Read-FileUtf8 $chatPath

# Add useCall + useGroupCall imports if missing
if ($chat -notmatch "useCall") {
    $chat = $chat.Replace(
        "import { colors, radius } from '@/lib/theme'",
        "import { colors, radius } from '@/lib/theme'`r`nimport { useCall } from '@/context/CallContext'`r`nimport { useGroupCall } from '@/context/GroupCallContext'"
    )
}

# Add hooks inside ChatScreen body (after channel/data setup, before return)
# Find the line `const channel = channels.find...` and inject right after the existing useEffect blocks
if ($chat -notmatch "const call = useCall") {
    $chat = $chat.Replace(
        "const subtitle = typingInChannel.length > 0",
        "const call = useCall()`r`n  const groupCall = useGroupCall()`r`n  const isDM = channel?.type === 'dm'`r`n  const dmPeer = isDM ? null : null  // computed below; mobile DM peer best-effort`r`n`r`n  const handleCall = (type) => {`r`n    if (channel?.type === 'dm') {`r`n      // For DM, use channel.dm_user_id (provided by API) as peer id`r`n      const peerId = channel.dm_user_id || channel.peer_id`r`n      if (!peerId) { Alert.alert('Cannot call', 'Peer id not available'); return }`r`n      call?.startCall(peerId, channel.name, type)`r`n    } else {`r`n      groupCall?.startCall(channelId, type)`r`n    }`r`n  }`r`n`r`n  const subtitle = typingInChannel.length > 0"
    )
}

# Replace the placeholder Alert handlers on phone/video icons with handleCall
$chat = $chat.Replace(
    "onPress={() => Alert.alert('Coming soon', 'Voice calls arrive in Phase 2')}",
    "onPress={() => handleCall('audio')}"
)
$chat = $chat.Replace(
    "onPress={() => Alert.alert('Coming soon', 'Video calls arrive in Phase 2')}",
    "onPress={() => handleCall('video')}"
)

Write-FileUtf8NoBom -Path $chatPath -Content $chat

# =====================================================================
# 9) app/(tabs)/calls.js -- make "Call again" button work
# =====================================================================
Write-Host "[9/9] Wiring 'Call again' in calls history..."

$callsPath = "app/(tabs)/calls.js"
$calls = Read-FileUtf8 $callsPath

if ($calls -notmatch "useCall") {
    $calls = $calls.Replace(
        "import { PhoneIcon, VideoIcon } from '@/components/icons'",
        "import { PhoneIcon, VideoIcon } from '@/components/icons'`r`nimport { useCall } from '@/context/CallContext'"
    )
}

# Inject useCall + onPress on CallRow's callBtn
$oldRow = "function CallRow({ item }) {"
$newRow = "function CallRow({ item, onCall }) {"
$calls = $calls.Replace($oldRow, $newRow)

$oldBtn = "<TouchableOpacity style={styles.callBtn}>"
$newBtn = "<TouchableOpacity style={styles.callBtn} onPress={() => onCall && onCall(item)}>"
$calls = $calls.Replace($oldBtn, $newBtn)

# Pass onCall prop from FlatList renderItem
$oldRender = "renderItem={CallRow}"
$newRender = @"
renderItem={({ item }) => <CallRow item={item} onCall={(c) => call?.startCall(c.peer_id, c.peer_name, c.type)} />}
"@
$calls = $calls.Replace($oldRender, $newRender.Trim())

# Use useCall hook inside CallsScreen
$calls = $calls.Replace(
    "export default function CallsScreen() {",
    "export default function CallsScreen() {`r`n  const call = useCall()"
)

Write-FileUtf8NoBom -Path $callsPath -Content $calls

Write-Host ""
Write-Host "================================================================="
Write-Host "PHASE 2 DONE."
Write-Host ""
Write-Host "NEXT STEPS (install + build):"
Write-Host ""
Write-Host "  1) Install native deps (correct versions for your Expo SDK):"
Write-Host "     npx expo install react-native-webrtc"
Write-Host "     npx expo install react-native-incall-manager"
Write-Host "     npx expo install react-native-safe-area-context"
Write-Host "     npx expo install expo-camera expo-av"
Write-Host "     npm install --save-dev @config-plugins/react-native-webrtc"
Write-Host ""
Write-Host "  2) Build an APK with EAS (you said EAS is set up):"
Write-Host "     npx eas build --profile preview --platform android"
Write-Host ""
Write-Host "     If your eas.json does not have a 'preview' profile yet, add:"
Write-Host '       "preview": { "android": { "buildType": "apk" }, "distribution": "internal" }'
Write-Host ""
Write-Host "  3) Install the APK on your phone, log in, test:"
Write-Host "     - Open a DM chat -> tap phone icon -> ringing on other device"
Write-Host "     - Tap video icon -> camera preview + WhatsApp popup"
Write-Host "     - Open a group/channel -> tap phone/video -> group call grid"
Write-Host "     - Tabs no longer overlap with Android gesture bar"
Write-Host "     - Chat input visible above keyboard (KeyboardAvoidingView)"
Write-Host ""
Write-Host "TROUBLESHOOTING:"
Write-Host "  - 'webrtc native module not found' -> you are running Expo Go."
Write-Host "    WebRTC needs a Dev Build / APK from EAS."
Write-Host "  - Black remote video -> check both devices granted CAMERA perm."
Write-Host "  - No audio -> check device not in silent mode + InCallManager active"
Write-Host "================================================================="
