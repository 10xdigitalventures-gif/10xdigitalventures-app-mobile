import { Platform, PermissionsAndroid, Alert, Linking } from 'react-native'

/**
 * Request mic (always) + camera (if video) permissions for a call.
 * Returns true if the MINIMUM required perms are granted.
 *
 * - Bluetooth perm is requested best-effort (some devices need it for
 *   headset audio) but is NOT required. If user denies it, calls still
 *   work over the regular speaker/earpiece.
 * - On Android we also detect "never_ask_again" and prompt the user to
 *   open settings.
 * - On iOS the system handles permissions per-track inside getUserMedia
 *   itself, so we just return true here and let the WebRTC layer prompt.
 */
export async function requestCallPermissions(needVideo) {
  if (Platform.OS !== 'android') return true

  const RESULTS = PermissionsAndroid.RESULTS
  const PERMS = PermissionsAndroid.PERMISSIONS

  // ---- 1) Mic is always required ----
  const requiredList = [PERMS.RECORD_AUDIO]
  if (needVideo && PERMS.CAMERA) requiredList.push(PERMS.CAMERA)

  let result = {}
  try {
    result = await PermissionsAndroid.requestMultiple(requiredList)
  } catch (e) {
    console.warn('permission requestMultiple error', e)
    return false
  }

  const blocked = []
  const denied = []
  for (const perm of requiredList) {
    const v = result[perm]
    if (v === RESULTS.GRANTED) continue
    if (v === RESULTS.NEVER_ASK_AGAIN) blocked.push(perm)
    else denied.push(perm)
  }

  // ---- 2) Bluetooth connect (best-effort, only Android 12+) ----
  // Fire-and-forget; do NOT block the call decision on this.
  if (PERMS.BLUETOOTH_CONNECT) {
    PermissionsAndroid.request(PERMS.BLUETOOTH_CONNECT).catch(() => {})
  }

  if (blocked.length > 0) {
    // User selected "Don't ask again" earlier; have to send them to settings.
    Alert.alert(
      'Permission needed',
      'Please enable Microphone' + (needVideo ? ' and Camera' : '') + ' for 10x Chat in your phone Settings.',
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Open Settings', onPress: () => Linking.openSettings() },
      ]
    )
    return false
  }

  if (denied.length > 0) {
    // User tapped "Deny" this time; show a soft hint, no settings link.
    Alert.alert('Permission denied', 'Microphone access is required to make calls.')
    return false
  }

  return true
}

/**
 * Check (do not request) if the required perms are already granted.
 * Useful to skip an extra prompt when accepting an incoming call.
 */
export async function hasCallPermissions(needVideo) {
  if (Platform.OS !== 'android') return true
  const PERMS = PermissionsAndroid.PERMISSIONS
  const checks = [PermissionsAndroid.check(PERMS.RECORD_AUDIO)]
  if (needVideo && PERMS.CAMERA) checks.push(PermissionsAndroid.check(PERMS.CAMERA))
  const results = await Promise.all(checks).catch(() => [])
  return results.every(Boolean)
}