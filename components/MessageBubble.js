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