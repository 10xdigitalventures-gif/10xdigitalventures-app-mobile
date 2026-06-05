import { Platform } from 'react-native'
import Constants from 'expo-constants'
import api from './api'

export async function registerForPushNotifications() {
  try {
    const isExpoGo = Constants.appOwnership === 'expo'

    // Expo Go on Android SDK 53+ does not support remote push notifications
    if (Platform.OS === 'android' && isExpoGo) {
      console.log('Push notifications skipped in Expo Go on Android.')
      return null
    }

    const Notifications = await import('expo-notifications')
    const Device = await import('expo-device')

    Notifications.setNotificationHandler({
      handleNotification: async () => ({
        shouldShowAlert: true,
        shouldShowBanner: true,
        shouldShowList: true,
        shouldPlaySound: true,
        shouldSetBadge: true,
      }),
    })

    if (!Device.isDevice) return null

    if (Platform.OS === 'android') {
      await Notifications.setNotificationChannelAsync('default', {
        name: 'default',
        importance: Notifications.AndroidImportance.MAX,
        vibrationPattern: [0, 250, 250, 250],
      })
    }

    const { status: existing } = await Notifications.getPermissionsAsync()
    let finalStatus = existing

    if (existing !== 'granted') {
      const { status } = await Notifications.requestPermissionsAsync()
      finalStatus = status
    }

    if (finalStatus !== 'granted') return null

    const projectId =
      Constants.expoConfig?.extra?.eas?.projectId ||
      Constants.easConfig?.projectId

    if (!projectId || projectId === '6872b78b-0888-466d-a60d-123456789abc') {
      console.log('Push notification projectId missing or placeholder. Skipping push token.')
      return null
    }

    const token = (await Notifications.getExpoPushTokenAsync({ projectId })).data

    try {
      await api.post('/users/push-token', { token })
    } catch (error) {
      console.log('Push token save skipped:', error?.message)
    }

    return token
  } catch (error) {
    console.log('Push notification registration skipped:', error?.message)
    return null
  }
}
