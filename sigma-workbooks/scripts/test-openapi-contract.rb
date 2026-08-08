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
