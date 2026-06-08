import { create } from 'zustand'

function unwrap(v) { return v?.data || v }

function toArray(v) {
  const x = unwrap(v)
  if (Array.isArray(x)) return x
  if (typeof x === 'string') {
    try { const p = JSON.parse(x); return Array.isArray(p) ? p : [] } catch { return [] }
  }
  return []
}

function normalizeMsg(m) {
  if (!m || typeof m !== 'object') return m
  return { ...m, reactions: toArray(m.reactions), status: toArray(m.status) }
}

const useChatStore = create((set, get) => ({
  user: null,
  channels: [],
  activeChannel: null,
  messages: {},
  onlineUsers: new Set(),
  typingUsers: {},
  members: [],
  replyTo: {},          // channelId -> message being replied to
  unreadCounts: {},     // channelId -> number
  lastSeen: {},         // userId -> timestamp

  setUser: (user) => set({ user: unwrap(user) }),
  setChannels: (channels) => set({ channels: toArray(channels) }),
  setActiveChannel: (channel) => set({ activeChannel: channel }),
  setMembers: (members) => set({ members: toArray(members) }),

  setReplyTo: (channelId, msg) => set((s) => ({
    replyTo: { ...s.replyTo, [channelId]: msg || null }
  })),

  clearUnread: (channelId) => set((s) => ({
    unreadCounts: { ...s.unreadCounts, [channelId]: 0 }
  })),

  setLastSeen: (userId, ts) => set((s) => ({
    lastSeen: { ...s.lastSeen, [userId]: ts }
  })),

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
    messages: { ...s.messages, [channelId]: toArray(msgs).map(normalizeMsg) }
  })),

  addMessage: (channelId, msg) => set((s) => {
    const newMsgs = { ...s.messages, [channelId]: [...(s.messages[channelId] || []), normalizeMsg(msg)] }
    const isActive = s.activeChannel?.id === channelId
    const isOwn = msg.sender_id === s.user?.id
    const inc = (!isActive && !isOwn) ? 1 : 0
    return {
      messages: newMsgs,
      unreadCounts: { ...s.unreadCounts, [channelId]: (s.unreadCounts[channelId] || 0) + inc }
    }
  }),

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
        if (action === 'removed') reactions = reactions.filter((r) => !(r.emoji === emoji && r.user_id === userId))
        else reactions.push({ emoji, user_id: userId })
        return { ...m, reactions }
      }),
    },
  })),

  // Real-time status update from server (delivered/read echo)
  applyStatusUpdate: (channelId, messageId, userId, status) => set((s) => ({
    messages: {
      ...s.messages,
      [channelId]: (s.messages[channelId] || []).map((m) => {
        if (m.id !== messageId) return m
        const stats = toArray(m.status)
        const i = stats.findIndex(x => x.user_id === userId)
        const now = new Date().toISOString()
        const patch = status === 'read' ? { read_at: now, delivered_at: now } : { delivered_at: now }
        if (i === -1) stats.push({ user_id: userId, ...patch })
        else stats[i] = { ...stats[i], ...patch }
        return { ...m, status: stats }
      }),
    },
  })),

  setUserOnline: (userId) => set((s) => {
    const o = new Set(s.onlineUsers); o.add(userId); return { onlineUsers: o }
  }),
  setUserOffline: (userId) => set((s) => {
    const o = new Set(s.onlineUsers); o.delete(userId)
    return { onlineUsers: o, lastSeen: { ...s.lastSeen, [userId]: Date.now() } }
  }),

  setTyping: (channelId, userId, isTyping) => set((s) => {
    const t = { ...s.typingUsers }
    if (!t[channelId]) t[channelId] = new Set()
    else t[channelId] = new Set(t[channelId])
    isTyping ? t[channelId].add(userId) : t[channelId].delete(userId)
    return { typingUsers: t }
  }),
}))

export default useChatStore