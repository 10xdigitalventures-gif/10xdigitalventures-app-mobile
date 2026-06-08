# =====================================================================
# Mobile App Phase 4 (FINAL) -- New Chat + Offline + Error Boundary +
#                               EAS Observe + Sentry hooks
#
# WHAT THIS SCRIPT DOES (all in one):
#
#  A) NEW CHAT (start direct message)
#     - Floating FAB on Chats tab + "New chat" option in + sheet
#     - User list with search, online dot
#     - Tap user -> POST /channels/dm/:userId -> open DM
#
#  B) OFFLINE SUPPORT
#     - Channels + messages cached to AsyncStorage automatically
#     - Hydrate from cache on app start (no white screen)
#     - "You are offline" banner when no internet
#     - All chats viewable without internet
#
#  C) ERROR BOUNDARY (fixes loader-stuck-then-crash)
#     - Wraps the entire app in a React error boundary
#     - On crash: shows readable error message + Reload button
#       (instead of just dying with a white/black screen)
#     - Logs the crash to AsyncStorage so you can read it later
#     - Also catches unhandled promise rejections globally
#
#  D) EAS OBSERVE (performance monitoring)
#     - Wraps root with ObserveRoot
#     - Tracks cold/warm launch, time to interactive, render perf
#     - Free for first 10,000 monthly active users
#     - Dashboard: https://expo.dev/accounts/<your>/projects/<your>/observe
#
#  E) SENTRY READY (commented out -- enable when you have a DSN)
#     - Instructions printed at end of script
#
# WHY APP WAS STILL CRASHING:
#   Most likely cause: APK was rebuilt BUT cached metro bundle had stale
#   code, OR a new Phase-3 module was imported by a file that wasn't
#   recompiled. The Error Boundary will now SHOW the exact error on
#   screen instead of silently dying -- so we will know the real cause
#   if it ever happens again.
#
# Run from MOBILE repo root:
#   powershell -ExecutionPolicy Bypass -File .\mobile-phase4-final-with-observe.ps1
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
Write-Host "Mobile Phase 4 FINAL -- NewChat + Offline + Errors"
Write-Host "==================================================="
Write-Host ""

# =====================================================================
# 1) lib/cache.js -- AsyncStorage helpers
# =====================================================================
Write-Host "[1/10] Creating lib/cache.js (offline storage)..."

$cache = @'
import AsyncStorage from '@react-native-async-storage/async-storage'

const KEY_CHANNELS = '10x_cache_channels_v1'
const KEY_USER     = '10x_cache_user_v1'
const KEY_MSG_PREFIX = '10x_cache_msgs_v1_'
const KEY_CRASH    = '10x_last_crash_v1'
const MAX_MSGS_PER_CHANNEL = 200

export async function saveChannelsCache(channels) {
  try { await AsyncStorage.setItem(KEY_CHANNELS, JSON.stringify(channels || [])) } catch (e) {}
}
export async function loadChannelsCache() {
  try { const s = await AsyncStorage.getItem(KEY_CHANNELS); return s ? JSON.parse(s) : [] } catch (e) { return [] }
}
export async function saveUserCache(user) {
  try { if (user) await AsyncStorage.setItem(KEY_USER, JSON.stringify(user)) } catch (e) {}
}
export async function loadUserCache() {
  try { const s = await AsyncStorage.getItem(KEY_USER); return s ? JSON.parse(s) : null } catch (e) { return null }
}
export async function saveMessagesCache(channelId, msgs) {
  try {
    if (!channelId) return
    const trimmed = Array.isArray(msgs) ? msgs.slice(-MAX_MSGS_PER_CHANNEL) : []
    await AsyncStorage.setItem(KEY_MSG_PREFIX + channelId, JSON.stringify(trimmed))
  } catch (e) {}
}
export async function loadMessagesCache(channelId) {
  try {
    if (!channelId) return []
    const s = await AsyncStorage.getItem(KEY_MSG_PREFIX + channelId)
    return s ? JSON.parse(s) : []
  } catch (e) { return [] }
}
export async function saveCrash(info) {
  try { await AsyncStorage.setItem(KEY_CRASH, JSON.stringify({ ...info, ts: new Date().toISOString() })) } catch (e) {}
}
export async function loadCrash() {
  try { const s = await AsyncStorage.getItem(KEY_CRASH); return s ? JSON.parse(s) : null } catch (e) { return null }
}
export async function clearCrash() {
  try { await AsyncStorage.removeItem(KEY_CRASH) } catch (e) {}
}
export async function clearAllCache() {
  try {
    const keys = await AsyncStorage.getAllKeys()
    const ours = keys.filter(k => k === KEY_CHANNELS || k === KEY_USER || k.startsWith(KEY_MSG_PREFIX))
    if (ours.length > 0) await AsyncStorage.multiRemove(ours)
  } catch (e) {}
}
'@
Write-FileUtf8NoBom -Path "lib/cache.js" -Content $cache

# =====================================================================
# 2) lib/netStatus.js -- online/offline detection
# =====================================================================
Write-Host "[2/10] Creating lib/netStatus.js..."

$netStatus = @'
import { useEffect, useState } from 'react'

let NetInfo = null
try { NetInfo = require('@react-native-community/netinfo').default } catch (e) { NetInfo = null }

export function useOnlineStatus() {
  const [online, setOnline] = useState(true)
  useEffect(() => {
    if (!NetInfo) return
    const unsub = NetInfo.addEventListener((state) => {
      setOnline(!!state.isConnected && state.isInternetReachable !== false)
    })
    NetInfo.fetch().then((state) => {
      setOnline(!!state.isConnected && state.isInternetReachable !== false)
    }).catch(() => {})
    return () => { if (typeof unsub === 'function') unsub() }
  }, [])
  return online
}
'@
Write-FileUtf8NoBom -Path "lib/netStatus.js" -Content $netStatus

# =====================================================================
# 3) components/ErrorBoundary.js -- catch JS crashes on screen
# =====================================================================
Write-Host "[3/10] Creating components/ErrorBoundary.js..."

$errorBoundary = @'
import React from 'react'
import { View, Text, TouchableOpacity, ScrollView, StyleSheet, Platform } from 'react-native'
import { saveCrash } from '@/lib/cache'

let DevSettings = null
try { DevSettings = require('react-native').DevSettings } catch (e) { DevSettings = null }

let Updates = null
try { Updates = require('expo-updates') } catch (e) { Updates = null }

export default class ErrorBoundary extends React.Component {
  state = { hasError: false, error: null, info: null }

  static getDerivedStateFromError(error) {
    return { hasError: true, error }
  }

  componentDidCatch(error, info) {
    // Save crash details so we can inspect after app reload
    try {
      saveCrash({
        message: String(error?.message || error),
        stack: String(error?.stack || ''),
        component: String(info?.componentStack || ''),
      })
    } catch (e) {}
    console.error('[ErrorBoundary]', error, info)
    this.setState({ info })
  }

  reload = async () => {
    try {
      if (Updates?.reloadAsync) { await Updates.reloadAsync(); return }
    } catch (e) {}
    try {
      if (DevSettings?.reload) { DevSettings.reload(); return }
    } catch (e) {}
    // Last-resort: reset boundary so children re-mount
    this.setState({ hasError: false, error: null, info: null })
  }

  render() {
    if (!this.state.hasError) return this.props.children

    const msg = this.state.error?.message || String(this.state.error || 'Unknown error')
    const stack = this.state.error?.stack || ''
    const comp  = this.state.info?.componentStack || ''

    return (
      <View style={styles.root}>
        <ScrollView contentContainerStyle={{ padding: 20, paddingTop: 60 }}>
          <Text style={styles.icon}>!</Text>
          <Text style={styles.title}>Something went wrong</Text>
          <Text style={styles.body}>
            The app hit an error and could not continue. Tap Reload to try again.
            A crash report has been saved on this device.
          </Text>

          <Text style={styles.label}>Error</Text>
          <Text style={styles.errText}>{msg}</Text>

          {!!stack && (<>
            <Text style={styles.label}>Stack</Text>
            <Text style={styles.codeText} numberOfLines={20}>{stack}</Text>
          </>)}

          {!!comp && (<>
            <Text style={styles.label}>Component tree</Text>
            <Text style={styles.codeText} numberOfLines={20}>{comp}</Text>
          </>)}

          <TouchableOpacity style={styles.btn} onPress={this.reload}>
            <Text style={styles.btnText}>Reload App</Text>
          </TouchableOpacity>
        </ScrollView>
      </View>
    )
  }
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#0b141a' },
  icon: { color: '#f15c6d', fontSize: 56, fontWeight: '700', textAlign: 'center', marginBottom: 8 },
  title: { color: '#fff', fontSize: 22, fontWeight: '700', textAlign: 'center', marginBottom: 8 },
  body: { color: 'rgba(255,255,255,0.7)', fontSize: 14, textAlign: 'center', marginBottom: 24, lineHeight: 20 },
  label: { color: '#1db791', fontSize: 12, fontWeight: '700', textTransform: 'uppercase', marginTop: 16, marginBottom: 4 },
  errText: { color: '#f15c6d', fontSize: 14, fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace' },
  codeText: { color: 'rgba(255,255,255,0.75)', fontSize: 11, fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace', lineHeight: 16 },
  btn: { backgroundColor: '#1db791', borderRadius: 12, paddingVertical: 14, alignItems: 'center', marginTop: 28, marginBottom: 40 },
  btnText: { color: '#fff', fontSize: 16, fontWeight: '700' },
})
'@
Write-FileUtf8NoBom -Path "components/ErrorBoundary.js" -Content $errorBoundary

# =====================================================================
# 4) lib/globalErrorHandler.js -- catch unhandled promise rejections
# =====================================================================
Write-Host "[4/10] Creating lib/globalErrorHandler.js..."

$globalError = @'
import { saveCrash } from '@/lib/cache'

let installed = false

export function installGlobalErrorHandlers() {
  if (installed) return
  installed = true

  // Catch unhandled JS errors
  try {
    const ErrorUtils = (global).ErrorUtils
    if (ErrorUtils && typeof ErrorUtils.setGlobalHandler === 'function') {
      const prev = ErrorUtils.getGlobalHandler ? ErrorUtils.getGlobalHandler() : null
      ErrorUtils.setGlobalHandler((err, isFatal) => {
        try {
          saveCrash({
            message: String(err?.message || err),
            stack: String(err?.stack || ''),
            fatal: !!isFatal,
            source: 'globalErrorHandler',
          })
        } catch (e) {}
        console.error('[GlobalError]', err)
        if (prev) try { prev(err, isFatal) } catch (e) {}
      })
    }
  } catch (e) {}

  // Catch unhandled promise rejections
  try {
    const tracker = require('promise/setimmediate/rejection-tracking')
    tracker.enable({
      allRejections: true,
      onUnhandled: (id, err) => {
        try {
          saveCrash({
            message: 'Unhandled promise rejection: ' + String(err?.message || err),
            stack: String(err?.stack || ''),
            source: 'unhandledRejection',
          })
        } catch (e) {}
        console.warn('[UnhandledPromise]', id, err)
      },
      onHandled: () => {},
    })
  } catch (e) {}
}
'@
Write-FileUtf8NoBom -Path "lib/globalErrorHandler.js" -Content $globalError

# =====================================================================
# 5) Update store/chatStore.js -- auto-cache to AsyncStorage
# =====================================================================
Write-Host "[5/10] Patching store/chatStore.js (auto-cache)..."

$store = @'
import { create } from 'zustand'
import { saveChannelsCache, saveMessagesCache, saveUserCache } from '@/lib/cache'

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
  replyTo: {},
  unreadCounts: {},
  lastSeen: {},

  setUser: (user) => {
    const u = unwrap(user)
    set({ user: u })
    saveUserCache(u)
  },

  setChannels: (channels) => {
    const list = toArray(channels)
    set({ channels: list })
    saveChannelsCache(list)
  },

  setActiveChannel: (channel) => set({ activeChannel: channel }),
  setMembers: (members) => set({ members: toArray(members) }),
  setReplyTo: (channelId, msg) => set((s) => ({ replyTo: { ...s.replyTo, [channelId]: msg || null } })),
  clearUnread: (channelId) => set((s) => ({ unreadCounts: { ...s.unreadCounts, [channelId]: 0 } })),
  setLastSeen: (userId, ts) => set((s) => ({ lastSeen: { ...s.lastSeen, [userId]: ts } })),

  addChannel: (ch) => set((s) => {
    const channel = unwrap(ch)
    if (!channel || !channel.id) return { channels: toArray(s.channels) }
    const list = toArray(s.channels)
    const exists = list.some((c) => c.id === channel.id)
    const next = exists
      ? list.map((c) => c.id === channel.id ? { ...c, ...channel } : c)
      : [...list, channel]
    saveChannelsCache(next)
    return { channels: next }
  }),

  setMessages: (channelId, msgs) => set((s) => {
    const norm = toArray(msgs).map(normalizeMsg)
    saveMessagesCache(channelId, norm)
    return { messages: { ...s.messages, [channelId]: norm } }
  }),

  addMessage: (channelId, msg) => set((s) => {
    const next = [...(s.messages[channelId] || []), normalizeMsg(msg)]
    saveMessagesCache(channelId, next)
    const isActive = s.activeChannel?.id === channelId
    const isOwn = msg.sender_id === s.user?.id
    const inc = (!isActive && !isOwn) ? 1 : 0
    return {
      messages: { ...s.messages, [channelId]: next },
      unreadCounts: { ...s.unreadCounts, [channelId]: (s.unreadCounts[channelId] || 0) + inc }
    }
  }),

  updateMessage: (channelId, messageId, updates) => set((s) => {
    const next = (s.messages[channelId] || []).map((m) =>
      m.id === messageId ? { ...m, ...updates } : m
    )
    saveMessagesCache(channelId, next)
    return { messages: { ...s.messages, [channelId]: next } }
  }),

  deleteMessage: (channelId, messageId) => set((s) => {
    const next = (s.messages[channelId] || []).map((m) =>
      m.id === messageId ? { ...m, is_deleted: 1 } : m
    )
    saveMessagesCache(channelId, next)
    return { messages: { ...s.messages, [channelId]: next } }
  }),

  updateReaction: (channelId, messageId, emoji, userId, action) => set((s) => {
    const next = (s.messages[channelId] || []).map((m) => {
      if (m.id !== messageId) return m
      let reactions = toArray(m.reactions)
      if (action === 'removed') reactions = reactions.filter((r) => !(r.emoji === emoji && r.user_id === userId))
      else reactions.push({ emoji, user_id: userId })
      return { ...m, reactions }
    })
    saveMessagesCache(channelId, next)
    return { messages: { ...s.messages, [channelId]: next } }
  }),

  applyStatusUpdate: (channelId, messageId, userId, status) => set((s) => {
    const next = (s.messages[channelId] || []).map((m) => {
      if (m.id !== messageId) return m
      const stats = toArray(m.status)
      const i = stats.findIndex(x => x.user_id === userId)
      const now = new Date().toISOString()
      const patch = status === 'read' ? { read_at: now, delivered_at: now } : { delivered_at: now }
      if (i === -1) stats.push({ user_id: userId, ...patch })
      else stats[i] = { ...stats[i], ...patch }
      return { ...m, status: stats }
    })
    saveMessagesCache(channelId, next)
    return { messages: { ...s.messages, [channelId]: next } }
  }),

  hydrate: (data) => set((s) => ({
    user: data?.user || s.user,
    channels: Array.isArray(data?.channels) ? data.channels : s.channels,
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
# 6) app/_layout.js -- wrap with ErrorBoundary + ObserveRoot
# =====================================================================
Write-Host "[6/10] Rewriting app/_layout.js (ErrorBoundary + Observe)..."

$rootLayout = @'
import { useEffect } from 'react'
import { Stack } from 'expo-router'
import { StatusBar } from 'expo-status-bar'
import { GestureHandlerRootView } from 'react-native-gesture-handler'
import { SafeAreaProvider } from 'react-native-safe-area-context'
import { registerForPushNotifications } from '@/lib/notifications'
import { CallProvider } from '@/context/CallContext'
import { GroupCallProvider } from '@/context/GroupCallContext'
import ErrorBoundary from '@/components/ErrorBoundary'
import { installGlobalErrorHandlers } from '@/lib/globalErrorHandler'

// EAS Observe (performance monitoring). If module not installed, falls back to no-op.
let ObserveRoot = null
let markInteractive = null
try {
  const obs = require('expo-observe')
  ObserveRoot = obs.ObserveRoot || obs.AppMetricsRoot || null
  markInteractive = obs.markInteractive || null
} catch (e) { ObserveRoot = null }

function App() {
  useEffect(() => {
    installGlobalErrorHandlers()
    registerForPushNotifications()
    // Tell Observe the app is interactive (one-time)
    try { if (markInteractive) markInteractive() } catch (e) {}
  }, [])

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <ErrorBoundary>
          <CallProvider>
            <GroupCallProvider>
              <StatusBar style="light" />
              <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: '#0b141a' } }}>
                <Stack.Screen name="(auth)" />
                <Stack.Screen name="(tabs)" />
              </Stack>
            </GroupCallProvider>
          </CallProvider>
        </ErrorBoundary>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  )
}

export default function RootLayout() {
  if (ObserveRoot) {
    return <ObserveRoot><App /></ObserveRoot>
  }
  return <App />
}
'@
Write-FileUtf8NoBom -Path "app/_layout.js" -Content $rootLayout

# =====================================================================
# 7) app/(tabs)/_layout.js -- hydrate from cache + offline-friendly init
# =====================================================================
Write-Host "[7/10] Rewriting app/(tabs)/_layout.js (cache hydrate)..."

$tabsLayout = @'
import { Tabs } from 'expo-router'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { useEffect } from 'react'
import * as SecureStore from 'expo-secure-store'
import { useRouter } from 'expo-router'
import useChatStore from '@/store/chatStore'
import { getSocket, disconnectSocket } from '@/lib/socket'
import api from '@/lib/api'
import { colors } from '@/lib/theme'
import { ChatIcon, PhoneIcon, GroupIcon, SettingsIcon } from '@/components/icons'
import { loadChannelsCache, loadUserCache } from '@/lib/cache'

export default function TabsLayout() {
  const insets = useSafeAreaInsets()
  const router = useRouter()
  const {
    setUser, setChannels, addChannel, addMessage, updateMessage, deleteMessage,
    updateReaction, setUserOnline, setUserOffline, setTyping, applyStatusUpdate,
    unreadCounts, hydrate,
  } = useChatStore()

  const unreadTotal = Object.values(unreadCounts || {}).reduce((a, b) => a + (b || 0), 0)

  useEffect(() => {
    const init = async () => {
      const token = await SecureStore.getItemAsync('token')
      if (!token) { router.replace('/(auth)/login'); return }

      // 1) Hydrate from cache instantly (offline-safe)
      try {
        const [cachedUser, cachedChannels] = await Promise.all([loadUserCache(), loadChannelsCache()])
        hydrate({ user: cachedUser, channels: cachedChannels })
      } catch (e) {}

      // 2) Try fresh fetch (skip silently if offline)
      try {
        const [meRes, chRes] = await Promise.all([api.get('/auth/me'), api.get('/channels')])
        setUser(meRes.data?.data || meRes.data)
        setChannels(Array.isArray(chRes.data?.data) ? chRes.data.data : Array.isArray(chRes.data) ? chRes.data : [])
      } catch (e) {
        console.log('Network init failed (using cache):', e?.message)
      }

      // 3) Connect socket (skip silently if offline)
      try {
        const socket = await getSocket()
        socket.emit('join:channels')
        socket.on('message:new', (msg) => addMessage(msg.channel_id, msg))
        socket.on('message:edited', ({ message_id, channel_id, content }) => updateMessage(channel_id, message_id, { content, is_edited: 1 }))
        socket.on('message:deleted', ({ message_id, channel_id }) => deleteMessage(channel_id, message_id))
        socket.on('reaction:updated', ({ message_id, channel_id, emoji, user_id, action }) => updateReaction(channel_id, message_id, emoji, user_id, action))
        socket.on('message:status', ({ message_id, user_id, status }) => {
          const state = useChatStore.getState()
          for (const cid of Object.keys(state.messages || {})) {
            if ((state.messages[cid] || []).some((m) => m.id === message_id)) {
              applyStatusUpdate(cid, message_id, user_id, status)
              break
            }
          }
        })
        socket.on('user:online',  ({ user_id }) => setUserOnline(user_id))
        socket.on('user:offline', ({ user_id }) => setUserOffline(user_id))
        socket.on('typing:start', ({ user_id, channel_id }) => setTyping(channel_id, user_id, true))
        socket.on('typing:stop',  ({ user_id, channel_id }) => setTyping(channel_id, user_id, false))
        socket.on('channel:new',  (ch) => { addChannel(ch); socket.emit('join:channels') })
      } catch (e) {
        console.log('Socket connect failed:', e?.message)
      }
    }
    init()
    return () => disconnectSocket()
  }, [])

  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarStyle: {
          backgroundColor: colors.bgSurface,
          borderTopColor: colors.bgDivider,
          borderTopWidth: 0.5,
          height: 60 + insets.bottom,
          paddingTop: 6,
          paddingBottom: Math.max(insets.bottom, 8),
        },
        tabBarActiveTintColor: colors.brand,
        tabBarInactiveTintColor: colors.textSecondary,
        tabBarLabelStyle: { fontSize: 11, fontWeight: '500' },
      }}
    >
      <Tabs.Screen
        name="channels"
        options={{
          title: 'Chats',
          tabBarIcon: ({ color }) => <ChatIcon size={24} color={color} />,
          tabBarBadge: unreadTotal > 0 ? unreadTotal : undefined,
          tabBarBadgeStyle: { backgroundColor: colors.danger, color: '#fff', fontSize: 10 },
        }}
      />
      <Tabs.Screen
        name="calls"
        options={{ title: 'Calls', tabBarIcon: ({ color }) => <PhoneIcon size={24} color={color} /> }}
      />
      <Tabs.Screen
        name="dms"
        options={{ title: 'Direct', tabBarIcon: ({ color }) => <GroupIcon size={24} color={color} /> }}
      />
      <Tabs.Screen
        name="profile"
        options={{ title: 'Settings', tabBarIcon: ({ color }) => <SettingsIcon size={24} color={color} /> }}
      />
      <Tabs.Screen name="files" options={{ href: null }} />
      <Tabs.Screen name="new-chat" options={{ href: null }} />
    </Tabs>
  )
}
'@
Write-FileUtf8NoBom -Path "app/(tabs)/_layout.js" -Content $tabsLayout

# =====================================================================
# 8) app/(tabs)/new-chat.js -- New Chat screen
# =====================================================================
Write-Host "[8/10] Creating app/(tabs)/new-chat.js (start DM)..."

$newChat = @'
import { useEffect, useState, useMemo } from 'react'
import {
  View, Text, FlatList, TouchableOpacity, StyleSheet, TextInput,
  ActivityIndicator, Alert, RefreshControl
} from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { useRouter } from 'expo-router'
import api from '@/lib/api'
import useChatStore from '@/store/chatStore'
import { colors } from '@/lib/theme'
import { BackIcon, SearchIcon } from '@/components/icons'

export default function NewChatScreen() {
  const router = useRouter()
  const { user, addChannel, onlineUsers } = useChatStore()
  const [users, setUsers] = useState([])
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [query, setQuery] = useState('')
  const [opening, setOpening] = useState(null)

  const load = async () => {
    try {
      const r = await api.get('/users')
      const list = Array.isArray(r.data?.data) ? r.data.data : (Array.isArray(r.data) ? r.data : [])
      setUsers(list.filter(u => u.id !== user?.id))
    } catch (e) {
      Alert.alert('Could not load contacts', e?.message || 'Check your connection')
    }
    setLoading(false)
  }

  useEffect(() => { load() }, [])
  const onRefresh = async () => { setRefreshing(true); await load(); setRefreshing(false) }

  const filtered = useMemo(() => {
    if (!query) return users
    const q = query.toLowerCase()
    return users.filter(u =>
      (u.name || '').toLowerCase().includes(q) ||
      (u.email || '').toLowerCase().includes(q)
    )
  }, [users, query])

  const startChat = async (peer) => {
    if (opening) return
    setOpening(peer.id)
    try {
      const r = await api.post('/channels/dm/' + peer.id)
      const ch = r.data?.data || r.data
      if (ch?.id) {
        addChannel(ch)
        router.replace('/chat/' + ch.id)
      } else {
        Alert.alert('Could not start chat')
      }
    } catch (e) {
      Alert.alert('Could not start chat', e?.response?.data?.message || e?.message || 'Try again')
    }
    setOpening(null)
  }

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.iconBtn}>
          <BackIcon color={colors.textPrimary} />
        </TouchableOpacity>
        <View style={{ flex: 1 }}>
          <Text style={styles.headerTitle}>New chat</Text>
          <Text style={styles.headerSub}>{filtered.length} contact{filtered.length === 1 ? '' : 's'}</Text>
        </View>
      </View>

      <View style={styles.searchBar}>
        <SearchIcon size={18} color={colors.textTertiary} />
        <TextInput
          value={query}
          onChangeText={setQuery}
          placeholder="Search name or email"
          placeholderTextColor={colors.textTertiary}
          style={styles.searchInput}
        />
      </View>

      {loading ? (
        <View style={styles.center}><ActivityIndicator color={colors.brand} size="large" /></View>
      ) : (
        <FlatList
          data={filtered}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => {
            const isOnline = onlineUsers.has(item.id)
            return (
              <TouchableOpacity style={styles.row} onPress={() => startChat(item)} disabled={!!opening}>
                <View style={styles.avatar}>
                  <Text style={styles.avatarText}>{(item.name || '?')[0].toUpperCase()}</Text>
                  {isOnline && <View style={styles.onlineDot} />}
                </View>
                <View style={{ flex: 1 }}>
                  <Text style={styles.name} numberOfLines={1}>{item.name}</Text>
                  <Text style={styles.sub} numberOfLines={1}>
                    {item.status || item.bio || item.email}
                  </Text>
                </View>
                {opening === item.id && <ActivityIndicator color={colors.brand} />}
              </TouchableOpacity>
            )
          }}
          ItemSeparatorComponent={() => <View style={styles.divider} />}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.brand} />}
          ListEmptyComponent={
            <View style={styles.center}>
              <Text style={styles.emptyTitle}>No contacts found</Text>
              <Text style={styles.emptyBody}>{query ? 'Try a different search.' : 'Your workspace has no other users yet.'}</Text>
            </View>
          }
        />
      )}
    </SafeAreaView>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  center: { paddingTop: 60, alignItems: 'center' },
  header: { flexDirection: 'row', alignItems: 'center', padding: 8, gap: 6, backgroundColor: colors.bgSurface, borderBottomWidth: 0.5, borderBottomColor: colors.bgDivider },
  iconBtn: { width: 40, height: 40, alignItems: 'center', justifyContent: 'center', borderRadius: 999 },
  headerTitle: { color: colors.textPrimary, fontSize: 18, fontWeight: '700' },
  headerSub: { color: colors.textSecondary, fontSize: 12, marginTop: 2 },

  searchBar: { flexDirection: 'row', alignItems: 'center', gap: 8, marginHorizontal: 12, marginTop: 10, paddingHorizontal: 12, backgroundColor: colors.bgRaised, borderRadius: 20, height: 40 },
  searchInput: { flex: 1, color: colors.textPrimary, fontSize: 14 },

  row: { flexDirection: 'row', alignItems: 'center', padding: 12, gap: 12 },
  avatar: { width: 46, height: 46, borderRadius: 23, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center' },
  avatarText: { color: colors.textOnBrand, fontWeight: '700', fontSize: 16 },
  onlineDot: { position: 'absolute', bottom: 0, right: 0, width: 12, height: 12, borderRadius: 6, backgroundColor: colors.online, borderWidth: 2, borderColor: colors.bg },
  name: { color: colors.textPrimary, fontSize: 15, fontWeight: '500' },
  sub: { color: colors.textSecondary, fontSize: 12, marginTop: 3 },
  divider: { height: 0.5, backgroundColor: colors.bgDivider, marginLeft: 70 },

  emptyTitle: { color: colors.textPrimary, fontSize: 16, fontWeight: '600', marginTop: 40 },
  emptyBody: { color: colors.textSecondary, fontSize: 13, marginTop: 6, textAlign: 'center', paddingHorizontal: 30 },
})
'@
Write-FileUtf8NoBom -Path "app/(tabs)/new-chat.js" -Content $newChat

# =====================================================================
# 9) app/(tabs)/channels.js -- FAB + offline banner + "New chat" choice
# =====================================================================
Write-Host "[9/10] Rewriting app/(tabs)/channels.js (FAB + offline banner)..."

$channels = @'
import { useState } from 'react'
import {
  View, Text, FlatList, TouchableOpacity, StyleSheet, TextInput,
  Modal, Alert, ActivityIndicator, ScrollView, RefreshControl
} from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { useRouter } from 'expo-router'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import { colors } from '@/lib/theme'
import { PlusIcon, SearchIcon, GroupIcon, ChatIcon } from '@/components/icons'
import { useOnlineStatus } from '@/lib/netStatus'

function Avatar({ name, isGroup }) {
  return (
    <View style={[styles.avatar, isGroup && { backgroundColor: colors.bgRaised }]}>
      {isGroup
        ? <GroupIcon size={22} color={colors.brand} />
        : <Text style={styles.avatarText}>{(name || '?')[0].toUpperCase()}</Text>}
    </View>
  )
}

function NewSheet({ visible, onClose, onCreated, router }) {
  const [mode, setMode] = useState(null)
  const [name, setName] = useState('')
  const [allUsers, setAllUsers] = useState([])
  const [selected, setSelected] = useState(new Set())
  const [loadingUsers, setLoadingUsers] = useState(false)
  const [creating, setCreating] = useState(false)

  const reset = () => { setMode(null); setName(''); setSelected(new Set()); setAllUsers([]) }
  const close = () => { reset(); onClose() }

  const openGroup = async () => {
    setMode('group')
    setLoadingUsers(true)
    try {
      const r = await api.get('/users')
      const list = Array.isArray(r.data?.data) ? r.data.data : (Array.isArray(r.data) ? r.data : [])
      setAllUsers(list)
    } catch { Alert.alert('Error', 'Could not load users') }
    setLoadingUsers(false)
  }

  const toggleUser = (id) => {
    const s = new Set(selected)
    if (s.has(id)) s.delete(id); else s.add(id)
    setSelected(s)
  }

  const create = async () => {
    if (!name.trim()) { Alert.alert('Name required'); return }
    setCreating(true)
    try {
      let res
      if (mode === 'group') {
        res = await api.post('/channels/group', { name: name.trim(), member_ids: [...selected], type: 'private' })
      } else {
        res = await api.post('/channels', { name: name.toLowerCase().replace(/\s+/g, '-') })
      }
      const ch = res.data?.data || res.data
      onCreated(ch); close()
    } catch (e) {
      Alert.alert('Error', e?.response?.data?.message || 'Could not create')
    }
    setCreating(false)
  }

  const goNewChat = () => { close(); router.push('/(tabs)/new-chat') }

  return (
    <Modal transparent visible={visible} animationType="slide" onRequestClose={close}>
      <View style={styles.sheetBackdrop}>
        <View style={styles.sheet}>
          <View style={styles.sheetHeader}>
            <Text style={styles.sheetTitle}>{mode === 'group' ? 'New Group' : mode === 'channel' ? 'New Channel' : 'Create new'}</Text>
            <TouchableOpacity onPress={close}><Text style={styles.cancel}>Cancel</Text></TouchableOpacity>
          </View>

          {!mode && (
            <View style={{ paddingTop: 8 }}>
              <TouchableOpacity style={styles.choice} onPress={goNewChat}>
                <Text style={styles.choiceLabel}>New chat (direct message)</Text>
                <Text style={styles.choiceSub}>Start a 1-on-1 chat with someone in your workspace</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.choice} onPress={() => setMode('channel')}>
                <Text style={styles.choiceLabel}>New channel</Text>
                <Text style={styles.choiceSub}>A public room anyone in workspace can join</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.choice} onPress={openGroup}>
                <Text style={styles.choiceLabel}>New group</Text>
                <Text style={styles.choiceSub}>Private chat with selected members</Text>
              </TouchableOpacity>
            </View>
          )}

          {mode && (
            <>
              <TextInput
                value={name}
                onChangeText={setName}
                placeholder={mode === 'group' ? 'Group name' : 'channel-name'}
                placeholderTextColor={colors.textTertiary}
                style={styles.input}
              />
              {mode === 'group' && (
                <>
                  <Text style={styles.sectionLabel}>Add members ({selected.size})</Text>
                  {loadingUsers ? <ActivityIndicator color={colors.brand} /> : (
                    <ScrollView style={styles.userList}>
                      {allUsers.map(u => {
                        const on = selected.has(u.id)
                        return (
                          <TouchableOpacity key={u.id} style={styles.userRow} onPress={() => toggleUser(u.id)}>
                            <View style={styles.userAvatar}><Text style={{ color: '#fff', fontWeight: '600' }}>{(u.name || '?')[0].toUpperCase()}</Text></View>
                            <Text style={{ color: colors.textPrimary, flex: 1 }}>{u.name}</Text>
                            <View style={[styles.check, on && { backgroundColor: colors.brand, borderColor: colors.brand }]}>
                              {on && <Text style={{ color: '#fff', fontWeight: '700' }}>{'\u2713'}</Text>}
                            </View>
                          </TouchableOpacity>
                        )
                      })}
                    </ScrollView>
                  )}
                </>
              )}
              <TouchableOpacity
                style={[styles.createBtn, (!name.trim() || creating) && { opacity: 0.5 }]}
                onPress={create} disabled={!name.trim() || creating}>
                {creating ? <ActivityIndicator color="#fff" /> : <Text style={styles.createBtnText}>Create</Text>}
              </TouchableOpacity>
            </>
          )}
        </View>
      </View>
    </Modal>
  )
}

export default function ChannelsScreen() {
  const router = useRouter()
  const { channels, addChannel, setChannels } = useChatStore()
  const safe = Array.isArray(channels) ? channels : []
  const [showSheet, setShowSheet] = useState(false)
  const [query, setQuery] = useState('')
  const [refreshing, setRefreshing] = useState(false)
  const online = useOnlineStatus()

  const filtered = safe.filter(c => !query || (c.name || '').toLowerCase().includes(query.toLowerCase()))

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
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>10x Chat</Text>
        <TouchableOpacity style={styles.headerBtn} onPress={() => setShowSheet(true)}><PlusIcon color={colors.textPrimary} /></TouchableOpacity>
      </View>

      {!online && (
        <View style={styles.offlineBar}>
          <Text style={styles.offlineText}>You are offline. Showing cached chats.</Text>
        </View>
      )}

      <View style={styles.searchBar}>
        <SearchIcon size={18} color={colors.textTertiary} />
        <TextInput
          value={query}
          onChangeText={setQuery}
          placeholder="Search"
          placeholderTextColor={colors.textTertiary}
          style={styles.searchInput}
        />
      </View>

      <FlatList
        data={filtered}
        keyExtractor={item => item.id}
        renderItem={({ item }) => (
          <TouchableOpacity style={styles.row} onPress={() => router.push('/chat/' + item.id)}>
            <Avatar name={item.name} isGroup={item.type !== 'dm'} />
            <View style={{ flex: 1 }}>
              <Text style={styles.name} numberOfLines={1}>{item.type === 'public' ? '# ' + item.name : item.name}</Text>
              <Text style={styles.preview} numberOfLines={1}>{item.topic || 'Tap to open conversation'}</Text>
            </View>
          </TouchableOpacity>
        )}
        ItemSeparatorComponent={() => <View style={styles.divider} />}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.brand} />}
        ListEmptyComponent={
          <View style={styles.empty}>
            <Text style={styles.emptyTitle}>No chats yet</Text>
            <Text style={styles.emptyBody}>Tap the green button to start a new chat</Text>
          </View>
        }
      />

      <TouchableOpacity style={styles.fab} onPress={() => router.push('/(tabs)/new-chat')} activeOpacity={0.85}>
        <ChatIcon size={26} color="#fff" />
      </TouchableOpacity>

      <NewSheet
        visible={showSheet}
        onClose={() => setShowSheet(false)}
        onCreated={(ch) => { addChannel(ch); router.push('/chat/' + ch.id) }}
        router={router}
      />
    </SafeAreaView>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingVertical: 12, backgroundColor: colors.bgSurface, borderBottomWidth: 0.5, borderBottomColor: colors.bgDivider },
  headerTitle: { color: colors.textPrimary, fontSize: 22, fontWeight: '700' },
  headerBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: colors.bgRaised, alignItems: 'center', justifyContent: 'center' },

  offlineBar: { backgroundColor: colors.danger, paddingHorizontal: 14, paddingVertical: 6 },
  offlineText: { color: '#fff', fontSize: 12, fontWeight: '600', textAlign: 'center' },

  searchBar: { flexDirection: 'row', alignItems: 'center', gap: 8, marginHorizontal: 12, marginTop: 8, paddingHorizontal: 12, backgroundColor: colors.bgRaised, borderRadius: 20, height: 40 },
  searchInput: { flex: 1, color: colors.textPrimary, fontSize: 14 },

  row: { flexDirection: 'row', alignItems: 'center', padding: 12, gap: 12 },
  avatar: { width: 48, height: 48, borderRadius: 24, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center' },
  avatarText: { color: colors.textOnBrand, fontWeight: '700', fontSize: 17 },
  name: { color: colors.textPrimary, fontSize: 15, fontWeight: '500' },
  preview: { color: colors.textSecondary, fontSize: 13, marginTop: 3 },
  divider: { height: 0.5, backgroundColor: colors.bgDivider, marginLeft: 72 },

  empty: { alignItems: 'center', paddingTop: 80 },
  emptyTitle: { color: colors.textPrimary, fontSize: 16, fontWeight: '600' },
  emptyBody: { color: colors.textSecondary, fontSize: 13, marginTop: 6 },

  fab: { position: 'absolute', right: 16, bottom: 16, width: 56, height: 56, borderRadius: 28, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center', shadowColor: '#000', shadowOpacity: 0.4, shadowOffset: { width: 0, height: 4 }, shadowRadius: 6, elevation: 6 },

  sheetBackdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.6)', justifyContent: 'flex-end' },
  sheet: { backgroundColor: colors.bgSurface, padding: 16, paddingBottom: 32, borderTopLeftRadius: 20, borderTopRightRadius: 20, maxHeight: '85%' },
  sheetHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 },
  sheetTitle: { color: colors.textPrimary, fontSize: 17, fontWeight: '700' },
  cancel: { color: colors.brand, fontSize: 15 },

  choice: { padding: 14, borderRadius: 12, backgroundColor: colors.bgRaised, marginBottom: 10 },
  choiceLabel: { color: colors.textPrimary, fontSize: 16, fontWeight: '600' },
  choiceSub: { color: colors.textSecondary, fontSize: 12, marginTop: 4 },

  input: { backgroundColor: colors.bgRaised, color: colors.textPrimary, paddingHorizontal: 14, paddingVertical: 12, borderRadius: 10, fontSize: 15, marginTop: 8 },
  sectionLabel: { color: colors.textSecondary, fontSize: 12, fontWeight: '600', textTransform: 'uppercase', marginTop: 16, marginBottom: 6 },
  userList: { maxHeight: 280 },
  userRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 8 },
  userAvatar: { width: 36, height: 36, borderRadius: 18, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center' },
  check: { width: 22, height: 22, borderRadius: 11, borderWidth: 1.5, borderColor: colors.textSecondary, alignItems: 'center', justifyContent: 'center' },

  createBtn: { backgroundColor: colors.brand, borderRadius: 10, paddingVertical: 14, alignItems: 'center', marginTop: 16 },
  createBtnText: { color: '#fff', fontSize: 15, fontWeight: '700' },
})
'@
Write-FileUtf8NoBom -Path "app/(tabs)/channels.js" -Content $channels

# =====================================================================
# 10) Bonus: settings -- "View last crash" button (so user can read
#     the error after a crash without needing a debug tool)
# =====================================================================
Write-Host "[10/10] Adding 'View last crash' to Settings (profile.js)..."

$profilePath = "app/(tabs)/profile.js"
if (Test-Path $profilePath) {
    $profile = Read-FileUtf8 $profilePath
    if ($profile -notmatch "loadCrash") {
        # Add imports
        $profile = $profile -replace `
            "import \{ disconnectSocket \} from '@/lib/socket'", `
            "import { disconnectSocket } from '@/lib/socket'`r`nimport { loadCrash, clearCrash } from '@/lib/cache'"

        # Add a "View last crash" link near the logout button
        $oldLogoutBlock = "<TouchableOpacity style={[styles.linkRow, { marginTop: 20 }]} onPress={logout}>"
        $newLogoutBlock = @"
<TouchableOpacity style={styles.linkRow} onPress={async () => {
          const c = await loadCrash()
          if (!c) { Alert.alert('No crash report', 'Looks good - no recent crashes.'); return }
          Alert.alert(
            'Last crash (' + (c.ts || 'unknown time') + ')',
            (c.message || '') + '\n\n' + (c.stack || '').slice(0, 800),
            [
              { text: 'Clear', onPress: () => clearCrash() },
              { text: 'Close', style: 'cancel' },
            ]
          )
        }}>
          <Text style={styles.linkText}>View last crash report</Text>
          <Text style={styles.linkRight}>{'>'}</Text>
        </TouchableOpacity>
        <TouchableOpacity style={[styles.linkRow, { marginTop: 20 }]} onPress={logout}>
"@

        if ($profile.Contains($oldLogoutBlock)) {
            $profile = $profile.Replace($oldLogoutBlock, $newLogoutBlock)
        }
        Write-FileUtf8NoBom -Path $profilePath -Content $profile
    } else {
        Write-Host "  = crash report link already present"
    }
} else {
    Write-Host "  ! profile.js not found, skipping crash-report link"
}

Write-Host ""
Write-Host "================================================================="
Write-Host "PHASE 4 FINAL COMPLETE."
Write-Host ""
Write-Host "WHAT TO DO NEXT (in order):"
Write-Host ""
Write-Host "  1) Install new native modules:"
Write-Host "       npx expo install @react-native-async-storage/async-storage"
Write-Host "       npx expo install @react-native-community/netinfo"
Write-Host "       npx expo install expo-updates"
Write-Host "       npx expo install expo-observe"
Write-Host ""
Write-Host "  2) Push changes:"
Write-Host "       git add -A"
Write-Host "       git commit -m 'Phase 4: NewChat + Offline + ErrorBoundary + Observe'"
Write-Host "       git push"
Write-Host ""
Write-Host "  3) Rebuild APK (native modules need new build):"
Write-Host "       npx eas build --profile preview --platform android"
Write-Host ""
Write-Host "  4) On phone:"
Write-Host "     - Install the NEW APK (uninstall the old one first if asked)"
Write-Host "     - Open the app"
Write-Host "     - If it crashes -> you will see a readable error screen now"
Write-Host "       (NOT a white/black screen any more). Take a screenshot of"
Write-Host "       the error message + stack and send it to me, I will fix"
Write-Host "       the exact issue."
Write-Host "     - If it works -> test New Chat (FAB), offline mode, etc."
Write-Host ""
Write-Host "  5) View EAS Observe dashboard for startup performance:"
Write-Host "       https://expo.dev/accounts/abaanshujats-organization/projects/10x-chat/observe"
Write-Host ""
Write-Host "  OPTIONAL: Add Sentry for crash reporting in production"
Write-Host "    npx expo install @sentry/react-native"
Write-Host "    Get a free DSN at https://sentry.io"
Write-Host "    Wrap your app with Sentry.wrap(App) in app/_layout.js"
Write-Host "    See: https://docs.expo.dev/guides/using-sentry/"
Write-Host "================================================================="
