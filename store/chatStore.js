import { create } from 'zustand'

function unwrap(v) {
  return v?.data || v
}

function toArray(v) {
  const x = unwrap(v)
  if (Array.isArray(x)) return x
  if (typeof x === 'string') {
    try {
      const parsed = JSON.parse(x)
      return Array.isArray(parsed) ? parsed : []
    } catch {
      return []
    }
  }
  return []
}

function normalizeMsg(m) {
  if (!m || typeof m !== 'object') return m
  return {
    ...m,
    reactions: toArray(m.reactions),
    status: toArray(m.status),
  }
}

const useChatStore = create((set) => ({
  user: null,
  channels: [],
  activeChannel: null,
  messages: {},
  onlineUsers: new Set(),
  typingUsers: {},
  members: [],

  setUser: (user) => set({ user: unwrap(user) }),

  setChannels: (channels) => set({
    channels: toArray(channels),
  }),

  setActiveChannel: (channel) => set({ activeChannel: channel }),

  setMembers: (members) => set({
    members: toArray(members),
  }),

  addChannel: (ch) => set((s) => {
    const channel = unwrap(ch)
    if (!channel || !channel.id) return { channels: toArray(s.channels) }

    const list = toArray(s.channels)
    const exists = list.some((c) => c.id === channel.id)

    return {
      channels: exists
        ? list.map((c) => c.id === channel.id ? { ...c, ...channel } : c)
        : [...list, channel],
    }
  }),

  setMessages: (channelId, msgs) => set((s) => ({
    messages: {
      ...s.messages,
      [channelId]: toArray(msgs).map(normalizeMsg),
    },
  })),

  addMessage: (channelId, msg) => set((s) => ({
    messages: {
      ...s.messages,
      [channelId]: [...(s.messages[channelId] || []), normalizeMsg(msg)],
    },
  })),

  updateMessage: (channelId, messageId, updates) => set((s) => ({
    messages: {
      ...s.messages,
      [channelId]: (s.messages[channelId] || []).map((m) =>
        m.id === messageId ? { ...m, ...updates } : m
      ),
    },
  })),

  deleteMessage: (channelId, messageId) => set((s) => ({
    messages: {
      ...s.messages,
      [channelId]: (s.messages[channelId] || []).map((m) =>
        m.id === messageId ? { ...m, is_deleted: 1 } : m
      ),
    },
  })),

  updateReaction: (channelId, messageId, emoji, userId, action) => set((s) => ({
    messages: {
      ...s.messages,
      [channelId]: (s.messages[channelId] || []).map((m) => {
        if (m.id !== messageId) return m

        let reactions = toArray(m.reactions)

        if (action === 'removed') {
          reactions = reactions.filter((r) => !(r.emoji === emoji && r.user_id === userId))
        } else {
          reactions.push({ emoji, user_id: userId })
        }

        return { ...m, reactions }
      }),
    },
  })),

  setUserOnline: (userId) => set((s) => {
    const o = new Set(s.onlineUsers)
    o.add(userId)
    return { onlineUsers: o }
  }),

  setUserOffline: (userId) => set((s) => {
    const o = new Set(s.onlineUsers)
    o.delete(userId)
    return { onlineUsers: o }
  }),

  setTyping: (channelId, userId, isTyping) => set((s) => {
    const t = { ...s.typingUsers }

    if (!t[channelId]) {
      t[channelId] = new Set()
    } else {
      t[channelId] = new Set(t[channelId])
    }

    isTyping ? t[channelId].add(userId) : t[channelId].delete(userId)

    return { typingUsers: t }
  }),
}))

export default useChatStore
