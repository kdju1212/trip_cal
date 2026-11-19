'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync('advertiser/image-ratio.js', 'utf8');
function run(width, height, broken = false) {
  const revoked = [];
  const context = { window:{}, URL:{createObjectURL:()=>'blob:test', revokeObjectURL:url=>revoked.push(url)}, Image:class {
    constructor() { this.naturalWidth=width; this.naturalHeight=height; }
    set src(_) { queueMicrotask(() => broken ? this.onerror() : this.onload()); }
  }, Promise, queueMicrotask };
  vm.runInNewContext(source, context);
  return context.window.TripImageRatio.isSquare({}).then(result => ({result,revoked}));
}
test('이미지는 실제 크기가 같은 정사각형만 허용한다', async () => {
  assert.deepEqual(await run(1000,1000), {result:true,revoked:['blob:test']});
  assert.deepEqual(await run(1000,999), {result:false,revoked:['blob:test']});
  assert.deepEqual(await run(0,0), {result:false,revoked:['blob:test']});
  assert.deepEqual(await run(0,0,true), {result:false,revoked:['blob:test']});
});
