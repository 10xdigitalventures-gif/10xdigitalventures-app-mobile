import { useEffect, useState } from 'react'
import { View, Text, FlatList, TouchableOpacity, StyleSheet, ActivityIndicator, Linking } from 'react-native'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import { format } from 'date-fns'

export default function FilesScreen() {
  const { channels } = useChatStore()
  const [files, setFiles] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const fetchFiles = async () => {
      try {
        const allFiles = await Promise.all(
          channels.map(ch => api.get(`/files/channel/${ch.id}`).then(r => r.data).catch(() => []))
        )
        const flat = allFiles.flat().sort((a, b) => new Date(b.created_at) - new Date(a.created_at))
        setFiles(flat)
      } catch {}
      setLoading(false)
    }
    if (channels.length) fetchFiles()
    else setLoading(false)
  }, [channels])

  const getIcon = (type) => {
    if (!type) return '📎'
    if (type.startsWith('image/')) return '🖼️'
    if (type.includes('pdf')) return '📄'
    if (type.includes('zip') || type.includes('rar')) return '🗜️'
    if (type.includes('video')) return '🎬'
    return '📎'
  }

  const formatSize = (bytes) => {
    if (!bytes) return ''
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Files</Text>
        <Text style={styles.headerSub}>{files.length} files shared</Text>
      </View>
      {loading ? (
        <View style={styles.center}><ActivityIndicator color="#185FA5" size="large" /></View>
      ) : (
        <FlatList
          data={files}
          keyExtractor={item => item.id}
          renderItem={({ item }) => (
            <TouchableOpacity style={styles.fileItem} onPress={() => Linking.openURL(item.file_url)}>
              <Text style={styles.fileIcon}>{getIcon(item.file_type)}</Text>
              <View style={styles.fileInfo}>
                <Text style={styles.fileName} numberOfLines={1}>{item.file_name}</Text>
                <Text style={styles.fileMeta}>{item.uploaded_by} · {formatSize(item.file_size)} · {format(new Date(item.created_at), 'MMM d')}</Text>
              </View>
              <Text style={styles.downloadIcon}>↓</Text>
            </TouchableOpacity>
          )}
          ListEmptyComponent={
            <View style={styles.empty}>
              <Text style={styles.emptyText}>No files shared yet</Text>
              <Text style={styles.emptySubText}>Files shared in channels appear here</Text>
            </View>
          }
          contentContainerStyle={{ paddingBottom: 20 }}
        />
      )}
    </View>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0f1117' },
  header: { padding: 16, paddingTop: 56, borderBottomWidth: 0.5, borderBottomColor: '#2a2d35', backgroundColor: '#12141a' },
  headerTitle: { fontSize: 17, fontWeight: '700', color: '#fff' },
  headerSub: { fontSize: 12, color: '#6b7280', marginTop: 2 },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  fileItem: { flexDirection: 'row', alignItems: 'center', padding: 16, gap: 12, borderBottomWidth: 0.5, borderBottomColor: '#1e2028' },
  fileIcon: { fontSize: 28 },
  fileInfo: { flex: 1 },
  fileName: { fontSize: 15, color: '#e8eaed', fontWeight: '500' },
  fileMeta: { fontSize: 12, color: '#6b7280', marginTop: 3 },
  downloadIcon: { fontSize: 18, color: '#185FA5' },
  empty: { alignItems: 'center', paddingTop: 80 },
  emptyText: { color: '#9ca3af', fontSize: 16, fontWeight: '500' },
  emptySubText: { color: '#6b7280', fontSize: 13, marginTop: 4 },
})
