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
  }
}

puts JSON.pretty_generate(contract)
