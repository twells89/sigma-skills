#!/usr/bin/env ruby
# Scan all data models for elements with source.kind == "sql".
# Outputs a JSON index keyed by normalized SQL to /tmp/dm-sql-index.json,
# used by plan-dedup.rb to decide whether to reuse an existing DM element
# or build a new one for a given custom-SQL fingerprint.
#
# Usage:
#   eval "$(bash scripts/get-token.sh)"
#   ruby scripts/scan-data-models.rb

require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'date'

BASE_URL = ENV.fetch('SIGMA_BASE_URL') { abort 'SIGMA_BASE_URL not set' }
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'sigma_rest'

# Full-site DM scans can outlive a single 1-hour token; Sigma.request
# auto-refreshes on 401.
def get(path)
  res = Sigma.request(:get, path, accept: '*/*')
  res.is_a?(String) ? res : res.to_json
end

# Normalize a SQL string for equivalence comparison.
# Removes leading/trailing whitespace, collapses internal whitespace, lowercases.
# Intentionally conservative — does not reformat or reorder clauses, so two
# functionally-equivalent queries written differently will be treated as
# distinct. The point is to catch true duplicates from copy/paste.
def normalize_sql(s)
  return nil if s.nil?
  s.to_s.strip.gsub(/\s+/, ' ').downcase
end

# Fetch all data models (paginate)
puts 'Fetching data model list...'
dms = []
next_page = nil
loop do
  path = '/v2/dataModels?limit=100'
  path += "&page=#{next_page}" if next_page
  body = JSON.parse(get(path))
  dms.concat(body.fetch('entries', []))
  next_page = body['nextPage']
  break unless next_page
end
puts "Found #{dms.size} data models total.\n\n"

# Walk each DM spec for SQL elements
index = {}  # normalized_sql => [ { dataModelId, dataModelName, elementId, elementName, connectionId, sql } ]
dms.each do |dm|
  dmid = dm['dataModelId']
  name = dm['name']

  begin
    raw  = get("/v2/dataModels/#{dmid}/spec")
    spec = JSON.parse(raw)
    next unless spec.is_a?(Hash) && spec['pages']
  rescue => e
    $stderr.puts "  [ERROR] #{name} (#{dmid}): #{e.message}"
    next
  end

  # Total element count across all pages — used by the planner to prefer
  # focused DMs (fewer elements) over kitchen-sink models when picking
  # between equivalent candidates.
  dm_element_count = spec['pages'].sum { |p| (p['elements'] || []).size }

  spec['pages'].each do |page|
    (page['elements'] || []).each do |el|
      src = el['source']
      next unless src.is_a?(Hash)

      case src['kind']
      when 'sql'
        norm = normalize_sql(src['statement'])
        entry = {
          dataModelId:      dmid,
          dataModelName:    name,
          dmElementCount:   dm_element_count,
          elementId:        el['id'],
          elementName:      el['name'],
          connectionId:     src['connectionId'],
          sourceKind:    'sql',
          sql:           src['statement']
        }
        (index[norm] ||= []) << entry
        puts "  [FOUND] #{name} / #{el['name']} (sql)"

      when 'warehouse-table'
        # Surface warehouse-table elements as candidates for trivial
        # `SELECT * FROM <path>` custom-SQL. Keyed by a synthetic
        # equivalent so the normalizer collapses to one bucket.
        path = (src['path'] || []).map { |p| p.to_s.downcase }.join('.')
        next if path.empty?
        synthetic = "select * from #{path}"
        entry = {
          dataModelId:      dmid,
          dataModelName:    name,
          dmElementCount:   dm_element_count,
          elementId:        el['id'],
          elementName:      el['name'],
          connectionId:     src['connectionId'],
          sourceKind:    'warehouse-table',
          path:          src['path']
        }
        (index[synthetic] ||= []) << entry
        puts "  [FOUND] #{name} / #{el['name']} (warehouse-table → #{synthetic})"
      end
    end
  end
end

puts "\n#{'=' * 60}"
puts "Unique SQL strings indexed across DMs: #{index.size}"

out = '/tmp/dm-sql-index.json'
File.write(out, JSON.pretty_generate(index))
puts "Index written to #{out}"
