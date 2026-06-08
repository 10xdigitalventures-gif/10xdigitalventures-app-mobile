import { useEffect } from 'react'
import { Stack } from 'expo-router'
import { StatusBar } from 'expo-status-bar'
import { GestureHandlerRootView } from 'react-native-gesture-handler'
import { SafeAreaProvider } from 'react-native-safe-area-context'
import { registerForPushNotifications } from '@/lib/notifications'
import { CallProvider } from '@/context/CallContext'
import { GroupCallProvider } from '@/context/GroupCallContext'
import ErrorBoundary from '@/components/ErrorBoundary'
import { installGlobalErrorHandlers } from '@/lib/globalErrorHandler'

// EAS Observe (performance monitoring). If module not installed, falls back to no-op.
let ObserveRoot = null
let markInteractive = null
try {
  const obs = require('expo-observe')
  ObserveRoot = obs.ObserveRoot || obs.AppMetricsRoot || null
  markInteractive = obs.markInteractive || null
} catch (e) { ObserveRoot = null }

function App() {
  useEffect(() => {
    installGlobalErrorHandlers()
    registerForPushNotifications()
    // Tell Observe the app is interactive (one-time)
    try { if (markInteractive) markInteractive() } catch (e) {}
  }, [])

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <ErrorBoundary>
          <CallProvider>
            <GroupCallProvider>
              <StatusBar style="light" />
              <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: '#0b141a' } }}>
                <Stack.Screen name="(auth)" />
                <Stack.Screen name="(tabs)" />
              </Stack>
            </GroupCallProvider>
          </CallProvider>
        </ErrorBoundary>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  )
}

export default function RootLayout() {
  if (ObserveRoot) {
    return <ObserveRoot><App /></ObserveRoot>
  }
  return <App />
}