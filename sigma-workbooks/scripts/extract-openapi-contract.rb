#!/usr/bin/env ruby
# frozen_string_literal: true

# Extract the small, executable workbook-as-code contract we pin in this repo.
# Usage:
#   ruby scripts/extract-openapi-contract.rb /path/to/sigma-openapi.json

require 'json'
require 'date'

def merged_required(schema)
  return [] unless schema.is_a?(Hash)

  values = Array(schema['required'])
  Array(schema['allOf']).each { |part| values.concat(merged_required(part)) }
  values.uniq.sort
end

def merged_properties(schema)
  return [] unless schema.is_a?(Hash)

  values = schema.fetch('properties', {}).keys
  Array(schema['allOf']).each { |part| values.concat(merged_properties(part)) }
  values.uniq.sort
end

def property(schema, name)
  return unless schema.is_a?(Hash)
  return schema.dig('properties', name) if schema.dig('properties', name)

  Array(schema['allOf']).each do |part|
    found = property(part, name)
    return found if found
  end
  nil
end

def shape(schema)
  {
    'required' => merged_required(schema),
    'properties' => merged_properties(schema)
  }
end

def collect_discriminators(schema, discriminator, out = [])
  return out unless schema.is_a?(Hash)

  values = property(schema, discriminator)&.fetch('enum', nil)
  if schema['title'] && values&.one?
    out << { 'title' => schema['title'], discriminator => values.first }
  end
  Array(schema['oneOf']).each { |part| collect_discriminators(part, discriminator, out) }
  Array(schema['allOf']).each { |part| collect_discriminators(part, discriminator, out) }
  out.uniq { |entry| entry[discriminator] }.sort_by { |entry| entry[discriminator] }
end

# ---- Actions coverage (issue: the 2026-08-26 action field rename) -----------
#
# This fixture pinned CreateWorkbookSpec and the element/control discriminators
# but had ZERO Actions coverage -- no `effect`, no insert-rows, nothing. So when
# Sigma renamed every action identifier field to a *Id shape (table ->
# tableElementId, and eight more), the pinned contract did not move and this gate
# stayed green while four repos emitted dead keys. It would not have caught the
# next one either.
#
# Effects are NOT a named schema; they hang off
# Actions.items.allOf[].properties.effects.items as a oneOf discriminated by
# `effect`. Pin each member's merged property + required sets so a rename,
# an added effect, or a newly-required field all show up as a fixture diff.
def effects_schema(actions)
  Array(actions['items'] && actions['items']['allOf']).each do |part|
    effects = property(part, 'effects')
    return effects['items'] if effects.is_a?(Hash) && effects['items']
  end
  nil
end

# Merged shape per `effect` value. Uses the same merged_* helpers as everything
# else here so allOf-split members (discriminator in one branch, properties in
# another -- which is how column-range hides minColumnId/maxColumnId) are seen.
def collect_effects(effects_items)
  out = {}
  walk = lambda do |node|
    next unless node.is_a?(Hash)
    props = merged_properties(node)
    names = props.is_a?(Hash) ? props.keys : Array(props)
    effect_prop = property(node, 'effect')
    values = effect_prop && (effect_prop['enum'] || (effect_prop['const'] ? [effect_prop['const']] : nil))
    if values
      values.each do |value|
        next unless value.is_a?(String)
        out[value] = {
          'required' => (merged_required(node) - ['effect']).sort,
          'properties' => (names - ['effect']).sort
        }
      end
    end
    Array(node['oneOf']).each { |part| walk.call(part) }
    Array(node['anyOf']).each { |part| walk.call(part) }
    Array(node['allOf']).each { |part| walk.call(part) }
  end
  walk.call(effects_items)
  out.sort.to_h
end

# The union members reached from inside an effect: value sources
# ({type: column} -> columnId), whichRows selectors, clear-control scopes,
# navigate/refresh targets. These are where the rename's NESTED half landed and
# where nothing was pinned at all. Keyed by "type" so `control` appearing with
# BOTH `control` (set-control-value, NOT renamed) and `controlId` (clear-control
# scope, renamed) is visible as two distinct shapes rather than collapsed.
def collect_union_shapes(node, out = {}, seen = {})
  return out unless node.is_a?(Hash)
  return out if seen[node.object_id]
  seen[node.object_id] = true

  type_prop = property(node, 'type')
  values = type_prop && (type_prop['enum'] || (type_prop['const'] ? [type_prop['const']] : nil))
  if values && values.length == 1 && values.first.is_a?(String)
    props = merged_properties(node)
    names = ((props.is_a?(Hash) ? props.keys : Array(props)) - ['type']).sort
    unless names.empty?
      key = "#{values.first}(#{names.join(',')})"
      out[key] = { 'type' => values.first, 'properties' => names,
                   'required' => (merged_required(node) - ['type']).sort }
    end
  end
  %w[oneOf anyOf allOf].each { |comb| Array(node[comb]).each { |part| collect_union_shapes(part, out, seen) } }
  node.each_value { |val| collect_union_shapes(val, out, seen) if val.is_a?(Hash) }
  out
end

# `automatedActions` hangs off document, not off the Actions schema.
def automated_actions_effects(document)
  aa = property(document, 'automatedActions')
  return nil unless aa.is_a?(Hash) && aa['items']
  Array(aa['items']['allOf']).each do |part|
    effects = property(part, 'effects')
    return effects['items'] if effects.is_a?(Hash) && effects['items']
  end
  nil
end

path = ARGV.fetch(0) { abort 'usage: extract-openapi-contract.rb OPENAPI_JSON' }
openapi = JSON.parse(File.read(path))
schemas = openapi.fetch('components').fetch('schemas')
create = schemas.fetch('CreateWorkbookSpec')
update = schemas.fetch('UpdateWorkbookSpec')
read = schemas.fetch('WorkbookSpec')
create_document = property(create, 'document')
update_document = property(update, 'document')
read_document = property(read, 'document')
pages = property(create_document, 'pages')

contract = {
  'source' => {
    'openapiVersion' => openapi.fetch('openapi'),
    'apiVersion' => openapi.fetch('info').fetch('version'),
    'capturedAt' => ENV.fetch('CAPTURED_AT', Date.today.iso8601)
  },
  'schemas' => {
    'CreateWorkbookSpec' => shape(create),
    'CreateWorkbookSpec.document' => shape(create_document),
    'UpdateWorkbookSpec' => shape(update),
    'UpdateWorkbookSpec.document' => shape(update_document),
    'WorkbookSpec' => shape(read),
    'WorkbookSpec.document' => shape(read_document),
    'WorkbookPage' => shape(pages.fetch('items'))
  },
  'releasedVariants' => {
    'elements' => (
      collect_discriminators(schemas.fetch('WorkbookElement'), 'kind') +
      collect_discriminators(schemas.fetch('CommonElement'), 'kind')
    ).uniq { |entry| entry['kind'] }.sort_by { |entry| entry['kind'] },
    'controls' => collect_discriminators(schemas.fetch('CommonElement'), 'controlType')
  },
  # Per-effect property/required sets + the nested union shapes they reference.
  # A rename on either level is now a fixture diff instead of a silent 400.
  'actions' => {
    # ELEMENT-level actions (the `Actions` schema): 22 effects. This is what a
    # button / on-select emits and what the converters generate.
    'effects' => collect_effects(effects_schema(schemas.fetch('Actions'))),
    'unionShapes' => collect_union_shapes(schemas.fetch('Actions')).sort.to_h,
    # DOCUMENT-level `automatedActions` is a SEPARATE surface with its own effect
    # union -- `call-agent` exists only here, which is why pinning `Actions`
    # alone reports 22 of the 23 effect names visible in the spec. Pinned so a
    # rename on either surface is a diff; note automatedActions is documented as
    # UI-authorable only, so this is contract-tracking, not an emit target.
    'automatedActionEffects' => collect_effects(automated_actions_effects(create_document))
  }
}

puts JSON.pretty_generate(contract)
