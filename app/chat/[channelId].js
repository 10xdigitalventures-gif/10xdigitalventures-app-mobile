import { useEffect, useRef, useState } from 'react'
import {
  View, Text, FlatList, TextInput, TouchableOpacity,
  StyleSheet, KeyboardAvoidingView, Platform,
  ActivityIndicator, Alert, ActionSheetIOS
} from 'react-native'
import { useLocalSearchParams, useRouter } from 'expo-router'
import * as ImagePicker from 'expo-image-picker'
import * as DocumentPicker from 'expo-document-picker'
import useChatStore from '@/store/chatStore'
import { getSocket } from '@/lib/socket'
import api from '@/lib/api'
import { format } from 'date-fns'

const EMOJIS = ['👍','❤️','😂','😮','😢','🔥','✅','👀']

function MessageBubble({ msg, channelId, currentUserId }) {
  const { updateMessage, deleteMessage, updateReaction } = useChatStore()
  const isOwn = msg.sender_id === currentUserId

  const longPress = async () => {
    if (!isOwn) return
    if (Platform.OS === 'ios') {
      ActionSheetIOS.showActionSheetWithOptions(
        { options: ['Cancel', 'Edit', 'Delete'], cancelButtonIndex: 0, destructiveButtonIndex: 2 },
        async (idx) => {
          if (idx === 1) promptEdit()
          if (idx === 2) confirmDelete()
        }
      )
    } else {
      Alert.alert('Message', 'Choose action', [
        { text: 'Edit', onPress: promptEdit },
        { text: 'Delete', onPress: confirmDelete, style: 'destructive' },
        { text: 'Cancel', style: 'cancel' },
      ])
    }
  }

  const promptEdit = () => {
    Alert.prompt('Edit Message', '', async (newText) => {
      if (!newText?.trim()) return
      const socket = await getSocket()
      socket.emit('message:edit', { message_id: msg.id, channel_id: channelId, content: newText })
      updateMessage(channelId, msg.id, { content: newText, is_edited: 1 })
    }, 'plain-text', msg.content)
  }

  const confirmDelete = () => {
    Alert.alert('Delete', 'Delete this message?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete', style: 'destructive', onPress: async () => {
          const socket = await getSocket()
          socket.emit('message:delete', { message_id: msg.id, channel_id: channelId })
          deleteMessage(channelId, msg.id)
        }
      }
    ])
  }

  const toggleReaction = async (emoji) => {
    const socket = await getSocket()
    socket.emit('reaction:toggle', { message_id: msg.id, channel_id: channelId, emoji })
  }

  if (msg.is_deleted) return (
    <View style={[styles.msgRow]}>
      <View style={styles.avatar}><Text style={styles.avatarText}>?</Text></View>
      <Text style={styles.deletedText}>Message deleted</Text>
    </View>
  )

  const groupedReactions = (msg.reactions || []).reduce((acc, r) => {
    acc[r.emoji] = acc[r.emoji] || []
    acc[r.emoji].push(r.user_id)
    return acc
  }, {})

  return (
    <TouchableOpacity style={styles.msgRow} onLongPress={longPress} activeOpacity={0.8}>
      <View style={styles.avatar}>
        <Text style={styles.avatarText}>{msg.sender_name?.[0]?.toUpperCase()}</Text>
      </View>
      <View style={styles.msgContent}>
        <View style={styles.msgHeader}>
          <Text style={styles.senderName}>{msg.sender_name}</Text>
          <Text style={styles.msgTime}>{msg.created_at ? format(new Date(msg.created_at), 'h:mm a') : ''}</Text>
          {msg.is_edited === 1 && <Text style={styles.editedBadge}>edited</Text>}
        </View>
        {msg.type === 'file' || msg.type === 'image' ? (
          <View style={styles.fileMsg}>
            <Text style={styles.fileIcon}>{msg.type === 'image' ? '🖼️' : '📎'}</Text>
            <Text style={styles.fileName}>{msg.content}</Text>
          </View>
        ) : (
          <Text style={styles.msgText}>{msg.content}</Text>
        )}
        {Object.keys(groupedReactions).length > 0 && (
          <View style={styles.reactionsRow}>
            {Object.entries(groupedReactions).map(([emoji, users]) => (
              <TouchableOpacity
                key={emoji}
                style={[styles.reactionChip, users.includes(currentUserId) && styles.reactionChipActive]}
                onPress={() => toggleReaction(emoji)}
              >
                <Text>{emoji} {users.length}</Text>
              </TouchableOpacity>
            ))}
          </View>
        )}
      </View>
    </TouchableOpacity>
  )
}

export default function ChatScreen() {
  const { channelId } = useLocalSearchParams()
  const router = useRouter()
  const { channels, messages, user, setMessages, typingUsers } = useChatStore()
  const [text, setText] = useState('')
  const [loading, setLoading] = useState(true)
  const [sending, setSending] = useState(false)
  const flatListRef = useRef(null)
  const typingRef = useRef(null)

  const channel = channels.find(c => c.id === channelId)
  const channelMessages = messages[channelId] || []
  const typingInChannel = typingUsers[channelId]
    ? [...typingUsers[channelId]].filter(id => id !== user?.id)
    : []

  useEffect(() => {
    api.get(`/messages/${channelId}`)
      .then(r => { setMessages(channelId, r.data); setLoading(false) })
      .catch(() => setLoading(false))
  }, [channelId])

  const handleTyping = async (val) => {
    setText(val)
    const socket = await getSocket()
    socket.emit('typing:start', { channel_id: channelId })
    clearTimeout(typingRef.current)
    typingRef.current = setTimeout(() => socket.emit('typing:stop', { channel_id: channelId }), 2000)
  }

  const sendMessage = async () => {
    if (!text.trim() || sending) return
    setSending(true)
    const socket = await getSocket()
    socket.emit('message:send', { channel_id: channelId, content: text.trim(), type: 'text' })
    socket.emit('typing:stop', { channel_id: channelId })
    setText('')
    setSending(false)
    setTimeout(() => flatListRef.current?.scrollToEnd({ animated: true }), 100)
  }

  const pickFile = async () => {
    Alert.alert('Attach', 'Choose file type', [
      {
        text: 'Image', onPress: async () => {
          const result = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ImagePicker.MediaTypeOptions.Images })
          if (!result.canceled) uploadFile(result.assets[0].uri, 'image/jpeg', 'photo.jpg')
        }
      },
      {
        text: 'Document', onPress: async () => {
          const result = await DocumentPicker.getDocumentAsync()
          if (!result.canceled && result.assets?.[0]) {
            const f = result.assets[0]
            uploadFile(f.uri, f.mimeType, f.name)
          }
        }
      },
      { text: 'Cancel', style: 'cancel' }
    ])
  }

  const uploadFile = async (uri, mimeType, name) => {
    try {
      const formData = new FormData()
      formData.append('file', { uri, type: mimeType, name })
      const { data } = await api.post(`/files/upload/${channelId}`, formData, {
        headers: { 'Content-Type': 'multipart/form-data' }
      })
      const socket = await getSocket()
      socket.emit('message:send', { channel_id: channelId, content: data.file_name, type: data.type, file_url: data.file_url })
    } catch {
      Alert.alert('Error', 'Upload failed')
    }
  }

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn}>
          <Text style={styles.backText}>‹</Text>
        </TouchableOpacity>
        <View style={styles.headerInfo}>
          <Text style={styles.headerTitle}>#{channel?.name || '...'}</Text>
          {channel?.topic && <Text style={styles.headerTopic} numberOfLines={1}>{channel.topic}</Text>}
        </View>
      </View>

      <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined} keyboardVerticalOffset={0}>
        {loading ? (
          <View style={styles.center}><ActivityIndicator color="#185FA5" size="large" /></View>
        ) : (
          <FlatList
            ref={flatListRef}
            data={channelMessages}
            keyExtractor={item => item.id}
            renderItem={({ item }) => <MessageBubble msg={item} channelId={channelId} currentUserId={user?.id} />}
            onContentSizeChange={() => flatListRef.current?.scrollToEnd({ animated: false })}
            contentContainerStyle={{ paddingVertical: 8 }}
            ListFooterComponent={
              typingInChannel.length > 0 ? (
                <View style={styles.typingRow}>
                  <Text style={styles.typingDots}>• • •</Text>
                  <Text style={styles.typingText}>Someone is typing</Text>
                </View>
              ) : null
            }
          />
        )}

        {/* Input */}
        <View style={styles.inputRow}>
          <TouchableOpacity onPress={pickFile} style={styles.attachBtn}>
            <Text style={styles.attachIcon}>+</Text>
          </TouchableOpacity>
          <TextInput
            style={styles.textInput}
            value={text}
            onChangeText={handleTyping}
            placeholder={`Message #${channel?.name || 'channel'}`}
            placeholderTextColor="#6b7280"
            multiline
          />
          <TouchableOpacity
            style={[styles.sendBtn, !text.trim() && styles.sendBtnDisabled]}
            onPress={sendMessage}
            disabled={!text.trim()}
          >
            <Text style={styles.sendIcon}>↑</Text>
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>
    </View>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0f1117' },
  flex: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', paddingTop: 52, paddingBottom: 12, paddingHorizontal: 12, borderBottomWidth: 0.5, borderBottomColor: '#2a2d35', backgroundColor: '#12141a', gap: 8 },
  backBtn: { padding: 4 },
  backText: { fontSize: 28, color: '#185FA5', lineHeight: 32 },
  headerInfo: { flex: 1 },
  headerTitle: { fontSize: 16, fontWeight: '700', color: '#fff' },
  headerTopic: { fontSize: 12, color: '#9ca3af', marginTop: 1 },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  msgRow: { flexDirection: 'row', padding: 12, paddingVertical: 8, gap: 10 },
  avatar: { width: 36, height: 36, borderRadius: 18, backgroundColor: '#185FA5', justifyContent: 'center', alignItems: 'center', flexShrink: 0, marginTop: 2 },
  avatarText: { color: '#fff', fontSize: 14, fontWeight: '600' },
  msgContent: { flex: 1 },
  msgHeader: { flexDirection: 'row', alignItems: 'baseline', gap: 6, marginBottom: 3 },
  senderName: { fontSize: 14, fontWeight: '600', color: '#fff' },
  msgTime: { fontSize: 11, color: '#6b7280' },
  editedBadge: { fontSize: 10, color: '#6b7280' },
  msgText: { fontSize: 15, color: '#d1d5db', lineHeight: 22 },
  fileMsg: { flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: '#1e2028', borderRadius: 8, padding: 10, borderWidth: 0.5, borderColor: '#3a3d45' },
  fileIcon: { fontSize: 20 },
  fileName: { color: '#b5d4f4', fontSize: 14, flex: 1 },
  deletedText: { color: '#6b7280', fontSize: 14, fontStyle: 'italic', marginTop: 10 },
  reactionsRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 4, marginTop: 4 },
  reactionChip: { flexDirection: 'row', alignItems: 'center', backgroundColor: '#1e2028', borderRadius: 12, paddingHorizontal: 8, paddingVertical: 3, borderWidth: 0.5, borderColor: '#3a3d45' },
  reactionChipActive: { backgroundColor: '#185FA520', borderColor: '#185FA5' },
  typingRow: { flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 16, paddingVertical: 8 },
  typingDots: { color: '#9ca3af', fontSize: 16, letterSpacing: 2 },
  typingText: { color: '#9ca3af', fontSize: 12 },
  inputRow: { flexDirection: 'row', alignItems: 'flex-end', padding: 8, gap: 8, borderTopWidth: 0.5, borderTopColor: '#2a2d35', backgroundColor: '#12141a' },
  attachBtn: { width: 36, height: 36, backgroundColor: '#1e2028', borderRadius: 18, justifyContent: 'center', alignItems: 'center', borderWidth: 0.5, borderColor: '#3a3d45' },
  attachIcon: { color: '#9ca3af', fontSize: 22, lineHeight: 26 },
  textInput: { flex: 1, backgroundColor: '#1e2028', borderRadius: 20, paddingHorizontal: 14, paddingVertical: 8, color: '#e8eaed', fontSize: 15, maxHeight: 100, borderWidth: 0.5, borderColor: '#3a3d45' },
  sendBtn: { width: 36, height: 36, backgroundColor: '#185FA5', borderRadius: 18, justifyContent: 'center', alignItems: 'center' },
  sendBtnDisabled: { backgroundColor: '#1e2028' },
  sendIcon: { color: '#fff', fontSize: 18 },
})
