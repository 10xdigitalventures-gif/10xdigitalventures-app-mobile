import React from 'react'
import { Modal, View, Text, TouchableOpacity, Pressable, StyleSheet, Share } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { colors } from '@/lib/theme'

let Clipboard = null
try { Clipboard = require('expo-clipboard') } catch (e) { Clipboard = null }

const QUICK_EMOJIS = ['\u{1F44D}', '\u2764\uFE0F', '\u{1F602}', '\u{1F62E}', '\u{1F625}', '\u{1F64F}']

export default function MessageActionSheet({ visible, msg, isOwn, onClose, onReact, onReply, onDelete }) {
  if (!visible || !msg) return null

  const copy = async () => {
    try {
      if (Clipboard?.setStringAsync) await Clipboard.setStringAsync(msg.content || '')
    } catch (e) {}
    onClose()
  }

  const forward = async () => {
    try { await Share.share({ message: msg.content || '' }) } catch (e) {}
    onClose()
  }

  return (
    <Modal visible transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={(e) => e.stopPropagation()}>
          {/* Quick reactions */}
          <View style={styles.reactionsRow}>
            {QUICK_EMOJIS.map(e => (
              <TouchableOpacity key={e} onPress={() => { onReact(e); onClose() }} style={styles.emojiBtn}>
                <Text style={{ fontSize: 28 }}>{e}</Text>
              </TouchableOpacity>
            ))}
          </View>

          <View style={styles.divider} />

          {/* Actions */}
          <TouchableOpacity style={styles.actionRow} onPress={() => { onReply(); onClose() }}>
            <Text style={styles.actionLabel}>Reply</Text>
          </TouchableOpacity>
          {msg.type === 'text' && (
            <TouchableOpacity style={styles.actionRow} onPress={copy}>
              <Text style={styles.actionLabel}>Copy</Text>
            </TouchableOpacity>
          )}
          <TouchableOpacity style={styles.actionRow} onPress={forward}>
            <Text style={styles.actionLabel}>Forward</Text>
          </TouchableOpacity>
          {isOwn && (
            <TouchableOpacity style={styles.actionRow} onPress={() => { onDelete(); onClose() }}>
              <Text style={[styles.actionLabel, { color: colors.danger }]}>Delete</Text>
            </TouchableOpacity>
          )}
        </Pressable>
      </Pressable>
    </Modal>
  )
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.55)', justifyContent: 'flex-end' },
  sheet: { backgroundColor: colors.bgSurface, borderTopLeftRadius: 20, borderTopRightRadius: 20, paddingTop: 12, paddingBottom: 28 },
  reactionsRow: { flexDirection: 'row', justifyContent: 'space-around', paddingHorizontal: 12, paddingVertical: 8 },
  emojiBtn: { padding: 6 },
  divider: { height: 0.5, backgroundColor: colors.bgDivider, marginVertical: 6 },
  actionRow: { paddingHorizontal: 20, paddingVertical: 14 },
  actionLabel: { color: colors.textPrimary, fontSize: 16 },
})