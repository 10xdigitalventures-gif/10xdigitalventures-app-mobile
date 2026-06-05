import { io } from 'socket.io-client'
import * as SecureStore from 'expo-secure-store'

let socket = null

export const getSocket = async () => {
  if (!socket) {
    const token = await SecureStore.getItemAsync('token')
    const SOCKET_URL = process.env.EXPO_PUBLIC_SOCKET_URL || 'http://localhost:5000'

    socket = io(SOCKET_URL, {
      auth: { token },
      transports: ['polling', 'websocket'], // Allow polling for Hostinger
    })
  }
  return socket
}

export const disconnectSocket = () => {
  if (socket) { socket.disconnect(); socket = null }
}
