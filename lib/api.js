import axios from 'axios'
import Constants from 'expo-constants'
import * as SecureStore from 'expo-secure-store'

const extra = Constants.expoConfig?.extra || Constants.manifest?.extra || {}

const API_URL =
  process.env.EXPO_PUBLIC_API_URL ||
  extra.apiUrl ||
  'https://api.10xdigitalventures.com/api'

const api = axios.create({
  baseURL: API_URL,
  timeout: 20000,
  headers: {
    'Content-Type': 'application/json',
  },
})

api.interceptors.request.use(async (config) => {
  const token = await SecureStore.getItemAsync('token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

api.interceptors.response.use(
  (response) => response,
  (error) => {
    console.log('API ERROR:', {
      baseURL: API_URL,
      url: error?.config?.url,
      method: error?.config?.method,
      message: error?.message,
      status: error?.response?.status,
      data: error?.response?.data,
    })
    return Promise.reject(error)
  }
)

export { API_URL }
export default api
