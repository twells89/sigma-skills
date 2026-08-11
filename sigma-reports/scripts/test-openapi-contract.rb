#!/usr/bin/env ruby
# frozen_string_literal: true

# Offline contract regression:
#   ruby scripts/test-openapi-contract.rb
# Compare with a freshly downloaded OpenAPI document:
#   ruby scripts/test-openapi-contract.rb /tmp/sigma-openapi.json

require 'json'
require 'open3'

FIXTURE = File.expand_path('fixtures/openapi-report-contract.json', __dir__)
EXTRACTOR = File.expand_path('extract-openapi-contract.rb', __dir__)
contract = JSON.parse(File.read(FIXTURE))
failures = []

def assert_contract(failures, description)
  failures << description unless yield
end

schemas = contract.fetch('schemas')
create = schemas.fetch('CreateReportSpec')
create_document = schemas.fetch('CreateReportSpec.document')
verify = schemas.fetch('VerifyReportSpec')
update = schemas.fetch('UpdateReportSpec')
read_document = schemas.fetch('ReportSpec.document')
page = schemas.fetch('ReportPage')
panel = schemas.fetch('ReportPanel')
panel_config = schemas.fetch('ReportPanel.config')
config = schemas.fetch('ReportConfig')
convert_response = schemas.fetch('ConvertWorkbookToReportResponse')
common_kinds = contract.dig('publishedVariants', 'commonElements').map { |entry| entry.fetch('kind') }
workbook_only_kinds = contract.dig('publishedVariants', 'workbookOnlyElements').map { |entry| entry.fetch('kind') }
control_types = contract.dig('publishedVariants', 'controls').map { |entry| entry.fetch('controlType') }

assert_contract(failures, 'report spec endpoints declare JSON only') do
  contract.fetch('mediaTypes').values.all? { |types| types == ['application/json'] }
end
assert_contract(failures, 'create requires name, folderId, and document') do
  create.fetch('required') == %w[document folderId name]
end
assert_contract(failures, 'verify uses the create envelope') do
  verify == create
end
assert_contract(failures, 'update accepts only a required document') do
  update.fetch('required') == ['document'] && update.fetch('properties') == ['document']
end
assert_contract(failures, 'report document requires core collections and report kind') do
  %w[elements kind pages schemaVersion].all? { |key| create_document.fetch('required').include?(key) } &&
    contract.dig('enums', 'documentKind') == ['report']
end
assert_contract(failures, 'report document exposes config, layout, and panels') do
  %w[config elements kind layout pages panels schemaVersion].all? do |key|
    create_document.fetch('properties').include?(key)
  end
end
assert_contract(failures, 'readback requires layout') do
  read_document.fetch('required').include?('layout')
end
assert_contract(failures, 'page metadata has no nested elements') do
  %w[id name].all? { |key| page.fetch('required').include?(key) } &&
    !page.fetch('properties').include?('elements')
end
assert_contract(failures, 'report config is pixel page sizing') do
  config.fetch('properties') == %w[margin pageHeight pageWidth]
end
assert_contract(failures, 'report panels are headers or footers with pixel config') do
  %w[id type].all? { |key| panel.fetch('required').include?(key) } &&
    %w[config id pages title type].all? { |key| panel.fetch('properties').include?(key) } &&
    contract.dig('enums', 'panelType') == %w[footer header] &&
    panel_config.fetch('properties') == %w[backgroundColor height]
end
assert_contract(failures, 'common report union publishes expected kinds') do
  %w[table text control waterfall-chart progress input-table].all? { |kind| common_kinds.include?(kind) }
end
assert_contract(failures, 'workbook-only union remains separate') do
  %w[chat container form navigation page-break repeated-container tabbed-container].all? do |kind|
    workbook_only_kinds.include?(kind) && !common_kinds.include?(kind)
  end
end
assert_contract(failures, 'synced control remains schema-published and policy-gated') do
  control_types.include?('synced')
end
assert_contract(failures, 'report resource has no delete method') do
  contract.dig('operations', 'reportResourceMethods') == ['get']
end
assert_contract(failures, 'conversion response requires warnings') do
  %w[convertedReport sourceWorkbook warnings].all? do |key|
    convert_response.fetch('required').include?(key)
  end
end

if ARGV[0]
  captured_at = contract.dig('source', 'capturedAt')
  stdout, stderr, status = Open3.capture3(
    {'CAPTURED_AT' => captured_at},
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
  puts "PASS: report OpenAPI contract (#{common_kinds.length} common elements, #{control_types.length} controls)"
  exit 0
end

failures.each { |failure| warn "FAIL: #{failure}" }
exit 1
