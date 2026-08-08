const fs = require("fs");

const wasmPath = process.argv[2];
const mode = process.argv[3] || "sum";
const calls = Number(process.argv[4] || 5000);
const tripCount = Number(process.argv[5] || 1000);
const samples = Number(process.argv[6] || 7);

if (!wasmPath) throw new Error("missing Wasm file path");
const moduleObject = new WebAssembly.Module(fs.readFileSync(wasmPath));
const instance = new WebAssembly.Instance(moduleObject, {});
const operation = instance.exports[mode];
if (typeof operation !== "function") throw new Error(`unknown export: ${mode}`);

for (let index = 0; index < 20; index++) operation(tripCount);

const elapsed = [];
let checksum = 0;
for (let sample = 0; sample < samples; sample++) {
  const start = process.hrtime.bigint();
  let result = 0;
  for (let index = 0; index < calls; index++) result += operation(tripCount);
  elapsed.push(Number(process.hrtime.bigint() - start));
  checksum = result;
}
elapsed.sort((a, b) => a - b);
const nanoseconds = elapsed[Math.floor(elapsed.length / 2)];
console.log(`V8 WebAssembly mode=${mode} calls=${calls} trip=${tripCount} samples=${samples}`);
console.log(`${(nanoseconds / 1e6).toFixed(3).padStart(8)} ms  ${(nanoseconds / (calls * tripCount)).toFixed(3).padStart(8)} ns/iteration  checksum=${checksum.toFixed(1)}`);

