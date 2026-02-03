use anyhow::Result;
use std::convert::Infallible;
use std::path::Path;
use wasm_encoder::reencode::{
    component_utils, Error as ReencodeError, Reencode, ReencodeComponent, RoundtripReencoder,
};
use wasm_encoder::{Component, NestedComponentSection};
use wasmparser::{
    ComponentAlias, ComponentExternalKind, ComponentInstance, ComponentOuterAliasKind, Parser,
    Payload,
};

#[derive(Clone, Debug)]
#[allow(dead_code)]
struct DcePlan {
    total_components: u32,
    kept_components: u32,
    removed: u32,
    keep: Vec<bool>,
    component_map: Vec<Option<u32>>,
}

struct DceReencoder {
    depth: u32,
    keep: Vec<bool>,
    component_map: Vec<Option<u32>>,
    next_component: u32,
}

impl DceReencoder {
    fn new(keep: Vec<bool>, component_map: Vec<Option<u32>>) -> Self {
        Self {
            depth: 0,
            keep,
            component_map,
            next_component: 0,
        }
    }
}

impl Reencode for DceReencoder {
    type Error = Infallible;
}

impl ReencodeComponent for DceReencoder {
    fn push_depth(&mut self) {
        self.depth += 1;
    }

    fn pop_depth(&mut self) {
        self.depth = self.depth.saturating_sub(1);
    }

    fn component_index(&mut self, ty: u32) -> u32 {
        if self.depth == 0 {
            let mapped = self.component_map.get(ty as usize).and_then(|v| *v);
            debug_assert!(mapped.is_some(), "DCE: missing component index mapping");
            mapped.unwrap_or(0)
        } else {
            ty
        }
    }

    fn outer_component_index(&mut self, count: u32, component: u32) -> u32 {
        if self.depth == 0 && count == 0 {
            self.component_index(component)
        } else {
            component
        }
    }

    fn parse_component_subcomponent(
        &mut self,
        component: &mut Component,
        _parser: Parser,
        data: &[u8],
        _whole_component: &[u8],
    ) -> Result<(), ReencodeError<Self::Error>> {
        if self.depth == 0 {
            let idx = self.next_component;
            self.next_component += 1;
            if idx as usize >= self.keep.len() || !self.keep[idx as usize] {
                return Ok(());
            }
        }
        let optimized = match component_dce_bytes(data) {
            Ok((bytes, _)) => bytes,
            Err(_) => data.to_vec(),
        };
        self.push_depth();
        let mut subcomponent = Component::new();
        let mut roundtrip = RoundtripReencoder;
        component_utils::parse_component(
            &mut roundtrip,
            &mut subcomponent,
            Parser::new(0),
            &optimized,
            &optimized,
        )?;
        component.section(&NestedComponentSection(&subcomponent));
        self.pop_depth();
        Ok(())
    }
}

pub(crate) fn apply_component_dce(output_path: &Path, enabled: bool) -> Result<()> {
    if !enabled {
        return Ok(());
    }
    let bytes = std::fs::read(output_path)?;
    let (optimized, plan) = component_dce_bytes(&bytes)?;
    if optimized == bytes {
        println!("DCE (component-level): no changes");
        return Ok(());
    }
    let original_len = bytes.len();
    let optimized_len = optimized.len();
    let delta = original_len as i64 - optimized_len as i64;
    let delta_abs = delta.unsigned_abs();
    let percent_abs = (delta_abs as f64) * 100.0 / original_len as f64;
    let percent = if delta >= 0 {
        -percent_abs
    } else {
        percent_abs
    };
    let size_msg = if delta >= 0 {
        format!("-{} bytes ({:+.2}%)", delta_abs, percent)
    } else {
        format!("+{} bytes ({:+.2}%)", delta_abs, percent)
    };
    std::fs::write(output_path, optimized)?;
    if plan.removed == 0 {
        println!(
            "DCE (component-level): removed 0 unused component(s), size {} (reencode)",
            size_msg
        );
    } else {
        println!(
            "DCE (component-level): removed {} unused component(s), size {}",
            plan.removed, size_msg
        );
    }
    Ok(())
}

fn component_dce_bytes(bytes: &[u8]) -> Result<(Vec<u8>, DcePlan)> {
    let plan = analyze_component(bytes)?;
    let mut component = Component::new();
    let mut reencoder = DceReencoder::new(plan.keep.clone(), plan.component_map.clone());
    reencoder.parse_component(&mut component, Parser::new(0), bytes)?;
    Ok((component.finish(), plan))
}

fn analyze_component(bytes: &[u8]) -> Result<DcePlan> {
    let mut component_imports = 0u32;
    let mut defined_components = 0u32;
    let mut used_component_indices: Vec<u32> = Vec::new();

    let mut parser = Parser::new(0);
    let mut remaining = bytes;
    while !remaining.is_empty() {
        let section = match parser.parse(remaining, true)? {
            wasmparser::Chunk::Parsed { consumed, payload } => {
                remaining = &remaining[consumed..];
                payload
            }
            wasmparser::Chunk::NeedMoreData(_) => unreachable!(),
        };
        match &section {
            Payload::ComponentSection { unchecked_range, .. }
            | Payload::ModuleSection { unchecked_range, .. } => {
                remaining = &remaining[unchecked_range.len()..];
            }
            _ => {}
        }
        match section {
            Payload::ComponentImportSection(section) => {
                for import in section {
                    let import = import?;
                    if import.ty.kind() == ComponentExternalKind::Component {
                        component_imports += 1;
                    }
                }
            }
            Payload::ComponentSection { .. } => {
                defined_components += 1;
            }
            Payload::ComponentInstanceSection(section) => {
                for instance in section {
                    let instance = instance?;
                    if let ComponentInstance::Instantiate { component_index, .. } = instance {
                        used_component_indices.push(component_index);
                    }
                }
            }
            Payload::ComponentExportSection(section) => {
                for export in section {
                    let export = export?;
                    if export.kind == ComponentExternalKind::Component {
                        used_component_indices.push(export.index);
                    }
                }
            }
            Payload::ComponentAliasSection(section) => {
                for alias in section {
                    let alias = alias?;
                    if let ComponentAlias::Outer {
                        kind: ComponentOuterAliasKind::Component,
                        count,
                        index,
                    } = alias
                    {
                        if count == 0 {
                            used_component_indices.push(index);
                        }
                    }
                }
            }
            _ => {}
        }
    }

    let mut keep = vec![false; defined_components as usize];
    for idx in &used_component_indices {
        if *idx >= component_imports {
            let def_idx = *idx - component_imports;
            if (def_idx as usize) < keep.len() {
                keep[def_idx as usize] = true;
            }
        }
    }
    let mut component_map = vec![None; (component_imports + defined_components) as usize];
    for idx in 0..component_imports {
        component_map[idx as usize] = Some(idx);
    }
    let mut next_def = 0u32;
    for def_idx in 0..defined_components {
        if keep[def_idx as usize] {
            let new_idx = component_imports + next_def;
            component_map[(component_imports + def_idx) as usize] = Some(new_idx);
            next_def += 1;
        }
    }

    let kept_components = keep.iter().filter(|v| **v).count() as u32;
    let removed = defined_components.saturating_sub(kept_components);

    Ok(DcePlan {
        total_components: defined_components,
        kept_components,
        removed,
        keep,
        component_map,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use wasm_encoder::{ComponentExportKind, ComponentInstanceSection};

    fn count_components(bytes: &[u8]) -> usize {
        let mut count = 0usize;
        let mut parser = Parser::new(0);
        let mut remaining = bytes;
        while !remaining.is_empty() {
            let section = match parser.parse(remaining, true).expect("parse") {
                wasmparser::Chunk::Parsed { consumed, payload } => {
                    remaining = &remaining[consumed..];
                    payload
                }
                wasmparser::Chunk::NeedMoreData(_) => unreachable!(),
            };
            match &section {
                Payload::ComponentSection { unchecked_range, .. }
                | Payload::ModuleSection { unchecked_range, .. } => {
                    remaining = &remaining[unchecked_range.len()..];
                }
                _ => {}
            }
            if let Payload::ComponentSection { .. } = section {
                count += 1;
            }
        }
        count
    }

    #[test]
    fn dce_trims_trailing_unused_components() {
        let used = Component::new();
        let unused = Component::new();

        let mut instances = ComponentInstanceSection::new();
        instances.instantiate(0, std::iter::empty::<(&str, ComponentExportKind, u32)>());

        let mut component = Component::new();
        component.section(&NestedComponentSection(&used));
        component.section(&NestedComponentSection(&unused));
        component.section(&instances);

        let bytes = component.finish();
        let original_count = count_components(&bytes);
        let (optimized, plan) = component_dce_bytes(&bytes).expect("dce");

        assert_eq!(original_count, 2);
        assert_eq!(plan.total_components, 2);
        assert_eq!(plan.kept_components, 1);
        assert_eq!(plan.removed, 1);
        assert!(optimized.len() < bytes.len());
        assert_eq!(count_components(&optimized), 1);
    }

    fn first_instance_component_index(bytes: &[u8]) -> Option<u32> {
        for payload in Parser::new(0).parse_all(bytes) {
            if let Payload::ComponentInstanceSection(section) = payload.ok()? {
                for instance in section {
                    if let ComponentInstance::Instantiate { component_index, .. } =
                        instance.ok()?
                    {
                        return Some(component_index);
                    }
                }
            }
        }
        None
    }

    #[test]
    fn dce_remaps_non_trailing_components() {
        let unused = Component::new();
        let used = Component::new();
        let unused2 = Component::new();

        let mut instances = ComponentInstanceSection::new();
        instances.instantiate(1, std::iter::empty::<(&str, ComponentExportKind, u32)>());

        let mut component = Component::new();
        component.section(&NestedComponentSection(&unused));
        component.section(&NestedComponentSection(&used));
        component.section(&NestedComponentSection(&unused2));
        component.section(&instances);

        let bytes = component.finish();
        let (optimized, plan) = component_dce_bytes(&bytes).expect("dce");

        assert_eq!(plan.total_components, 3);
        assert_eq!(plan.kept_components, 1);
        assert_eq!(plan.removed, 2);
        assert_eq!(count_components(&optimized), 1);
        assert_eq!(first_instance_component_index(&optimized), Some(0));
    }

    fn first_subcomponent_bytes(bytes: &[u8]) -> Option<Vec<u8>> {
        let mut parser = Parser::new(0);
        let mut remaining = bytes;
        while !remaining.is_empty() {
            let section = match parser.parse(remaining, true).ok()? {
                wasmparser::Chunk::Parsed { consumed, payload } => {
                    remaining = &remaining[consumed..];
                    payload
                }
                wasmparser::Chunk::NeedMoreData(_) => return None,
            };
            match &section {
                Payload::ComponentSection { unchecked_range, .. } => {
                    return Some(bytes[unchecked_range.clone()].to_vec());
                }
                Payload::ModuleSection { unchecked_range, .. } => {
                    remaining = &remaining[unchecked_range.len()..];
                }
                _ => {}
            }
        }
        None
    }

    #[test]
    fn dce_recurses_into_subcomponents() {
        let inner_used = Component::new();
        let inner_unused = Component::new();

        let mut inner_instances = ComponentInstanceSection::new();
        inner_instances.instantiate(0, std::iter::empty::<(&str, ComponentExportKind, u32)>());

        let mut subcomponent = Component::new();
        subcomponent.section(&NestedComponentSection(&inner_used));
        subcomponent.section(&NestedComponentSection(&inner_unused));
        subcomponent.section(&inner_instances);

        let mut outer_instances = ComponentInstanceSection::new();
        outer_instances.instantiate(0, std::iter::empty::<(&str, ComponentExportKind, u32)>());

        let mut outer = Component::new();
        outer.section(&NestedComponentSection(&subcomponent));
        outer.section(&outer_instances);

        let bytes = outer.finish();
        let original_sub = first_subcomponent_bytes(&bytes).expect("subcomponent");
        assert_eq!(&original_sub[0..4], b"\0asm");
        assert_eq!(count_components(&original_sub), 2);
        let (direct_opt, _) = component_dce_bytes(&original_sub).expect("dce sub");
        assert_eq!(count_components(&direct_opt), 1);
        let mut roundtrip_component = Component::new();
        let mut roundtrip = RoundtripReencoder;
        component_utils::parse_component(
            &mut roundtrip,
            &mut roundtrip_component,
            Parser::new(0),
            &direct_opt,
            &direct_opt,
        )
        .expect("roundtrip parse");
        let roundtrip_bytes = roundtrip_component.finish();
        assert_eq!(count_components(&roundtrip_bytes), 1);
        let (optimized, plan) = component_dce_bytes(&bytes).expect("dce");

        assert_eq!(plan.total_components, 1);
        assert_eq!(plan.kept_components, 1);
        assert_eq!(plan.removed, 0);
        assert_eq!(count_components(&optimized), 1);

        let sub_bytes = first_subcomponent_bytes(&optimized).expect("subcomponent");
        assert_eq!(&sub_bytes[0..4], b"\0asm");
        assert_eq!(count_components(&sub_bytes), 1);
    }
}
