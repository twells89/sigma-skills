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
    'controls' => collect_discriminators(schemas.fetch('CommonElement'), 'controlType', openapi)
  },
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
