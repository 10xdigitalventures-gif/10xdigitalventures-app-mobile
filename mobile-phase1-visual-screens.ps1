# =====================================================================
# Mobile App Phase 1: Visual overhaul + Settings + New Group + Calls history
#
# Stack: Expo + React Native + expo-router + Zustand
# Build mode: Expo Go (no native modules required for this phase)
#
# WHAT THIS PHASE DELIVERS:
#  1) Color theme:  blue (#185FA5) -> WhatsApp green (#1db791) everywhere
#  2) WhatsApp-style chat bubbles (sent right green, received left grey)
#  3) Ticks (sent / delivered / read) using react-native-svg
#  4) Slim reaction popup (long-press a message)
#  5) Proper image/file rendering (not just filename text)
#  6) FlatList `inverted` -> proper auto-scroll, top/bottom fixed
#  7) Tabs reorganized like WhatsApp: Chats | Calls | Groups | Settings
#  8) Calls tab with history (GET /calls)
#  9) New Group modal (multi-select users -> POST /channels/group)
# 10) Settings screen polished (profile + theme accent + logout)
#
# WHAT THIS PHASE DOES NOT DO (Phase 2):
#  - 1:1 voice/video calls (needs react-native-webrtc, custom dev build)
#  - Group calls
#
# Run from MOBILE repo root (the folder with package.json that says
# "10x-chat-mobile"):
#   powershell -ExecutionPolicy Bypass -File .\mobile-phase1-visual-screens.ps1
#   npx expo install react-native-svg     # if not already installed
#   npx expo start --clear
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

# ---------- Locate mobile repo ----------
if (-not (Test-Path "package.json")) {
    Write-Host "ERROR: Run from mobile repo root (folder with package.json)."
    exit 1
}
$pkg = Get-Content "package.json" -Raw
if ($pkg -notmatch '"10x-chat-mobile"' -and $pkg -notmatch 'expo-router') {
    Write-Host "WARNING: This does not look like the mobile app folder."
    Write-Host "         package.json does not mention 10x-chat-mobile or expo-router."
    Write-Host "         Continuing anyway..."
}

Write-Host "==================================================="
Write-Host "Mobile App Phase 1 -- Visual + Screens"
Write-Host "==================================================="
Write-Host ""

# =====================================================================
# 1) lib/theme.js -- central color tokens (WhatsApp green)
# =====================================================================
Write-Host "[1/9] Creating lib/theme.js (color tokens)..."

$theme = @'
// Centralized theme tokens. Import { colors } from '@/lib/theme'.
// WhatsApp-inspired green accent on dark background.

export const colors = {
  // Backgrounds (dark mode default)
  bg:          '#0b141a',   // main app bg
  bgSurface:   '#111b21',   // headers, tab bar
  bgRaised:    '#1f2c33',   // cards, inputs
  bgDivider:   '#2a3942',

  // Brand accent (WhatsApp greens)
  brand:       '#1db791',   // primary
  brandDark:   '#17a884',
  brandLight:  '#25d366',   // WhatsApp signature
  brandFaint:  '#1db79122',

  // Bubble colors (WhatsApp Web dark)
  bubbleSent:     '#005c4b', // your messages (right)
  bubbleReceived: '#202c33', // their messages (left)

  // Text
  textPrimary:    '#e9edef',
  textSecondary:  '#8696a0',
  textTertiary:   '#667781',
  textOnBrand:    '#06291f',
  textInverted:   '#0b141a',

  // Status
  online:    '#1db791',
  away:      '#ffa726',
  danger:    '#f15c6d',
  dangerDark:'#e04658',
  read:      '#53bdeb',   // blue ticks
  pending:   '#8696a0',   // gray ticks

  // Misc
  white:     '#ffffff',
  black:     '#000000',
  overlay:   'rgba(0,0,0,0.85)',
  ripple:    'rgba(255,255,255,0.08)',
}

export const radius = { sm: 6, md: 10, lg: 14, xl: 20, pill: 999 }
export const spacing = { xs: 4, sm: 8, md: 12, lg: 16, xl: 24 }
export const fontSize = { xs: 11, sm: 13, md: 15, lg: 17, xl: 20, xxl: 24 }
'@
Write-FileUtf8NoBom -Path "lib/theme.js" -Content $theme

# =====================================================================
# 2) components/icons.js -- SVG icons (no emoji as icons)
# =====================================================================
Write-Host "[2/9] Creating components/icons.js (SVG icon set)..."

$icons = @'
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
'@
Write-FileUtf8NoBom -Path "components/icons.js" -Content $icons

# =====================================================================
# 3) components/MessageBubble.js -- WhatsApp-style bubble
# =====================================================================
Write-Host "[3/9] Creating components/MessageBubble.js (WA-style bubble)..."

$bubble = @'
import React, { useState } from 'react'
import { View, Text, TouchableOpacity, Image, StyleSheet, Linking, Modal, Pressable } from 'react-native'
import { format } from 'date-fns'
import useChatStore from '@/store/chatStore'
import { getSocket } from '@/lib/socket'
import { colors, radius } from '@/lib/theme'
import { TickSingle, TickDouble, FileIcon } from '@/components/icons'

const QUICK_EMOJIS = ['\u{1F44D}', '\u2764\uFE0F', '\u{1F602}', '\u{1F62E}', '\u{1F625}', '\u{1F64F}']

function mediaUrlOf(msg) {
  const u = msg.file_url || msg.content || ''
  if (!u) return ''
  if (/^https?:\/\//.test(u)) return u
  // assume backend serves uploads at API_HOST/uploads/...
  const base = (process.env.EXPO_PUBLIC_API_URL || 'https://api.10xdigitalventures.com/api').replace(/\/api\/?$/, '')
  return base + (u.startsWith('/') ? u : '/uploads/' + u)
}

function fmtSize(b) {
  if (!b) return ''
  const kb = b / 1024
  return kb < 1024 ? Math.round(kb) + ' KB' : (kb / 1024).toFixed(1) + ' MB'
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

export default function MessageBubble({ msg, channelId, currentUserId }) {
  const { updateReaction, deleteMessage } = useChatStore()
  const [showPicker, setShowPicker] = useState(false)
  const isOwn = msg.sender_id === currentUserId
  const time  = msg.created_at ? format(new Date(msg.created_at), 'h:mm a') : ''
  const url   = mediaUrlOf(msg)

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

  const toggle = async (emoji) => {
    const rx = msg.reactions || []
    const has = rx.some(r => r.emoji === emoji && r.user_id === currentUserId)
    updateReaction(channelId, msg.id, emoji, currentUserId, has ? 'removed' : 'added')
    const sock = await getSocket(); sock.emit('reaction:toggle', { message_id: msg.id, channel_id: channelId, emoji })
  }

  const onLongPress = () => setShowPicker(true)

  const renderBody = () => {
    if (msg.type === 'image') {
      return (
        <TouchableOpacity onPress={() => Linking.openURL(url)} activeOpacity={0.9}>
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
    return <Text style={styles.text}>{msg.content}</Text>
  }

  return (
    <>
      <View style={[styles.row, isOwn ? styles.rowRight : styles.rowLeft]}>
        <TouchableOpacity activeOpacity={0.92} onLongPress={onLongPress}
          style={[styles.bubble, isOwn ? styles.bubbleSent : styles.bubbleReceived]}>
          {!isOwn && <Text style={styles.sender}>{msg.sender_name}</Text>}
          {renderBody()}
          <View style={styles.footer}>
            <Text style={styles.time}>{time}{msg.is_edited === 1 ? '  edited' : ''}</Text>
            <Status isOwn={isOwn} status={msg.status} />
          </View>
          {Object.keys(grouped).length > 0 && (
            <View style={styles.reactionsRow}>
              {Object.entries(grouped).map(([e, users]) => (
                <TouchableOpacity key={e} onPress={() => toggle(e)}
                  style={[styles.chip, users.includes(currentUserId) && styles.chipActive]}>
                  <Text style={{ fontSize: 13 }}>{e}</Text>
                  {users.length > 1 && <Text style={styles.chipCount}>{users.length}</Text>}
                </TouchableOpacity>
              ))}
            </View>
          )}
        </TouchableOpacity>
      </View>

      <Modal transparent visible={showPicker} animationType="fade" onRequestClose={() => setShowPicker(false)}>
        <Pressable style={styles.pickerBackdrop} onPress={() => setShowPicker(false)}>
          <Pressable style={styles.pickerCard}>
            <View style={styles.pickerRow}>
              {QUICK_EMOJIS.map(e => (
                <TouchableOpacity key={e} onPress={() => { toggle(e); setShowPicker(false) }}
                  style={styles.pickerBtn}>
                  <Text style={{ fontSize: 28 }}>{e}</Text>
                </TouchableOpacity>
              ))}
            </View>
            {isOwn && (
              <TouchableOpacity style={styles.pickerDelete}
                onPress={async () => {
                  setShowPicker(false)
                  const sock = await getSocket()
                  sock.emit('message:delete', { message_id: msg.id, channel_id: channelId })
                  deleteMessage(channelId, msg.id)
                }}>
                <Text style={{ color: colors.danger, fontSize: 15, fontWeight: '600' }}>Delete message</Text>
              </TouchableOpacity>
            )}
          </Pressable>
        </Pressable>
      </Modal>
    </>
  )
}

const styles = StyleSheet.create({
  row: { paddingHorizontal: 10, marginVertical: 2, flexDirection: 'row' },
  rowRight: { justifyContent: 'flex-end' },
  rowLeft:  { justifyContent: 'flex-start' },
  bubble: { maxWidth: '78%', borderRadius: 8, paddingHorizontal: 10, paddingTop: 6, paddingBottom: 6 },
  bubbleSent:     { backgroundColor: colors.bubbleSent,     borderBottomRightRadius: 2 },
  bubbleReceived: { backgroundColor: colors.bubbleReceived, borderBottomLeftRadius: 2 },
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

  pickerBackdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.6)', justifyContent: 'center', alignItems: 'center', padding: 24 },
  pickerCard: { backgroundColor: colors.bgRaised, borderRadius: 20, padding: 12, minWidth: 280, borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)' },
  pickerRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 4 },
  pickerBtn: { padding: 6, borderRadius: 999 },
  pickerDelete: { marginTop: 8, paddingTop: 12, paddingBottom: 6, borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.06)', alignItems: 'center' },
})
'@
Write-FileUtf8NoBom -Path "components/MessageBubble.js" -Content $bubble

# =====================================================================
# 4) app/chat/[channelId].js -- rewrite with inverted FlatList + WA UI
# =====================================================================
Write-Host "[4/9] Rewriting app/chat/[channelId].js (inverted scroll + WA UI)..."

$chat = @'
import { useEffect, useRef, useState } from 'react'
import {
  View, Text, FlatList, TextInput, TouchableOpacity, StyleSheet,
  KeyboardAvoidingView, Platform, ActivityIndicator, Alert
} from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { useLocalSearchParams, useRouter } from 'expo-router'
import * as ImagePicker from 'expo-image-picker'
import * as DocumentPicker from 'expo-document-picker'
import useChatStore from '@/store/chatStore'
import { getSocket } from '@/lib/socket'
import api from '@/lib/api'
import { colors, radius } from '@/lib/theme'
import { BackIcon, AttachIcon, SendIcon, PhoneIcon, VideoIcon, SmileIcon } from '@/components/icons'
import MessageBubble from '@/components/MessageBubble'

export default function ChatScreen() {
  const { channelId } = useLocalSearchParams()
  const router = useRouter()
  const { channels, messages, user, setMessages, typingUsers, members, setMembers } = useChatStore()
  const [text, setText] = useState('')
  const [loading, setLoading] = useState(true)
  const [sending, setSending] = useState(false)
  const listRef = useRef(null)
  const typingRef = useRef(null)

  const channel = channels.find(c => c.id === channelId)
  const channelMessages = (messages[channelId] || [])
  // FlatList inverted -> we display newest first; pass reversed copy
  const data = [...channelMessages].reverse()
  const isDM = channel?.type === 'dm'
  const typingInChannel = typingUsers[channelId]
    ? [...typingUsers[channelId]].filter(id => id !== user?.id)
    : []

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

      // Emit read receipts for unread incoming messages
      const unread = list
        .filter(m => m.sender_id !== user?.id && (!Array.isArray(m.status) || !m.status.some(s => s.user_id === user?.id && s.read_at)))
        .map(m => m.id)
      if (unread.length > 0) {
        getSocket().then(s => s.emit('message:read', { channel_id: channelId, message_ids: unread }))
      }
    }).catch(() => setLoading(false))
  }, [channelId])

  // Mark new incoming messages as read when they arrive while screen is open
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
    const sock = await getSocket()
    sock.emit('message:send', { channel_id: channelId, content: text.trim(), type: 'text' })
    sock.emit('typing:stop', { channel_id: channelId })
    setText('')
    setSending(false)
  }

  const pickFile = () => {
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
      await api.post(`/files/upload/${channelId}`, fd, { headers: { 'Content-Type': 'multipart/form-data' } })
      // Backend (post Part 3 web fixes) emits message:new itself, so no extra socket call needed.
    } catch (e) {
      Alert.alert('Upload failed', e?.message || 'Could not upload file')
    }
  }

  const subtitle = typingInChannel.length > 0
    ? 'typing...'
    : isDM ? 'online' : `${members?.length || 0} members`

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.iconBtn}><BackIcon color={colors.textPrimary} /></TouchableOpacity>
        <View style={styles.avatar}><Text style={styles.avatarText}>{(channel?.name || '?')[0].toUpperCase()}</Text></View>
        <View style={{ flex: 1 }}>
          <Text style={styles.title} numberOfLines={1}>{channel?.name || 'Chat'}</Text>
          <Text style={[styles.subtitle, typingInChannel.length > 0 && { color: colors.brand }]} numberOfLines={1}>{subtitle}</Text>
        </View>
        <TouchableOpacity style={styles.iconBtn} onPress={() => Alert.alert('Coming soon', 'Voice calls arrive in Phase 2')}><PhoneIcon color={colors.textPrimary} /></TouchableOpacity>
        <TouchableOpacity style={styles.iconBtn} onPress={() => Alert.alert('Coming soon', 'Video calls arrive in Phase 2')}><VideoIcon color={colors.textPrimary} /></TouchableOpacity>
      </View>

      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        {loading ? (
          <View style={styles.center}><ActivityIndicator color={colors.brand} size="large" /></View>
        ) : (
          <FlatList
            ref={listRef}
            data={data}
            inverted
            keyExtractor={item => item.id}
            renderItem={({ item }) => <MessageBubble msg={item} channelId={channelId} currentUserId={user?.id} />}
            contentContainerStyle={{ paddingVertical: 8 }}
            keyboardShouldPersistTaps="handled"
            ListEmptyComponent={
              <View style={[styles.center, { transform: [{ scaleY: -1 }], paddingTop: 80 }]}>
                <Text style={styles.emptyTitle}>{isDM ? channel?.name : '#' + (channel?.name || '')}</Text>
                <Text style={styles.emptyBody}>Send a message to start the conversation.</Text>
              </View>
            }
          />
        )}

        {typingInChannel.length > 0 && (
          <View style={styles.typingBar}><Text style={styles.typingText}>typing...</Text></View>
        )}

        {/* Input row */}
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
          <TouchableOpacity onPress={send} disabled={!text.trim()}
            style={[styles.sendBtn, !text.trim() && { backgroundColor: colors.bgRaised }]}>
            <SendIcon color={!text.trim() ? colors.textTertiary : colors.white} size={20} />
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  emptyTitle: { color: colors.textPrimary, fontSize: 18, fontWeight: '700' },
  emptyBody: { color: colors.textSecondary, fontSize: 13, marginTop: 6 },

  header: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 8, paddingVertical: 8, gap: 6, backgroundColor: colors.bgSurface, borderBottomWidth: 0.5, borderBottomColor: colors.bgDivider },
  iconBtn: { width: 40, height: 40, alignItems: 'center', justifyContent: 'center', borderRadius: 999 },
  avatar: { width: 38, height: 38, borderRadius: 19, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center' },
  avatarText: { color: colors.textOnBrand, fontWeight: '700', fontSize: 15 },
  title: { color: colors.textPrimary, fontSize: 16, fontWeight: '600' },
  subtitle: { color: colors.textSecondary, fontSize: 12, marginTop: 1 },

  typingBar: { paddingHorizontal: 16, paddingVertical: 4 },
  typingText: { color: colors.brand, fontSize: 12, fontStyle: 'italic' },

  inputRow: { flexDirection: 'row', alignItems: 'flex-end', padding: 8, gap: 6, backgroundColor: colors.bgSurface, borderTopWidth: 0.5, borderTopColor: colors.bgDivider },
  inputIcon: { padding: 8 },
  inputBox: { flex: 1, flexDirection: 'row', alignItems: 'center', backgroundColor: colors.bgRaised, borderRadius: 22, paddingHorizontal: 6, paddingVertical: 4, minHeight: 40 },
  textInput: { flex: 1, color: colors.textPrimary, fontSize: 15, paddingVertical: 6, paddingHorizontal: 6, maxHeight: 120 },
  sendBtn: { width: 44, height: 44, borderRadius: 22, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center' },
})
'@
Write-FileUtf8NoBom -Path "app/chat/[channelId].js" -Content $chat

# =====================================================================
# 5) app/(tabs)/_layout.js -- WhatsApp-style tabs with SVG icons + green
# =====================================================================
Write-Host "[5/9] Rewriting app/(tabs)/_layout.js (green tabs + SVG icons)..."

$tabsLayout = @'
import { Tabs } from 'expo-router'
import { useEffect } from 'react'
import * as SecureStore from 'expo-secure-store'
import { useRouter } from 'expo-router'
import useChatStore from '@/store/chatStore'
import { getSocket, disconnectSocket } from '@/lib/socket'
import api from '@/lib/api'
import { colors } from '@/lib/theme'
import { ChatIcon, PhoneIcon, GroupIcon, SettingsIcon } from '@/components/icons'

export default function TabsLayout() {
  const router = useRouter()
  const {
    setUser, setChannels, addChannel, addMessage, updateMessage, deleteMessage,
    updateReaction, setUserOnline, setUserOffline, setTyping,
  } = useChatStore()

  useEffect(() => {
    const init = async () => {
      const token = await SecureStore.getItemAsync('token')
      if (!token) { router.replace('/(auth)/login'); return }

      try {
        const [meRes, chRes] = await Promise.all([api.get('/auth/me'), api.get('/channels')])
        setUser(meRes.data?.data || meRes.data)
        setChannels(Array.isArray(chRes.data?.data) ? chRes.data.data : Array.isArray(chRes.data) ? chRes.data : [])

        const socket = await getSocket()
        socket.emit('join:channels')
        socket.on('message:new', msg => addMessage(msg.channel_id, msg))
        socket.on('message:edited', ({ message_id, channel_id, content }) => updateMessage(channel_id, message_id, { content, is_edited: 1 }))
        socket.on('message:deleted', ({ message_id, channel_id }) => deleteMessage(channel_id, message_id))
        socket.on('reaction:updated', ({ message_id, channel_id, emoji, user_id, action }) => updateReaction(channel_id, message_id, emoji, user_id, action))
        socket.on('user:online',  ({ user_id }) => setUserOnline(user_id))
        socket.on('user:offline', ({ user_id }) => setUserOffline(user_id))
        socket.on('typing:start', ({ user_id, channel_id }) => setTyping(channel_id, user_id, true))
        socket.on('typing:stop',  ({ user_id, channel_id }) => setTyping(channel_id, user_id, false))
        socket.on('channel:new',  (ch) => { addChannel(ch); socket.emit('join:channels') })
      } catch {
        router.replace('/(auth)/login')
      }
    }
    init()
    return () => disconnectSocket()
  }, [])

  return (
    <Tabs screenOptions={{
      headerShown: false,
      tabBarStyle: { backgroundColor: colors.bgSurface, borderTopColor: colors.bgDivider, borderTopWidth: 0.5, height: 60, paddingTop: 6, paddingBottom: 8 },
      tabBarActiveTintColor: colors.brand,
      tabBarInactiveTintColor: colors.textSecondary,
      tabBarLabelStyle: { fontSize: 11, fontWeight: '500' },
    }}>
      <Tabs.Screen name="channels" options={{ title: 'Chats',    tabBarIcon: ({ color }) => <ChatIcon     size={24} color={color} /> }} />
      <Tabs.Screen name="calls"    options={{ title: 'Calls',    tabBarIcon: ({ color }) => <PhoneIcon    size={24} color={color} /> }} />
      <Tabs.Screen name="dms"      options={{ title: 'Direct',   tabBarIcon: ({ color }) => <GroupIcon    size={24} color={color} /> }} />
      <Tabs.Screen name="profile"  options={{ title: 'Settings', tabBarIcon: ({ color }) => <SettingsIcon size={24} color={color} /> }} />
      {/* Hide the files tab from bottom bar; it is reachable from chat header */}
      <Tabs.Screen name="files"    options={{ href: null }} />
    </Tabs>
  )
}
'@
Write-FileUtf8NoBom -Path "app/(tabs)/_layout.js" -Content $tabsLayout

# =====================================================================
# 6) app/(tabs)/calls.js -- NEW: Calls history screen
# =====================================================================
Write-Host "[6/9] Creating app/(tabs)/calls.js (history list)..."

$callsScreen = @'
import { useEffect, useState, useCallback } from 'react'
import { View, Text, FlatList, TouchableOpacity, StyleSheet, RefreshControl } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { format } from 'date-fns'
import api from '@/lib/api'
import { colors } from '@/lib/theme'
import { PhoneIcon, VideoIcon } from '@/components/icons'

function fmtTime(ts) {
  if (!ts) return ''
  try { return format(new Date(ts), 'h:mm a, d MMM') } catch { return '' }
}
function fmtDuration(s) {
  if (!s) return ''
  const m = Math.floor(s/60), sec = s%60
  return m + ':' + String(sec).padStart(2,'0')
}

function CallRow({ item }) {
  const isVideo = item.type === 'video'
  const dirColor = item.status === 'missed' ? colors.danger
                : item.direction === 'out'  ? colors.brand
                : colors.textSecondary
  const arrow = item.direction === 'out' ? '\u2197' : '\u2199'  // up-right / down-left

  return (
    <View style={styles.row}>
      <View style={styles.avatar}><Text style={styles.avatarText}>{(item.peer_name || '?')[0].toUpperCase()}</Text></View>
      <View style={{ flex: 1 }}>
        <Text style={[styles.name, item.status === 'missed' && { color: colors.danger }]}>{item.peer_name || 'Unknown'}</Text>
        <View style={styles.metaRow}>
          <Text style={[styles.arrow, { color: dirColor }]}>{arrow}</Text>
          <Text style={styles.meta}>{fmtTime(item.created_at)}{item.duration ? '  -  ' + fmtDuration(item.duration) : ''}</Text>
        </View>
      </View>
      <TouchableOpacity style={styles.callBtn}>
        {isVideo ? <VideoIcon size={22} color={colors.brand} /> : <PhoneIcon size={22} color={colors.brand} />}
      </TouchableOpacity>
    </View>
  )
}

export default function CallsScreen() {
  const [calls, setCalls] = useState([])
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)

  const load = useCallback(async () => {
    try {
      const r = await api.get('/calls')
      const list = Array.isArray(r.data?.data) ? r.data.data : (Array.isArray(r.data) ? r.data : [])
      setCalls(list)
    } catch {}
    setLoading(false)
  }, [])

  useEffect(() => { load() }, [load])

  const onRefresh = async () => { setRefreshing(true); await load(); setRefreshing(false) }

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.header}><Text style={styles.headerTitle}>Calls</Text></View>
      <FlatList
        data={calls}
        keyExtractor={(item, i) => item.id || String(i)}
        renderItem={CallRow}
        ItemSeparatorComponent={() => <View style={styles.divider} />}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.brand} />}
        ListEmptyComponent={
          loading ? null : (
            <View style={styles.empty}>
              <Text style={styles.emptyTitle}>No call history yet</Text>
              <Text style={styles.emptyBody}>Voice and video calls arrive in Phase 2.{'\n'}History will appear here.</Text>
            </View>
          )
        }
      />
    </SafeAreaView>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  header: { paddingHorizontal: 16, paddingVertical: 14, backgroundColor: colors.bgSurface, borderBottomWidth: 0.5, borderBottomColor: colors.bgDivider },
  headerTitle: { color: colors.textPrimary, fontSize: 22, fontWeight: '700' },
  row: { flexDirection: 'row', alignItems: 'center', padding: 12, gap: 12 },
  avatar: { width: 48, height: 48, borderRadius: 24, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center' },
  avatarText: { color: colors.textOnBrand, fontWeight: '700', fontSize: 17 },
  name: { color: colors.textPrimary, fontSize: 15, fontWeight: '500' },
  metaRow: { flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 3 },
  arrow: { fontSize: 13 },
  meta: { color: colors.textSecondary, fontSize: 12 },
  callBtn: { padding: 10 },
  divider: { height: 0.5, backgroundColor: colors.bgDivider, marginLeft: 72 },
  empty: { alignItems: 'center', paddingTop: 80, paddingHorizontal: 30 },
  emptyTitle: { color: colors.textPrimary, fontSize: 16, fontWeight: '600' },
  emptyBody: { color: colors.textSecondary, fontSize: 13, marginTop: 8, textAlign: 'center', lineHeight: 19 },
})
'@
Write-FileUtf8NoBom -Path "app/(tabs)/calls.js" -Content $callsScreen

# =====================================================================
# 7) app/(tabs)/channels.js -- polish: green, WA-style rows, "New" FAB
#    that opens a modal supporting both channel + group creation
# =====================================================================
Write-Host "[7/9] Rewriting app/(tabs)/channels.js (WA-style + New Group)..."

$channelsScreen = @'
import { useState } from 'react'
import {
  View, Text, FlatList, TouchableOpacity, StyleSheet, TextInput,
  Modal, Alert, ActivityIndicator, ScrollView
} from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { useRouter } from 'expo-router'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import { colors, radius } from '@/lib/theme'
import { PlusIcon, SearchIcon, GroupIcon } from '@/components/icons'

function Avatar({ name, isGroup }) {
  return (
    <View style={[styles.avatar, isGroup && { backgroundColor: colors.bgRaised }]}>
      {isGroup
        ? <GroupIcon size={22} color={colors.brand} />
        : <Text style={styles.avatarText}>{(name || '?')[0].toUpperCase()}</Text>}
    </View>
  )
}

function NewSheet({ visible, onClose, onCreated }) {
  const [mode, setMode] = useState(null) // 'channel' | 'group'
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
              <TouchableOpacity style={styles.choice} onPress={() => setMode('channel')}>
                <Text style={styles.choiceLabel}>#  New Channel</Text>
                <Text style={styles.choiceSub}>A public room anyone in workspace can join</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.choice} onPress={openGroup}>
                <Text style={styles.choiceLabel}>{'\u{1F465}'}  New Group</Text>
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
  const { channels, addChannel } = useChatStore()
  const safe = Array.isArray(channels) ? channels : []
  const [showSheet, setShowSheet] = useState(false)
  const [query, setQuery] = useState('')

  const filtered = safe.filter(c => !query || (c.name || '').toLowerCase().includes(query.toLowerCase()))

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>10x Chat</Text>
        <TouchableOpacity style={styles.headerBtn} onPress={() => setShowSheet(true)}><PlusIcon color={colors.textPrimary} /></TouchableOpacity>
      </View>

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
          <TouchableOpacity style={styles.row} onPress={() => router.push(`/chat/${item.id}`)}>
            <Avatar name={item.name} isGroup={item.type !== 'dm'} />
            <View style={{ flex: 1 }}>
              <Text style={styles.name} numberOfLines={1}>{item.type === 'public' ? '# ' + item.name : item.name}</Text>
              <Text style={styles.preview} numberOfLines={1}>{item.topic || 'Tap to open conversation'}</Text>
            </View>
          </TouchableOpacity>
        )}
        ItemSeparatorComponent={() => <View style={styles.divider} />}
        ListEmptyComponent={
          <View style={styles.empty}>
            <Text style={styles.emptyTitle}>No chats yet</Text>
            <Text style={styles.emptyBody}>Tap + to create a new channel or group</Text>
          </View>
        }
      />

      <NewSheet
        visible={showSheet}
        onClose={() => setShowSheet(false)}
        onCreated={(ch) => { addChannel(ch); router.push(`/chat/${ch.id}`) }}
      />
    </SafeAreaView>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingVertical: 12, backgroundColor: colors.bgSurface, borderBottomWidth: 0.5, borderBottomColor: colors.bgDivider },
  headerTitle: { color: colors.textPrimary, fontSize: 22, fontWeight: '700' },
  headerBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: colors.bgRaised, alignItems: 'center', justifyContent: 'center' },

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
Write-FileUtf8NoBom -Path "app/(tabs)/channels.js" -Content $channelsScreen

# =====================================================================
# 8) app/(tabs)/profile.js -- Settings polish (green + clean rows)
# =====================================================================
Write-Host "[8/9] Rewriting app/(tabs)/profile.js (Settings polish)..."

$profile = @'
import { useState } from 'react'
import {
  View, Text, TextInput, TouchableOpacity, StyleSheet, Alert,
  ActivityIndicator, ScrollView
} from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { useRouter } from 'expo-router'
import * as SecureStore from 'expo-secure-store'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import { disconnectSocket } from '@/lib/socket'
import { colors } from '@/lib/theme'
import { LogoutIcon } from '@/components/icons'

export default function ProfileScreen() {
  const router = useRouter()
  const { user, setUser } = useChatStore()
  const [name, setName] = useState(user?.name || '')
  const [bio, setBio] = useState(user?.bio || '')
  const [status, setStatus] = useState(user?.status || '')
  const [saving, setSaving] = useState(false)

  const save = async () => {
    setSaving(true)
    try {
      // Try the auth profile endpoint first (web backend exposes /auth/profile),
      // fall back to /users/profile (older route).
      try { await api.put('/auth/profile', { name, bio, status }) }
      catch { await api.put('/users/profile', { name, bio, status }) }
      setUser({ ...user, name, bio, status })
      Alert.alert('Saved', 'Profile updated')
    } catch (e) {
      Alert.alert('Error', e?.response?.data?.message || 'Could not save profile')
    }
    setSaving(false)
  }

  const logout = () => {
    Alert.alert('Logout', 'Are you sure?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Logout', style: 'destructive',
        onPress: async () => {
          disconnectSocket()
          await SecureStore.deleteItemAsync('token')
          await SecureStore.deleteItemAsync('user')
          router.replace('/(auth)/login')
        }
      }
    ])
  }

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <ScrollView contentContainerStyle={{ paddingBottom: 24 }}>
        <View style={styles.header}><Text style={styles.headerTitle}>Settings</Text></View>

        {/* Profile card */}
        <View style={styles.profileCard}>
          <View style={styles.bigAvatar}>
            <Text style={styles.bigAvatarText}>{(user?.name || '?')[0].toUpperCase()}</Text>
          </View>
          <View style={{ flex: 1 }}>
            <Text style={styles.profileName}>{user?.name || 'You'}</Text>
            <Text style={styles.profileEmail}>{user?.email}</Text>
          </View>
        </View>

        {/* Profile editor */}
        <Text style={styles.sectionLabel}>Account</Text>
        <View style={styles.fieldCard}>
          <Text style={styles.fieldLabel}>Name</Text>
          <TextInput style={styles.field} value={name} onChangeText={setName} placeholder="Your name" placeholderTextColor={colors.textTertiary}/>
        </View>
        <View style={styles.fieldCard}>
          <Text style={styles.fieldLabel}>About</Text>
          <TextInput style={[styles.field, { minHeight: 60, textAlignVertical: 'top' }]} value={bio} onChangeText={setBio} placeholder="Tell people about you" placeholderTextColor={colors.textTertiary} multiline/>
        </View>
        <View style={styles.fieldCard}>
          <Text style={styles.fieldLabel}>Status</Text>
          <TextInput style={styles.field} value={status} onChangeText={setStatus} placeholder="Available" placeholderTextColor={colors.textTertiary}/>
        </View>

        <TouchableOpacity style={styles.primaryBtn} onPress={save} disabled={saving}>
          {saving ? <ActivityIndicator color="#fff" /> : <Text style={styles.primaryBtnText}>Save changes</Text>}
        </TouchableOpacity>

        <Text style={styles.sectionLabel}>App</Text>
        <TouchableOpacity style={styles.linkRow} onPress={() => Alert.alert('Coming soon', 'Theme settings will be available in a future update.')}>
          <Text style={styles.linkText}>Theme</Text>
          <Text style={styles.linkRight}>Dark</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.linkRow} onPress={() => Alert.alert('Coming soon', 'Notifications settings.')}>
          <Text style={styles.linkText}>Notifications</Text>
          <Text style={styles.linkRight}>{'>'}</Text>
        </TouchableOpacity>

        <TouchableOpacity style={[styles.linkRow, { marginTop: 20 }]} onPress={logout}>
          <LogoutIcon color={colors.danger} />
          <Text style={[styles.linkText, { color: colors.danger, marginLeft: 8 }]}>Log out</Text>
          <View style={{ flex: 1 }} />
        </TouchableOpacity>
      </ScrollView>
    </SafeAreaView>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  header: { paddingHorizontal: 16, paddingVertical: 14, backgroundColor: colors.bgSurface, borderBottomWidth: 0.5, borderBottomColor: colors.bgDivider },
  headerTitle: { color: colors.textPrimary, fontSize: 22, fontWeight: '700' },

  profileCard: { flexDirection: 'row', alignItems: 'center', gap: 14, padding: 18, backgroundColor: colors.bgSurface, marginTop: 8 },
  bigAvatar: { width: 72, height: 72, borderRadius: 36, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center' },
  bigAvatarText: { color: colors.textOnBrand, fontWeight: '700', fontSize: 28 },
  profileName: { color: colors.textPrimary, fontSize: 18, fontWeight: '700' },
  profileEmail: { color: colors.textSecondary, fontSize: 13, marginTop: 3 },

  sectionLabel: { color: colors.textSecondary, fontSize: 12, fontWeight: '700', textTransform: 'uppercase', marginTop: 22, marginHorizontal: 16, marginBottom: 6 },

  fieldCard: { backgroundColor: colors.bgSurface, paddingHorizontal: 16, paddingVertical: 10, borderTopWidth: 0.5, borderBottomWidth: 0.5, borderColor: colors.bgDivider, marginBottom: -0.5 },
  fieldLabel: { color: colors.textSecondary, fontSize: 12, marginBottom: 4 },
  field: { color: colors.textPrimary, fontSize: 15, padding: 0 },

  primaryBtn: { marginHorizontal: 16, marginTop: 18, backgroundColor: colors.brand, borderRadius: 10, paddingVertical: 14, alignItems: 'center' },
  primaryBtnText: { color: '#fff', fontWeight: '700', fontSize: 15 },

  linkRow: { flexDirection: 'row', alignItems: 'center', backgroundColor: colors.bgSurface, paddingHorizontal: 16, paddingVertical: 16, borderTopWidth: 0.5, borderBottomWidth: 0.5, borderColor: colors.bgDivider, marginBottom: -0.5 },
  linkText: { color: colors.textPrimary, fontSize: 15, flex: 1 },
  linkRight: { color: colors.textSecondary, fontSize: 14 },
})
'@
Write-FileUtf8NoBom -Path "app/(tabs)/profile.js" -Content $profile

# =====================================================================
# 9) app/(tabs)/dms.js + (auth)/login + register -- color sweep
# =====================================================================
Write-Host "[9/9] Color sweep on remaining files (blue -> green)..."

function ReplaceColors([string]$path) {
    if (-not (Test-Path $path)) { return }
    $t = Read-FileUtf8 $path
    $orig = $t
    # Replace all blue accent variants with green
    $t = $t.Replace("#185FA5", "#1db791")
    $t = $t.Replace("#185fa5", "#1db791")
    $t = $t.Replace("#185FA520", "#1db79122")
    $t = $t.Replace("#185fa520", "#1db79122")
    $t = $t.Replace("#b5d4f4", "#a7e9d7")
    if ($t -ne $orig) { Write-FileUtf8NoBom -Path $path -Content $t }
}

ReplaceColors "app/(tabs)/dms.js"
ReplaceColors "app/(tabs)/files.js"
ReplaceColors "app/(auth)/login.js"
ReplaceColors "app/(auth)/register.js"
ReplaceColors "app/index.js"
ReplaceColors "app/_layout.js"

Write-Host ""
Write-Host "================================================================="
Write-Host "PHASE 1 DONE."
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1) Install react-native-svg if not already (used by icons.js):"
Write-Host "     npx expo install react-native-svg"
Write-Host ""
Write-Host "  2) Clear Metro cache and restart:"
Write-Host "     npx expo start --clear"
Write-Host ""
Write-Host "What changed visually:"
Write-Host "  - All blue (#185FA5) -> WhatsApp green (#1db791)"
Write-Host "  - WhatsApp-style chat bubbles (sent right green, recv left grey)"
Write-Host "  - SVG ticks (sent / delivered / read) on your messages"
Write-Host "  - Long-press a message -> slim emoji reaction picker"
Write-Host "  - Images and files render properly (Image / file card)"
Write-Host "  - FlatList inverted: chat auto-scrolls to bottom, input fixed"
Write-Host "  - Tabs: Chats / Calls / Direct / Settings with SVG icons"
Write-Host "  - Calls tab shows call history from GET /calls"
Write-Host "  - + button on Chats -> New Channel or New Group (multi-select)"
Write-Host "  - Settings: profile editor, theme/notifs (placeholders), logout"
Write-Host ""
Write-Host "Phase 2 (not in this script): WebRTC voice/video for mobile."
Write-Host "  Requires: react-native-webrtc + EAS Dev Build."
Write-Host "================================================================="
