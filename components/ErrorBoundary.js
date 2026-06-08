import React from 'react'
import { View, Text, TouchableOpacity, ScrollView, StyleSheet, Platform } from 'react-native'
import { saveCrash } from '@/lib/cache'

let DevSettings = null
try { DevSettings = require('react-native').DevSettings } catch (e) { DevSettings = null }

let Updates = null
try { Updates = require('expo-updates') } catch (e) { Updates = null }

export default class ErrorBoundary extends React.Component {
  state = { hasError: false, error: null, info: null }

  static getDerivedStateFromError(error) {
    return { hasError: true, error }
  }

  componentDidCatch(error, info) {
    // Save crash details so we can inspect after app reload
    try {
      saveCrash({
        message: String(error?.message || error),
        stack: String(error?.stack || ''),
        component: String(info?.componentStack || ''),
      })
    } catch (e) {}
    console.error('[ErrorBoundary]', error, info)
    this.setState({ info })
  }

  reload = async () => {
    try {
      if (Updates?.reloadAsync) { await Updates.reloadAsync(); return }
    } catch (e) {}
    try {
      if (DevSettings?.reload) { DevSettings.reload(); return }
    } catch (e) {}
    // Last-resort: reset boundary so children re-mount
    this.setState({ hasError: false, error: null, info: null })
  }

  render() {
    if (!this.state.hasError) return this.props.children

    const msg = this.state.error?.message || String(this.state.error || 'Unknown error')
    const stack = this.state.error?.stack || ''
    const comp  = this.state.info?.componentStack || ''

    return (
      <View style={styles.root}>
        <ScrollView contentContainerStyle={{ padding: 20, paddingTop: 60 }}>
          <Text style={styles.icon}>!</Text>
          <Text style={styles.title}>Something went wrong</Text>
          <Text style={styles.body}>
            The app hit an error and could not continue. Tap Reload to try again.
            A crash report has been saved on this device.
          </Text>

          <Text style={styles.label}>Error</Text>
          <Text style={styles.errText}>{msg}</Text>

          {!!stack && (<>
            <Text style={styles.label}>Stack</Text>
            <Text style={styles.codeText} numberOfLines={20}>{stack}</Text>
          </>)}

          {!!comp && (<>
            <Text style={styles.label}>Component tree</Text>
            <Text style={styles.codeText} numberOfLines={20}>{comp}</Text>
          </>)}

          <TouchableOpacity style={styles.btn} onPress={this.reload}>
            <Text style={styles.btnText}>Reload App</Text>
          </TouchableOpacity>
        </ScrollView>
      </View>
    )
  }
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#0b141a' },
  icon: { color: '#f15c6d', fontSize: 56, fontWeight: '700', textAlign: 'center', marginBottom: 8 },
  title: { color: '#fff', fontSize: 22, fontWeight: '700', textAlign: 'center', marginBottom: 8 },
  body: { color: 'rgba(255,255,255,0.7)', fontSize: 14, textAlign: 'center', marginBottom: 24, lineHeight: 20 },
  label: { color: '#1db791', fontSize: 12, fontWeight: '700', textTransform: 'uppercase', marginTop: 16, marginBottom: 4 },
  errText: { color: '#f15c6d', fontSize: 14, fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace' },
  codeText: { color: 'rgba(255,255,255,0.75)', fontSize: 11, fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace', lineHeight: 16 },
  btn: { backgroundColor: '#1db791', borderRadius: 12, paddingVertical: 14, alignItems: 'center', marginTop: 28, marginBottom: 40 },
  btnText: { color: '#fff', fontSize: 16, fontWeight: '700' },
})