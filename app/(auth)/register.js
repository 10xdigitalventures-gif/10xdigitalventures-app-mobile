import { useState } from 'react'
import { View, Text, TextInput, TouchableOpacity, StyleSheet, KeyboardAvoidingView, Platform, ActivityIndicator, Alert, ScrollView } from 'react-native'
import { useRouter } from 'expo-router'
import * as SecureStore from 'expo-secure-store'
import api from '@/lib/api'

export default function RegisterScreen() {
  const router = useRouter()
  const [form, setForm] = useState({
    name: '',
    email: '',
    password: '',
    invite_code: '',
  })
  const [loading, setLoading] = useState(false)

  const handle = (key, val) => setForm(f => ({ ...f, [key]: val }))

  const register = async () => {
    if (!form.name || !form.email || !form.password || !form.invite_code) {
      Alert.alert('Error', 'All fields are required')
      return
    }

    setLoading(true)

    try {
      const { data } = await api.post('/auth/register', form)
      const payload = data?.data || data

      if (!payload?.token || !payload?.user) {
        throw new Error('Invalid registration response')
      }

      await SecureStore.setItemAsync('token', payload.token)
      await SecureStore.setItemAsync('user', JSON.stringify(payload.user))

      router.replace('/(tabs)/channels')
    } catch (err) {
      Alert.alert('Error', err.response?.data?.message || err.message || 'Registration failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <KeyboardAvoidingView style={styles.container} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView contentContainerStyle={styles.scroll}>
        <View style={styles.logoBox}>
          <Text style={styles.logoText}>10x</Text>
        </View>

        <Text style={styles.title}>Create Account</Text>
        <Text style={styles.subtitle}>You need an invite code to join</Text>

        <View style={styles.form}>
          {[
            { key: 'name', label: 'Full Name', placeholder: 'Your name' },
            { key: 'email', label: 'Email', placeholder: 'you@example.com', keyboardType: 'email-address' },
            { key: 'password', label: 'Password', placeholder: 'Min 8 characters', secure: true },
            { key: 'invite_code', label: 'Invite Code', placeholder: 'Workspace invite code' },
          ].map(f => (
            <View key={f.key}>
              <Text style={styles.label}>{f.label}</Text>
              <TextInput
                value={form[f.key]}
                onChangeText={val => handle(f.key, val)}
                placeholder={f.placeholder}
                placeholderTextColor="#6b7280"
                secureTextEntry={f.secure}
                keyboardType={f.keyboardType}
                autoCapitalize="none"
                style={styles.input}
              />
            </View>
          ))}

          <TouchableOpacity style={styles.btn} onPress={register} disabled={loading}>
            {loading ? <ActivityIndicator color="#fff" /> : <Text style={styles.btnText}>Create Account</Text>}
          </TouchableOpacity>

          <TouchableOpacity onPress={() => router.back()} style={styles.linkRow}>
            <Text style={styles.linkText}>Already have an account? <Text style={styles.link}>Sign in</Text></Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0f1117' },
  scroll: { flexGrow: 1, justifyContent: 'center', padding: 24 },
  logoBox: { width: 64, height: 64, backgroundColor: '#1db791', borderRadius: 16, justifyContent: 'center', alignItems: 'center', alignSelf: 'center', marginBottom: 20 },
  logoText: { color: '#fff', fontSize: 22, fontWeight: '700' },
  title: { fontSize: 24, fontWeight: '700', color: '#fff', textAlign: 'center' },
  subtitle: { fontSize: 14, color: '#9ca3af', textAlign: 'center', marginTop: 4, marginBottom: 32 },
  form: { gap: 8 },
  label: { fontSize: 12, color: '#9ca3af', marginBottom: 4 },
  input: { backgroundColor: '#1e2028', borderWidth: 1, borderColor: '#3a3d45', borderRadius: 10, padding: 14, color: '#e8eaed', fontSize: 15, marginBottom: 4 },
  btn: { backgroundColor: '#1db791', borderRadius: 10, padding: 16, alignItems: 'center', marginTop: 12 },
  btnText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  linkRow: { alignItems: 'center', marginTop: 16 },
  linkText: { color: '#9ca3af', fontSize: 14 },
  link: { color: '#a7e9d7' },
})
