#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

path = ARGV.fetch(0) { abort 'usage: ruby scripts/test-table-columns-openapi.rb OPENAPI_JSON' }
openapi = JSON.parse(File.read(path))
operation = openapi.dig('paths', '/v2/connections/tables/{tableId}/columns', 'get') ||
            abort('table columns operation missing from OpenAPI')
parameters = operation.fetch('parameters')
by_name = parameters.each_with_object({}) { |parameter, out| out[parameter['name']] = parameter }
page_size = by_name.fetch('pageSize').fetch('schema')
page_token = by_name.fetch('pageToken').fetch('schema')
response = operation.dig('responses', '200', 'content', 'application/json', 'schema')
response_parts = response.fetch('allOf')
pagination = response_parts.find { |part| part.dig('properties', 'nextPageToken') }
failures = []

failures << 'pageSize default must remain 50' unless page_size['description'].to_s.include?('Defaults to 50')
failures << 'pageSize maximum must remain 1000' unless page_size['description'].to_s.include?('maximum of 1000')
failures << 'pageToken must be a string' unless page_token['type'] == 'string'
failures << 'pageToken must consume nextPageToken' unless page_token['description'].to_s.include?('nextPageToken')
failures << 'response must publish nextPageToken' unless pagination
if pagination && !pagination.dig('properties', 'nextPageToken', 'description').to_s.include?('opaque')
  failures << 'nextPageToken must remain opaque'
end

if failures.empty?
  puts 'PASS: table-column pagination contract (default 50, max 1000, opaque page token)'
  exit 0
end

failures.each { |failure| warn "FAIL: #{failure}" }
exit 1
