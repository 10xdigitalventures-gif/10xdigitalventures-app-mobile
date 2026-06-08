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