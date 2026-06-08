import AsyncStorage from '@react-native-async-storage/async-storage'

const KEY_CHANNELS = '10x_cache_channels_v1'
const KEY_USER     = '10x_cache_user_v1'
const KEY_MSG_PREFIX = '10x_cache_msgs_v1_'
const MAX_MSGS_PER_CHANNEL = 200

export async function saveChannelsCache(channels) {
  try {
    await AsyncStorage.setItem(KEY_CHANNELS, JSON.stringify(channels || []))
  } catch (e) {}
}

export async function loadChannelsCache() {
  try {
    const s = await AsyncStorage.getItem(KEY_CHANNELS)
    return s ? JSON.parse(s) : []
  } catch (e) { return [] }
}

export async function saveUserCache(user) {
  try {
    if (user) await AsyncStorage.setItem(KEY_USER, JSON.stringify(user))
  } catch (e) {}
}

export async function loadUserCache() {
  try {
    const s = await AsyncStorage.getItem(KEY_USER)
    return s ? JSON.parse(s) : null
  } catch (e) { return null }
}

export async function saveMessagesCache(channelId, msgs) {
  try {
    if (!channelId) return
    // Keep only last N messages to avoid storage bloat
    const trimmed = Array.isArray(msgs) ? msgs.slice(-MAX_MSGS_PER_CHANNEL) : []
    await AsyncStorage.setItem(KEY_MSG_PREFIX + channelId, JSON.stringify(trimmed))
  } catch (e) {}
}

export async function loadMessagesCache(channelId) {
  try {
    if (!channelId) return []
    const s = await AsyncStorage.getItem(KEY_MSG_PREFIX + channelId)
    return s ? JSON.parse(s) : []
  } catch (e) { return [] }
}

export async function clearAllCache() {
  try {
    const keys = await AsyncStorage.getAllKeys()
    const ours = keys.filter(k => k === KEY_CHANNELS || k === KEY_USER || k.startsWith(KEY_MSG_PREFIX))
    if (ours.length > 0) await AsyncStorage.multiRemove(ours)
  } catch (e) {}
}