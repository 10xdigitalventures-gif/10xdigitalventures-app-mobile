import { saveCrash } from '@/lib/cache'

let installed = false

export function installGlobalErrorHandlers() {
  if (installed) return
  installed = true

  // Catch unhandled JS errors
  try {
    const ErrorUtils = (global).ErrorUtils
    if (ErrorUtils && typeof ErrorUtils.setGlobalHandler === 'function') {
      const prev = ErrorUtils.getGlobalHandler ? ErrorUtils.getGlobalHandler() : null
      ErrorUtils.setGlobalHandler((err, isFatal) => {
        try {
          saveCrash({
            message: String(err?.message || err),
            stack: String(err?.stack || ''),
            fatal: !!isFatal,
            source: 'globalErrorHandler',
          })
        } catch (e) {}
        console.error('[GlobalError]', err)
        if (prev) try { prev(err, isFatal) } catch (e) {}
      })
    }
  } catch (e) {}

  // Catch unhandled promise rejections
  try {
    const tracker = require('promise/setimmediate/rejection-tracking')
    tracker.enable({
      allRejections: true,
      onUnhandled: (id, err) => {
        try {
          saveCrash({
            message: 'Unhandled promise rejection: ' + String(err?.message || err),
            stack: String(err?.stack || ''),
            source: 'unhandledRejection',
          })
        } catch (e) {}
        console.warn('[UnhandledPromise]', id, err)
      },
      onHandled: () => {},
    })
  } catch (e) {}
}