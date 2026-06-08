# =====================================================================
# Mobile App: Fix install-crash + cleanup junk files
#
# DIAGNOSIS:
#   In app/(tabs)/_layout.js, line 64 references `unreadTotal` but the
#   variable was never declared. Phase 3's regex-based patcher missed
#   inserting the `const unreadTotal = ...` line because the anchor it
#   was looking for had slightly different whitespace.
#   Result: ReferenceError on first render -> APK crashes on open.
#
# CLEANUP:
#   - context/CallContext.js.bak-merged  (old backup from Phase 2)
#   - any other *.bak* files left over from earlier scripts
#
# Run from MOBILE repo root:
#   powershell -ExecutionPolicy Bypass -File .\mobile-fix-crash-cleanup.ps1
#   git add -A; git commit -m "Fix crash + cleanup"; git push
#   npx eas build --profile preview --platform android
# =====================================================================

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Read-FileUtf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}
function Write-FileUtf8NoBom([string]$Path, [string]$Content) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
    Write-Host "  wrote: $Path"
}

if (-not (Test-Path "package.json")) {
    Write-Host "ERROR: Run from mobile repo root."
    exit 1
}

Write-Host "==================================================="
Write-Host "Fix crash + cleanup"
Write-Host "==================================================="
Write-Host ""

# =====================================================================
# 1) Fix app/(tabs)/_layout.js -- rewrite cleanly with unreadTotal defined
# =====================================================================
Write-Host "[1/3] Rewriting app/(tabs)/_layout.js (fix unreadTotal crash)..."

$tabsLayout = @'
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
    updateReaction, setUserOnline, setUserOffline, setTyping, applyStatusUpdate,
    unreadCounts,
  } = useChatStore()

  // Compute total unread for the Chats tab badge
  const unreadTotal = Object.values(unreadCounts || {}).reduce((a, b) => a + (b || 0), 0)

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
        socket.on('message:new', (msg) => addMessage(msg.channel_id, msg))
        socket.on('message:edited', ({ message_id, channel_id, content }) => updateMessage(channel_id, message_id, { content, is_edited: 1 }))
        socket.on('message:deleted', ({ message_id, channel_id }) => deleteMessage(channel_id, message_id))
        socket.on('reaction:updated', ({ message_id, channel_id, emoji, user_id, action }) => updateReaction(channel_id, message_id, emoji, user_id, action))
        socket.on('message:status', ({ message_id, user_id, status }) => {
          // Look up the channel that contains this message id
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
        router.replace('/(auth)/login')
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
      {/* Hide the files tab from bottom bar; reachable from chat header */}
      <Tabs.Screen name="files" options={{ href: null }} />
    </Tabs>
  )
}
'@
Write-FileUtf8NoBom -Path "app/(tabs)/_layout.js" -Content $tabsLayout

# =====================================================================
# 2) Delete junk / backup files
# =====================================================================
Write-Host ""
Write-Host "[2/3] Cleaning up backup / junk files..."

$junk = @(
    "context/CallContext.js.bak-merged",
    "context/CallContext.js.bak",
    "context/GroupCallContext.js.bak",
    "app/chat/[channelId].js.bak",
    "components/MessageBubble.js.bak",
    "app/(tabs)/_layout.js.bak"
)

$deletedCount = 0
foreach ($f in $junk) {
    if (Test-Path $f) {
        Remove-Item $f -Force
        Write-Host "  deleted: $f"
        $deletedCount++
    }
}

# Also sweep for any *.bak* under the project (excluding node_modules / .git)
Write-Host "  scanning for stray backup files..."
$strays = Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FullName -notmatch '[\\/]node_modules[\\/]' -and
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
        ($_.Name -like "*.bak*" -or $_.Name -like "*.orig" -or $_.Name -like "*~")
    }
foreach ($s in $strays) {
    Remove-Item $s.FullName -Force
    Write-Host "  deleted: $($s.FullName)"
    $deletedCount++
}

if ($deletedCount -eq 0) {
    Write-Host "  no junk files found (clean already)"
}

# =====================================================================
# 3) Quick sanity check on the rewritten file
# =====================================================================
Write-Host ""
Write-Host "[3/3] Sanity check..."

$check = Read-FileUtf8 "app/(tabs)/_layout.js"
$ok = $true

if ($check -notmatch "const unreadTotal") {
    Write-Host "  FAIL: unreadTotal still missing"
    $ok = $false
} else {
    Write-Host "  OK: unreadTotal defined"
}

if ($check -notmatch "useSafeAreaInsets") {
    Write-Host "  FAIL: useSafeAreaInsets import missing"
    $ok = $false
} else {
    Write-Host "  OK: SafeArea insets wired"
}

if ($check -notmatch "applyStatusUpdate") {
    Write-Host "  FAIL: applyStatusUpdate missing"
    $ok = $false
} else {
    Write-Host "  OK: real-time read receipts wired"
}

if ($check -notmatch "tabBarBadge") {
    Write-Host "  FAIL: tabBarBadge missing"
    $ok = $false
} else {
    Write-Host "  OK: unread badge wired"
}

Write-Host ""
if ($ok) {
    Write-Host "================================================================="
    Write-Host "FIX COMPLETE."
    Write-Host ""
    Write-Host "What was wrong:"
    Write-Host "  app/(tabs)/_layout.js used `unreadTotal` but never declared it."
    Write-Host "  This caused a ReferenceError on the very first tab render,"
    Write-Host "  which is why the APK closed immediately after opening."
    Write-Host ""
    Write-Host "Now do:"
    Write-Host "  git add -A"
    Write-Host "  git commit -m 'Fix unreadTotal crash + cleanup backups'"
    Write-Host "  git push"
    Write-Host ""
    Write-Host "Then rebuild APK:"
    Write-Host "  npx eas build --profile preview --platform android"
    Write-Host "================================================================="
} else {
    Write-Host "WARNING: One or more checks failed. Re-run the script or paste"
    Write-Host "         app/(tabs)/_layout.js content for manual review."
}
