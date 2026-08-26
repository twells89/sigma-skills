#!/usr/bin/env ruby
# frozen_string_literal: true

# Creds-free lint of the operational-app fixtures. Run from anywhere:
#   ruby sigma-workbooks/scripts/test-app-fixtures.rb

require 'yaml'
require_relative 'lib/app_intake'

failures = []

def check(name, failures)
  yield
  puts "PASS: #{name}"
rescue StandardError => e
  failures << "#{name}: #{e.message}"
  warn "FAIL: #{name}: #{e.message}"
end

SKILL_ROOT = AppIntake::SKILL_ROOT
UUID = /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i
PLACEHOLDERS = %w[<FOLDER_ID> <WRITE_CONNECTION_ID> <SOURCE_CONNECTION_ID>].freeze

REQUIRED_KINDS = {
  'planning' => {
    warehouse: true,
    empty_input: 2,
    linked_input: 1,
    join: true,
    insert_rows: true,
    hidden_page: true
  },
  'allocation' => {
    warehouse: true,
    empty_input: 1,
    linked_input: 1,
    join: false,
    insert_rows: true,
    hidden_page: true
  },
  'approval' => {
    warehouse: true,
    empty_input: 1,
    linked_input: 1,
    join: false,
    insert_rows: true,
    update_rows: true,
    which_rows: true,
    hidden_page: true
  },
  'exception' => {
    warehouse: true,
    empty_input: 1,
    linked_input: 1,
    join: false,
    insert_rows: true,
    hidden_page: true,
    recommendation: true
  }
}.freeze

def elements(doc)
  doc.fetch('document').fetch('elements')
end

def input_tables(doc)
  elements(doc).select { |el| el['kind'] == 'input-table' }
end

def buttons(doc)
  elements(doc).select { |el| el['kind'] == 'button' }
end

def effects(doc)
  buttons(doc).flat_map do |button|
    Array(button['actions']).flat_map { |action| Array(action['effects']) }
  end
end

def layout(doc)
  doc.fetch('document').fetch('layout').to_s
end

AppIntake::APP_TYPES.each do |app_type|
  rel = AppIntake.fixture_for(app_type)
  path = File.join(SKILL_ROOT, rel)
  raw = File.read(path)
  doc = YAML.safe_load(raw)
  req = REQUIRED_KINDS.fetch(app_type)

  check("#{app_type} fixture parses as a workbook spec", failures) do
    raise 'missing document.kind workbook' unless doc.dig('document', 'kind') == 'workbook'
    raise 'elements must be a non-empty array' unless elements(doc).is_a?(Array) && !elements(doc).empty?
    raise 'pages must be a non-empty array' unless doc.dig('document', 'pages').is_a?(Array) && !doc['document']['pages'].empty?
    raise 'layout must be present' if layout(doc).strip.empty?
  end

  check("#{app_type} fixture keeps placeholders and no live ids", failures) do
    PLACEHOLDERS.each do |token|
      raise "missing placeholder #{token}" unless raw.include?(token)
    end
    raise 'contains a UUID (live id?)' if raw.match?(UUID)
    raise 'contains a live app URL' if raw.match?(%r{https://app\.}i)
  end

  check("#{app_type} input tables use inputMode view", failures) do
    tables = input_tables(doc)
    raise 'expected at least one input-table' if tables.empty?

    tables.each do |table|
      raise "#{table['id']} missing inputMode" unless table['inputMode'] == 'view'
    end
  end

  check("#{app_type} fixture encodes required layers", failures) do
    warehouse = elements(doc).any? { |el| el.dig('source', 'kind') == 'warehouse-table' }
    raise 'missing warehouse-table source' if req[:warehouse] && !warehouse

    empty = input_tables(doc).count { |table| table.dig('source', 'kind') == 'empty' }
    raise "expected #{req[:empty_input]} empty input-table(s), got #{empty}" unless empty == req[:empty_input]

    linked = input_tables(doc).count { |table| table.dig('source', 'kind') == 'linked' }
    raise "expected #{req[:linked_input]} linked input-table(s), got #{linked}" unless linked == req[:linked_input]

    join = elements(doc).any? { |el| el.dig('source', 'kind') == 'join' }
    raise 'missing join matrix' if req[:join] && !join
    raise 'unexpected join' if req[:join] == false && join

    fx = effects(doc)
    raise 'missing insert-rows' if req[:insert_rows] && fx.none? { |effect| effect['effect'] == 'insert-rows' }
    raise 'missing update-rows' if req[:update_rows] && fx.none? { |effect| effect['effect'] == 'update-rows' }
    raise 'missing whichRows on the stable entity key' if req[:which_rows] && fx.none? { |effect| effect.key?('whichRows') }

    hidden = Array(doc.dig('document', 'pages')).any? { |page| page['visibility'] == 'hidden' }
    raise 'missing hidden source page' if req[:hidden_page] && !hidden
  end

  check("#{app_type} layout places every element", failures) do
    xml = layout(doc)
    elements(doc).each do |el|
      id = el.fetch('id')
      raise "layout missing elementId=#{id}" unless xml.include?(%(elementId="#{id}"))
    end
    Array(doc.dig('document', 'pages')).each do |page|
      id = page.fetch('id')
      raise "layout missing Page id=#{id}" unless xml.include?(%(id="#{id}"))
    end
  end
end

check('exception fixture uses a policy recommendation, not an AI label', failures) do
  path = File.join(SKILL_ROOT, AppIntake.fixture_for('exception'))
  doc = YAML.safe_load(File.read(path))
  queue = input_tables(doc).find { |table| table.dig('source', 'kind') == 'linked' }
  raise 'missing linked action queue' unless queue

  names = Array(queue['columns']).map { |col| col['name'].to_s }
  raise 'recommendation labeled AI' if names.any? { |name| name.match?(/\bAI\b/i) }
  raise 'missing Suggested Order' unless names.include?('Suggested Order')
  raise 'missing Final Order' unless names.include?('Final Order')

  final = Array(queue['columns']).find { |col| col['name'] == 'Final Order' }
  raise 'Final Order must Coalesce override over suggestion' unless
    final['formula'].to_s.include?('Coalesce') && final['formula'].to_s.include?('Override')
end

check('approval whichRows uses the entity key', failures) do
  path = File.join(SKILL_ROOT, AppIntake.fixture_for('approval'))
  doc = YAML.safe_load(File.read(path))
  update = effects(doc).find { |effect| effect['effect'] == 'update-rows' }
  raise 'missing update-rows' unless update

  formula = update.dig('whichRows', 'formula').to_s
  raise "whichRows must key on Deal ID, got #{formula.inspect}" unless formula.include?('[Deal ID]')
end

check('planning grid keys stable context only', failures) do
  path = File.join(SKILL_ROOT, AppIntake.fixture_for('planning'))
  doc = YAML.safe_load(File.read(path))
  grid = elements(doc).find { |el| el['id'] == 'plan-grid' }
  raise 'missing plan-grid' unless grid

  key_names = Array(grid['columns']).select { |col| col['key'] }.map { |col| col['name'] }
  %w[Scenario Period Planning\ Line Section Baseline].each do |name|
    raise "plan-grid missing key #{name}" unless key_names.include?(name)
  end
  bad = key_names & ['Status', 'Owner']
  raise "volatile key columns #{bad.inspect}" unless bad.empty?
end

{
  'Edit forecasts and compare scenarios' => 'planning',
  'Redistribute headcount across departments' => 'allocation',
  'Approve or reject pending deals' => 'approval',
  'Triage inventory exceptions and log resolution' => 'exception'
}.each do |phrase, app_type|
  check("classifier maps #{phrase.inspect} to #{app_type} fixture", failures) do
    result = AppIntake.classify(phrase)
    expected = AppIntake.fixture_for(app_type)
    raise "expected #{expected}, got #{result.inspect}" unless result && result['fixture'] == expected
    path = File.join(SKILL_ROOT, expected)
    raise "fixture missing on disk: #{expected}" unless File.file?(path)
  end
end

abort "#{failures.length} failure(s)" unless failures.empty?
puts 'All app-fixture tests passed.'
