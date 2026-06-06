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