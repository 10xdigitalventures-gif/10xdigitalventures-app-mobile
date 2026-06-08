import {
  View, Text, FlatList, TouchableOpacity, StyleSheet, TextInput,
  Modal, Alert, ActivityIndicator, ScrollView, RefreshControl
} from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { useRouter } from 'expo-router'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import { colors, radius } from '@/lib/theme'
import { PlusIcon, SearchIcon, GroupIcon } from '@/components/icons'

function Avatar({ name, isGroup }) {
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
  const [refreshing, setRefreshing] = useState(false)
  const safe = Array.isArray(channels) ? channels : []
  const [showSheet, setShowSheet] = useState(false)
  const [query, setQuery] = useState('')

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
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.brand} />}
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