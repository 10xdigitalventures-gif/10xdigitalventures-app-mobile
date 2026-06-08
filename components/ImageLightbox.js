import React, { useState } from 'react'
import { Modal, View, Text, TouchableOpacity, Image, Alert, StyleSheet, Pressable } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { CloseIcon } from '@/components/icons'

let MediaLibrary = null
try { MediaLibrary = require('expo-media-library') } catch (e) { MediaLibrary = null }

let FileSystem = null
try { FileSystem = require('expo-file-system') } catch (e) { FileSystem = null }

export default function ImageLightbox({ uri, visible, onClose, fileName }) {
  const [saving, setSaving] = useState(false)
  if (!uri) return null

  const save = async () => {
    if (!MediaLibrary) { Alert.alert('Save', 'Media library not available'); return }
    setSaving(true)
    try {
      const { status } = await MediaLibrary.requestPermissionsAsync()
      if (status !== 'granted') { Alert.alert('Permission denied'); setSaving(false); return }
      // Download to cache first if remote
      let localUri = uri
      if (/^https?:\/\//.test(uri) && FileSystem) {
        const safeName = (fileName || 'image_' + Date.now() + '.jpg').replace(/[^a-zA-Z0-9._-]/g, '_')
        const dest = FileSystem.cacheDirectory + safeName
        const dl = await FileSystem.downloadAsync(uri, dest)
        localUri = dl.uri
      }
      await MediaLibrary.saveToLibraryAsync(localUri)
      Alert.alert('Saved', 'Image saved to your gallery')
    } catch (e) {
      Alert.alert('Save failed', e?.message || 'Could not save image')
    }
    setSaving(false)
  }

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <SafeAreaView style={styles.root}>
        <Pressable style={styles.backdrop} onPress={onClose}>
          <Image source={{ uri }} style={styles.image} resizeMode="contain" />
        </Pressable>
        <View style={styles.topBar}>
          <TouchableOpacity onPress={onClose} style={styles.btn}>
            <CloseIcon size={22} color="#fff" />
          </TouchableOpacity>
          <TouchableOpacity onPress={save} disabled={saving} style={styles.saveBtn}>
            <Text style={styles.saveText}>{saving ? 'Saving...' : 'Save'}</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    </Modal>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#000' },
  backdrop: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  image: { width: '100%', height: '100%' },
  topBar: { position: 'absolute', top: 0, left: 0, right: 0, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', padding: 12, paddingTop: 36 },
  btn: { width: 40, height: 40, borderRadius: 20, backgroundColor: 'rgba(0,0,0,0.5)', alignItems: 'center', justifyContent: 'center' },
  saveBtn: { backgroundColor: 'rgba(0,0,0,0.55)', paddingHorizontal: 14, paddingVertical: 8, borderRadius: 16 },
  saveText: { color: '#fff', fontWeight: '600', fontSize: 13 },
})