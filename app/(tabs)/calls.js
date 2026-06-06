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

function CallRow({ item, onCall }) {
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
      <TouchableOpacity style={styles.callBtn} onPress={() => onCall && onCall(item)}>
        {isVideo ? <VideoIcon size={22} color={colors.brand} /> : <PhoneIcon size={22} color={colors.brand} />}
      </TouchableOpacity>
    </View>
  )
}

export default function CallsScreen() {
  const call = useCall()
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
        renderItem={({ item }) => <CallRow item={item} onCall={(c) => call?.startCall(c.peer_id, c.peer_name, c.type)} />}
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