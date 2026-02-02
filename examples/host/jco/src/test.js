/**
 * jco Host Test for wit-bindgen-moonbit generated components
 * Tests the transpiled WebAssembly Component in Node.js
 */

import * as typesTest from './gen/types-test.js';

// Test utilities
let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) {
    passed++;
    console.log(`  ${message} ✓`);
  } else {
    failed++;
    console.log(`  ${message} ✗`);
  }
}

function assertEq(actual, expected, message) {
  const eq = actual === expected;
  if (eq) {
    passed++;
    console.log(`  ${message} ✓`);
  } else {
    failed++;
    console.log(`  ${message}: got ${actual}, expected ${expected} ✗`);
  }
}

function assertApprox(actual, expected, epsilon, message) {
  assert(Math.abs(actual - expected) < epsilon, `${message}: ${actual} ≈ ${expected}`);
}

// Test primitives
function testPrimitives() {
  console.log('--- Testing primitives ---');

  const { primitives } = typesTest;

  assertEq(primitives.echoS32(42), 42, 'echo-s32(42)');
  assertEq(primitives.echoS64(9999999999n), 9999999999n, 'echo-s64(9999999999)');
  assertApprox(primitives.echoF32(3.14), 3.14, 0.001, 'echo-f32(3.14)');
  assertApprox(primitives.echoF64(3.14159265359), 3.14159265359, 0.0000001, 'echo-f64(3.14159265359)');
  assertEq(primitives.echoBool(true), true, 'echo-bool(true)');
  assertEq(primitives.echoString('hello'), 'hello', 'echo-string("hello")');
}

// Test enums
function testEnums() {
  console.log('\n--- Testing enums ---');

  const { enums } = typesTest;

  assertEq(enums.echoColor('red'), 'red', 'echo-color(red)');
  assertEq(enums.echoColor('green'), 'green', 'echo-color(green)');
  assertEq(enums.echoColor('blue'), 'blue', 'echo-color(blue)');
  assertEq(enums.colorName('blue'), 'blue', 'color-name(blue)');
}

// Test flags
function testFlags() {
  console.log('\n--- Testing flags ---');

  const { flagsTest } = typesTest;

  assertEq(flagsTest.hasRead({ read: true }), true, 'has-read({read})');
  assertEq(flagsTest.hasRead({}), false, 'has-read({})');
  assertEq(flagsTest.hasWrite({ write: true }), true, 'has-write({write})');

  const perms = flagsTest.echoPermissions({ read: true, execute: true });
  assert(perms.read === true && perms.execute === true && !perms.write,
    'echo-permissions({read, execute})');
}

// Test containers
function testContainers() {
  console.log('\n--- Testing containers ---');

  const { containers } = typesTest;

  // list<s32> is typed as Int32Array in jco
  const sumResult = containers.sumList(new Int32Array([1, 2, 3, 4]));
  assertEq(sumResult, 10, 'sum-list([1,2,3,4])');

  assertEq(containers.countList(['a', 'b', 'c']), 3, 'count-list(["a","b","c"])');

  // jco returns the value directly for Ok, throws ComponentError for Err
  try {
    const divOk = containers.divide(10, 2);
    assertEq(divOk, 5, 'divide(10, 2) = Ok(5)');
  } catch (e) {
    failed++;
    console.log(`  divide(10, 2) = Ok(5): unexpected error ${e.message} ✗`);
  }

  try {
    containers.divide(10, 0);
    failed++;
    console.log('  divide(10, 0) = Err: should have thrown ✗');
  } catch (e) {
    if (e.message && e.message.includes('division by zero')) {
      passed++;
      console.log('  divide(10, 0) = Err("division by zero") ✓');
    } else {
      failed++;
      console.log(`  divide(10, 0) = Err: wrong error ${e.message} ✗`);
    }
  }
}

// Test multi-params
function testMultiParams() {
  console.log('\n--- Testing multi-params ---');

  const { multiParams } = typesTest;

  assertEq(multiParams.add2(3, 4), 7, 'add2(3, 4)');
  assertEq(multiParams.add3(1, 2, 3), 6, 'add3(1, 2, 3)');
  assertEq(multiParams.add4(1, 2, 3, 4), 10, 'add4(1, 2, 3, 4)');
  assertEq(multiParams.concat3('Hello', ' ', 'World'), 'Hello World', 'concat3("Hello", " ", "World")');
  assertEq(multiParams.mixedParams(42, 'test', true), '42:test:true', 'mixed-params(42, "test", true)');
}

// Test side-effects
function testSideEffects() {
  console.log('\n--- Testing side-effects ---');

  const { sideEffects } = typesTest;

  sideEffects.noReturn('test message');
  console.log('  no-return("test message") completed ✓');
  passed++;

  sideEffects.noParamsNoReturn();
  console.log('  no-params-no-return() completed ✓');
  passed++;
}

// Run all tests
async function main() {
  console.log('jco Host Test for types-test component\n');

  try {
    testPrimitives();
    testEnums();
    testFlags();
    testContainers();
    testMultiParams();
    testSideEffects();

    console.log(`\n--- Results ---`);
    console.log(`Passed: ${passed}`);
    console.log(`Failed: ${failed}`);

    if (failed > 0) {
      console.log('\nSome tests FAILED!');
      process.exit(1);
    } else {
      console.log('\nAll tests PASSED!');
    }
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

main();
