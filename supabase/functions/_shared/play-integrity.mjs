// Evaluates ONLY a verdict independently decoded by Google over an authenticated
// server-to-server request. Never pass an app-supplied JSON payload directly.
// This helper does not decode tokens, manage nonces, or enable billing.
export function isAcceptablePlayVerdict(response, expected, nowMs = Date.now()) {
  try {
    const payload = response?.tokenPayloadExternal;
    const request = payload?.requestDetails;
    const app = payload?.appIntegrity;
    const device = payload?.deviceIntegrity;
    const account = payload?.accountDetails;
    const signatures = expected?.certificateDigests;
    if (!expected || typeof expected.packageName !== 'string' || !expected.packageName ||
        typeof expected.requestHash !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(expected.requestHash) ||
        !Array.isArray(signatures) || signatures.length === 0 ||
        !signatures.every(value => typeof value === 'string' && /^[A-Za-z0-9_-]{43}=?$/.test(value)) ||
        !Number.isSafeInteger(expected.minVersionCode) || expected.minVersionCode < 1 ||
        !Number.isSafeInteger(nowMs)) return false;
    if (request?.requestPackageName !== expected.packageName || request?.requestHash !== expected.requestHash) return false;
    if (typeof request.timestampMillis !== 'string' || !/^\d{1,16}$/.test(request.timestampMillis)) return false;
    const timestamp = Number(request.timestampMillis);
    if (!Number.isSafeInteger(timestamp) || timestamp > nowMs + 30000 || nowMs - timestamp > 120000) return false;
    if (app?.appRecognitionVerdict !== 'PLAY_RECOGNIZED' || app?.packageName !== expected.packageName ||
        typeof app.versionCode !== 'string' || !/^\d{1,15}$/.test(app.versionCode) ||
        !Number.isSafeInteger(Number(app.versionCode)) || Number(app.versionCode) < expected.minVersionCode ||
        !Array.isArray(app.certificateSha256Digest) || !app.certificateSha256Digest.some(value => signatures.includes(value))) return false;
    if (!Array.isArray(device?.deviceRecognitionVerdict) || !device.deviceRecognitionVerdict.includes('MEETS_DEVICE_INTEGRITY')) return false;
    if (account?.appLicensingVerdict !== 'LICENSED') return false;
    return true;
  } catch (_) { return false; }
}
