///|
test "parse component type alias export" {
  let name = @utf8.encode("foo")
  let bytes : Array[Byte] = []
  bytes.push(0x03U.to_byte()) // type
  bytes.push(0x00U.to_byte()) // export target
  bytes.push(0x00U.to_byte()) // instance index 0
  bytes.push(0x03U.to_byte()) // name length
  for b in name {
    bytes.push(b)
  }
  let parser = Parser::new(Bytes::from_array(bytes))
  let entry = parse_component_type_alias(parser)
  match entry {
    InstanceTypeEntry::Alias(InstanceAliasTarget::Export(idx, alias_name)) => {
      assert_eq(idx, 0U)
      assert_eq(alias_name, name)
    }
    _ => fail("expected export alias")
  }
}

///|
test "parse component type alias outer" {
  let bytes : Array[Byte] = []
  bytes.push(0x03U.to_byte()) // type
  bytes.push(0x02U.to_byte()) // outer target
  bytes.push(0x01U.to_byte()) // count
  bytes.push(0x02U.to_byte()) // index
  let parser = Parser::new(Bytes::from_array(bytes))
  let entry = parse_component_type_alias(parser)
  match entry {
    InstanceTypeEntry::Alias(InstanceAliasTarget::Outer(count, index)) => {
      assert_eq(count, 1U)
      assert_eq(index, 2U)
    }
    _ => fail("expected outer alias")
  }
}
