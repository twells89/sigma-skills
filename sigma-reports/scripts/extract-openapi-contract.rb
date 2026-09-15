#!/usr/bin/env ruby
# frozen_string_literal: true

# Extract the small, executable report-as-code contract pinned by this skill.
# Usage: ruby scripts/extract-openapi-contract.rb OPENAPI_JSON

require 'date'
require 'json'

def resolve(schema, openapi)
  return schema unless schema.is_a?(Hash) && schema['$ref']

  schema['$ref'].delete_prefix('#/').split('/').reduce(openapi) { |node, key| node.fetch(key) }
end

def merged_required(schema, openapi)
  schema = resolve(schema, openapi)
  return [] unless schema.is_a?(Hash)

  (Array(schema['required']) + Array(schema['allOf']).flat_map { |part| merged_required(part, openapi) }).uniq.sort
end

def merged_properties(schema, openapi)
  schema = resolve(schema, openapi)
  return [] unless schema.is_a?(Hash)

  (schema.fetch('properties', {}).keys + Array(schema['allOf']).flat_map { |part| merged_properties(part, openapi) }).uniq.sort
end

def property(schema, name, openapi)
  schema = resolve(schema, openapi)
  return unless schema.is_a?(Hash)
  return schema.dig('properties', name) if schema.dig('properties', name)

  Array(schema['allOf']).each do |part|
    found = property(part, name, openapi)
    return found if found
  end
  nil
end

def shape(schema, openapi)
  {'required' => merged_required(schema, openapi), 'properties' => merged_properties(schema, openapi)}
end

def enum_values(schema, openapi)
  schema = resolve(schema, openapi)
  return [] unless schema.is_a?(Hash)

  (Array(schema['enum']) + %w[oneOf anyOf allOf].flat_map do |key|
    Array(schema[key]).flat_map { |part| enum_values(part, openapi) }
  end).uniq.sort
end

def collect_discriminators(schema, discriminator, openapi, out = [], seen = {})
  return out unless schema.is_a?(Hash)

  if schema['$ref']
    return out if seen[schema['$ref']]

    seen[schema['$ref']] = true
    schema = resolve(schema, openapi)
  end
  values = enum_values(property(schema, discriminator, openapi), openapi)
  out << {'title' => schema['title'], discriminator => values.first} if schema['title'] && values.one?
  %w[oneOf anyOf allOf].each do |key|
    Array(schema[key]).each { |part| collect_discriminators(part, discriminator, openapi, out, seen.dup) }
  end
  out.uniq { |entry| entry[discriminator] }.sort_by { |entry| entry[discriminator] }
end

def collect_discriminator_values(schema, discriminator, openapi, out = [], seen = {})
  return out unless schema.is_a?(Hash)

  if schema['$ref']
    return out if seen[schema['$ref']]

    seen[schema['$ref']] = true
    schema = resolve(schema, openapi)
  end
  values = enum_values(property(schema, discriminator, openapi), openapi)
  if values.one?
    out << {
      'title' => schema['title'] || values.first.split('-').map(&:capitalize).join(' '),
      discriminator => values.first
    }
  end
  %w[oneOf anyOf allOf].each do |key|
    Array(schema[key]).each do |part|
      collect_discriminator_values(part, discriminator, openapi, out, seen.dup)
    end
  end
  out.uniq { |entry| entry[discriminator] }.sort_by { |entry| entry[discriminator] }
end

def discriminator_schema(schema, discriminator, value, openapi, matches = [], seen = {})
  return unless schema.is_a?(Hash)

  if schema['$ref']
    return if seen[schema['$ref']]

    seen[schema['$ref']] = true
    schema = resolve(schema, openapi)
  end
  values = enum_values(property(schema, discriminator, openapi), openapi)
  matches << schema if values == [value]
  %w[oneOf anyOf allOf].each do |key|
    Array(schema[key]).each do |part|
      discriminator_schema(part, discriminator, value, openapi, matches, seen.dup)
    end
  end
  matches.max_by { |entry| merged_properties(entry, openapi).length }
end

def property_enums(schema, name, openapi, out = [], seen = {})
  return out unless schema.is_a?(Hash)

  if schema['$ref']
    return out if seen[schema['$ref']]

    seen[schema['$ref']] = true
    schema = resolve(schema, openapi)
  end
  out.concat(enum_values(schema.dig('properties', name), openapi)) if schema.dig('properties', name)
  %w[oneOf anyOf allOf].each do |key|
    Array(schema[key]).each { |part| property_enums(part, name, openapi, out, seen.dup) }
  end
  out.uniq.sort
end

def array_contract(schema, openapi)
  schema = resolve(schema, openapi)
  return unless schema.is_a?(Hash)

  {
    'type' => schema['type'],
    'items' => shape(schema['items'], openapi)
  }
end

def shared_breaking_shapes(schemas, create_document, openapi)
  common = schemas.fetch('CommonElement')
  text = discriminator_schema(common, 'kind', 'text', openapi)
  kpi = discriminator_schema(common, 'kind', 'kpi-chart', openapi)
  divider = discriminator_schema(common, 'kind', 'divider', openapi)
  pivot = discriminator_schema(common, 'kind', 'pivot-table', openapi)
  geography = discriminator_schema(common, 'kind', 'geography-map', openapi)
  point = discriminator_schema(common, 'kind', 'point-map', openapi)
  region = discriminator_schema(common, 'kind', 'region-map', openapi)
  combo = discriminator_schema(common, 'kind', 'combo-chart', openapi)
  kpi_layout = property(kpi, 'layout', openapi)
  settings = property(create_document, 'settings', openapi)
  theme = property(settings, 'theme', openapi)
  overrides = property(theme, 'overrides', openapi)

  {
    'alignment' => {
      'textVerticalAlign' => enum_values(property(text, 'verticalAlign', openapi), openapi),
      'kpiAnchor' => enum_values(property(kpi_layout, 'anchor', openapi), openapi),
      'kpiVerticalAnchor' => enum_values(property(kpi_layout, 'verticalAnchor', openapi), openapi),
      'dividerAlign' => property_enums(divider, 'align', openapi)
    },
    'columnIdPointers' => {
      'geography' => shape(property(geography, 'geography', openapi), openapi),
      'latitude' => shape(property(point, 'latitude', openapi), openapi),
      'longitude' => shape(property(point, 'longitude', openapi), openapi),
      'region' => shape(property(region, 'region', openapi), openapi),
      'pivotRowsByItem' => shape(property(pivot, 'rowsBy', openapi).fetch('items'), openapi),
      'pivotColumnsByItem' => shape(property(pivot, 'columnsBy', openapi).fetch('items'), openapi)
    },
    'listShapes' => {
      'seriesLineAreaStyle' => array_contract(property(combo, 'seriesLineAreaStyle', openapi), openapi),
      'colorOverrides' => array_contract(property(overrides, 'colorOverrides', openapi), openapi)
    }
  }
end

def request_schema(openapi, path, method)
  openapi.dig('paths', path, method, 'requestBody', 'content', 'application/json', 'schema')
end

def response_schema(openapi, path, method, status)
  openapi.dig('paths', path, method, 'responses', status, 'content', 'application/json', 'schema')
end

path = ARGV.fetch(0) { abort 'usage: extract-openapi-contract.rb OPENAPI_JSON' }
openapi = JSON.parse(File.read(path))
schemas = openapi.fetch('components').fetch('schemas')
create_path = '/v2/reports/spec'
verify_path = '/v2/reports/spec/verify'
spec_path = '/v2/reports/{reportId}/spec'
resource_path = '/v2/reports/{reportId}'
convert_path = '/v2/workbooks/{workbookId}/convertToReport'

create = request_schema(openapi, create_path, 'post')
verify = request_schema(openapi, verify_path, 'post')
update = request_schema(openapi, spec_path, 'put')
read = response_schema(openapi, spec_path, 'get', '200')
convert_request = request_schema(openapi, convert_path, 'post')
convert_response = response_schema(openapi, convert_path, 'post', '201')
create_document = property(create, 'document', openapi)
update_document = property(update, 'document', openapi)
read_document = property(read, 'document', openapi)
page = resolve(property(create_document, 'pages', openapi).fetch('items'), openapi)
panel = resolve(property(create_document, 'panels', openapi).fetch('items'), openapi)
config = property(create_document, 'config', openapi)
panel_config = property(panel, 'config', openapi)
common_elements = collect_discriminators(schemas.fetch('CommonElement'), 'kind', openapi)
common_kinds = common_elements.map { |entry| entry.fetch('kind') }
workbook_only_elements = collect_discriminators(schemas.fetch('WorkbookElement'), 'kind', openapi)
                         .reject { |entry| common_kinds.include?(entry.fetch('kind')) }
controls = (
  collect_discriminator_values(schemas.fetch('Control'), 'controlType', openapi) +
  collect_discriminator_values(schemas.fetch('CommonElement'), 'controlType', openapi)
).uniq { |entry| entry.fetch('controlType') }.sort_by { |entry| entry.fetch('controlType') }

contract = {
  'source' => {
    'openapiVersion' => openapi.fetch('openapi'),
    'apiVersion' => openapi.fetch('info').fetch('version'),
    'capturedAt' => ENV.fetch('CAPTURED_AT', Date.today.iso8601)
  },
  'mediaTypes' => {
    'create' => openapi.dig('paths', create_path, 'post', 'requestBody', 'content').keys.sort,
    'verify' => openapi.dig('paths', verify_path, 'post', 'requestBody', 'content').keys.sort,
    'read' => openapi.dig('paths', spec_path, 'get', 'responses', '200', 'content').keys.sort,
    'update' => openapi.dig('paths', spec_path, 'put', 'requestBody', 'content').keys.sort
  },
  'schemas' => {
    'CreateReportSpec' => shape(create, openapi),
    'CreateReportSpec.document' => shape(create_document, openapi),
    'VerifyReportSpec' => shape(verify, openapi),
    'UpdateReportSpec' => shape(update, openapi),
    'UpdateReportSpec.document' => shape(update_document, openapi),
    'ReportSpec' => shape(read, openapi),
    'ReportSpec.document' => shape(read_document, openapi),
    'ReportPage' => shape(page, openapi),
    'ReportPanel' => shape(panel, openapi),
    'ReportPanel.config' => shape(panel_config, openapi),
    'ReportConfig' => shape(config, openapi),
    'ConvertWorkbookToReport' => shape(convert_request, openapi),
    'ConvertWorkbookToReportResponse' => shape(convert_response, openapi)
  },
  'enums' => {
    'documentKind' => enum_values(property(create_document, 'kind', openapi), openapi),
    'panelType' => enum_values(property(panel, 'type', openapi), openapi)
  },
  'publishedVariants' => {
    'commonElements' => common_elements,
    'workbookOnlyElements' => workbook_only_elements,
    'controls' => controls
  },
  'sharedBreakingShapes' => shared_breaking_shapes(schemas, create_document, openapi),
  'operations' => {
    'reportResourceMethods' => openapi.fetch('paths').fetch(resource_path).keys.grep(/\A(?:get|post|put|patch|delete)\z/).sort,
    'createStatuses' => openapi.dig('paths', create_path, 'post', 'responses').keys.sort,
    'verifyStatuses' => openapi.dig('paths', verify_path, 'post', 'responses').keys.sort,
    'readStatuses' => openapi.dig('paths', spec_path, 'get', 'responses').keys.sort,
    'updateStatuses' => openapi.dig('paths', spec_path, 'put', 'responses').keys.sort,
    'convertStatuses' => openapi.dig('paths', convert_path, 'post', 'responses').keys.sort
  }
}

puts JSON.pretty_generate(contract)
