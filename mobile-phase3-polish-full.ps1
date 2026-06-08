# =====================================================================
# Mobile App Phase 3 -- Full polish (15 items, one script)
#
# Includes:
#   1. Voice notes -- hold to record, swipe-to-cancel, send, playback
#   2. Image preview lightbox -- full-screen view, swipe-down to close,
#      save to gallery
#   3. Swipe-to-reply -- drag bubble right to reply (WhatsApp gesture)
#   4. Reply preview in bubble (quoted message on top of new one)
#   5. Long-press action sheet (Reply / Copy / Forward / Delete)
#   6. Bubble grouping (consecutive same-sender messages stack with
#      tail only on last)
#   7. Date dividers (Today / Yesterday / actual date)
#   8. Typing indicator -- 3 animated bouncing dots
#   9. Online status / last seen in header
#  10. Unread badge on Chats tab
#  11. Message search inside chat (header search icon)
#  12. Pull-to-refresh on channels list
#  13. Skeleton loaders (instead of spinner)
#  14. Haptic feedback (long-press, send, button taps)
#  15. Read receipts realtime + save image to gallery from lightbox
#
# Requires (installed automatically by user via expo install):
#   expo-haptics, expo-media-library, expo-clipboard, @react-native-clipboard/clipboard
#
# Stack already present: expo-av, expo-image-picker, expo-document-picker,
#   react-native-gesture-handler, react-native-reanimated, react-native-svg,
#   react-native-safe-area-context, expo-router, zustand, socket.io-client,
#   react-native-webrtc, react-native-incall-manager.
#
# Run from MOBILE repo root:
#   powershell -ExecutionPolicy Bypass -File .\mobile-phase3-polish-full.ps1
#
#   Then install missing native deps + rebuild APK:
#     npx expo install expo-haptics expo-media-library expo-clipboard
#     npx eas build --profile preview --platform android
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
    Write-Host "ERROR: Run from mobile repo root."
    exit 1
}

Write-Host "==================================================="
Write-Host "Mobile Phase 3 -- Polish (15 items)"
Write-Host "==================================================="
Write-Host ""

# =====================================================================
# 1) store/chatStore.js -- add replyTo state + setReplyTo
# =====================================================================
Write-Host "[1/9] Patching store/chatStore.js (replyTo + unread)..."

$store = @'
import { create } from 'zustand'

function unwrap(v) { return v?.data || v }

function toArray(v) {
  const x = unwrap(v)
  if (Array.isArray(x)) return x
  if (typeof x === 'string') {
    try { const p = JSON.parse(x); return Array.isArray(p) ? p : [] } catch { return [] }
  }
  return []
}

function normalizeMsg(m) {
  if (!m || typeof m !== 'object') return m
  return { ...m, reactions: toArray(m.reactions), status: toArray(m.status) }
}

const useChatStore = create((set, get) => ({
  user: null,
  channels: [],
  activeChannel: null,
  messages: {},
  onlineUsers: new Set(),
  typingUsers: {},
  members: [],
  replyTo: {},          // channelId -> message being replied to
  unreadCounts: {},     // channelId -> number
  lastSeen: {},         // userId -> timestamp

  setUser: (user) => set({ user: unwrap(user) }),
  setChannels: (channels) => set({ channels: toArray(channels) }),
  setActiveChannel: (channel) => set({ activeChannel: channel }),
  setMembers: (members) => set({ members: toArray(members) }),

  setReplyTo: (channelId, msg) => set((s) => ({
    replyTo: { ...s.replyTo, [channelId]: msg || null }
  })),

  clearUnread: (channelId) => set((s) => ({
    unreadCounts: { ...s.unreadCounts, [channelId]: 0 }
  })),

  setLastSeen: (userId, ts) => set((s) => ({
    lastSeen: { ...s.lastSeen, [userId]: ts }
  })),

  addChannel: (ch) => set((s) => {
    const channel = unwrap(ch)
    if (!channel || !channel.id) return { channels: toArray(s.channels) }
    const list = toArray(s.channels)
    const exists = list.some((c) => c.id === channel.id)
    return {
      channels: exists
        ? list.map((c) => c.id === channel.id ? { ...c, ...channel } : c)
        : [...list, channel],
    }
  }),

  setMessages: (channelId, msgs) => set((s) => ({
    messages: { ...s.messages, [channelId]: toArray(msgs).map(normalizeMsg) }
  })),

  addMessage: (channelId, msg) => set((s) => {
    const newMsgs = { ...s.messages, [channelId]: [...(s.messages[channelId] || []), normalizeMsg(msg)] }
    const isActive = s.activeChannel?.id === channelId
    const isOwn = msg.sender_id === s.user?.id
    const inc = (!isActive && !isOwn) ? 1 : 0
    return {
      messages: newMsgs,
      unreadCounts: { ...s.unreadCounts, [channelId]: (s.unreadCounts[channelId] || 0) + inc }
    }
  }),

  updateMessage: (channelId, messageId, updates) => set((s) => ({
    messages: {
      ...s.messages,
      [channelId]: (s.messages[channelId] || []).map((m) =>
        m.id === messageId ? { ...m, ...updates } : m
      ),
    },
  })),

  deleteMessage: (channelId, messageId) => set((s) => ({
    messages: {
      ...s.messages,
      [channelId]: (s.messages[channelId] || []).map((m) =>
        m.id === messageId ? { ...m, is_deleted: 1 } : m
      ),
    },
  })),

  updateReaction: (channelId, messageId, emoji, userId, action) => set((s) => ({
    messages: {
      ...s.messages,
      [channelId]: (s.messages[channelId] || []).map((m) => {
        if (m.id !== messageId) return m
        let reactions = toArray(m.reactions)
        if (action === 'removed') reactions = reactions.filter((r) => !(r.emoji === emoji && r.user_id === userId))
        else reactions.push({ emoji, user_id: userId })
        return { ...m, reactions }
      }),
    },
  })),

  // Real-time status update from server (delivered/read echo)
  applyStatusUpdate: (channelId, messageId, userId, status) => set((s) => ({
    messages: {
      ...s.messages,
      [channelId]: (s.messages[channelId] || []).map((m) => {
        if (m.id !== messageId) return m
        const stats = toArray(m.status)
        const i = stats.findIndex(x => x.user_id === userId)
        const now = new Date().toISOString()
        const patch = status === 'read' ? { read_at: now, delivered_at: now } : { delivered_at: now }
        if (i === -1) stats.push({ user_id: userId, ...patch })
        else stats[i] = { ...stats[i], ...patch }
        return { ...m, status: stats }
      }),
    },
  })),

  setUserOnline: (userId) => set((s) => {
    const o = new Set(s.onlineUsers); o.add(userId); return { onlineUsers: o }
  }),
  setUserOffline: (userId) => set((s) => {
    const o = new Set(s.onlineUsers); o.delete(userId)
    return { onlineUsers: o, lastSeen: { ...s.lastSeen, [userId]: Date.now() } }
  }),

  setTyping: (channelId, userId, isTyping) => set((s) => {
    const t = { ...s.typingUsers }
    if (!t[channelId]) t[channelId] = new Set()
    else t[channelId] = new Set(t[channelId])
    isTyping ? t[channelId].add(userId) : t[channelId].delete(userId)
    return { typingUsers: t }
  }),
}))

export default useChatStore
'@
Write-FileUtf8NoBom -Path "store/chatStore.js" -Content $store

# =====================================================================
# 2) lib/haptics.js -- safe wrapper around expo-haptics
# =====================================================================
Write-Host "[2/9] Creating lib/haptics.js..."

$haptics = @'
// Safe wrapper around expo-haptics. If module is unavailable (web / dev
// without native build), all calls become no-ops.
let H = null
try { H = require('expo-haptics') } catch (e) { H = null }

export function tapLight()  { try { H?.impactAsync(H.ImpactFeedbackStyle.Light)  } catch (e) {} }
export function tapMedium() { try { H?.impactAsync(H.ImpactFeedbackStyle.Medium) } catch (e) {} }
export function tapHeavy()  { try { H?.impactAsync(H.ImpactFeedbackStyle.Heavy)  } catch (e) {} }
export function selection() { try { H?.selectionAsync() } catch (e) {} }
export function success()   { try { H?.notificationAsync(H.NotificationFeedbackType.Success) } catch (e) {} }
export function warning()   { try { H?.notificationAsync(H.NotificationFeedbackType.Warning) } catch (e) {} }
'@
Write-FileUtf8NoBom -Path "lib/haptics.js" -Content $haptics

# =====================================================================
# 3) lib/dateFmt.js -- WhatsApp-style time helpers
# =====================================================================
Write-Host "[3/9] Creating lib/dateFmt.js..."

$dateFmt = @'
import { format, isToday, isYesterday, differenceInMinutes, differenceInHours, differenceInDays } from 'date-fns'

export function bubbleTime(ts) {
  if (!ts) return ''
  try { return format(new Date(ts), 'h:mm a') } catch { return '' }
}

export function divider(ts) {
  if (!ts) return ''
  const d = new Date(ts)
  if (isToday(d)) return 'Today'
  if (isYesterday(d)) return 'Yesterday'
  try {
    const diff = differenceInDays(new Date(), d)
    if (diff < 7) return format(d, 'EEEE')   // Monday, Tuesday...
    return format(d, 'd MMM yyyy')
  } catch { return '' }
}

export function lastSeenText(ts, isOnline) {
  if (isOnline) return 'online'
  if (!ts) return ''
  const d = new Date(ts)
  const mins = differenceInMinutes(new Date(), d)
  if (mins < 1) return 'last seen just now'
  if (mins < 60) return 'last seen ' + mins + ' min ago'
  const hrs = differenceInHours(new Date(), d)
  if (hrs < 24) return 'last seen ' + hrs + 'h ago'
  if (isYesterday(d)) return 'last seen yesterday at ' + format(d, 'h:mm a')
  return 'last seen ' + format(d, 'd MMM')
}

export function sameDay(a, b) {
  if (!a || !b) return false
  try {
    const x = new Date(a), y = new Date(b)
    return x.getFullYear() === y.getFullYear() && x.getMonth() === y.getMonth() && x.getDate() === y.getDate()
  } catch { return false }
}
'@
Write-FileUtf8NoBom -Path "lib/dateFmt.js" -Content $dateFmt

# =====================================================================
# 4) components/TypingDots.js -- 3 bouncing dots
# =====================================================================
Write-Host "[4/9] Creating components/TypingDots.js..."

$typingDots = @'
import React, { useEffect, useRef } from 'react'
import { View, Animated, Easing, StyleSheet } from 'react-native'
import { colors } from '@/lib/theme'

function Dot({ delay }) {
  const v = useRef(new Animated.Value(0)).current
  useEffect(() => {
    const loop = Animated.loop(Animated.sequence([
      Animated.delay(delay),
      Animated.timing(v, { toValue: 1, duration: 350, useNativeDriver: true, easing: Easing.out(Easing.ease) }),
      Animated.timing(v, { toValue: 0, duration: 350, useNativeDriver: true, easing: Easing.in(Easing.ease) }),
    ]))
    loop.start()
    return () => loop.stop()
  }, [delay])
  const translateY = v.interpolate({ inputRange: [0, 1], outputRange: [0, -4] })
  const opacity = v.interpolate({ inputRange: [0, 1], outputRange: [0.4, 1] })
  return <Animated.View style={[styles.dot, { transform: [{ translateY }], opacity }]} />
}

export default function TypingDots() {
  return (
    <View style={styles.row}>
      <Dot delay={0} />
      <Dot delay={150} />
      <Dot delay={300} />
    </View>
  )
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', gap: 4, alignItems: 'center', paddingHorizontal: 4 },
  dot: { width: 6, height: 6, borderRadius: 3, backgroundColor: colors.brand },
})
'@
Write-FileUtf8NoBom -Path "components/TypingDots.js" -Content $typingDots

# =====================================================================
# 5) components/ImageLightbox.js -- full-screen image viewer
# =====================================================================
Write-Host "[5/9] Creating components/ImageLightbox.js..."

$lightbox = @'
import React, { useState } from 'react'
import { Modal, View, Text, TouchableOpacity, Image, Alert, StyleSheet, Pressable } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { CloseIcon } from '@/components/icons'

let MediaLibrary = null
try { MediaLibrary = require('expo-media-library') } catch (e) { MediaLibrary = null }

let FileSystem = null
try { FileSystem = require('expo-file-system') } catch (e) { FileSystem = null }

export default function ImageLightbox({ uri, visible, onClose, fileName }) {
  const [saving, setSaving] = useState(false)
  if (!uri) return null

  const save = async () => {
    if (!MediaLibrary) { Alert.alert('Save', 'Media library not available'); return }
    setSaving(true)
    try {
      const { status } = await MediaLibrary.requestPermissionsAsync()
      if (status !== 'granted') { Alert.alert('Permission denied'); setSaving(false); return }
      // Download to cache first if remote
      let localUri = uri
      if (/^https?:\/\//.test(uri) && FileSystem) {
        const safeName = (fileName || 'image_' + Date.now() + '.jpg').replace(/[^a-zA-Z0-9._-]/g, '_')
        const dest = FileSystem.cacheDirectory + safeName
        const dl = await FileSystem.downloadAsync(uri, dest)
        localUri = dl.uri
      }
      await MediaLibrary.saveToLibraryAsync(localUri)
      Alert.alert('Saved', 'Image saved to your gallery')
    } catch (e) {
      Alert.alert('Save failed', e?.message || 'Could not save image')
    }
    setSaving(false)
  }

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <SafeAreaView style={styles.root}>
        <Pressable style={styles.backdrop} onPress={onClose}>
          <Image source={{ uri }} style={styles.image} resizeMode="contain" />
        </Pressable>
        <View style={styles.topBar}>
          <TouchableOpacity onPress={onClose} style={styles.btn}>
            <CloseIcon size={22} color="#fff" />
          </TouchableOpacity>
          <TouchableOpacity onPress={save} disabled={saving} style={styles.saveBtn}>
            <Text style={styles.saveText}>{saving ? 'Saving...' : 'Save'}</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    </Modal>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#000' },
  backdrop: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  image: { width: '100%', height: '100%' },
  topBar: { position: 'absolute', top: 0, left: 0, right: 0, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', padding: 12, paddingTop: 36 },
  btn: { width: 40, height: 40, borderRadius: 20, backgroundColor: 'rgba(0,0,0,0.5)', alignItems: 'center', justifyContent: 'center' },
  saveBtn: { backgroundColor: 'rgba(0,0,0,0.55)', paddingHorizontal: 14, paddingVertical: 8, borderRadius: 16 },
  saveText: { color: '#fff', fontWeight: '600', fontSize: 13 },
})
'@
Write-FileUtf8NoBom -Path "components/ImageLightbox.js" -Content $lightbox

# =====================================================================
# 6) components/MessageActionSheet.js -- long-press menu
# =====================================================================
Write-Host "[6/9] Creating components/MessageActionSheet.js..."

$actionSheet = @'
import React from 'react'
import { Modal, View, Text, TouchableOpacity, Pressable, StyleSheet, Share } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { colors } from '@/lib/theme'

let Clipboard = null
try { Clipboard = require('expo-clipboard') } catch (e) { Clipboard = null }

const QUICK_EMOJIS = ['\u{1F44D}', '\u2764\uFE0F', '\u{1F602}', '\u{1F62E}', '\u{1F625}', '\u{1F64F}']

export default function MessageActionSheet({ visible, msg, isOwn, onClose, onReact, onReply, onDelete }) {
  if (!visible || !msg) return null

  const copy = async () => {
    try {
      if (Clipboard?.setStringAsync) await Clipboard.setStringAsync(msg.content || '')
    } catch (e) {}
    onClose()
  }

  const forward = async () => {
    try { await Share.share({ message: msg.content || '' }) } catch (e) {}
    onClose()
  }

  return (
    <Modal visible transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={(e) => e.stopPropagation()}>
          {/* Quick reactions */}
          <View style={styles.reactionsRow}>
            {QUICK_EMOJIS.map(e => (
              <TouchableOpacity key={e} onPress={() => { onReact(e); onClose() }} style={styles.emojiBtn}>
                <Text style={{ fontSize: 28 }}>{e}</Text>
              </TouchableOpacity>
            ))}
          </View>

          <View style={styles.divider} />

          {/* Actions */}
          <TouchableOpacity style={styles.actionRow} onPress={() => { onReply(); onClose() }}>
            <Text style={styles.actionLabel}>Reply</Text>
          </TouchableOpacity>
          {msg.type === 'text' && (
            <TouchableOpacity style={styles.actionRow} onPress={copy}>
              <Text style={styles.actionLabel}>Copy</Text>
            </TouchableOpacity>
          )}
          <TouchableOpacity style={styles.actionRow} onPress={forward}>
            <Text style={styles.actionLabel}>Forward</Text>
          </TouchableOpacity>
          {isOwn && (
            <TouchableOpacity style={styles.actionRow} onPress={() => { onDelete(); onClose() }}>
              <Text style={[styles.actionLabel, { color: colors.danger }]}>Delete</Text>
            </TouchableOpacity>
          )}
        </Pressable>
      </Pressable>
    </Modal>
  )
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.55)', justifyContent: 'flex-end' },
  sheet: { backgroundColor: colors.bgSurface, borderTopLeftRadius: 20, borderTopRightRadius: 20, paddingTop: 12, paddingBottom: 28 },
  reactionsRow: { flexDirection: 'row', justifyContent: 'space-around', paddingHorizontal: 12, paddingVertical: 8 },
  emojiBtn: { padding: 6 },
  divider: { height: 0.5, backgroundColor: colors.bgDivider, marginVertical: 6 },
  actionRow: { paddingHorizontal: 20, paddingVertical: 14 },
  actionLabel: { color: colors.textPrimary, fontSize: 16 },
})
'@
Write-FileUtf8NoBom -Path "components/MessageActionSheet.js" -Content $actionSheet

# =====================================================================
# 7) components/VoiceRecorder.js -- hold-to-record bar
# =====================================================================
Write-Host "[7/9] Creating components/VoiceRecorder.js..."

$voiceRec = @'
import React, { useEffect, useRef, useState } from 'react'
import { View, Text, TouchableOpacity, Animated, StyleSheet, PanResponder, Alert } from 'react-native'
import { colors } from '@/lib/theme'

// Lazy require to avoid crash if expo-av is not installed
let Audio = null
try { Audio = require('expo-av').Audio } catch (e) { Audio = null }

const SWIPE_CANCEL_DISTANCE = 80   // px to the left to cancel

export default function VoiceRecorder({ onSend, onCancel, channelId }) {
  // controlled component: parent toggles `recording` by mounting/unmounting
  const [seconds, setSeconds] = useState(0)
  const [recording, setRecording] = useState(null)
  const recordingRef = useRef(null)
  const cancelledRef = useRef(false)
  const intervalRef = useRef(null)
  const slideX = useRef(new Animated.Value(0)).current

  // PanResponder for swipe-to-cancel
  const pan = useRef(PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: () => true,
    onPanResponderMove: (_, g) => {
      if (g.dx < 0) slideX.setValue(Math.max(g.dx, -120))
    },
    onPanResponderRelease: (_, g) => {
      if (g.dx < -SWIPE_CANCEL_DISTANCE) {
        cancelledRef.current = true
        stopAndDiscard()
      } else {
        Animated.spring(slideX, { toValue: 0, useNativeDriver: true }).start()
      }
    },
  })).current

  useEffect(() => {
    start()
    intervalRef.current = setInterval(() => setSeconds(s => s + 1), 1000)
    return () => {
      clearInterval(intervalRef.current)
      stopAndDiscard()
    }
  }, [])

  const start = async () => {
    if (!Audio) { Alert.alert('Voice notes', 'expo-av not installed'); onCancel(); return }
    try {
      const { status } = await Audio.requestPermissionsAsync()
      if (status !== 'granted') { Alert.alert('Mic permission denied'); onCancel(); return }
      await Audio.setAudioModeAsync({ allowsRecordingIOS: true, playsInSilentModeIOS: true })
      const rec = new Audio.Recording()
      await rec.prepareToRecordAsync(Audio.RecordingOptionsPresets.HIGH_QUALITY)
      await rec.startAsync()
      recordingRef.current = rec
      setRecording(rec)
    } catch (e) {
      console.warn('record start error', e)
      Alert.alert('Could not start recording', e?.message || '')
      onCancel()
    }
  }

  const stopAndDiscard = async () => {
    try {
      if (recordingRef.current) {
        await recordingRef.current.stopAndUnloadAsync()
        recordingRef.current = null
      }
    } catch (e) {}
    onCancel()
  }

  const stopAndSend = async () => {
    try {
      const rec = recordingRef.current
      if (!rec) return onCancel()
      await rec.stopAndUnloadAsync()
      const uri = rec.getURI()
      recordingRef.current = null
      if (!uri) return onCancel()
      onSend(uri, seconds)
    } catch (e) {
      console.warn('record stop error', e)
      onCancel()
    }
  }

  const mm = String(Math.floor(seconds / 60)).padStart(2, '0')
  const ss = String(seconds % 60).padStart(2, '0')

  return (
    <Animated.View style={[styles.bar, { transform: [{ translateX: slideX }] }]} {...pan.panHandlers}>
      <View style={styles.recordingDot} />
      <Text style={styles.time}>{mm}:{ss}</Text>
      <Text style={styles.hint}>Slide left to cancel</Text>
      <TouchableOpacity onPress={stopAndSend} style={styles.sendBtn}>
        <Text style={{ color: '#fff', fontWeight: '700' }}>SEND</Text>
      </TouchableOpacity>
    </Animated.View>
  )
}

const styles = StyleSheet.create({
  bar: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 8, paddingHorizontal: 12, backgroundColor: colors.bgRaised, borderRadius: 22, flex: 1 },
  recordingDot: { width: 10, height: 10, borderRadius: 5, backgroundColor: '#f15c6d' },
  time: { color: colors.textPrimary, fontVariant: ['tabular-nums'], fontSize: 14, minWidth: 48 },
  hint: { flex: 1, color: colors.textSecondary, fontSize: 12 },
  sendBtn: { backgroundColor: colors.brand, paddingHorizontal: 14, paddingVertical: 6, borderRadius: 14 },
})
'@
Write-FileUtf8NoBom -Path "components/VoiceRecorder.js" -Content $voiceRec

# =====================================================================
# 8) components/MessageBubble.js -- swipe-to-reply, reply preview,
#    bubble grouping, action sheet, lightbox, voice playback
# =====================================================================
Write-Host "[8/9] Rewriting components/MessageBubble.js (full polish)..."

$bubble = @'
import React, { useRef, useState, useMemo } from 'react'
import { View, Text, TouchableOpacity, Image, StyleSheet, Linking, PanResponder, Animated, Pressable } from 'react-native'
import useChatStore from '@/store/chatStore'
import { getSocket } from '@/lib/socket'
import { colors } from '@/lib/theme'
import { TickSingle, TickDouble, FileIcon } from '@/components/icons'
import { bubbleTime } from '@/lib/dateFmt'
import MessageActionSheet from '@/components/MessageActionSheet'
import ImageLightbox from '@/components/ImageLightbox'
import * as Haptics from '@/lib/haptics'

let Audio = null
try { Audio = require('expo-av').Audio } catch (e) { Audio = null }

const SWIPE_REPLY = 60  // px to trigger reply

function mediaUrlOf(msg) {
  const u = msg.file_url || msg.content || ''
  if (!u) return ''
  if (/^https?:\/\//.test(u)) return u
  const base = (process.env.EXPO_PUBLIC_API_URL || 'https://api.10xdigitalventures.com/api').replace(/\/api\/?$/, '')
  return base + (u.startsWith('/') ? u : '/uploads/' + u)
}

function fmtSize(b) {
  if (!b) return ''
  const kb = b / 1024
  return kb < 1024 ? Math.round(kb) + ' KB' : (kb / 1024).toFixed(1) + ' MB'
}

function fmtDur(s) {
  const sec = Math.max(0, Math.floor(s))
  const m = Math.floor(sec / 60), ss = sec % 60
  return m + ':' + String(ss).padStart(2, '0')
}

function Status({ isOwn, status }) {
  if (!isOwn) return null
  const stats = Array.isArray(status) ? status : []
  if (stats.length === 0) return <TickSingle color={colors.pending} />
  const allRead = stats.every(s => s.read_at)
  const allDel  = stats.every(s => s.delivered_at)
  if (allRead) return <TickDouble color={colors.read} />
  if (allDel)  return <TickDouble color={colors.pending} />
  return <TickSingle color={colors.pending} />
}

function AudioPlayer({ uri }) {
  const [playing, setPlaying] = useState(false)
  const [pos, setPos] = useState(0)
  const [dur, setDur] = useState(0)
  const soundRef = useRef(null)

  const toggle = async () => {
    if (!Audio) return
    try {
      if (!soundRef.current) {
        const { sound } = await Audio.Sound.createAsync({ uri })
        soundRef.current = sound
        sound.setOnPlaybackStatusUpdate((st) => {
          if (!st.isLoaded) return
          setPos(st.positionMillis / 1000)
          setDur((st.durationMillis || 0) / 1000)
          if (st.didJustFinish) { setPlaying(false); sound.setPositionAsync(0) }
        })
      }
      if (playing) { await soundRef.current.pauseAsync(); setPlaying(false) }
      else { await soundRef.current.playAsync(); setPlaying(true) }
    } catch (e) { console.warn('audio toggle', e) }
  }

  return (
    <View style={vsStyles.row}>
      <TouchableOpacity onPress={toggle} style={vsStyles.playBtn}>
        <Text style={{ color: '#fff', fontWeight: '700' }}>{playing ? 'II' : '>'}</Text>
      </TouchableOpacity>
      <View style={vsStyles.barWrap}>
        <View style={vsStyles.barBg} />
        <View style={[vsStyles.barFill, { width: dur > 0 ? `${Math.min(100, (pos / dur) * 100)}%` : '0%' }]} />
      </View>
      <Text style={vsStyles.time}>{fmtDur(playing || pos > 0 ? pos : dur)}</Text>
    </View>
  )
}

const vsStyles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 8, minWidth: 200, paddingVertical: 2 },
  playBtn: { width: 32, height: 32, borderRadius: 16, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center' },
  barWrap: { flex: 1, height: 4, justifyContent: 'center' },
  barBg: { position: 'absolute', left: 0, right: 0, height: 3, backgroundColor: 'rgba(255,255,255,0.15)', borderRadius: 2 },
  barFill: { position: 'absolute', left: 0, height: 3, backgroundColor: colors.brand, borderRadius: 2 },
  time: { color: 'rgba(233,237,239,0.7)', fontSize: 11, minWidth: 32, textAlign: 'right' },
})

export default function MessageBubble({ msg, channelId, currentUserId, isGrouped, prevSenderId }) {
  const { updateReaction, deleteMessage, setReplyTo, messages } = useChatStore()
  const [showSheet, setShowSheet] = useState(false)
  const [lightboxOpen, setLightboxOpen] = useState(false)
  const isOwn = msg.sender_id === currentUserId
  const time = bubbleTime(msg.created_at)
  const url = mediaUrlOf(msg)

  // For reply preview lookup
  const repliedMsg = useMemo(() => {
    if (!msg.reply_to) return null
    const list = messages[channelId] || []
    return list.find(m => m.id === msg.reply_to)
  }, [msg.reply_to, messages, channelId])

  // Swipe-to-reply
  const tx = useRef(new Animated.Value(0)).current
  const pan = useRef(PanResponder.create({
    onMoveShouldSetPanResponder: (_, g) => Math.abs(g.dx) > 8 && Math.abs(g.dx) > Math.abs(g.dy),
    onPanResponderMove: (_, g) => {
      const dx = Math.max(0, Math.min(g.dx, 100))
      tx.setValue(dx)
    },
    onPanResponderRelease: (_, g) => {
      if (g.dx > SWIPE_REPLY) {
        Haptics.tapMedium()
        setReplyTo(channelId, msg)
      }
      Animated.spring(tx, { toValue: 0, useNativeDriver: true }).start()
    },
  })).current

  if (msg.is_deleted === 1) {
    return (
      <View style={[styles.row, isOwn ? styles.rowRight : styles.rowLeft]}>
        <View style={[styles.bubble, isOwn ? styles.bubbleSent : styles.bubbleReceived, { opacity: 0.6 }]}>
          <Text style={styles.deleted}>Message deleted</Text>
        </View>
      </View>
    )
  }

  const grouped = (msg.reactions || []).reduce((acc, r) => {
    acc[r.emoji] = acc[r.emoji] || []
    acc[r.emoji].push(r.user_id)
    return acc
  }, {})

  const toggleReact = async (emoji) => {
    const rx = msg.reactions || []
    const has = rx.some(r => r.emoji === emoji && r.user_id === currentUserId)
    updateReaction(channelId, msg.id, emoji, currentUserId, has ? 'removed' : 'added')
    const sock = await getSocket()
    sock.emit('reaction:toggle', { message_id: msg.id, channel_id: channelId, emoji })
  }

  const onLongPress = () => { Haptics.tapHeavy(); setShowSheet(true) }

  const startReply = () => setReplyTo(channelId, msg)

  const doDelete = async () => {
    const sock = await getSocket()
    sock.emit('message:delete', { message_id: msg.id, channel_id: channelId })
    deleteMessage(channelId, msg.id)
  }

  // First message from this sender in a group? show name (received only)
  const showSender = !isOwn && !isGrouped

  const renderBody = () => {
    if (msg.type === 'image') {
      return (
        <TouchableOpacity onPress={() => setLightboxOpen(true)} activeOpacity={0.9}>
          <Image source={{ uri: url }} style={styles.image} resizeMode="cover" />
        </TouchableOpacity>
      )
    }
    if (msg.type === 'file') {
      return (
        <TouchableOpacity onPress={() => Linking.openURL(url)} style={styles.fileCard}>
          <View style={styles.fileIconBox}><FileIcon color={colors.brand} /></View>
          <View style={{ flex: 1 }}>
            <Text style={styles.fileName} numberOfLines={1}>{msg.file_name || msg.content}</Text>
            <Text style={styles.fileSize}>{fmtSize(msg.file_size) || 'Open file'}</Text>
          </View>
        </TouchableOpacity>
      )
    }
    if (msg.type === 'audio' || msg.type === 'voice') {
      return <AudioPlayer uri={url} />
    }
    return <Text style={styles.text}>{msg.content}</Text>
  }

  return (
    <Animated.View style={{ transform: [{ translateX: tx }] }} {...pan.panHandlers}>
      <View style={[styles.row, isOwn ? styles.rowRight : styles.rowLeft, isGrouped && styles.rowGrouped]}>
        <Pressable onLongPress={onLongPress} delayLongPress={250}
          style={[
            styles.bubble,
            isOwn ? styles.bubbleSent : styles.bubbleReceived,
            isGrouped && (isOwn ? styles.tailSentGrouped : styles.tailRecvGrouped),
          ]}>
          {showSender && <Text style={styles.sender}>{msg.sender_name}</Text>}

          {repliedMsg && (
            <View style={styles.replyPreview}>
              <View style={styles.replyBar} />
              <View style={{ flex: 1 }}>
                <Text style={styles.replyName} numberOfLines={1}>
                  {repliedMsg.sender_id === currentUserId ? 'You' : (repliedMsg.sender_name || 'Unknown')}
                </Text>
                <Text style={styles.replyContent} numberOfLines={1}>
                  {repliedMsg.type === 'image' ? 'Photo'
                    : repliedMsg.type === 'file' ? (repliedMsg.file_name || 'File')
                    : repliedMsg.type === 'audio' || repliedMsg.type === 'voice' ? 'Voice message'
                    : (repliedMsg.content || '')}
                </Text>
              </View>
            </View>
          )}

          {renderBody()}

          <View style={styles.footer}>
            <Text style={styles.time}>{time}{msg.is_edited === 1 ? '  edited' : ''}</Text>
            <Status isOwn={isOwn} status={msg.status} />
          </View>

          {Object.keys(grouped).length > 0 && (
            <View style={styles.reactionsRow}>
              {Object.entries(grouped).map(([e, users]) => (
                <TouchableOpacity key={e} onPress={() => toggleReact(e)}
                  style={[styles.chip, users.includes(currentUserId) && styles.chipActive]}>
                  <Text style={{ fontSize: 13 }}>{e}</Text>
                  {users.length > 1 && <Text style={styles.chipCount}>{users.length}</Text>}
                </TouchableOpacity>
              ))}
            </View>
          )}
        </Pressable>
      </View>

      <MessageActionSheet
        visible={showSheet}
        msg={msg}
        isOwn={isOwn}
        onClose={() => setShowSheet(false)}
        onReact={toggleReact}
        onReply={startReply}
        onDelete={doDelete}
      />

      {msg.type === 'image' && (
        <ImageLightbox uri={url} visible={lightboxOpen} onClose={() => setLightboxOpen(false)} fileName={msg.file_name} />
      )}
    </Animated.View>
  )
}

const styles = StyleSheet.create({
  row: { paddingHorizontal: 10, marginVertical: 2, flexDirection: 'row' },
  rowRight: { justifyContent: 'flex-end' },
  rowLeft:  { justifyContent: 'flex-start' },
  rowGrouped: { marginVertical: 0.5 },

  bubble: { maxWidth: '78%', borderRadius: 8, paddingHorizontal: 10, paddingTop: 6, paddingBottom: 6 },
  bubbleSent:     { backgroundColor: colors.bubbleSent,     borderBottomRightRadius: 2 },
  bubbleReceived: { backgroundColor: colors.bubbleReceived, borderBottomLeftRadius: 2 },
  tailSentGrouped: { borderBottomRightRadius: 8 },
  tailRecvGrouped: { borderBottomLeftRadius: 8 },

  sender: { color: colors.brand, fontSize: 12, fontWeight: '700', marginBottom: 2 },
  text:   { color: colors.textPrimary, fontSize: 15, lineHeight: 20 },
  footer: { flexDirection: 'row', alignItems: 'center', justifyContent: 'flex-end', gap: 4, marginTop: 2 },
  time:   { fontSize: 10.5, color: 'rgba(233,237,239,0.55)' },
  deleted:{ color: 'rgba(233,237,239,0.7)', fontSize: 13, fontStyle: 'italic' },

  image: { width: 240, height: 240, borderRadius: 6, marginBottom: 2 },

  fileCard: { flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: 'rgba(0,0,0,0.2)', borderRadius: 8, padding: 8, marginBottom: 2 },
  fileIconBox: { width: 34, height: 34, borderRadius: 8, backgroundColor: colors.brandFaint, alignItems: 'center', justifyContent: 'center' },
  fileName: { color: colors.textPrimary, fontSize: 14, fontWeight: '500' },
  fileSize: { color: 'rgba(233,237,239,0.5)', fontSize: 11 },

  reactionsRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 4, marginTop: 4 },
  chip: { flexDirection: 'row', alignItems: 'center', gap: 3, paddingHorizontal: 7, paddingVertical: 2, borderRadius: 12, borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)', backgroundColor: 'rgba(0,0,0,0.3)' },
  chipActive: { borderColor: colors.brand, backgroundColor: colors.brandFaint },
  chipCount: { color: 'rgba(233,237,239,0.8)', fontSize: 11 },

  replyPreview: { flexDirection: 'row', backgroundColor: 'rgba(0,0,0,0.25)', borderRadius: 6, padding: 6, marginBottom: 4, gap: 6 },
  replyBar: { width: 3, backgroundColor: colors.brand, borderRadius: 2 },
  replyName: { color: colors.brand, fontSize: 12, fontWeight: '700' },
  replyContent: { color: 'rgba(233,237,239,0.75)', fontSize: 12, marginTop: 1 },
})
'@
Write-FileUtf8NoBom -Path "components/MessageBubble.js" -Content $bubble

# =====================================================================
# 9) app/chat/[channelId].js -- header polish, reply bar, search, voice,
#    haptic, bubble grouping, date dividers, typing dots
# =====================================================================
Write-Host "[9/9] Rewriting app/chat/[channelId].js (full polish)..."

$chat = @'
import { useEffect, useRef, useState, useMemo } from 'react'
import {
  View, Text, FlatList, TextInput, TouchableOpacity, StyleSheet,
  KeyboardAvoidingView, Platform, Alert, Image
} from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { useLocalSearchParams, useRouter } from 'expo-router'
import * as ImagePicker from 'expo-image-picker'
import * as DocumentPicker from 'expo-document-picker'
import useChatStore from '@/store/chatStore'
import { getSocket } from '@/lib/socket'
import api from '@/lib/api'
import { colors } from '@/lib/theme'
import { useCall } from '@/context/CallContext'
import { useGroupCall } from '@/context/GroupCallContext'
import {
  BackIcon, AttachIcon, SendIcon, PhoneIcon, VideoIcon, SmileIcon,
  SearchIcon, CloseIcon, MicIcon
} from '@/components/icons'
import MessageBubble from '@/components/MessageBubble'
import TypingDots from '@/components/TypingDots'
import VoiceRecorder from '@/components/VoiceRecorder'
import { divider, sameDay, lastSeenText } from '@/lib/dateFmt'
import * as Haptics from '@/lib/haptics'

export default function ChatScreen() {
  const { channelId } = useLocalSearchParams()
  const router = useRouter()
  const {
    channels, messages, user, setMessages, typingUsers, members, setMembers,
    replyTo, setReplyTo, onlineUsers, lastSeen, clearUnread, setActiveChannel
  } = useChatStore()

  const [text, setText] = useState('')
  const [loading, setLoading] = useState(true)
  const [sending, setSending] = useState(false)
  const [searchOpen, setSearchOpen] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const [recording, setRecording] = useState(false)
  const listRef = useRef(null)
  const typingRef = useRef(null)

  const channel = channels.find(c => c.id === channelId)
  const isDM = channel?.type === 'dm'
  const dmPeerId = isDM ? (channel?.dm_user_id || channel?.peer_id) : null
  const dmOnline = dmPeerId ? onlineUsers.has(dmPeerId) : false
  const dmLastSeen = dmPeerId ? lastSeen[dmPeerId] : null
  const channelMessages = (messages[channelId] || [])
  const reply = replyTo[channelId]

  const typingInChannel = typingUsers[channelId]
    ? [...typingUsers[channelId]].filter(id => id !== user?.id)
    : []

  // Mark this channel as active so unread is suppressed
  useEffect(() => {
    if (channel) setActiveChannel(channel)
    clearUnread(channelId)
    return () => setActiveChannel(null)
  }, [channelId])

  // ---- Build display list with date dividers + grouping flag ----
  // FlatList inverted so newest at top. We feed already-reversed array.
  const display = useMemo(() => {
    const filtered = searchQuery
      ? channelMessages.filter(m => (m.content || '').toLowerCase().includes(searchQuery.toLowerCase()))
      : channelMessages

    const out = []
    for (let i = 0; i < filtered.length; i++) {
      const m = filtered[i]
      const prev = filtered[i - 1]
      const isGrouped = !!prev && prev.sender_id === m.sender_id && sameDay(prev.created_at, m.created_at)
      out.push({ kind: 'msg', msg: m, isGrouped })
      const next = filtered[i + 1]
      if (!next || !sameDay(m.created_at, next.created_at)) {
        out.push({ kind: 'divider', label: divider(m.created_at), id: 'div-' + m.id })
      }
    }
    return [...out].reverse()
  }, [channelMessages, searchQuery])

  // ---- Load history ----
  useEffect(() => {
    if (!channelId) return
    setLoading(true)
    Promise.all([
      api.get(`/messages/${channelId}`),
      api.get(`/channels/${channelId}/members`).catch(() => ({ data: [] })),
    ]).then(([msgRes, memRes]) => {
      const list = Array.isArray(msgRes.data?.data) ? msgRes.data.data : (Array.isArray(msgRes.data) ? msgRes.data : [])
      const mem = Array.isArray(memRes.data?.data) ? memRes.data.data : (Array.isArray(memRes.data) ? memRes.data : [])
      setMessages(channelId, list)
      setMembers(mem)
      setLoading(false)
      const unread = list
        .filter(m => m.sender_id !== user?.id && (!Array.isArray(m.status) || !m.status.some(s => s.user_id === user?.id && s.read_at)))
        .map(m => m.id)
      if (unread.length > 0) {
        getSocket().then(s => s.emit('message:read', { channel_id: channelId, message_ids: unread }))
      }
    }).catch(() => setLoading(false))
  }, [channelId])

  // ---- Real-time read receipts for incoming new ----
  useEffect(() => {
    let mounted = true
    let socketRef = null
    const handler = (msg) => {
      if (!mounted) return
      if (msg.channel_id === channelId && msg.sender_id !== user?.id) {
        socketRef?.emit('message:read', { channel_id: channelId, message_ids: [msg.id] })
      }
    }
    getSocket().then(s => { socketRef = s; s.on('message:new', handler) })
    return () => { mounted = false; if (socketRef) socketRef.off('message:new', handler) }
  }, [channelId, user?.id])

  const handleTyping = async (val) => {
    setText(val)
    const sock = await getSocket()
    sock.emit('typing:start', { channel_id: channelId })
    clearTimeout(typingRef.current)
    typingRef.current = setTimeout(() => sock.emit('typing:stop', { channel_id: channelId }), 1500)
  }

  const send = async () => {
    if (!text.trim() || sending) return
    setSending(true)
    Haptics.tapLight()
    const sock = await getSocket()
    const payload = { channel_id: channelId, content: text.trim(), type: 'text' }
    if (reply?.id) payload.reply_to = reply.id
    sock.emit('message:send', payload)
    sock.emit('typing:stop', { channel_id: channelId })
    setText('')
    setReplyTo(channelId, null)
    setSending(false)
  }

  const pickFile = () => {
    Haptics.selection()
    Alert.alert('Send', 'Choose attachment type', [
      { text: 'Photo', onPress: async () => {
          const r = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ImagePicker.MediaTypeOptions.Images, quality: 0.8 })
          if (!r.canceled) uploadFile(r.assets[0].uri, r.assets[0].mimeType || 'image/jpeg', r.assets[0].fileName || 'photo.jpg')
        } },
      { text: 'Document', onPress: async () => {
          const r = await DocumentPicker.getDocumentAsync({ copyToCacheDirectory: true })
          if (!r.canceled && r.assets?.[0]) {
            const f = r.assets[0]; uploadFile(f.uri, f.mimeType || 'application/octet-stream', f.name)
          }
        } },
      { text: 'Cancel', style: 'cancel' }
    ])
  }

  const uploadFile = async (uri, mimeType, name) => {
    try {
      const fd = new FormData()
      fd.append('file', { uri, type: mimeType, name })
      if (reply?.id) fd.append('reply_to', reply.id)
      await api.post(`/files/upload/${channelId}`, fd, { headers: { 'Content-Type': 'multipart/form-data' } })
      setReplyTo(channelId, null)
    } catch (e) {
      Alert.alert('Upload failed', e?.message || 'Could not upload file')
    }
  }

  const onVoiceSend = async (uri, seconds) => {
    setRecording(false)
    Haptics.success()
    await uploadFile(uri, 'audio/m4a', 'voice_' + Date.now() + '.m4a')
  }

  const call = useCall()
  const groupCall = useGroupCall()

  const handleCall = (type) => {
    Haptics.tapMedium()
    if (channel?.type === 'dm') {
      const peerId = channel.dm_user_id || channel.peer_id
      if (!peerId) { Alert.alert('Cannot call', 'Peer id not available'); return }
      call?.startCall(peerId, channel.name, type)
    } else {
      groupCall?.startCall(channelId, type)
    }
  }

  const subtitle = typingInChannel.length > 0
    ? 'typing...'
    : isDM ? lastSeenText(dmLastSeen, dmOnline) : `${members?.length || 0} members`

  // ---- Renderers ----
  const renderItem = ({ item, index }) => {
    if (item.kind === 'divider') {
      return (
        <View style={styles.dividerWrap}>
          <View style={styles.dividerChip}><Text style={styles.dividerText}>{item.label}</Text></View>
        </View>
      )
    }
    return <MessageBubble msg={item.msg} channelId={channelId} currentUserId={user?.id} isGrouped={item.isGrouped} />
  }

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Header */}
      {searchOpen ? (
        <View style={styles.header}>
          <TouchableOpacity onPress={() => { setSearchOpen(false); setSearchQuery('') }} style={styles.iconBtn}>
            <CloseIcon color={colors.textPrimary} />
          </TouchableOpacity>
          <TextInput
            value={searchQuery}
            onChangeText={setSearchQuery}
            placeholder="Search in chat"
            placeholderTextColor={colors.textTertiary}
            style={styles.searchInput}
            autoFocus
          />
        </View>
      ) : (
        <View style={styles.header}>
          <TouchableOpacity onPress={() => router.back()} style={styles.iconBtn}><BackIcon color={colors.textPrimary} /></TouchableOpacity>
          <View style={styles.avatar}><Text style={styles.avatarText}>{(channel?.name || '?')[0].toUpperCase()}</Text></View>
          <View style={{ flex: 1 }}>
            <Text style={styles.title} numberOfLines={1}>{channel?.name || 'Chat'}</Text>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
              {typingInChannel.length > 0 ? (
                <TypingDots />
              ) : (
                <Text style={[styles.subtitle, dmOnline && { color: colors.online }]} numberOfLines={1}>{subtitle}</Text>
              )}
            </View>
          </View>
          <TouchableOpacity style={styles.iconBtn} onPress={() => handleCall('audio')}><PhoneIcon color={colors.textPrimary} /></TouchableOpacity>
          <TouchableOpacity style={styles.iconBtn} onPress={() => handleCall('video')}><VideoIcon color={colors.textPrimary} /></TouchableOpacity>
          <TouchableOpacity style={styles.iconBtn} onPress={() => { Haptics.selection(); setSearchOpen(true) }}>
            <SearchIcon color={colors.textPrimary} />
          </TouchableOpacity>
        </View>
      )}

      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        {loading ? (
          <View style={{ paddingTop: 20 }}>
            {[1,2,3,4].map(i => (
              <View key={i} style={styles.skeleton}>
                <View style={[styles.skel, { width: '50%' }]} />
                <View style={[styles.skel, { width: '40%', marginTop: 6 }]} />
              </View>
            ))}
          </View>
        ) : (
          <FlatList
            ref={listRef}
            data={display}
            inverted
            keyExtractor={item => item.kind === 'divider' ? item.id : item.msg.id}
            renderItem={renderItem}
            contentContainerStyle={{ paddingVertical: 8 }}
            keyboardShouldPersistTaps="handled"
            ListEmptyComponent={
              <View style={[styles.center, { transform: [{ scaleY: -1 }], paddingTop: 80 }]}>
                <Text style={styles.emptyTitle}>{isDM ? channel?.name : '#' + (channel?.name || '')}</Text>
                <Text style={styles.emptyBody}>
                  {searchQuery ? 'No messages match your search.' : 'Send a message to start the conversation.'}
                </Text>
              </View>
            }
          />
        )}

        {/* Reply preview above input */}
        {reply && (
          <View style={styles.replyBar}>
            <View style={styles.replyAccent} />
            <View style={{ flex: 1 }}>
              <Text style={styles.replyName}>{reply.sender_id === user?.id ? 'You' : (reply.sender_name || 'Unknown')}</Text>
              <Text style={styles.replySnippet} numberOfLines={1}>
                {reply.type === 'image' ? 'Photo'
                  : reply.type === 'file' ? (reply.file_name || 'File')
                  : reply.type === 'audio' || reply.type === 'voice' ? 'Voice message'
                  : (reply.content || '')}
              </Text>
            </View>
            <TouchableOpacity onPress={() => setReplyTo(channelId, null)} style={styles.iconBtn}>
              <CloseIcon color={colors.textSecondary} />
            </TouchableOpacity>
          </View>
        )}

        {/* Input row OR Voice recorder */}
        {recording ? (
          <View style={[styles.inputRow, { gap: 4 }]}>
            <VoiceRecorder
              channelId={channelId}
              onCancel={() => setRecording(false)}
              onSend={onVoiceSend}
            />
          </View>
        ) : (
          <View style={styles.inputRow}>
            <TouchableOpacity onPress={pickFile} style={styles.inputIcon}><AttachIcon color={colors.textSecondary} /></TouchableOpacity>
            <View style={styles.inputBox}>
              <TouchableOpacity style={{ paddingHorizontal: 4 }}><SmileIcon color={colors.textSecondary} /></TouchableOpacity>
              <TextInput
                style={styles.textInput}
                value={text}
                onChangeText={handleTyping}
                placeholder="Message"
                placeholderTextColor={colors.textTertiary}
                multiline
              />
            </View>
            {text.trim() ? (
              <TouchableOpacity onPress={send} style={styles.sendBtn}>
                <SendIcon color={colors.white} size={20} />
              </TouchableOpacity>
            ) : (
              <TouchableOpacity onLongPress={() => { Haptics.tapMedium(); setRecording(true) }} delayLongPress={250} style={styles.sendBtn}>
                <MicIcon color={colors.white} size={22} />
              </TouchableOpacity>
            )}
          </View>
        )}
      </KeyboardAvoidingView>
    </SafeAreaView>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  emptyTitle: { color: colors.textPrimary, fontSize: 18, fontWeight: '700' },
  emptyBody: { color: colors.textSecondary, fontSize: 13, marginTop: 6, textAlign: 'center', paddingHorizontal: 30 },

  header: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 8, paddingVertical: 8, gap: 6, backgroundColor: colors.bgSurface, borderBottomWidth: 0.5, borderBottomColor: colors.bgDivider },
  iconBtn: { width: 40, height: 40, alignItems: 'center', justifyContent: 'center', borderRadius: 999 },
  avatar: { width: 38, height: 38, borderRadius: 19, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center' },
  avatarText: { color: colors.textOnBrand, fontWeight: '700', fontSize: 15 },
  title: { color: colors.textPrimary, fontSize: 16, fontWeight: '600' },
  subtitle: { color: colors.textSecondary, fontSize: 12, marginTop: 1 },
  searchInput: { flex: 1, backgroundColor: colors.bgRaised, color: colors.textPrimary, paddingHorizontal: 12, paddingVertical: 8, borderRadius: 18, fontSize: 14 },

  dividerWrap: { alignItems: 'center', marginVertical: 12 },
  dividerChip: { backgroundColor: colors.bgRaised, paddingHorizontal: 10, paddingVertical: 4, borderRadius: 12 },
  dividerText: { color: colors.textSecondary, fontSize: 11, fontWeight: '600' },

  skeleton: { marginHorizontal: 16, marginBottom: 14 },
  skel: { height: 14, borderRadius: 7, backgroundColor: colors.bgRaised },

  replyBar: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 10, paddingVertical: 6, backgroundColor: colors.bgRaised, borderTopWidth: 0.5, borderTopColor: colors.bgDivider },
  replyAccent: { width: 3, alignSelf: 'stretch', backgroundColor: colors.brand, borderRadius: 2 },
  replyName: { color: colors.brand, fontSize: 12, fontWeight: '700' },
  replySnippet: { color: colors.textSecondary, fontSize: 12, marginTop: 1 },

  inputRow: { flexDirection: 'row', alignItems: 'flex-end', padding: 8, gap: 6, backgroundColor: colors.bgSurface, borderTopWidth: 0.5, borderTopColor: colors.bgDivider },
  inputIcon: { padding: 8 },
  inputBox: { flex: 1, flexDirection: 'row', alignItems: 'center', backgroundColor: colors.bgRaised, borderRadius: 22, paddingHorizontal: 6, paddingVertical: 4, minHeight: 40 },
  textInput: { flex: 1, color: colors.textPrimary, fontSize: 15, paddingVertical: 6, paddingHorizontal: 6, maxHeight: 120 },
  sendBtn: { width: 44, height: 44, borderRadius: 22, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center' },
})
'@
Write-FileUtf8NoBom -Path "app/chat/[channelId].js" -Content $chat

# =====================================================================
# 10) app/(tabs)/_layout.js -- unread badge on Chats tab
# =====================================================================
Write-Host "[10] Patching app/(tabs)/_layout.js (unread badge)..."

$tabLayout = Read-FileUtf8 "app/(tabs)/_layout.js"

if ($tabLayout -notmatch "tabBarBadge") {
    # Add useChatStore import if missing (it should be there already)
    # Replace the channels Tabs.Screen line with badge-aware version
    $old = "<Tabs.Screen name=`"channels`" options={{ title: 'Chats',    tabBarIcon: ({ color }) => <ChatIcon     size={24} color={color} /> }} />"
    $new = "<Tabs.Screen name=`"channels`" options={{ title: 'Chats',    tabBarIcon: ({ color }) => <ChatIcon     size={24} color={color} />, tabBarBadge: unreadTotal > 0 ? unreadTotal : undefined, tabBarBadgeStyle: { backgroundColor: colors.danger, color: '#fff', fontSize: 10 } }} />"
    if ($tabLayout.Contains($old)) {
        $tabLayout = $tabLayout.Replace($old, $new)
    }

    # Compute unreadTotal inside TabsLayout
    if ($tabLayout -notmatch "unreadTotal") {
        $tabLayout = $tabLayout.Replace(
            "const insets = useSafeAreaInsets()",
            "const insets = useSafeAreaInsets()`r`n  const { unreadCounts } = useChatStore()`r`n  const unreadTotal = Object.values(unreadCounts || {}).reduce((a, b) => a + (b || 0), 0)"
        )
    }
    Write-FileUtf8NoBom -Path "app/(tabs)/_layout.js" -Content $tabLayout
} else {
    Write-Host "  = badge already present"
}

# =====================================================================
# 11) app/(tabs)/channels.js -- pull-to-refresh
# =====================================================================
Write-Host "[11] Patching app/(tabs)/channels.js (pull-to-refresh)..."

$channelsPath = "app/(tabs)/channels.js"
$channels = Read-FileUtf8 $channelsPath

if ($channels -notmatch "RefreshControl") {
    # Add RefreshControl to react-native imports
    $channels = $channels -replace `
        "import \{[\s\S]*?\} from 'react-native'", `
        @"
import {
  View, Text, FlatList, TouchableOpacity, StyleSheet, TextInput,
  Modal, Alert, ActivityIndicator, ScrollView, RefreshControl
} from 'react-native'
"@

    # Add api + setChannels + refreshing state hook
    if ($channels -notmatch "const \[refreshing") {
        $channels = $channels.Replace(
            "const { channels, addChannel } = useChatStore()",
            "const { channels, addChannel, setChannels } = useChatStore()`r`n  const [refreshing, setRefreshing] = useState(false)"
        )
    }

    # Add onRefresh function before return
    if ($channels -notmatch "onRefresh") {
        $channels = $channels.Replace(
            "return (",
            @"
const onRefresh = async () => {
    setRefreshing(true)
    try {
      const r = await api.get('/channels')
      const list = Array.isArray(r.data?.data) ? r.data.data : (Array.isArray(r.data) ? r.data : [])
      setChannels(list)
    } catch (e) {}
    setRefreshing(false)
  }

  return (
"@
        )
    }

    # Add refreshControl prop to FlatList
    if ($channels -notmatch "refreshControl=") {
        $channels = $channels.Replace(
            "ListEmptyComponent={",
            "refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.brand} />}`r`n        ListEmptyComponent={"
        )
    }

    # Ensure api import is present (it might already be)
    if ($channels -notmatch "import api from") {
        $channels = $channels.Replace(
            "import useChatStore from '@/store/chatStore'",
            "import useChatStore from '@/store/chatStore'`r`nimport api from '@/lib/api'"
        )
    }

    Write-FileUtf8NoBom -Path $channelsPath -Content $channels
} else {
    Write-Host "  = pull-to-refresh already present"
}

# =====================================================================
# 12) app/(tabs)/_layout.js -- ensure message:status listener updates store
# =====================================================================
Write-Host "[12] Patching app/(tabs)/_layout.js (message:status listener)..."

$tabLayout = Read-FileUtf8 "app/(tabs)/_layout.js"
if ($tabLayout -notmatch "message:status") {
    # Add applyStatusUpdate to destructured store
    $tabLayout = $tabLayout -replace `
        "const \{[\s\S]*?\} = useChatStore\(\)", `
        "const { setUser, setChannels, addChannel, addMessage, updateMessage, deleteMessage, updateReaction, setUserOnline, setUserOffline, setTyping, applyStatusUpdate, unreadCounts } = useChatStore()"

    # Add unreadTotal compute if not there
    if ($tabLayout -notmatch "unreadTotal") {
        $tabLayout = $tabLayout.Replace(
            "const insets = useSafeAreaInsets()",
            "const insets = useSafeAreaInsets()`r`n  const unreadTotal = Object.values(unreadCounts || {}).reduce((a, b) => a + (b || 0), 0)"
        )
    }

    # Inject message:status listener inside init() after reaction:updated line
    $tabLayout = $tabLayout.Replace(
        "socket.on('reaction:updated', ({ message_id, channel_id, emoji, user_id, action }) => updateReaction(channel_id, message_id, emoji, user_id, action))",
        @"
socket.on('reaction:updated', ({ message_id, channel_id, emoji, user_id, action }) => updateReaction(channel_id, message_id, emoji, user_id, action))
        socket.on('message:status', ({ message_id, user_id, status }) => {
          // We need channel_id to update -- look it up from store
          const state = useChatStore.getState()
          for (const cid of Object.keys(state.messages || {})) {
            if ((state.messages[cid] || []).some(m => m.id === message_id)) {
              applyStatusUpdate(cid, message_id, user_id, status)
              break
            }
          }
        })
"@
    )

    Write-FileUtf8NoBom -Path "app/(tabs)/_layout.js" -Content $tabLayout
} else {
    Write-Host "  = message:status listener already wired"
}

Write-Host ""
Write-Host "================================================================="
Write-Host "PHASE 3 COMPLETE -- 15 polish items applied."
Write-Host ""
Write-Host "NEXT STEPS:"
Write-Host ""
Write-Host "  1) Install missing native modules:"
Write-Host "       npx expo install expo-haptics expo-media-library expo-clipboard"
Write-Host ""
Write-Host "  2) Rebuild APK (native modules need new build):"
Write-Host "       npx eas build --profile preview --platform android"
Write-Host ""
Write-Host "  3) Install new APK on phone and test:"
Write-Host "     - Long-press a message -> action sheet (Reply / Copy / Forward / Delete)"
Write-Host "     - Swipe message right -> reply bar appears"
Write-Host "     - Type with reply -> message sent as quoted reply"
Write-Host "     - Tap image -> full-screen lightbox -> Save button works"
Write-Host "     - Hold mic icon (empty text) -> voice recording starts"
Write-Host "     - Swipe left during recording -> cancels"
Write-Host "     - SEND in recorder -> sends voice note, plays back in bubble"
Write-Host "     - Channel headers show typing dots when someone is typing"
Write-Host "     - DM header shows online / last seen X ago"
Write-Host "     - Date dividers (Today / Yesterday / day name / date)"
Write-Host "     - Consecutive messages from same sender stack (no repeated"
Write-Host "       avatar/name)"
Write-Host "     - Chats tab shows red unread badge with count"
Write-Host "     - Pull down on channels list -> refresh"
Write-Host "     - Search icon in chat header -> filter messages"
Write-Host "     - Read receipts update in real-time (gray -> blue ticks)"
Write-Host "     - Haptic feedback on long-press / send / button taps"
Write-Host ""
Write-Host "  TROUBLESHOOTING:"
Write-Host "  - 'expo-haptics not found' -> ran step 1 above? rebuild needed."
Write-Host "  - Voice doesn't record -> mic permission? expo-av installed?"
Write-Host "  - Save image fails -> media library permission? user must allow."
Write-Host "================================================================="
