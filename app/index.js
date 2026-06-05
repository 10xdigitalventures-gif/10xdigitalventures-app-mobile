import { useEffect } from 'react'
import { useRouter } from 'expo-router'
import { View, ActivityIndicator } from 'react-native'
import * as SecureStore from 'expo-secure-store'

export default function Index() {
  const router = useRouter()

  useEffect(() => {
    SecureStore.getItemAsync('token').then(token => {
      if (token) router.replace('/(tabs)/channels')
      else router.replace('/(auth)/login')
    })
  }, [])

  return (
    <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#0f1117' }}>
      <ActivityIndicator color="#185FA5" size="large" />
    </View>
  )
}
