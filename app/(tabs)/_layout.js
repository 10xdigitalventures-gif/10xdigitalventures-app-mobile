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
import { loadChannelsCache, loadUserCache } from '@/lib/cache'

export default function TabsLayout() {
  const insets = useSafeAreaInsets()
  const router = useRouter()
  const {
    setUser, setChannels, addChannel, addMessage, updateMessage, deleteMessage,
    updateReaction, setUserOnline, setUserOffline, setTyping, applyStatusUpdate,
    unreadCounts, hydrate,
  } = useChatStore()

  const unreadTotal = Object.values(unreadCounts || {}).reduce((a, b) => a + (b || 0), 0)

  useEffect(() => {
    const init = async () => {
      const token = await SecureStore.getItemAsync('token')
      if (!token) { router.replace('/(auth)/login'); return }

      // 1) Instant hydrate from offline cache (no white screen)
      try {
        const [cachedUser, cachedChannels] = await Promise.all([loadUserCache(), loadChannelsCache()])
        hydrate({ user: cachedUser, channels: cachedChannels })
      } catch (e) {}

      // 2) Fresh data from network (will overwrite cache via store setters)
      try {
        const [meRes, chRes] = await Promise.all([api.get('/auth/me'), api.get('/channels')])
        setUser(meRes.data?.data || meRes.data)
        setChannels(Array.isArray(chRes.data?.data) ? chRes.data.data : Array.isArray(chRes.data) ? chRes.data : [])
      } catch (e) {
        // Offline / network down -- continue with cached data
        console.log('Network init failed (offline?). Using cached data.')
      }

      // 3) Try socket connection regardless
      try {
        const socket = await getSocket()
        socket.emit('join:channels')
        socket.on('message:new', (msg) => addMessage(msg.channel_id, msg))
        socket.on('message:edited', ({ message_id, channel_id, content }) => updateMessage(channel_id, message_id, { content, is_edited: 1 }))
        socket.on('message:deleted', ({ message_id, channel_id }) => deleteMessage(channel_id, message_id))
        socket.on('reaction:updated', ({ message_id, channel_id, emoji, user_id, action }) => updateReaction(channel_id, message_id, emoji, user_id, action))
        socket.on('message:status', ({ message_id, user_id, status }) => {
          const state = useChatStore.getState()
          for (const cid of Object.keys(state.messages || {})) {
            if ((state.messages[cid] || []).some((m) => m.id === message_id)) {
              applyStatusUpdate(cid, message_id, user_id, status)
              break
            }
          }
        })
        socket.on('user:online',  ({ user_id }) => setUserOnline(user_id))
        socket.on('user:offline', ({ user_id }) => setUserOffline(user_id))
        socket.on('typing:start', ({ user_id, channel_id }) => setTyping(channel_id, user_id, true))
        socket.on('typing:stop',  ({ user_id, channel_id }) => setTyping(channel_id, user_id, false))
        socket.on('channel:new',  (ch) => { addChannel(ch); socket.emit('join:channels') })
      } catch (e) {
        console.log('Socket connect failed (offline?).')
      }
    }
    init()
    return () => disconnectSocket()
  }, [])

  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarStyle: {
          backgroundColor: colors.bgSurface,
          borderTopColor: colors.bgDivider,
          borderTopWidth: 0.5,
          height: 60 + insets.bottom,
          paddingTop: 6,
          paddingBottom: Math.max(insets.bottom, 8),
        },
        tabBarActiveTintColor: colors.brand,
        tabBarInactiveTintColor: colors.textSecondary,
        tabBarLabelStyle: { fontSize: 11, fontWeight: '500' },
      }}
    >
      <Tabs.Screen
        name="channels"
        options={{
          title: 'Chats',
          tabBarIcon: ({ color }) => <ChatIcon size={24} color={color} />,
          tabBarBadge: unreadTotal > 0 ? unreadTotal : undefined,
          tabBarBadgeStyle: { backgroundColor: colors.danger, color: '#fff', fontSize: 10 },
        }}
      />
      <Tabs.Screen
        name="calls"
        options={{
          title: 'Calls',
          tabBarIcon: ({ color }) => <PhoneIcon size={24} color={color} />,
        }}
      />
      <Tabs.Screen
        name="dms"
        options={{
          title: 'Direct',
          tabBarIcon: ({ color }) => <GroupIcon size={24} color={color} />,
        }}
      />
      <Tabs.Screen
        name="profile"
        options={{
          title: 'Settings',
          tabBarIcon: ({ color }) => <SettingsIcon size={24} color={color} />,
        }}
      />
      <Tabs.Screen name="files" options={{ href: null }} />
      <Tabs.Screen name="new-chat" options={{ href: null }} />
    </Tabs>
  )
}