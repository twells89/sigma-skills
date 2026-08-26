#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'tmpdir'
require_relative 'app_intake'

failures = []

def check(name, failures)
  yield
  puts "PASS: #{name}"
rescue StandardError => e
  failures << "#{name}: #{e.message}"
  warn "FAIL: #{name}: #{e.message}"
end

AppIntake::APP_TYPES.each do |app_type|
  check("#{app_type} template passes validation", failures) do
    errors = AppIntake.errors(AppIntake.template_for(app_type))
    raise errors.join('; ') unless errors.empty?
  end

  check("#{app_type} template includes required grain keys", failures) do
    keys = AppIntake.template_for(app_type).fetch('grain').fetch('keys')
    required = AppIntake::GRAIN_KEYS.fetch(app_type)
    missing = required - keys
    raise "missing keys #{missing.inspect}" unless missing.empty?
  end

  check("#{app_type} template does not pass strict completion", failures) do
    errors = AppIntake.errors(AppIntake.template_for(app_type), strict: true)
    raise 'strict check unexpectedly passed' if errors.empty?
    raise 'missing write connection error' unless errors.any? { |error| error.include?('writeConnectionId') }
    raise 'missing expectedRows error' unless errors.any? { |error| error.include?('expectedRows') }
  end
end

check('unknown appType is rejected', failures) do
  manifest = AppIntake.template_for('planning')
  manifest['appType'] = 'crm'
  errors = AppIntake.errors(manifest)
  raise 'unknown appType was accepted' unless errors.any? { |error| error.include?('appType must be one of') }
end

check('mismatched recipe is rejected', failures) do
  manifest = AppIntake.template_for('planning')
  manifest['recipe'] = 'reference/workflows/approval-apps.md'
  errors = AppIntake.errors(manifest)
  raise 'mismatched recipe was accepted' unless errors.any? { |error| error.include?('recipe must be') }
end

check('missing grain keys are rejected', failures) do
  manifest = AppIntake.template_for('planning')
  manifest['grain']['keys'] = %w[period]
  errors = AppIntake.errors(manifest)
  raise 'incomplete grain was accepted' unless errors.any? { |error| error.include?('grain.keys must include') }
end

check('completed manifest passes strict validation', failures) do
  manifest = AppIntake.template_for('planning')
  manifest['sources'] = {
    'connectionId' => 'source-conn',
    'tablePath' => %w[DB SCHEMA Source],
    'writeConnectionId' => 'write-conn'
  }
  manifest['grain']['expectedRows'] = 12
  errors = AppIntake.errors(manifest, strict: true)
  raise errors.join('; ') unless errors.empty?
end

check('init refuses to overwrite an existing manifest', failures) do
  Dir.mktmpdir do |dir|
    path = File.join(dir, 'app-intake.json')
    AppIntake.write_template(path, 'approval')
    begin
      AppIntake.write_template(path, 'approval')
    rescue ArgumentError
      next
    end
    raise 'existing manifest was overwritten'
  end
end

check('init writes the requested appType', failures) do
  Dir.mktmpdir do |dir|
    path = File.join(dir, 'app-intake.json')
    AppIntake.write_template(path, 'exception')
    manifest = JSON.parse(File.read(path))
    raise "expected exception, got #{manifest['appType']}" unless manifest['appType'] == 'exception'
    raise 'wrong fixture' unless manifest['fixture'] == AppIntake.fixture_for('exception')
  end
end

{
  'Edit forecasts and compare scenarios' => 'planning',
  'Redistribute marketing budget across channels' => 'allocation',
  'Approve or reject pending deals' => 'approval',
  'Triage inventory exceptions and log resolution' => 'exception'
}.each do |phrase, app_type|
  check("classify #{phrase.inspect} → #{app_type}", failures) do
    result = AppIntake.classify(phrase)
    raise "expected #{app_type}, got #{result.inspect}" unless result && result['appType'] == app_type
    raise 'fixture mismatch' unless result['fixture'] == AppIntake.fixture_for(app_type)
  end
end

{
  'Sales KPI dashboard' => 'dashboard',
  'PDF invoice' => 'report'
}.each do |phrase, redirect|
  check("classify #{phrase.inspect} redirects to #{redirect}", failures) do
    result = AppIntake.classify(phrase)
    raise "expected redirect #{redirect}, got #{result.inspect}" unless result && result['redirect'] == redirect
  end
end

abort "#{failures.length} failure(s)" unless failures.empty?
puts 'All app-intake tests passed.'
