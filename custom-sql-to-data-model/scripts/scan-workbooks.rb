#!/usr/bin/env ruby
# Scan all workbooks for elements with source.kind == "sql".
# Outputs a JSON manifest to /tmp/custom-sql-manifest.json
#
# Usage:
#   eval "$(bash scripts/get-token.sh)"
#   ruby scripts/scan-workbooks.rb

require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'date'

BASE_URL = ENV.fetch('SIGMA_BASE_URL') { abort 'SIGMA_BASE_URL not set — run: eval "$(bash scripts/get-token.sh)"' }
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'sigma_rest'

# Full-site workbook scans paginate over hundreds of items and can take >1
# hour on large customer orgs; Sigma.request auto-refreshes on 401.
def get(path)
  res = Sigma.request(:get, path, accept: '*/*')
  res.is_a?(String) ? res : res.to_json
end

# Fetch all workbooks (paginate)
puts "Fetching workbook list..."
workbooks = []
next_page = nil
loop do
  path = '/v2/workbooks?limit=100'
  path += "&page=#{next_page}" if next_page
  body = JSON.parse(get(path))
  workbooks.concat(body.fetch('entries', []))
  next_page = body['nextPage']
  break unless next_page
end
puts "Found #{workbooks.size} workbooks total.\n\n"

# Scan each workbook spec for SQL elements
findings = []
workbooks.each do |wb|
  wid  = wb['workbookId']
  name = wb['name']

  begin
    raw  = get("/v2/workbooks/#{wid}/spec")
    spec = YAML.safe_load(raw, permitted_classes: [Date, Time])
    next unless spec.is_a?(Hash) && spec['pages']

    folder_id = spec['folderId']

    spec['pages'].each do |page|
      (page['elements'] || []).each do |el|
        src = el['source']
        next unless src.is_a?(Hash) && src['kind'] == 'sql'

        # Use element name if set, otherwise fall back to workbook name
        el_name = (el['name'] && !el['name'].strip.empty?) ? el['name'] : "#{name} SQL"

        findings << {
          workbook_id:   wid,
          workbook_name: name,
          folder_id:     folder_id,
          element_id:    el['id'],
          element_name:  el_name,
          connection_id: src['connectionId'],
          sql:           src['statement'],
          column_count:  (el['columns'] || []).size
        }
        puts "  [FOUND] #{name} / #{el_name}"
        puts "          SQL: #{src['statement'][0..100]}#{'...' if src['statement'].length > 100}"
      end
    end
  rescue => e
    $stderr.puts "  [ERROR] #{name}: #{e.message}"
  end
end

puts "\n#{'='*60}"
puts "Custom SQL elements found: #{findings.size}"

if findings.empty?
  puts "No custom SQL elements found in any workbook."
else
  out = '/tmp/custom-sql-manifest.json'
  File.write(out, JSON.pretty_generate(findings))
  puts "Manifest written to #{out}"
end
