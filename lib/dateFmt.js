import { format, isToday, isYesterday, differenceInMinutes, differenceInHours, differenceInDays } from 'date-fns'

export function bubbleTime(ts) {
  if (!ts) return ''
  try { return format(new Date(ts), 'h:mm a') } catch { return '' }
}

export function divider(ts) {
  if (!ts) return ''
  const d = new Date(ts)
  if (isToday(d)) return 'Today'
  if (isYesterday(d)) return 'Yesterday'
  try {
    const diff = differenceInDays(new Date(), d)
    if (diff < 7) return format(d, 'EEEE')   // Monday, Tuesday...
    return format(d, 'd MMM yyyy')
  } catch { return '' }
}

export function lastSeenText(ts, isOnline) {
  if (isOnline) return 'online'
  if (!ts) return ''
  const d = new Date(ts)
  const mins = differenceInMinutes(new Date(), d)
  if (mins < 1) return 'last seen just now'
  if (mins < 60) return 'last seen ' + mins + ' min ago'
  const hrs = differenceInHours(new Date(), d)
  if (hrs < 24) return 'last seen ' + hrs + 'h ago'
  if (isYesterday(d)) return 'last seen yesterday at ' + format(d, 'h:mm a')
  return 'last seen ' + format(d, 'd MMM')
}

export function sameDay(a, b) {
  if (!a || !b) return false
  try {
    const x = new Date(a), y = new Date(b)
    return x.getFullYear() === y.getFullYear() && x.getMonth() === y.getMonth() && x.getDate() === y.getDate()
  } catch { return false }
}