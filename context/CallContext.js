import React, { createContext, useContext, useEffect, useRef, useState, useCallback } from 'react'
import { View, Text, TouchableOpacity, StyleSheet, Modal, Platform, Alert, Animated, Easing } from 'react-native'
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
import {
  MicIcon, MicOffIcon, SpeakerIcon, SpeakerOffIcon,
  CameraOnIcon, CameraOffIcon, FlipCameraIcon,
  EndCallIcon, AcceptCallIcon, CloseIcon, LockIcon,
  MessageIcon, PhoneIcon, VideoIcon,
} from '@/components/icons'
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
