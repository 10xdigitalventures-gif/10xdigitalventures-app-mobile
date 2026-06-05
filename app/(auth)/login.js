import { useState } from 'react'
import { View, Text, TextInput, TouchableOpacity, StyleSheet, KeyboardAvoidingView, Platform, ActivityIndicator, Alert, ScrollView } from 'react-native'
import { useRouter } from 'expo-router'
import * as SecureStore from 'expo-secure-store'
import api from '@/lib/api'

export default function LoginScreen() {
  const router = useRouter()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)

  const login = async () => {
    if (!email || !password) {
      Alert.alert('Error', 'Please fill all fields')
      return
    }

    setLoading(true)

    try {
      const { data } = await api.post('/auth/login', { email, password })
      const payload = data?.data || data

      if (!payload?.token || !payload?.user) {
        throw new Error('Invalid login response')
      }

      await SecureStore.setItemAsync('token', payload.token)
      await SecureStore.setItemAsync('user', JSON.stringify(payload.user))

      router.replace('/(tabs)/channels')
    } catch (err) {
      Alert.alert('Login Failed', err.response?.data?.message || err.message || 'Please try again')
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

        <Text style={styles.title}>Welcome back</Text>
        <Text style={styles.subtitle}>Sign in to 10x Chat</Text>

        <View style={styles.form}>
          <Text style={styles.label}>Email</Text>
          <TextInput
            value={email}
            onChangeText={setEmail}
            autoCapitalize="none"
            keyboardType="email-address"
            placeholder="you@example.com"
            placeholderTextColor="#6b7280"
            style={styles.input}
          />

          <Text style={styles.label}>Password</Text>
          <TextInput
            value={password}
            onChangeText={setPassword}
            secureTextEntry
            placeholder="Password"
            placeholderTextColor="#6b7280"
            style={styles.input}
          />

          <TouchableOpacity style={styles.btn} onPress={login} disabled={loading}>
            {loading ? <ActivityIndicator color="#fff" /> : <Text style={styles.btnText}>Sign In</Text>}
          </TouchableOpacity>

          <TouchableOpacity onPress={() => router.push('/(auth)/register')} style={styles.linkRow}>
            <Text style={styles.linkText}>No account? <Text style={styles.link}>Register with invite code</Text></Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  )
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0f1117' },
  scroll: { flexGrow: 1, justifyContent: 'center', padding: 24 },
  logoBox: { width: 64, height: 64, backgroundColor: '#185FA5', borderRadius: 16, justifyContent: 'center', alignItems: 'center', alignSelf: 'center', marginBottom: 20 },
  logoText: { color: '#fff', fontSize: 22, fontWeight: '700' },
  title: { fontSize: 24, fontWeight: '700', color: '#fff', textAlign: 'center' },
  subtitle: { fontSize: 14, color: '#9ca3af', textAlign: 'center', marginTop: 4, marginBottom: 32 },
  form: { gap: 12 },
  label: { fontSize: 12, color: '#9ca3af', marginBottom: 4 },
  input: { backgroundColor: '#1e2028', borderWidth: 1, borderColor: '#3a3d45', borderRadius: 10, padding: 14, color: '#e8eaed', fontSize: 15, marginBottom: 8 },
  btn: { backgroundColor: '#185FA5', borderRadius: 10, padding: 16, alignItems: 'center', marginTop: 8 },
  btnText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  linkRow: { alignItems: 'center', marginTop: 16 },
  linkText: { color: '#9ca3af', fontSize: 14 },
  link: { color: '#b5d4f4' },
})
