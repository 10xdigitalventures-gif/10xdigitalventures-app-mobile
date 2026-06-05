import { Tabs } from 'expo-router'
import { View, Text } from 'react-native'
import { useEffect } from 'react'
import * as SecureStore from 'expo-secure-store'
import { useRouter } from 'expo-router'
import useChatStore from '@/store/chatStore'
import { getSocket, disconnectSocket } from '@/lib/socket'
import api from '@/lib/api'

function TabIcon({ name, focused }) {
  const icons = { channels: '#', dms: '✉', files: '📎', profile: '👤' }
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: 18, color: focused ? '#185FA5' : '#6b7280' }}>{icons[name]}</Text>
    </View>
  )
}

export default function TabsLayout() {
  const router = useRouter()
  const { setUser, setChannels, addMessage, updateMessage, deleteMessage, updateReaction, setUserOnline, setUserOffline, setTyping } = useChatStore()

  useEffect(() => {
    const init = async () => {
      const token = await SecureStore.getItemAsync('token')
      if (!token) { router.replace('/(auth)/login'); return }

      try {
        const [meRes, chRes] = await Promise.all([
          api.get('/auth/me'),
          api.get('/channels'),
        ])
        setUser(meRes.data?.data || meRes.data)
        setChannels(Array.isArray(chRes.data?.data) ? chRes.data.data : Array.isArray(chRes.data) ? chRes.data : [])

        const socket = await getSocket()
        socket.emit('join:channels')

        socket.on('message:new', msg => addMessage(msg.channel_id, msg))
        socket.on('message:edited', ({ message_id, channel_id, content }) => updateMessage(channel_id, message_id, { content, is_edited: 1 }))
        socket.on('message:deleted', ({ message_id, channel_id }) => deleteMessage(channel_id, message_id))
        socket.on('reaction:updated', ({ message_id, channel_id, emoji, user_id, action }) => updateReaction(channel_id, message_id, emoji, user_id, action))
        socket.on('user:online', ({ user_id }) => setUserOnline(user_id))
        socket.on('user:offline', ({ user_id }) => setUserOffline(user_id))
        socket.on('typing:start', ({ user_id, channel_id }) => setTyping(channel_id, user_id, true))
        socket.on('typing:stop', ({ user_id, channel_id }) => setTyping(channel_id, user_id, false))
      } catch {
        router.replace('/(auth)/login')
      }
    }
    init()
    return () => disconnectSocket()
  }, [])

  return (
    <Tabs screenOptions={{
      headerShown: false,
      tabBarStyle: { backgroundColor: '#12141a', borderTopColor: '#2a2d35', borderTopWidth: 0.5 },
      tabBarActiveTintColor: '#185FA5',
      tabBarInactiveTintColor: '#6b7280',
      tabBarLabelStyle: { fontSize: 11 },
    }}>
      <Tabs.Screen name="channels" options={{ title: 'Channels', tabBarIcon: ({ focused }) => <TabIcon name="channels" focused={focused} /> }} />
      <Tabs.Screen name="dms" options={{ title: 'Messages', tabBarIcon: ({ focused }) => <TabIcon name="dms" focused={focused} /> }} />
      <Tabs.Screen name="files" options={{ title: 'Files', tabBarIcon: ({ focused }) => <TabIcon name="files" focused={focused} /> }} />
      <Tabs.Screen name="profile" options={{ title: 'Profile', tabBarIcon: ({ focused }) => <TabIcon name="profile" focused={focused} /> }} />
    </Tabs>
  )
}
