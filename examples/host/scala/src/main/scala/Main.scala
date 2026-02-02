package scalahost

import com.dylibso.chicory.runtime.Instance
import com.dylibso.chicory.wasm.Parser
import com.dylibso.chicory.runtime.ExportFunction
import java.io.File
import java.nio.file.Files
import scala.util.{Try, Success, Failure}

/** Scala WebAssembly Host for testing wit-bindgen-moonbit generated modules
  * Uses Chicory - a pure Java WebAssembly runtime
  */
object Main:
  def main(args: Array[String]): Unit =
    val wasmPath = args.headOption.getOrElse(
      "../../tests/types-test/_build/wasm/release/build/src/src.wasm"
    )

    println(s"Loading wasm module: $wasmPath")

    Try {
      val host = WasmTestHost(wasmPath)
      println("Wasm module loaded successfully!")
      println("Running tests...\n")
      host.runAllTests()
      println("\nAll tests PASSED!")
    } match
      case Success(_) => ()
      case Failure(e) =>
        println(s"Error: ${e.getMessage}")
        e.printStackTrace()
        sys.exit(1)

class WasmTestHost(wasmPath: String):
  private val wasmBytes = Files.readAllBytes(File(wasmPath).toPath)
  private val module = Parser.parse(wasmBytes)
  private val instance = Instance.builder(module).build()

  // Function calling helpers
  private def getFunction(name: String): ExportFunction =
    val fn = instance.`export`(name)
    if fn == null then
      throw new RuntimeException(s"Function not found: $name")
    fn

  private def callI32ToI32(name: String, arg: Int): Int =
    val fn = getFunction(name)
    val results = fn.apply(arg.toLong)
    results(0).toInt

  private def callI64ToI64(name: String, arg: Long): Long =
    val fn = getFunction(name)
    val results = fn.apply(arg)
    results(0)

  private def callF32ToF32(name: String, arg: Float): Float =
    val fn = getFunction(name)
    val results = fn.apply(java.lang.Float.floatToRawIntBits(arg).toLong)
    java.lang.Float.intBitsToFloat(results(0).toInt)

  private def callF64ToF64(name: String, arg: Double): Double =
    val fn = getFunction(name)
    val results = fn.apply(java.lang.Double.doubleToRawLongBits(arg))
    java.lang.Double.longBitsToDouble(results(0))

  private def callI32I32ToI32(name: String, a: Int, b: Int): Int =
    val fn = getFunction(name)
    val results = fn.apply(a.toLong, b.toLong)
    results(0).toInt

  private def callI32I32I32ToI32(name: String, a: Int, b: Int, c: Int): Int =
    val fn = getFunction(name)
    val results = fn.apply(a.toLong, b.toLong, c.toLong)
    results(0).toInt

  private def callI32x4ToI32(name: String, a: Int, b: Int, c: Int, d: Int): Int =
    val fn = getFunction(name)
    val results = fn.apply(a.toLong, b.toLong, c.toLong, d.toLong)
    results(0).toInt

  // Test runner
  def runAllTests(): Unit =
    testPrimitives()
    testEnums()
    testFlags()
    testMultiParams()

  private def testPrimitives(): Unit =
    println("--- Testing primitives ---")

    // echo-s32
    val s32Result = callI32ToI32("local:types-test/primitives#echo-s32", 42)
    assert(s32Result == 42, s"echo-s32 failed: got $s32Result")
    println("  echo-s32(42) = 42 ✓")

    // echo-s64
    val s64Result = callI64ToI64("local:types-test/primitives#echo-s64", 9999999999L)
    assert(s64Result == 9999999999L, s"echo-s64 failed: got $s64Result")
    println("  echo-s64(9999999999) = 9999999999 ✓")

    // echo-f32
    val f32Result = callF32ToF32("local:types-test/primitives#echo-f32", 3.14f)
    assert(math.abs(f32Result - 3.14f) < 0.001f, s"echo-f32 failed: got $f32Result")
    println("  echo-f32(3.14) ≈ 3.14 ✓")

    // echo-f64
    val f64Result = callF64ToF64("local:types-test/primitives#echo-f64", 3.14159265359)
    assert(math.abs(f64Result - 3.14159265359) < 0.0000001, s"echo-f64 failed: got $f64Result")
    println("  echo-f64(3.14159265359) ≈ 3.14159265359 ✓")

    // echo-bool
    val boolResult = callI32ToI32("local:types-test/primitives#echo-bool", 1)
    assert(boolResult == 1, s"echo-bool failed: got $boolResult")
    println("  echo-bool(true) = true ✓")

  private def testEnums(): Unit =
    println("\n--- Testing enums ---")

    // echo-color (red=0, green=1, blue=2)
    val redResult = callI32ToI32("local:types-test/enums#echo-color", 0)
    assert(redResult == 0, s"echo-color(red) failed: got $redResult")
    println("  echo-color(red=0) = 0 ✓")

    val greenResult = callI32ToI32("local:types-test/enums#echo-color", 1)
    assert(greenResult == 1, s"echo-color(green) failed: got $greenResult")
    println("  echo-color(green=1) = 1 ✓")

    val blueResult = callI32ToI32("local:types-test/enums#echo-color", 2)
    assert(blueResult == 2, s"echo-color(blue) failed: got $blueResult")
    println("  echo-color(blue=2) = 2 ✓")

  private def testFlags(): Unit =
    println("\n--- Testing flags ---")

    // has-read (read=1, write=2, execute=4)
    val hasReadTrue = callI32ToI32("local:types-test/flags-test#has-read", 0x001)
    assert(hasReadTrue == 1, s"has-read({read}) failed: got $hasReadTrue")
    println("  has-read({read}) = true ✓")

    val hasReadFalse = callI32ToI32("local:types-test/flags-test#has-read", 0)
    assert(hasReadFalse == 0, s"has-read({}) failed: got $hasReadFalse")
    println("  has-read({}) = false ✓")

    // has-write
    val hasWrite = callI32ToI32("local:types-test/flags-test#has-write", 0x002)
    assert(hasWrite == 1, s"has-write({write}) failed: got $hasWrite")
    println("  has-write({write}) = true ✓")

    // echo-permissions
    val permsResult = callI32ToI32("local:types-test/flags-test#echo-permissions", 0x005)
    assert(permsResult == 0x005, s"echo-permissions failed: got $permsResult")
    println("  echo-permissions({read, execute}) = {read, execute} ✓")

  private def testMultiParams(): Unit =
    println("\n--- Testing multi-params ---")

    // add2
    val add2Result = callI32I32ToI32("local:types-test/multi-params#add2", 3, 4)
    assert(add2Result == 7, s"add2 failed: got $add2Result")
    println("  add2(3, 4) = 7 ✓")

    // add3
    val add3Result = callI32I32I32ToI32("local:types-test/multi-params#add3", 1, 2, 3)
    assert(add3Result == 6, s"add3 failed: got $add3Result")
    println("  add3(1, 2, 3) = 6 ✓")

    // add4
    val add4Result = callI32x4ToI32("local:types-test/multi-params#add4", 1, 2, 3, 4)
    assert(add4Result == 10, s"add4 failed: got $add4Result")
    println("  add4(1, 2, 3, 4) = 10 ✓")
