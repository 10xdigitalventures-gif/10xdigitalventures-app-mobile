import React, { useEffect, useRef, useState } from 'react'
import { View, Text, TouchableOpacity, Animated, StyleSheet, PanResponder, Alert } from 'react-native'
import { colors } from '@/lib/theme'

// Lazy require to avoid crash if expo-av is not installed
let Audio = null
try { Audio = require('expo-av').Audio } catch (e) { Audio = null }

const SWIPE_CANCEL_DISTANCE = 80   // px to the left to cancel

export default function VoiceRecorder({ onSend, onCancel, channelId }) {
  // controlled component: parent toggles `recording` by mounting/unmounting
  const [seconds, setSeconds] = useState(0)
  const [recording, setRecording] = useState(null)
  const recordingRef = useRef(null)
  const cancelledRef = useRef(false)
  const intervalRef = useRef(null)
  const slideX = useRef(new Animated.Value(0)).current

  // PanResponder for swipe-to-cancel
  const pan = useRef(PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: () => true,
    onPanResponderMove: (_, g) => {
      if (g.dx < 0) slideX.setValue(Math.max(g.dx, -120))
    },
    onPanResponderRelease: (_, g) => {
      if (g.dx < -SWIPE_CANCEL_DISTANCE) {
        cancelledRef.current = true
        stopAndDiscard()
      } else {
        Animated.spring(slideX, { toValue: 0, useNativeDriver: true }).start()
      }
    },
  })).current

  useEffect(() => {
    start()
    intervalRef.current = setInterval(() => setSeconds(s => s + 1), 1000)
    return () => {
      clearInterval(intervalRef.current)
      stopAndDiscard()
    }
  }, [])

  const start = async () => {
    if (!Audio) { Alert.alert('Voice notes', 'expo-av not installed'); onCancel(); return }
    try {
      const { status } = await Audio.requestPermissionsAsync()
      if (status !== 'granted') { Alert.alert('Mic permission denied'); onCancel(); return }
      await Audio.setAudioModeAsync({ allowsRecordingIOS: true, playsInSilentModeIOS: true })
      const rec = new Audio.Recording()
      await rec.prepareToRecordAsync(Audio.RecordingOptionsPresets.HIGH_QUALITY)
      await rec.startAsync()
      recordingRef.current = rec
      setRecording(rec)
    } catch (e) {
      console.warn('record start error', e)
      Alert.alert('Could not start recording', e?.message || '')
      onCancel()
    }
  }

  const stopAndDiscard = async () => {
    try {
      if (recordingRef.current) {
        await recordingRef.current.stopAndUnloadAsync()
        recordingRef.current = null
      }
    } catch (e) {}
    onCancel()
  }

  const stopAndSend = async () => {
    try {
      const rec = recordingRef.current
      if (!rec) return onCancel()
      await rec.stopAndUnloadAsync()
      const uri = rec.getURI()
      recordingRef.current = null
      if (!uri) return onCancel()
      onSend(uri, seconds)
    } catch (e) {
      console.warn('record stop error', e)
      onCancel()
    }
  }

  const mm = String(Math.floor(seconds / 60)).padStart(2, '0')
  const ss = String(seconds % 60).padStart(2, '0')

  return (
    <Animated.View style={[styles.bar, { transform: [{ translateX: slideX }] }]} {...pan.panHandlers}>
      <View style={styles.recordingDot} />
      <Text style={styles.time}>{mm}:{ss}</Text>
      <Text style={styles.hint}>Slide left to cancel</Text>
      <TouchableOpacity onPress={stopAndSend} style={styles.sendBtn}>
        <Text style={{ color: '#fff', fontWeight: '700' }}>SEND</Text>
      </TouchableOpacity>
    </Animated.View>
  )
}

const styles = StyleSheet.create({
  bar: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 8, paddingHorizontal: 12, backgroundColor: colors.bgRaised, borderRadius: 22, flex: 1 },
  recordingDot: { width: 10, height: 10, borderRadius: 5, backgroundColor: '#f15c6d' },
  time: { color: colors.textPrimary, fontVariant: ['tabular-nums'], fontSize: 14, minWidth: 48 },
  hint: { flex: 1, color: colors.textSecondary, fontSize: 12 },
  sendBtn: { backgroundColor: colors.brand, paddingHorizontal: 14, paddingVertical: 6, borderRadius: 14 },
})