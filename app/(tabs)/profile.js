import { useState } from 'react'
import {
  View, Text, TextInput, TouchableOpacity, StyleSheet, Alert,
  ActivityIndicator, ScrollView
} from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { useRouter } from 'expo-router'
import * as SecureStore from 'expo-secure-store'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import { disconnectSocket } from '@/lib/socket'
import { colors } from '@/lib/theme'
import { LogoutIcon } from '@/components/icons'

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
      // Try the auth profile endpoint first (web backend exposes /auth/profile),
      // fall back to /users/profile (older route).
      try { await api.put('/auth/profile', { name, bio, status }) }
      catch { await api.put('/users/profile', { name, bio, status }) }
      setUser({ ...user, name, bio, status })
      Alert.alert('Saved', 'Profile updated')
    } catch (e) {
      Alert.alert('Error', e?.response?.data?.message || 'Could not save profile')
    }
    setSaving(false)
  }

  const logout = () => {
    Alert.alert('Logout', 'Are you sure?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Logout', style: 'destructive',
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
    <SafeAreaView style={styles.container} edges={['top']}>
      <ScrollView contentContainerStyle={{ paddingBottom: 24 }}>
        <View style={styles.header}><Text style={styles.headerTitle}>Settings</Text></View>

        {/* Profile card */}
        <View style={styles.profileCard}>
          <View style={styles.bigAvatar}>
            <Text style={styles.bigAvatarText}>{(user?.name || '?')[0].toUpperCase()}</Text>
          </View>
          <View style={{ flex: 1 }}>
            <Text style={styles.profileName}>{user?.name || 'You'}</Text>
            <Text style={styles.profileEmail}>{user?.email}</Text>
          </View>
        </View>

        {/* Profile editor */}
        <Text style={styles.sectionLabel}>Account</Text>
        <View style={styles.fieldCard}>
          <Text style={styles.fieldLabel}>Name</Text>
          <TextInput style={styles.field} value={name} onChangeText={setName} placeholder="Your name" placeholderTextColor={colors.textTertiary}/>
        </View>
        <View style={styles.fieldCard}>
          <Text style={styles.fieldLabel}>About</Text>
          <TextInput style={[styles.field, { minHeight: 60, textAlignVertical: 'top' }]} value={bio} onChangeText={setBio} placeholder="Tell people about you" placeholderTextColor={colors.textTertiary} multiline/>
        </View>
        <View style={styles.fieldCard}>
          <Text style={styles.fieldLabel}>Status</Text>
          <TextInput style={styles.field} value={status} onChangeText={setStatus} placeholder="Available" placeholderTextColor={colors.textTertiary}/>
        </View>

        <TouchableOpacity style={styles.primaryBtn} onPress={save} disabled={saving}>
          {saving ? <ActivityIndicator color="#fff" /> : <Text style={styles.primaryBtnText}>Save changes</Text>}
        </TouchableOpacity>

        <Text style={styles.sectionLabel}>App</Text>
        <TouchableOpacity style={styles.linkRow} onPress={() => Alert.alert('Coming soon', 'Theme settings will be available in a future update.')}>
          <Text style={styles.linkText}>Theme</Text>
          <Text style={styles.linkRight}>Dark</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.linkRow} onPress={() => Alert.alert('Coming soon', 'Notifications settings.')}>
          <Text style={styles.linkText}>Notifications</Text>
          <Text style={styles.linkRight}>{'>'}</Text>
        </TouchableOpacity>

        <TouchableOpacity style={[styles.linkRow, { marginTop: 20 }]} onPress={logout}>
          <LogoutIcon color={colors.danger} />
          <Text style={[styles.linkText, { color: colors.danger, marginLeft: 8 }]}>Log out</Text>
          <View style={{ flex: 1 }} />
        </TouchableOpacity>
      </ScrollView>
    </SafeAreaView>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  header: { paddingHorizontal: 16, paddingVertical: 14, backgroundColor: colors.bgSurface, borderBottomWidth: 0.5, borderBottomColor: colors.bgDivider },
  headerTitle: { color: colors.textPrimary, fontSize: 22, fontWeight: '700' },

  profileCard: { flexDirection: 'row', alignItems: 'center', gap: 14, padding: 18, backgroundColor: colors.bgSurface, marginTop: 8 },
  bigAvatar: { width: 72, height: 72, borderRadius: 36, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center' },
  bigAvatarText: { color: colors.textOnBrand, fontWeight: '700', fontSize: 28 },
  profileName: { color: colors.textPrimary, fontSize: 18, fontWeight: '700' },
  profileEmail: { color: colors.textSecondary, fontSize: 13, marginTop: 3 },

  sectionLabel: { color: colors.textSecondary, fontSize: 12, fontWeight: '700', textTransform: 'uppercase', marginTop: 22, marginHorizontal: 16, marginBottom: 6 },

  fieldCard: { backgroundColor: colors.bgSurface, paddingHorizontal: 16, paddingVertical: 10, borderTopWidth: 0.5, borderBottomWidth: 0.5, borderColor: colors.bgDivider, marginBottom: -0.5 },
  fieldLabel: { color: colors.textSecondary, fontSize: 12, marginBottom: 4 },
  field: { color: colors.textPrimary, fontSize: 15, padding: 0 },

  primaryBtn: { marginHorizontal: 16, marginTop: 18, backgroundColor: colors.brand, borderRadius: 10, paddingVertical: 14, alignItems: 'center' },
  primaryBtnText: { color: '#fff', fontWeight: '700', fontSize: 15 },

  linkRow: { flexDirection: 'row', alignItems: 'center', backgroundColor: colors.bgSurface, paddingHorizontal: 16, paddingVertical: 16, borderTopWidth: 0.5, borderBottomWidth: 0.5, borderColor: colors.bgDivider, marginBottom: -0.5 },
  linkText: { color: colors.textPrimary, fontSize: 15, flex: 1 },
  linkRight: { color: colors.textSecondary, fontSize: 14 },
})