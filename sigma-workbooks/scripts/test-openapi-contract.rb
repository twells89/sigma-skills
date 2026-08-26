#!/usr/bin/env ruby
# frozen_string_literal: true

# Offline contract regression:
#   ruby scripts/test-openapi-contract.rb
# Compare the pin with a freshly downloaded OpenAPI document:
#   ruby scripts/test-openapi-contract.rb /tmp/sigma-openapi.json

require 'json'
require 'open3'

FIXTURE = File.expand_path('fixtures/openapi-workbook-contract.json', __dir__)
EXTRACTOR = File.expand_path('extract-openapi-contract.rb', __dir__)
contract = JSON.parse(File.read(FIXTURE))
failures = []

def assert_contract(failures, description)
  failures << description unless yield
end

schemas = contract.fetch('schemas')
create = schemas.fetch('CreateWorkbookSpec')
create_doc = schemas.fetch('CreateWorkbookSpec.document')
update = schemas.fetch('UpdateWorkbookSpec')
read_doc = schemas.fetch('WorkbookSpec.document')
page = schemas.fetch('WorkbookPage')
actions = contract.fetch('actions')
effects = actions.fetch('effects')
union_shapes = actions.fetch('unionShapes').values

# ---- the 2026-08-26 action field rename -----------------------------------
# This fixture pinned CreateWorkbookSpec and the element/control discriminators
# but had ZERO Actions coverage. So when Sigma renamed every action identifier
# field to a *Id shape, the pin did not move, this gate stayed green, and four
# repos emitted dead keys. These assertions exist so the NEXT rename is a
# failing test rather than a field incident.
#
# `_renamed` pairs are asserted in BOTH directions: the new key must be pinned
# AND the old key must be gone. Only checking the new key would keep passing if
# the API ever accepted both.
{
  'insert-rows' => 'tableElementId',
  'update-rows' => 'tableElementId',
  'delete-rows' => 'tableElementId',
  'set-form-values' => 'formElementId',
  'select-tab' => 'tabbedContainerElementId',
  'open-document' => 'documentId',
  'custom-sort' => 'elementId',
  'run-python-element' => 'codeElementId',
  'clear-chat-element-messages' => 'chatElementId'
}.each do |effect, new_key|
  assert_contract(failures, "#{effect} requires #{new_key} (post-rename)") do
    effects.fetch(effect, {}).fetch('required', []).include?(new_key)
  end
end

{
  'insert-rows' => 'table', 'update-rows' => 'table', 'delete-rows' => 'table',
  'set-form-values' => 'form', 'select-tab' => 'tabbedContainer',
  'open-document' => 'document'
}.each do |effect, dead_key|
  assert_contract(failures, "#{effect} no longer exposes the dead `#{dead_key}` key") do
    !effects.fetch(effect, {}).fetch('properties', []).include?(dead_key)
  end
end

assert_contract(failures, 'trigger-plugin uses pluginElementId + pluginEffectId') do
  effects.fetch('trigger-plugin', {}).fetch('required', []).sort == %w[pluginEffectId pluginElementId]
end

# The rename is SELECTIVE. These three were probed and deliberately NOT renamed,
# so a future "cleanup" to *Id would be a live 400. Pin the bare names.
assert_contract(failures, 'set-control-value keeps the bare `control` key') do
  effects.fetch('set-control-value', {}).fetch('required', []).include?('control')
end
assert_contract(failures, 'a {type:page} union member with a bare `page` still exists (navigate target)') do
  union_shapes.any? { |shape| shape['type'] == 'page' && shape['properties'] == ['page'] }
end
assert_contract(failures, 'a {type:element} union member with a bare `element` still exists (refresh-element target)') do
  union_shapes.any? { |shape| shape['type'] == 'element' && shape['properties'] == ['element'] }
end
assert_contract(failures, 'a {type:control} union member with a bare `control` still exists (set-control-value)') do
  union_shapes.any? { |shape| shape['type'] == 'control' && shape['properties'] == ['control'] }
end

# ...while the SAME discriminators renamed under a clear-control scope.
assert_contract(failures, 'clear-control scope union renamed to pageId/controlId/containerElementId') do
  %w[pageId controlId containerElementId].all? do |key|
    union_shapes.any? { |shape| shape['properties'] == [key] }
  end
end

# The nested half of the rename -- value sources, whichRows selectors, sort keys.
assert_contract(failures, 'column union members use columnId, never bare `column`') do
  cols = union_shapes.select { |shape| shape['type'] == 'column' }
  cols.any? && cols.none? { |shape| shape['properties'].include?('column') } &&
    cols.all? { |shape| shape['properties'].include?('columnId') }
end
assert_contract(failures, 'column-match uses columnId') do
  union_shapes.any? { |shape| shape['type'] == 'column-match' && shape['properties'] == ['columnId'] }
end
assert_contract(failures, 'column-range uses minColumnId/maxColumnId, not min/max') do
  ranges = union_shapes.select { |shape| shape['type'] == 'column-range' }
  ranges.any? && ranges.all? { |shape| shape['properties'].sort == %w[maxColumnId minColumnId] }
end

# Coverage floor: element actions currently expose 22 effects and
# automatedActions exposes only call-agent. A DROP means the pin lost coverage;
# a RISE means Sigma shipped an effect nobody has looked at yet.
assert_contract(failures, "element actions expose 22 effects (got #{effects.length})") do
  effects.length == 22
end
assert_contract(failures, 'automatedActions exposes call-agent (its own separate surface)') do
  actions.fetch('automatedActionEffects').key?('call-agent')
end

element_kinds = contract.dig('releasedVariants', 'elements').map { |entry| entry.fetch('kind') }
control_types = contract.dig('releasedVariants', 'controls').map { |entry| entry.fetch('controlType') }

assert_contract(failures, 'create envelope requires name, folderId, and document') do
  create.fetch('required') == %w[document folderId name]
end
assert_contract(failures, 'update accepts only a required document') do
  update.fetch('required') == ['document'] && update.fetch('properties') == ['document']
end
assert_contract(failures, 'document owns every released top-level collection') do
  %w[elements overlays pages panels settings agents layout].all? do |key|
    create_doc.fetch('properties').include?(key)
  end
end
assert_contract(failures, 'elements and pages are required document collections') do
  %w[elements pages].all? { |key| create_doc.fetch('required').include?(key) }
end
assert_contract(failures, 'pages are metadata-only and expose styling') do
  !page.fetch('properties').include?('elements') &&
    %w[backgroundColor backgroundImage].all? { |key| page.fetch('properties').include?(key) }
end
assert_contract(failures, 'readback requires layout even while create OpenAPI leaves it nullable') do
  read_doc.fetch('required').include?('layout') && !create_doc.fetch('required').include?('layout')
end
assert_contract(failures, 'released element kinds are pinned') do
  %w[
    waterfall-chart navigation repeated-container tabbed-container page-break progress
  ].all? { |kind| element_kinds.include?(kind) }
end
assert_contract(failures, 'legend and drill controls are pinned') do
  %w[legend drill].all? { |control_type| control_types.include?(control_type) }
end
assert_contract(failures, 'box chart remains gated until it is published') do
  (element_kinds & %w[box-chart box-plot]).empty?
end

if ARGV[0]
  captured_at = contract.dig('source', 'capturedAt')
  stdout, stderr, status = Open3.capture3(
    { 'CAPTURED_AT' => captured_at },
    'ruby', EXTRACTOR, ARGV[0]
  )
  if status.success?
    live_contract = JSON.parse(stdout)
    failures << 'committed fixture differs from supplied OpenAPI' unless live_contract == contract
  else
    failures << "extractor failed: #{stderr.strip}"
  end
end

if failures.empty?
  puts "PASS — workbook OpenAPI contract (#{element_kinds.length} elements, #{control_types.length} controls)"
  exit 0
end

failures.each { |failure| warn "FAIL — #{failure}" }
exit 1
