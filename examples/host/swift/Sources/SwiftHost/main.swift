import Foundation
import WasmKit

/// Swift WebAssembly Host for testing wit-bindgen-moonbit generated modules
/// Uses WasmKit - a pure Swift WebAssembly runtime

// MARK: - Test Runner

@main
struct SwiftHost {
    static func main() async throws {
        let args = CommandLine.arguments
        let wasmPath = args.count > 1
            ? args[1]
            : "../../tests/types-test/_build/wasm/release/build/src/src.wasm"

        print("Loading wasm module: \(wasmPath)")

        do {
            let host = try WasmTestHost(wasmPath: wasmPath)

            print("Wasm module loaded successfully!")
            print("Running tests...\n")

            try host.runAllTests()

            print("\nAll tests PASSED!")
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    }
}

// MARK: - Wasm Host

class WasmTestHost {
    let engine: Engine
    let store: Store
    let instance: Instance

    init(wasmPath: String) throws {
        // Read wasm file
        let wasmBytes = try Data(contentsOf: URL(fileURLWithPath: wasmPath))

        // Parse module
        let module = try parseWasm(bytes: Array(wasmBytes))

        // Create engine and store
        engine = Engine()
        store = Store(engine: engine)

        // Instantiate module
        instance = try module.instantiate(store: store)
    }

    // MARK: - Function Calling Helpers

    func getFunction(_ name: String) throws -> Function {
        guard let export = instance.export(name),
              case let .function(function) = export else {
            throw WasmHostError.functionNotFound(name)
        }
        return function
    }

    func callI32ToI32(_ name: String, _ arg: Int32) throws -> Int32 {
        let function = try getFunction(name)
        let results = try function([.i32(UInt32(bitPattern: arg))])
        guard let result = results.first, case .i32(let value) = result else {
            throw WasmHostError.invalidResult
        }
        return Int32(bitPattern: value)
    }

    func callI64ToI64(_ name: String, _ arg: Int64) throws -> Int64 {
        let function = try getFunction(name)
        let results = try function([.i64(UInt64(bitPattern: arg))])
        guard let result = results.first, case .i64(let value) = result else {
            throw WasmHostError.invalidResult
        }
        return Int64(bitPattern: value)
    }

    func callF32ToF32(_ name: String, _ arg: Float) throws -> Float {
        let function = try getFunction(name)
        let results = try function([.f32(arg.bitPattern)])
        guard let result = results.first, case .f32(let value) = result else {
            throw WasmHostError.invalidResult
        }
        return Float(bitPattern: value)
    }

    func callF64ToF64(_ name: String, _ arg: Double) throws -> Double {
        let function = try getFunction(name)
        let results = try function([.f64(arg.bitPattern)])
        guard let result = results.first, case .f64(let value) = result else {
            throw WasmHostError.invalidResult
        }
        return Double(bitPattern: value)
    }

    func callI32I32ToI32(_ name: String, _ a: Int32, _ b: Int32) throws -> Int32 {
        let function = try getFunction(name)
        let results = try function([
            .i32(UInt32(bitPattern: a)),
            .i32(UInt32(bitPattern: b))
        ])
        guard let result = results.first, case .i32(let value) = result else {
            throw WasmHostError.invalidResult
        }
        return Int32(bitPattern: value)
    }

    func callI32I32I32ToI32(_ name: String, _ a: Int32, _ b: Int32, _ c: Int32) throws -> Int32 {
        let function = try getFunction(name)
        let results = try function([
            .i32(UInt32(bitPattern: a)),
            .i32(UInt32(bitPattern: b)),
            .i32(UInt32(bitPattern: c))
        ])
        guard let result = results.first, case .i32(let value) = result else {
            throw WasmHostError.invalidResult
        }
        return Int32(bitPattern: value)
    }

    func callI32x4ToI32(_ name: String, _ a: Int32, _ b: Int32, _ c: Int32, _ d: Int32) throws -> Int32 {
        let function = try getFunction(name)
        let results = try function([
            .i32(UInt32(bitPattern: a)),
            .i32(UInt32(bitPattern: b)),
            .i32(UInt32(bitPattern: c)),
            .i32(UInt32(bitPattern: d))
        ])
        guard let result = results.first, case .i32(let value) = result else {
            throw WasmHostError.invalidResult
        }
        return Int32(bitPattern: value)
    }

    // MARK: - Tests

    func runAllTests() throws {
        try testPrimitives()
        try testEnums()
        try testFlags()
        try testMultiParams()
    }

    func testPrimitives() throws {
        print("--- Testing primitives ---")

        // echo-s32
        let s32Result = try callI32ToI32("local:types-test/primitives#echo-s32", 42)
        assert(s32Result == 42, "echo-s32 failed")
        print("  echo-s32(42) = 42 ✓")

        // echo-s64
        let s64Result = try callI64ToI64("local:types-test/primitives#echo-s64", 9999999999)
        assert(s64Result == 9999999999, "echo-s64 failed")
        print("  echo-s64(9999999999) = 9999999999 ✓")

        // echo-f32
        let f32Result = try callF32ToF32("local:types-test/primitives#echo-f32", 3.14)
        assert(abs(f32Result - 3.14) < 0.001, "echo-f32 failed")
        print("  echo-f32(3.14) ≈ 3.14 ✓")

        // echo-f64
        let f64Result = try callF64ToF64("local:types-test/primitives#echo-f64", 3.14159265359)
        assert(abs(f64Result - 3.14159265359) < 0.0000001, "echo-f64 failed")
        print("  echo-f64(3.14159265359) ≈ 3.14159265359 ✓")

        // echo-bool
        let boolResult = try callI32ToI32("local:types-test/primitives#echo-bool", 1)
        assert(boolResult == 1, "echo-bool failed")
        print("  echo-bool(true) = true ✓")
    }

    func testEnums() throws {
        print("\n--- Testing enums ---")

        // echo-color (red=0, green=1, blue=2)
        let redResult = try callI32ToI32("local:types-test/enums#echo-color", 0)
        assert(redResult == 0, "echo-color(red) failed")
        print("  echo-color(red=0) = 0 ✓")

        let greenResult = try callI32ToI32("local:types-test/enums#echo-color", 1)
        assert(greenResult == 1, "echo-color(green) failed")
        print("  echo-color(green=1) = 1 ✓")

        let blueResult = try callI32ToI32("local:types-test/enums#echo-color", 2)
        assert(blueResult == 2, "echo-color(blue) failed")
        print("  echo-color(blue=2) = 2 ✓")
    }

    func testFlags() throws {
        print("\n--- Testing flags ---")

        // has-read (read=1, write=2, execute=4)
        let hasReadTrue = try callI32ToI32("local:types-test/flags-test#has-read", 0b001)
        assert(hasReadTrue == 1, "has-read({read}) failed")
        print("  has-read({read}) = true ✓")

        let hasReadFalse = try callI32ToI32("local:types-test/flags-test#has-read", 0)
        assert(hasReadFalse == 0, "has-read({}) failed")
        print("  has-read({}) = false ✓")

        // has-write
        let hasWrite = try callI32ToI32("local:types-test/flags-test#has-write", 0b010)
        assert(hasWrite == 1, "has-write({write}) failed")
        print("  has-write({write}) = true ✓")

        // echo-permissions
        let permsResult = try callI32ToI32("local:types-test/flags-test#echo-permissions", 0b101)
        assert(permsResult == 0b101, "echo-permissions failed")
        print("  echo-permissions({read, execute}) = {read, execute} ✓")
    }

    func testMultiParams() throws {
        print("\n--- Testing multi-params ---")

        // add2
        let add2Result = try callI32I32ToI32("local:types-test/multi-params#add2", 3, 4)
        assert(add2Result == 7, "add2 failed")
        print("  add2(3, 4) = 7 ✓")

        // add3
        let add3Result = try callI32I32I32ToI32("local:types-test/multi-params#add3", 1, 2, 3)
        assert(add3Result == 6, "add3 failed")
        print("  add3(1, 2, 3) = 6 ✓")

        // add4
        let add4Result = try callI32x4ToI32("local:types-test/multi-params#add4", 1, 2, 3, 4)
        assert(add4Result == 10, "add4 failed")
        print("  add4(1, 2, 3, 4) = 10 ✓")
    }
}

// MARK: - Errors

enum WasmHostError: Error, CustomStringConvertible {
    case functionNotFound(String)
    case memoryNotFound
    case invalidResult
    case assertionFailed(String)

    var description: String {
        switch self {
        case .functionNotFound(let name):
            return "Function not found: \(name)"
        case .memoryNotFound:
            return "Memory export not found"
        case .invalidResult:
            return "Invalid result type"
        case .assertionFailed(let msg):
            return "Assertion failed: \(msg)"
        }
    }
}
