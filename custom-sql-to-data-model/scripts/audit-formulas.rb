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
# Or, drive from <Dir.tmpdir>/swap-plan.json (e.g. /tmp/swap-plan.json on macOS/Linux):
#   ruby scripts/audit-formulas.rb --from-plan

require 'net/http'
require 'uri'
require 'json'
require 'tmpdir'

BASE_URL = ENV.fetch('SIGMA_BASE_URL')
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'sigma_rest'
require 'code_rep'
require 'formula_audit'

# Audit loops over every dedup candidate's workbook + PUTs corrections;
# Sigma.request auto-refreshes on 401 mid-run.
def http_req(method, path, body = nil)
  res = Sigma.request(method, path, body: body, accept: '*/*')
  res.is_a?(String) ? res : res.to_json
end

def audit_one(wb_id)
  raw = http_req(:get, "/v2/workbooks/#{wb_id}/spec")
  j = JSON.parse(raw)
  doc = Sigma::CodeRep.document(j)
  abort "GET returned no flat document.elements array for #{wb_id}" unless doc['elements'].is_a?(Array)

  fixed_count = Sigma::FormulaAudit.repair!(doc)

  return [wb_id, 0] if fixed_count.zero?

  # PUT accepts exactly one top-level field: the complete replacement document.
  resp = http_req(:put, "/v2/workbooks/#{wb_id}/spec",
                  JSON.pretty_generate(Sigma::CodeRep.wrap(doc)))
  parsed = JSON.parse(resp)
  ok = parsed['success'] || Sigma::CodeRep.metadata(parsed)['workbookId']
  abort "PUT failed for #{wb_id}: #{resp}" unless ok
  [wb_id, fixed_count]
end

ids =
  if ARGV.first == '--from-plan'
    plan = JSON.parse(File.read(File.join(Dir.tmpdir, 'swap-plan.json')))
    plan.flat_map { |e| (e['workbooks'] || []).map { |w| w['workbook_id'] } }.uniq
  else
    ARGV
  end

abort 'no workbooks specified' if ids.empty?

ids.each do |id|
  wb, fixed = audit_one(id)
  puts "  #{wb}: #{fixed} formula(s) repaired"
end
