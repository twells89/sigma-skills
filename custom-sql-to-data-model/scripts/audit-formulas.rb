#!/usr/bin/env ruby
# Post-swap formula audit. After :swapSources, the Sigma auto-match converts
# most SQL aliases (e.g. `EMPLOYEE_ID`) into the matching DM column's display
# name (`Employee Id`). It silently misses some — short uppercase tokens,
# tokens that share a prefix with siblings, etc. — leaving broken formulas
# like `[OT Summary/OT_HOURS]` that point at a column ID the DM doesn't expose.
#
# This script walks every workbook the user passes, finds residual
# `[Prefix/SNAKE_CASE]` formulas where SNAKE_CASE matches a sibling column's
# `id` field but not its `name`, and rewrites them to `[Prefix/<Display Name>]`.
# It does NOT touch warehouse formulas (`[WAREHOUSE_TABLE/COL]`) — those are
# legitimate.
#
# Usage:
#   ruby scripts/audit-formulas.rb <workbookId> [<workbookId> ...]
# Or, drive from /tmp/swap-plan.json:
#   ruby scripts/audit-formulas.rb --from-plan

require 'net/http'
require 'uri'
require 'json'

BASE_URL = ENV.fetch('SIGMA_BASE_URL')
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'sigma_rest'

# Audit loops over every dedup candidate's workbook + PUTs corrections;
# Sigma.request auto-refreshes on 401 mid-run.
def http_req(method, path, body = nil)
  res = Sigma.request(method, path, body: body, accept: '*/*')
  res.is_a?(String) ? res : res.to_json
end

def audit_one(wb_id)
  raw = http_req(:get, "/v2/workbooks/#{wb_id}/spec")
  spec = JSON.parse(raw)

  fixed_count = 0
  spec['pages'].each do |page|
    (page['elements'] || []).each do |el|
      next unless el['columns'].is_a?(Array)
      # Map: column id (often the SQL alias) → display name
      alias_to_display = el['columns'].to_h { |c| [c['id'], c['name']] }

      el['columns'].each do |col|
        next unless col['formula']
        new_formula = col['formula'].gsub(/\[([^\/\]]+)\/([A-Z0-9_]+)\]/) do
          prefix, snake = $1, $2
          display = alias_to_display[snake]
          # Only rewrite when display differs (i.e. there's a real Title-Cased name available)
          if display && display != snake
            fixed_count += 1
            "[#{prefix}/#{display}]"
          else
            $~[0]
          end
        end
        col['formula'] = new_formula
      end
    end
  end

  return [wb_id, 0] if fixed_count.zero?

  # Strip response-only top-level fields before PUT
  %w[workbookId url ownerId createdBy updatedBy createdAt updatedAt latestDocumentVersion documentVersion].each { |k| spec.delete(k) }

  resp = http_req(:put, "/v2/workbooks/#{wb_id}/spec", JSON.pretty_generate(spec))
  ok = JSON.parse(resp)['workbookId'] rescue nil
  abort "PUT failed for #{wb_id}: #{resp}" unless ok
  [wb_id, fixed_count]
end

ids =
  if ARGV.first == '--from-plan'
    plan = JSON.parse(File.read('/tmp/swap-plan.json'))
    plan.flat_map { |e| (e['workbooks'] || []).map { |w| w['workbook_id'] } }.uniq
  else
    ARGV
  end

abort 'no workbooks specified' if ids.empty?

ids.each do |id|
  wb, fixed = audit_one(id)
  puts "  #{wb}: #{fixed} formula(s) repaired"
end
