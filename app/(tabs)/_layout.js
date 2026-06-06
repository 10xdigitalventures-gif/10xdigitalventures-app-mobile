import { Tabs } from 'expo-router'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { useEffect } from 'react'
import * as SecureStore from 'expo-secure-store'
import { useRouter } from 'expo-router'
import useChatStore from '@/store/chatStore'
import { getSocket, disconnectSocket } from '@/lib/socket'
import api from '@/lib/api'
import { colors } from '@/lib/theme'
import { ChatIcon, PhoneIcon, GroupIcon, SettingsIcon } from '@/components/icons'

export default function TabsLayout() {
  const insets = useSafeAreaInsets()
  const router = useRouter()
  const {
    setUser, setChannels, addChannel, addMessage, updateMessage, deleteMessage,
    updateReaction, setUserOnline, setUserOffline, setTyping,
  } = useChatStore()

  useEffect(() => {
    const init = async () => {
      const token = await SecureStore.getItemAsync('token')
      if (!token) { router.replace('/(auth)/login'); return }

      try {
        const [meRes, chRes] = await Promise.all([api.get('/auth/me'), api.get('/channels')])
        setUser(meRes.data?.data || meRes.data)
        setChannels(Array.isArray(chRes.data?.data) ? chRes.data.data : Array.isArray(chRes.data) ? chRes.data : [])

        const socket = await getSocket()
        socket.emit('join:channels')
        socket.on('message:new', msg => addMessage(msg.channel_id, msg))
        socket.on('message:edited', ({ message_id, channel_id, content }) => updateMessage(channel_id, message_id, { content, is_edited: 1 }))
        socket.on('message:deleted', ({ message_id, channel_id }) => deleteMessage(channel_id, message_id))
        socket.on('reaction:updated', ({ message_id, channel_id, emoji, user_id, action }) => updateReaction(channel_id, message_id, emoji, user_id, action))
        socket.on('user:online',  ({ user_id }) => setUserOnline(user_id))
        socket.on('user:offline', ({ user_id }) => setUserOffline(user_id))
        socket.on('typing:start', ({ user_id, channel_id }) => setTyping(channel_id, user_id, true))
        socket.on('typing:stop',  ({ user_id, channel_id }) => setTyping(channel_id, user_id, false))
        socket.on('channel:new',  (ch) => { addChannel(ch); socket.emit('join:channels') })
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
      tabBarStyle: { backgroundColor: colors.bgSurface, borderTopColor: colors.bgDivider, borderTopWidth: 0.5, height: 60 + insets.bottom, paddingTop: 6, paddingBottom: Math.max(insets.bottom, 8) },
      tabBarActiveTintColor: colors.brand,
      tabBarInactiveTintColor: colors.textSecondary,
      tabBarLabelStyle: { fontSize: 11, fontWeight: '500' },
    }}>
      <Tabs.Screen name="channels" options={{ title: 'Chats',    tabBarIcon: ({ color }) => <ChatIcon     size={24} color={color} /> }} />
      <Tabs.Screen name="calls"    options={{ title: 'Calls',    tabBarIcon: ({ color }) => <PhoneIcon    size={24} color={color} /> }} />
      <Tabs.Screen name="dms"      options={{ title: 'Direct',   tabBarIcon: ({ color }) => <GroupIcon    size={24} color={color} /> }} />
      <Tabs.Screen name="profile"  options={{ title: 'Settings', tabBarIcon: ({ color }) => <SettingsIcon size={24} color={color} /> }} />
      {/* Hide the files tab from bottom bar; it is reachable from chat header */}
      <Tabs.Screen name="files"    options={{ href: null }} />
    </Tabs>
  )
}