import test from 'node:test';
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import {decodePlayIntegrityToken} from '../supabase/functions/_shared/google-play-client.mjs';
function b64(bytes) { return Buffer.from(bytes).toString('base64'); }
const decode = s => Buffer.from(s,'base64url');
test('uses only Google endpoints and signs a short-lived server assertion', async () => {
  const pair=await webcrypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
  const privateKey=await webcrypto.subtle.exportKey('pkcs8',pair.privateKey);
  const account={client_email:'server@example.iam.gserviceaccount.com',private_key:`-----BEGIN PRIVATE KEY-----\n${b64(privateKey)}\n-----END PRIVATE KEY-----`};
  const calls=[];
  const fetchImpl=async (url,options) => {
    calls.push({url,options});
    if (calls.length===1) return {ok:true,json:async()=>({access_token:'test-access-token'})};
    return {ok:true,json:async()=>({tokenPayloadExternal:{requestDetails:{requestHash:'test'}}})};
  };
  const result=await decodePlayIntegrityToken({packageName:'com.tripcal.app',integrityToken:'test-token',serviceAccount:account,fetchImpl,cryptoImpl:webcrypto,nowMs:1800000000000});
  assert.equal(result.tokenPayloadExternal.requestDetails.requestHash,'test');
  assert.equal(calls[0].url,'https://oauth2.googleapis.com/token');
  assert.equal(calls[1].url,'https://playintegrity.googleapis.com/v1/com.tripcal.app:decodeIntegrityToken');
  assert.equal(calls[1].options.headers.Authorization,'Bearer test-access-token');
  assert.deepEqual(JSON.parse(calls[1].options.body),{integrity_token:'test-token'});
  const assertion=calls[0].options.body.get('assertion'), [header,payload,signature]=assertion.split('.');
  const claims=JSON.parse(decode(payload));
  assert.equal(claims.aud,'https://oauth2.googleapis.com/token');
  assert.equal(claims.exp-claims.iat,300);
  assert.equal(await webcrypto.subtle.verify('RSASSA-PKCS1-v1_5',pair.publicKey,decode(signature),new TextEncoder().encode(`${header}.${payload}`)),true);
  await assert.rejects(()=>decodePlayIntegrityToken({packageName:'com.tripcal.app',integrityToken:'test-token',serviceAccount:account,fetchImpl:async()=>({ok:false}),cryptoImpl:webcrypto,nowMs:1800000000000}),/verification unavailable/);
});
test('fails closed for missing configuration and Google errors', async () => {
  await assert.rejects(()=>decodePlayIntegrityToken({packageName:'https://attacker',integrityToken:'x',serviceAccount:{}}));
  await assert.rejects(()=>decodePlayIntegrityToken({packageName:'com.tripcal.app',integrityToken:'x',serviceAccount:{client_email:'x@y',private_key:'not-a-key'},cryptoImpl:webcrypto}));
});
