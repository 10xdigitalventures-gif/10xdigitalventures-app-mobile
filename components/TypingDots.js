import React, { useEffect, useRef } from 'react'
import { View, Animated, Easing, StyleSheet } from 'react-native'
import { colors } from '@/lib/theme'

function Dot({ delay }) {
  const v = useRef(new Animated.Value(0)).current
  useEffect(() => {
    const loop = Animated.loop(Animated.sequence([
      Animated.delay(delay),
      Animated.timing(v, { toValue: 1, duration: 350, useNativeDriver: true, easing: Easing.out(Easing.ease) }),
      Animated.timing(v, { toValue: 0, duration: 350, useNativeDriver: true, easing: Easing.in(Easing.ease) }),
    ]))
    loop.start()
    return () => loop.stop()
  }, [delay])
  const translateY = v.interpolate({ inputRange: [0, 1], outputRange: [0, -4] })
  const opacity = v.interpolate({ inputRange: [0, 1], outputRange: [0.4, 1] })
  return <Animated.View style={[styles.dot, { transform: [{ translateY }], opacity }]} />
}

export default function TypingDots() {
  return (
    <View style={styles.row}>
      <Dot delay={0} />
      <Dot delay={150} />
      <Dot delay={300} />
    </View>
  )
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', gap: 4, alignItems: 'center', paddingHorizontal: 4 },
  dot: { width: 6, height: 6, borderRadius: 3, backgroundColor: colors.brand },
})