'use strict';
// A short-lived session is shared only within this browser tab. Authorization
// is always checked again against Supabase when a dashboard opens.
window.TripSession = (() => {
  const key = 'trip-cal-dashboard-session-v1';
  function clear() { try { sessionStorage.removeItem(key); } catch (_) {} }
  function save(session, projectUrl) {
    if (!session?.access_token || !session?.user?.id || !projectUrl) return false;
    const expiresAt = Number(session.expires_at) || Math.floor(Date.now() / 1000) + (Number(session.expires_in) || 3600);
    const saved = {projectUrl, access_token: session.access_token, expires_at: expiresAt, user: {id: session.user.id, email: session.user.email || ''}};
    try { sessionStorage.setItem(key, JSON.stringify(saved)); return true; } catch (_) { return false; }
  }
  function read(projectUrl) {
    try {
      const saved = JSON.parse(sessionStorage.getItem(key) || 'null');
      if (!saved || saved.projectUrl !== projectUrl || typeof saved.access_token !== 'string' || !saved.user?.id || !Number.isFinite(saved.expires_at) || saved.expires_at <= Date.now() / 1000) { clear(); return null; }
      return saved;
    } catch (_) { clear(); return null; }
  }
  return {save, read, clear};
})();
