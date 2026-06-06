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