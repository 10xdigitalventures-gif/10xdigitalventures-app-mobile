import Constants from 'expo-constants'
import { io } from 'socket.io-client'
import * as SecureStore from 'expo-secure-store'

const extra = Constants.expoConfig?.extra || Constants.manifest?.extra || {}

const SOCKET_URL =
  process.env.EXPO_PUBLIC_SOCKET_URL ||
  extra.socketUrl ||
  'https://api.10xdigitalventures.com'

let socket = null

export async function getSocket() {
  if (socket?.connected) return socket

  const token = await SecureStore.getItemAsync('token')

  socket = io(SOCKET_URL, {
    transports: ['websocket', 'polling'],
    auth: { token },
    extraHeaders: token ? { Authorization: `Bearer ${token}` } : {},
    reconnection: true,
    reconnectionAttempts: 10,
    reconnectionDelay: 1000,
  })

  socket.on('connect_error', (err) => {
    console.log('SOCKET CONNECT ERROR:', err?.message)
  })

  return socket
}

export function disconnectSocket() {
  if (socket) {
    socket.disconnect()
    socket = null
  }
}

export { SOCKET_URL }
