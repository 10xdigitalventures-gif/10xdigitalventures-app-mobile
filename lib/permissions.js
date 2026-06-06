import { Platform, PermissionsAndroid } from 'react-native'

export async function requestCallPermissions(needVideo) {
  if (Platform.OS !== 'android') return true
  const list = [PermissionsAndroid.PERMISSIONS.RECORD_AUDIO]
  if (needVideo) list.push(PermissionsAndroid.PERMISSIONS.CAMERA)
  // Bluetooth connect is required on Android 12+ for audio routing
  if (PermissionsAndroid.PERMISSIONS.BLUETOOTH_CONNECT) {
    list.push(PermissionsAndroid.PERMISSIONS.BLUETOOTH_CONNECT)
  }
  try {
    const granted = await PermissionsAndroid.requestMultiple(list)
    return Object.values(granted).every(v => v === PermissionsAndroid.RESULTS.GRANTED)
  } catch (e) {
    console.warn('permission error', e)
    return false
  }
}