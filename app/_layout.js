import { useEffect } from 'react'
import { Stack } from 'expo-router'
import { StatusBar } from 'expo-status-bar'
import { GestureHandlerRootView } from 'react-native-gesture-handler'
import { SafeAreaProvider } from 'react-native-safe-area-context'
import { registerForPushNotifications } from '@/lib/notifications'
import { CallProvider } from '@/context/CallContext'
import { GroupCallProvider } from '@/context/GroupCallContext'

export default function RootLayout() {
  useEffect(() => {
    registerForPushNotifications()
  }, [])

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <CallProvider>
          <GroupCallProvider>
            <StatusBar style="light" />
            <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: '#0b141a' } }}>
              <Stack.Screen name="(auth)" />
              <Stack.Screen name="(tabs)" />
            </Stack>
          </GroupCallProvider>
        </CallProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  )
}