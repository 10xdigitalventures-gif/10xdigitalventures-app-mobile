import { useState } from 'react'
import {
  View, Text, FlatList, TouchableOpacity,
  StyleSheet, TextInput, Modal, Alert, ActivityIndicator
} from 'react-native'
import { useRouter } from 'expo-router'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'

export default function ChannelsScreen() {
  const router = useRouter()
  const { channels, addChannel } = useChatStore()
  const safeChannels = Array.isArray(channels) ? channels : []
  const [showModal, setShowModal] = useState(false)
  const [newName, setNewName] = useState('')
  const [creating, setCreating] = useState(false)

  const publicChannels = safeChannels.filter(c => c.type === 'public')
  const privateChannels = safeChannels.filter(c => c.type === 'private')

  const createChannel = async () => {
    if (!newName.trim()) return
    setCreating(true)
    try {
      const { data } = await api.post('/channels', { name: newName.toLowerCase().replace(/\s+/g, '-') })
      const channel = data?.data || data; addChannel(channel)
      setShowModal(false)
      setNewName('')
      router.push(`/chat/${channel.id}`)
    } catch {
      Alert.alert('Error', 'Could not create channel')
    } finally {
      setCreating(false)
    }
  }

  const renderChannel = ({ item }) => (
    <TouchableOpacity style={styles.channelItem} onPress={() => router.push(`/chat/${item.id}`)}>
      <Text style={styles.channelHash}>{item.type === 'private' ? '🔒' : '#'}</Text>
      <View style={styles.channelInfo}>
        <Text style={styles.channelName}>{item.name}</Text>
        {item.topic ? <Text style={styles.channelTopic} numberOfLines={1}>{item.topic}</Text> : null}
      </View>
    </TouchableOpacity>
  )

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <View>
          <Text style={styles.headerTitle}>10x Digital Ventures</Text>
          <Text style={styles.headerSub}>Workspace</Text>
        </View>
        <TouchableOpacity style={styles.addBtn} onPress={() => setShowModal(true)}>
          <Text style={styles.addBtnText}>+</Text>
        </TouchableOpacity>
      </View>

      <FlatList
        data={[
          ...(publicChannels.length ? [{ id: 'pub-header', isHeader: true, label: 'CHANNELS' }] : []),
          ...publicChannels,
          ...(privateChannels.length ? [{ id: 'priv-header', isHeader: true, label: 'PRIVATE GROUPS' }] : []),
          ...privateChannels,
        ]}
        keyExtractor={item => item.id}
        renderItem={({ item }) => item.isHeader
          ? <Text style={styles.sectionHeader}>{item.label}</Text>
          : renderChannel({ item })
        }
        contentContainerStyle={{ paddingBottom: 20 }}
        ListEmptyComponent={
          <View style={styles.empty}>
            <Text style={styles.emptyText}>No channels yet</Text>
            <Text style={styles.emptySubText}>Tap + to create one</Text>
          </View>
        }
      />

      {/* Create Channel Modal */}
      <Modal visible={showModal} transparent animationType="slide">
        <View style={styles.modalOverlay}>
          <View style={styles.modalBox}>
            <Text style={styles.modalTitle}>New Channel</Text>
            <TextInput
              style={styles.modalInput}
              placeholder="channel-name"
              placeholderTextColor="#6b7280"
              autoCapitalize="none"
              value={newName}
              onChangeText={setNewName}
              autoFocus
            />
            <TouchableOpacity style={styles.modalBtn} onPress={createChannel} disabled={creating}>
              {creating ? <ActivityIndicator color="#fff" /> : <Text style={styles.modalBtnText}>Create Channel</Text>}
            </TouchableOpacity>
            <TouchableOpacity onPress={() => setShowModal(false)} style={styles.cancelBtn}>
              <Text style={styles.cancelText}>Cancel</Text>
            </TouchableOpacity>
          </View>
        </View>
      </Modal>
    </View>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0f1117' },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', padding: 16, paddingTop: 56, borderBottomWidth: 0.5, borderBottomColor: '#2a2d35', backgroundColor: '#12141a' },
  headerTitle: { fontSize: 17, fontWeight: '700', color: '#fff' },
  headerSub: { fontSize: 12, color: '#6b7280', marginTop: 2 },
  addBtn: { width: 32, height: 32, backgroundColor: '#185FA5', borderRadius: 8, justifyContent: 'center', alignItems: 'center' },
  addBtnText: { color: '#fff', fontSize: 22, lineHeight: 28 },
  sectionHeader: { fontSize: 11, fontWeight: '600', color: '#6b7280', letterSpacing: 0.8, paddingHorizontal: 16, paddingVertical: 10, paddingTop: 20 },
  channelItem: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12, gap: 12 },
  channelHash: { fontSize: 18, color: '#6b7280', width: 24, textAlign: 'center' },
  channelInfo: { flex: 1 },
  channelName: { fontSize: 15, color: '#e8eaed', fontWeight: '500' },
  channelTopic: { fontSize: 12, color: '#6b7280', marginTop: 2 },
  empty: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingTop: 80 },
  emptyText: { color: '#9ca3af', fontSize: 16, fontWeight: '500' },
  emptySubText: { color: '#6b7280', fontSize: 13, marginTop: 4 },
  modalOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.7)', justifyContent: 'flex-end' },
  modalBox: { backgroundColor: '#1a1d24', borderTopLeftRadius: 20, borderTopRightRadius: 20, padding: 24, paddingBottom: 40 },
  modalTitle: { fontSize: 18, fontWeight: '700', color: '#fff', marginBottom: 16 },
  modalInput: { backgroundColor: '#1e2028', borderWidth: 1, borderColor: '#3a3d45', borderRadius: 10, padding: 14, color: '#e8eaed', fontSize: 15, marginBottom: 12 },
  modalBtn: { backgroundColor: '#185FA5', borderRadius: 10, padding: 16, alignItems: 'center' },
  modalBtnText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  cancelBtn: { alignItems: 'center', marginTop: 12 },
  cancelText: { color: '#9ca3af', fontSize: 15 },
})
