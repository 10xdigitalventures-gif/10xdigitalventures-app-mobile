// Safe wrapper around expo-haptics. If module is unavailable (web / dev
// without native build), all calls become no-ops.
let H = null
try { H = require('expo-haptics') } catch (e) { H = null }

export function tapLight()  { try { H?.impactAsync(H.ImpactFeedbackStyle.Light)  } catch (e) {} }
export function tapMedium() { try { H?.impactAsync(H.ImpactFeedbackStyle.Medium) } catch (e) {} }
export function tapHeavy()  { try { H?.impactAsync(H.ImpactFeedbackStyle.Heavy)  } catch (e) {} }
export function selection() { try { H?.selectionAsync() } catch (e) {} }
export function success()   { try { H?.notificationAsync(H.NotificationFeedbackType.Success) } catch (e) {} }
export function warning()   { try { H?.notificationAsync(H.NotificationFeedbackType.Warning) } catch (e) {} }