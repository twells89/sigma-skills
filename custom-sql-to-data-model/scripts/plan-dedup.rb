#!/usr/bin/env ruby
# Read the workbook manifest and the DM-SQL index, group manifest entries by
# normalized SQL, and emit a swap plan. For each unique SQL:
#   - If a DM element already wraps it → reuse (status: "existing")
#   - Otherwise → mark as needs-build (status: "to-build")
#
# Output: /tmp/swap-plan.json — an array of plan entries. Each entry has the
# normalized SQL, the list of workbook occurrences that share it, and either
# an existing target {dataModelId, elementId} OR a `to_build: true` flag with
# a representative sql/connection_id/folder_id the user can pass to Phase 2.
#
# Usage:
#   ruby scripts/scan-workbooks.rb
#   ruby scripts/scan-data-models.rb
#   ruby scripts/plan-dedup.rb

require 'json'

MANIFEST = '/tmp/custom-sql-manifest.json'
DM_INDEX = '/tmp/dm-sql-index.json'
OUT      = '/tmp/swap-plan.json'

unless File.exist?(MANIFEST)
  abort "missing #{MANIFEST} — run scan-workbooks.rb first"
end
unless File.exist?(DM_INDEX)
  abort "missing #{DM_INDEX} — run scan-data-models.rb first"
end

def normalize_sql(s)
  return nil if s.nil?
  s.to_s.strip.gsub(/\s+/, ' ').downcase
end

manifest = JSON.parse(File.read(MANIFEST))
dm_index = JSON.parse(File.read(DM_INDEX))

# Group manifest by normalized SQL
groups = manifest.group_by { |m| normalize_sql(m['sql']) }

plan = groups.map do |norm, occurrences|
  rep = occurrences.first  # representative for SQL/connection/folder

  # Look up existing DM element
  candidates = dm_index[norm] || []

  # Pick the best candidate. Heuristic in order:
  #   1. Same connection as the workbook's custom-SQL
  #   2. Fewest elements in the DM (most focused — beats kitchen-sink DMs)
  #   3. Stable tiebreak by DM name then element name
  match = candidates
    .sort_by { |c| [
      c['connectionId'] == rep['connection_id'] ? 0 : 1,
      c['dmElementCount'] || 999_999,
      c['dataModelName'].to_s,
      c['elementName'].to_s
    ] }
    .first

  entry = {
    normalized_sql_preview: norm.to_s.slice(0, 120),
    occurrence_count:       occurrences.size,
    workbooks:              occurrences.map { |o|
                              { workbook_id:   o['workbook_id'],
                                workbook_name: o['workbook_name'],
                                element_id:    o['element_id'],
                                element_name:  o['element_name'] }
                            },
    representative: {
      sql:           rep['sql'],
      connection_id: rep['connection_id'],
      folder_id:     rep['folder_id']
    }
  }

  if match
    entry[:status]      = 'existing'
    entry[:target]      = {
      dataModelId:   match['dataModelId'],
      dataModelName: match['dataModelName'],
      elementId:     match['elementId'],
      elementName:   match['elementName']
    }
  else
    entry[:status]      = 'to-build'
    entry[:target]      = nil
  end
  entry
end

# Order: to-build first (most actionable), then existing
plan.sort_by! { |e| [e[:status] == 'to-build' ? 0 : 1, -e[:occurrence_count]] }

File.write(OUT, JSON.pretty_generate(plan))
puts "Plan written to #{OUT}\n\n"

plan.each_with_index do |e, i|
  marker = e[:status] == 'existing' ? '[REUSE]' : '[BUILD]'
  puts "#{marker} group #{i + 1}: #{e[:occurrence_count]} occurrence(s)"
  puts "  SQL: #{e[:normalized_sql_preview]}#{'…' if e[:normalized_sql_preview].length >= 120}"
  e[:workbooks].each do |w|
    puts "    - #{w[:workbook_name]} / #{w[:element_name]} (#{w[:element_id]})"
  end
  if e[:status] == 'existing'
    t = e[:target]
    puts "  -> #{t[:dataModelName]} / #{t[:elementName]} (#{t[:dataModelId]} / #{t[:elementId]})"
  else
    puts "  -> needs new DM (connection #{e[:representative][:connection_id]}, folder #{e[:representative][:folder_id]})"
  end
  puts
end

build_count = plan.count { |e| e[:status] == 'to-build' }
reuse_count = plan.count { |e| e[:status] == 'existing' }
total_swaps = plan.sum { |e| e[:occurrence_count] }
puts "Summary: #{plan.size} unique SQL strings → #{reuse_count} reuse, #{build_count} build. #{total_swaps} total swap actions."
