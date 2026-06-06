import { View, Text, FlatList, TouchableOpacity, StyleSheet } from 'react-native'
import { useRouter } from 'expo-router'
import useChatStore from '@/store/chatStore'

export default function DMsScreen() {
  const router = useRouter()
  const { channels, onlineUsers } = useChatStore()
  const safeChannels = Array.isArray(channels) ? channels : []
  const dms = safeChannels.filter(c => c.type === 'dm')

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Direct Messages</Text>
      </View>
      <FlatList
        data={dms}
        keyExtractor={item => item.id}
        renderItem={({ item }) => (
          <TouchableOpacity style={styles.dmItem} onPress={() => router.push(`/chat/${item.id}`)}>
            <View style={styles.avatar}>
              <Text style={styles.avatarText}>{item.name?.[0]?.toUpperCase()}</Text>
              {onlineUsers.has(item.dm_user_id) && <View style={styles.onlineDot} />}
            </View>
            <View style={styles.dmInfo}>
              <Text style={styles.dmName}>{item.name}</Text>
              <Text style={styles.dmLast} numberOfLines={1}>Tap to open conversation</Text>
            </View>
          </TouchableOpacity>
        )}
        ListEmptyComponent={
          <View style={styles.empty}>
            <Text style={styles.emptyText}>No direct messages</Text>
            <Text style={styles.emptySubText}>Start a conversation from a channel member</Text>
          </View>
        }
        contentContainerStyle={{ paddingBottom: 20 }}
      />
    </View>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0f1117' },
  header: { padding: 16, paddingTop: 56, borderBottomWidth: 0.5, borderBottomColor: '#2a2d35', backgroundColor: '#12141a' },
  headerTitle: { fontSize: 17, fontWeight: '700', color: '#fff' },
  dmItem: { flexDirection: 'row', alignItems: 'center', padding: 16, gap: 12, borderBottomWidth: 0.5, borderBottomColor: '#1e2028' },
  avatar: { width: 44, height: 44, borderRadius: 22, backgroundColor: '#1db791', justifyContent: 'center', alignItems: 'center', position: 'relative' },
  avatarText: { color: '#fff', fontSize: 18, fontWeight: '600' },
  onlineDot: { position: 'absolute', bottom: 0, right: 0, width: 12, height: 12, borderRadius: 6, backgroundColor: '#22c55e', borderWidth: 2, borderColor: '#0f1117' },
  dmInfo: { flex: 1 },
  dmName: { fontSize: 15, color: '#e8eaed', fontWeight: '500' },
  dmLast: { fontSize: 13, color: '#6b7280', marginTop: 2 },
  empty: { alignItems: 'center', justifyContent: 'center', paddingTop: 80 },
  emptyText: { color: '#9ca3af', fontSize: 16, fontWeight: '500' },
  emptySubText: { color: '#6b7280', fontSize: 13, marginTop: 4, textAlign: 'center', paddingHorizontal: 32 },
})
