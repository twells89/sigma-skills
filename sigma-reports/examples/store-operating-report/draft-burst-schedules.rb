#!/usr/bin/env ruby
# frozen_string_literal: true

# Drafts one POST /v2/reports/{reportId}/schedules body per store. It writes a
# local JSON array and never calls the API: review the drafts, then create them
# deliberately. Test mode (the default) routes every copy to --test-email and
# notes the intended recipient in the message body.
#
#   ruby draft-burst-schedules.rb --recipients recipients.csv \
#     --test-email you@example.com --output /tmp/burst-schedules.json
#
# recipients.csv columns: store_id,store_name,recipient_email,recipient_type
# (produce it with recipients.sql).

require 'csv'
require 'json'
require 'optparse'

options = {
  cron: '0 7 2 * *', # 07:00 on the 2nd, after the prior month closes
  timezone: 'America/New_York',
  control_id: 'store',
  live: false,
  output: File.join(Dir.pwd, 'burst-schedules.json')
}
OptionParser.new do |opts|
  opts.banner = 'Usage: ruby draft-burst-schedules.rb --recipients CSV (--test-email ADDR | --live) [options]'
  opts.on('--recipients PATH', 'CSV of store_id,store_name,recipient_email,recipient_type') { |v| options[:recipients] = v }
  opts.on('--test-email ADDR', 'Send every copy here instead of the real recipient') { |v| options[:test_email] = v }
  opts.on('--live', 'Target the real recipients (only after sign-off)') { options[:live] = true }
  opts.on('--cron SPEC', "Cron expression (default #{options[:cron]})") { |v| options[:cron] = v }
  opts.on('--timezone TZ', "IANA timezone (default #{options[:timezone]})") { |v| options[:timezone] = v }
  opts.on('--control-id ID', "Report control that selects the store (default #{options[:control_id]})") { |v| options[:control_id] = v }
  opts.on('-o', '--output PATH', 'Output JSON path') { |v| options[:output] = v }
end.parse!

abort 'draft-burst-schedules.rb: --recipients is required' unless options[:recipients]
abort 'draft-burst-schedules.rb: pass --test-email, or --live after sign-off' unless options[:live] || options[:test_email]
abort 'draft-burst-schedules.rb: --test-email and --live are mutually exclusive' if options[:live] && options[:test_email]

rows = CSV.read(options[:recipients], headers: true)
missing = %w[store_id store_name recipient_email] - rows.headers
abort "draft-burst-schedules.rb: recipients CSV is missing #{missing.join(', ')}" unless missing.empty?
duplicates = rows.map { |row| row['store_id'] }.tally.select { |_, count| count > 1 }.keys
abort "draft-burst-schedules.rb: duplicate store_id rows: #{duplicates.join(', ')}" unless duplicates.empty?

bodies = rows.map do |row|
  intended = row['recipient_email']
  note = options[:live] ? '' : " [TEST — intended for #{intended}]"
  {
    'target' => [{ 'email' => options[:live] ? intended : options[:test_email] }],
    'schedule' => { 'cronSpec' => options[:cron], 'timezone' => options[:timezone] },
    'configV2' => {
      'title' => "#{row['store_name']} (#{row['store_id']}) — Monthly Store Operating Report",
      'messageBody' => "Attached is last month's operating report for #{row['store_name']}.#{note}",
      'exportAttachments' => [{ 'formatOptions' => { 'type' => 'PDF', 'layout' => 'portrait' } }],
      'exportName' => "Store report — #{row['store_id']}",
      'includeLink' => false,
      'conditionOptions' => { 'type' => 'always' },
      'controlValues' => { options[:control_id] => { 'type' => 'text', 'value' => row['store_id'] } }
    }
  }
end

File.write(options[:output], JSON.pretty_generate(bodies))
mode = options[:live] ? 'LIVE recipients' : "TEST → #{options[:test_email]}"
puts "drafted #{bodies.size} schedule bodies (#{mode}) → #{options[:output]}"
