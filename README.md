# 10x Chat - Mobile App (React Native + Expo)

## Setup

1. Install Expo CLI:
```
npm install -g expo-cli eas-cli
```

2. Install dependencies:
```
npm install
```

3. Edit `.env` with your backend URL

4. Start dev server:
```
npx expo start
```
Scan QR with Expo Go app on your phone.

## Build for Production

### Android APK
```
eas build --platform android --profile preview
```

### iOS (needs Mac + Apple account)
```
eas build --platform ios
```

### Setup EAS first
```
eas init
eas build:configure
```

## Screens
- Login / Register
- Channels list (tab 1)
- Direct Messages (tab 2)
- Files browser (tab 3)
- Profile & settings (tab 4)
- Chat screen (full screen per channel)

## Features
- Real-time messaging (Socket.io)
- File & image sharing
- Emoji reactions
- Edit & delete messages
- Push notifications (Expo)
- Online/offline status
- Typing indicators
