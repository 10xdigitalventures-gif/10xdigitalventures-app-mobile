import { useEffect, useState } from 'react'

let NetInfo = null
try { NetInfo = require('@react-native-community/netinfo').default } catch (e) { NetInfo = null }

/**
 * Returns true if device has internet connectivity, false otherwise.
 * If @react-native-community/netinfo is not installed, defaults to true
 * (assumes online) so app does not break.
 */
export function useOnlineStatus() {
  const [online, setOnline] = useState(true)

  useEffect(() => {
    if (!NetInfo) return
    const unsub = NetInfo.addEventListener((state) => {
      setOnline(!!state.isConnected && state.isInternetReachable !== false)
    })
    NetInfo.fetch().then((state) => {
      setOnline(!!state.isConnected && state.isInternetReachable !== false)
    }).catch(() => {})
    return () => { if (typeof unsub === 'function') unsub() }
  }, [])

  return online
}