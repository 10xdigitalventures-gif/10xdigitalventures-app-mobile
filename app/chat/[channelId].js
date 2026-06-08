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