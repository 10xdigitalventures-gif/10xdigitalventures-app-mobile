import { useState } from 'react'
import { View, Text, TextInput, TouchableOpacity, StyleSheet, Alert, ActivityIndicator, ScrollView } from 'react-native'
import { useRouter } from 'expo-router'
import * as SecureStore from 'expo-secure-store'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import { disconnectSocket } from '@/lib/socket'

export default function ProfileScreen() {
  const router = useRouter()
  const { user, setUser } = useChatStore()
  const [name, setName] = useState(user?.name || '')
  const [bio, setBio] = useState(user?.bio || '')
  const [status, setStatus] = useState(user?.status || '')
  const [saving, setSaving] = useState(false)

  const save = async () => {
    setSaving(true)
    try {
      await api.put('/users/profile', { name, bio, status })
      setUser({ ...user, name, bio, status })
      Alert.alert('Saved', 'Profile updated!')
    } catch {
      Alert.alert('Error', 'Could not save profile')
    } finally {
      setSaving(false)
    }
  }

  const logout = async () => {
    Alert.alert('Logout', 'Are you sure?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Logout',
        style: 'destructive',
        onPress: async () => {
          disconnectSocket()
          await SecureStore.deleteItemAsync('token')
          await SecureStore.deleteItemAsync('user')
          router.replace('/(auth)/login')
        }
      }
    ])
  }

  return (
    <ScrollView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Profile</Text>
      </View>

      <View style={styles.avatarSection}>
        <View style={styles.avatar}>
          <Text style={styles.avatarText}>{user?.name?.[0]?.toUpperCase() || 'U'}</Text>
        </View>
        <Text style={styles.avatarName}>{user?.name}</Text>
        <Text style={styles.avatarEmail}>{user?.email}</Text>
      </View>

      <View style={styles.form}>
        <Text style={styles.sectionTitle}>Edit Profile</Text>

        <Text style={styles.label}>Display Name</Text>
        <TextInput style={styles.input} value={name} onChangeText={setName} placeholder="Your name" placeholderTextColor="#6b7280" />

        <Text style={styles.label}>Bio</Text>
        <TextInput style={[styles.input, styles.textarea]} value={bio} onChangeText={setBio} placeholder="Tell your team about yourself" placeholderTextColor="#6b7280" multiline numberOfLines={3} />

        <Text style={styles.label}>Status</Text>
        <TextInput style={styles.input} value={status} onChangeText={setStatus} placeholder="e.g. 🎯 Focused | 🏖️ On leave" placeholderTextColor="#6b7280" />

        <TouchableOpacity style={styles.saveBtn} onPress={save} disabled={saving}>
          {saving ? <ActivityIndicator color="#fff" /> : <Text style={styles.saveBtnText}>Save Changes</Text>}
        </TouchableOpacity>
      </View>

      <TouchableOpacity style={styles.logoutBtn} onPress={logout}>
        <Text style={styles.logoutText}>Logout</Text>
      </TouchableOpacity>

      <View style={{ height: 40 }} />
    </ScrollView>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0f1117' },
  header: { padding: 16, paddingTop: 56, borderBottomWidth: 0.5, borderBottomColor: '#2a2d35', backgroundColor: '#12141a' },
  headerTitle: { fontSize: 17, fontWeight: '700', color: '#fff' },
  avatarSection: { alignItems: 'center', paddingVertical: 28 },
  avatar: { width: 80, height: 80, borderRadius: 40, backgroundColor: '#185FA5', justifyContent: 'center', alignItems: 'center', marginBottom: 12 },
  avatarText: { color: '#fff', fontSize: 32, fontWeight: '700' },
  avatarName: { fontSize: 20, fontWeight: '700', color: '#fff' },
  avatarEmail: { fontSize: 14, color: '#9ca3af', marginTop: 4 },
  form: { paddingHorizontal: 16, paddingBottom: 8 },
  sectionTitle: { fontSize: 13, fontWeight: '600', color: '#6b7280', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 16, marginTop: 8 },
  label: { fontSize: 12, color: '#9ca3af', marginBottom: 6 },
  input: { backgroundColor: '#1e2028', borderWidth: 1, borderColor: '#3a3d45', borderRadius: 10, padding: 14, color: '#e8eaed', fontSize: 15, marginBottom: 16 },
  textarea: { height: 80, textAlignVertical: 'top' },
  saveBtn: { backgroundColor: '#185FA5', borderRadius: 10, padding: 16, alignItems: 'center', marginTop: 4 },
  saveBtnText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  logoutBtn: { marginHorizontal: 16, marginTop: 24, backgroundColor: '#1e2028', borderWidth: 1, borderColor: '#ef4444', borderRadius: 10, padding: 16, alignItems: 'center' },
  logoutText: { color: '#ef4444', fontSize: 16, fontWeight: '600' },
})
