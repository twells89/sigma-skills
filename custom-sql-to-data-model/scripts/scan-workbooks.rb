#!/usr/bin/env ruby
# Scan all workbooks for elements with source.kind == "sql".
# Outputs a JSON manifest to <Dir.tmpdir>/custom-sql-manifest.json
# (e.g. /tmp/custom-sql-manifest.json on macOS/Linux)
#
# Usage:
#   eval "$(bash scripts/get-token.sh)"
#   ruby scripts/scan-workbooks.rb

require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'date'
require 'tmpdir'

BASE_URL = ENV.fetch('SIGMA_BASE_URL') { abort 'SIGMA_BASE_URL not set — run: eval "$(bash scripts/get-token.sh)"' }
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'sigma_rest'
require 'code_rep'
require 'workbook_sql'

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

# Scan each workbook document for SQL elements
findings = []
workbooks.each do |wb|
  wid  = wb['workbookId']
  name = wb['name']

  begin
    raw  = get(Sigma::CodeRep.read_path(wid))
    y = YAML.safe_load(raw, permitted_classes: [Date, Time])
    workbook_findings = Sigma::WorkbookSql.findings(
      y, workbook_id: wid, workbook_name: name
    )
    # GET /v2/workbooks/{id} returns `path`, not `folderId` (unlike the
    # deprecated /spec read); the parent folder comes from the file record.
    if workbook_findings.any? { |f| f[:folder_id].nil? }
      parent_id = JSON.parse(get("/v2/files/#{wid}"))['parentId']
      workbook_findings.each { |f| f[:folder_id] ||= parent_id }
    end
    findings.concat(workbook_findings)
    workbook_findings.each do |finding|
      puts "  [FOUND] #{name} / #{finding[:element_name]}"
      sql = finding[:sql].to_s
      puts "          SQL: #{sql[0..100]}#{'...' if sql.length > 100}"
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
  out = File.join(Dir.tmpdir, 'custom-sql-manifest.json')
  File.write(out, JSON.pretty_generate(findings))
  puts "Manifest written to #{out}"
end
