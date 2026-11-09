// Server-only Google Play Integrity client. Not an HTTP endpoint and not wired to billing.
// Service account private keys must be stored only in server-side secrets.
const tokenUrl = 'https://oauth2.googleapis.com/token';
const scope = 'https://www.googleapis.com/auth/playintegrity';
const encoder = new TextEncoder();
function base64url(bytes) {
  let binary=''; for (const value of bytes) binary+=String.fromCharCode(value);
  return btoa(binary).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
}
function pemBytes(pem) {
  if (typeof pem !== 'string' || !/^-----BEGIN PRIVATE KEY-----[\s\S]+-----END PRIVATE KEY-----\s*$/.test(pem)) throw new Error('Invalid service configuration');
  const data=pem.replace('-----BEGIN PRIVATE KEY-----','').replace('-----END PRIVATE KEY-----','').replace(/\s/g,'');
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(data)) throw new Error('Invalid service configuration');
  const binary=atob(data); return Uint8Array.from(binary,c=>c.charCodeAt(0));
}
export async function decodePlayIntegrityToken({packageName, integrityToken, serviceAccount, fetchImpl=fetch, cryptoImpl=crypto, nowMs=Date.now()}) {
  if (typeof packageName !== 'string' || !/^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/.test(packageName) || packageName.length>255 ||
      typeof integrityToken !== 'string' || integrityToken.length<1 || integrityToken.length>20000 ||
      typeof serviceAccount?.client_email !== 'string' || !/^[^\s@]+@[^\s@]+$/.test(serviceAccount.client_email) ||
      !Number.isSafeInteger(nowMs)) throw new Error('Invalid verification request');
  const issued=Math.floor(nowMs/1000);
  const header=base64url(encoder.encode(JSON.stringify({alg:'RS256',typ:'JWT'})));
  const claims=base64url(encoder.encode(JSON.stringify({iss:serviceAccount.client_email,scope,aud:tokenUrl,iat:issued,exp:issued+300})));
  let key;
  try { key=await cryptoImpl.subtle.importKey('pkcs8',pemBytes(serviceAccount.private_key),{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']); }
  catch (_) { throw new Error('Invalid service configuration'); }
  const unsigned=`${header}.${claims}`;
  const signature=new Uint8Array(await cryptoImpl.subtle.sign('RSASSA-PKCS1-v1_5',key,encoder.encode(unsigned)));
  const assertion=`${unsigned}.${base64url(signature)}`;
  const tokenResponse=await fetchImpl(tokenUrl,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion}),signal:AbortSignal.timeout(5000)});
  if (!tokenResponse.ok) throw new Error('Integrity verification unavailable');
  const tokenBody=await tokenResponse.json();
  if (typeof tokenBody?.access_token !== 'string' || !tokenBody.access_token || tokenBody.access_token.length>8192) throw new Error('Integrity verification unavailable');
  const decodedResponse=await fetchImpl(`https://playintegrity.googleapis.com/v1/${encodeURIComponent(packageName)}:decodeIntegrityToken`,{method:'POST',headers:{Authorization:`Bearer ${tokenBody.access_token}`,'Content-Type':'application/json'},body:JSON.stringify({integrity_token:integrityToken}),signal:AbortSignal.timeout(5000)});
  if (!decodedResponse.ok) throw new Error('Integrity verification unavailable');
  const decoded=await decodedResponse.json();
  if (!decoded || typeof decoded !== 'object' || !decoded.tokenPayloadExternal) throw new Error('Integrity verification unavailable');
  return decoded;
}
