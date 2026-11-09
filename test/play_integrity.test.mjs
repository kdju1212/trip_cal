import test from 'node:test';
import assert from 'node:assert/strict';
import {isAcceptablePlayVerdict} from '../supabase/functions/_shared/play-integrity.mjs';
const now = 1800000000000;
const hash = 'A'.repeat(43), cert = 'B'.repeat(43);
const expected = {packageName:'com.tripcal.app', requestHash:hash, certificateDigests:[cert], minVersionCode:4};
const valid = () => ({tokenPayloadExternal:{
  requestDetails:{requestPackageName:'com.tripcal.app',requestHash:hash,timestampMillis:String(now-1000)},
  appIntegrity:{appRecognitionVerdict:'PLAY_RECOGNIZED',packageName:'com.tripcal.app',certificateSha256Digest:[cert],versionCode:'4'},
  deviceIntegrity:{deviceRecognitionVerdict:['MEETS_DEVICE_INTEGRITY']},
  accountDetails:{appLicensingVerdict:'LICENSED'},
}});
test('accepts only a fresh verdict bound to the expected app and request', () => {
  assert.equal(isAcceptablePlayVerdict(valid(),expected,now),true);
  const cases = [
    v=>{v.tokenPayloadExternal.requestDetails.requestHash='C'.repeat(43)},
    v=>{v.tokenPayloadExternal.requestDetails.timestampMillis=String(now-120001)},
    v=>{v.tokenPayloadExternal.requestDetails.timestampMillis=String(now+30001)},
    v=>{v.tokenPayloadExternal.appIntegrity.packageName='other.app'},
    v=>{v.tokenPayloadExternal.appIntegrity.certificateSha256Digest=['D'.repeat(43)]},
    v=>{v.tokenPayloadExternal.appIntegrity.versionCode='3'},
    v=>{v.tokenPayloadExternal.appIntegrity.appRecognitionVerdict='UNRECOGNIZED_VERSION'},
    v=>{v.tokenPayloadExternal.deviceIntegrity.deviceRecognitionVerdict=[]},
    v=>{v.tokenPayloadExternal.accountDetails.appLicensingVerdict='UNLICENSED'},
  ];
  for (const change of cases) { const value=valid(); change(value); assert.equal(isAcceptablePlayVerdict(value,expected,now),false); }
  assert.equal(isAcceptablePlayVerdict(valid(),{...expected,certificateDigests:[]},now),false);
  assert.equal(isAcceptablePlayVerdict({},expected,now),false);
});
