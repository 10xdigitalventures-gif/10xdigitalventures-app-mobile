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
import { BackIcon, SearchIcon, GroupIcon } from '@/components/icons'
import * as Haptics from '@/lib/haptics'

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
    Haptics.tapLight()
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
              <Text style={styles.emptyBody}>
                {query ? 'Try a different search.' : 'Your workspace has no other users yet.'}
              </Text>
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