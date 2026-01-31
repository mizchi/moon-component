// Stub implementation - copy-based resource handling
// This demonstrates resource semantics with full data copy

// Handle table for blob resources
let blob_table : Ref[Array[Array[Byte]]] = { val: [] }

///|
/// Allocate a new blob and return its handle
fn allocate_blob(data : Array[Byte]) -> @exports.Blob {
  let handle = blob_table.val.length()
  blob_table.val.push(data)
  @exports.Blob(handle)
}

///|
/// Get blob data by handle
fn get_blob(handle : @exports.Blob) -> Array[Byte] {
  blob_table.val[handle.0]
}

///|
pub(all) struct BlobStoreImpl {}

///|
pub impl @exports.Exports for BlobStoreImpl with blob_new(self, data : Array[Byte]) -> @exports.Blob {
  allocate_blob(data)
}

///|
pub impl @exports.Exports for BlobStoreImpl with blob_size(self, this : @exports.Blob) -> UInt {
  get_blob(this).length().reinterpret_as_uint()
}

///|
pub impl @exports.Exports for BlobStoreImpl with blob_read(self, this : @exports.Blob, offset : UInt, len : UInt) -> Array[Byte] {
  let data = get_blob(this)
  let start = offset.reinterpret_as_int()
  let end = start + len.reinterpret_as_int()
  let result : Array[Byte] = Array::new(capacity=len.reinterpret_as_int())
  for i = start; i < end && i < data.length(); i = i + 1 {
    result.push(data[i])
  }
  result
}

///|
pub impl @exports.Exports for BlobStoreImpl with blob_write(self, this : @exports.Blob, offset : UInt, data : Array[Byte]) -> Unit {
  let blob = get_blob(this)
  let start = offset.reinterpret_as_int()
  // Extend blob if necessary
  let required_len = start + data.length()
  while blob.length() < required_len {
    blob.push(b'\x00')
  }
  // Write data
  for i, byte in data {
    blob[start + i] = byte
  }
}

///|
pub impl @exports.Exports for BlobStoreImpl with create_blob(self, data : Array[Byte]) -> @exports.Blob {
  allocate_blob(data)
}

///|
pub impl @exports.Exports for BlobStoreImpl with get_blob_size(self, b : @exports.Blob) -> UInt {
  get_blob(b).length().reinterpret_as_uint()
}

///|
pub impl @exports.Exports for BlobStoreImpl with consume_blob(self, b : @exports.Blob) -> Array[Byte] {
  // In a real implementation, this would deallocate the blob
  // For copy-based implementation, we just return the data
  get_blob(b)
}

///|
fn init {
  @exports.register(BlobStoreImpl::{})
}
