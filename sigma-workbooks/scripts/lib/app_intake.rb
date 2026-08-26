#!/usr/bin/env ruby
# frozen_string_literal: true

# Local intake manifest for question-driven operational-app builds.
# Stdlib only; customer table paths and org identifiers stay outside the
# skill tree.

require 'json'

module AppIntake
  SKILL_ROOT = File.expand_path('../..', __dir__)

  APP_TYPES = %w[planning allocation approval exception].freeze
  REDIRECTS = %w[dashboard report].freeze

  GRAIN_KEYS = {
    'planning' => %w[scenario period planningLine],
    'allocation' => %w[period allocationDimension],
    'approval' => %w[entity],
    'exception' => %w[operationalEntity]
  }.freeze

  RECIPES = {
    'planning' => 'reference/workflows/planning-apps.md',
    'allocation' => 'reference/workflows/allocation-apps.md',
    'approval' => 'reference/workflows/approval-apps.md',
    'exception' => 'reference/workflows/exception-apps.md'
  }.freeze

  FIXTURES = {
    'planning' => 'reference/workflows/fixtures/planning-app.yaml',
    'allocation' => 'reference/workflows/fixtures/allocation-app.yaml',
    'approval' => 'reference/workflows/fixtures/approval-app.yaml',
    'exception' => 'reference/workflows/fixtures/exception-app.yaml'
  }.freeze

  REDIRECT_LOAD = {
    'dashboard' => 'reference/workflows/composition.md',
    'report' => 'sigma-reports'
  }.freeze

  REDIRECT_RULES = [
    { type: 'report', patterns: [/\binvoice\b/i, /\bstatement\b/i, /\bpdf\b/i, /\bprintable\b/i, /\bfixed[- ]layout\b/i] },
    { type: 'dashboard', patterns: [/\bdashboard\b/i, /\bkpi overview\b/i, /\bread[- ]only\b/i, /\bexec(utive)? overview\b/i] }
  ].freeze

  APP_RULES = [
    { type: 'allocation', patterns: [/\ballocat/i, /\bheadcount\b/i, /\bquota\b/i, /\bcapacit/i, /\bredistribut/i, /\bterritor/i] },
    { type: 'approval', patterns: [/\bapprov/i, /\breject\b/i, /\bcounter[- ]value\b/i, /\bdecision queue\b/i, /\bpending (deals|requests)\b/i] },
    { type: 'exception', patterns: [/\bexception\b/i, /\btriage\b/i, /\breplenish/i, /\bsla breach/i, /\banomal/i] },
    { type: 'planning', patterns: [/\bforecast/i, /\bscenario/i, /\bassumption/i, /\bbudget/i, /\bworking plan\b/i, /\bfp&a\b/i] }
  ].freeze

  ANSWER_KEYS = {
    'planning' => %w[mode filterPropagation],
    'allocation' => %w[allocationDimension],
    'approval' => %w[allowedDecisions],
    'exception' => %w[override]
  }.freeze

  module_function

  def recipe_for(app_type)
    RECIPES[app_type]
  end

  def fixture_for(app_type)
    FIXTURES[app_type]
  end

  def route_for(app_type)
    return nil unless APP_TYPES.include?(app_type)

    {
      'appType' => app_type,
      'recipe' => recipe_for(app_type),
      'fixture' => fixture_for(app_type)
    }
  end

  def classify(text)
    blob = text.to_s
    REDIRECT_RULES.each do |rule|
      next unless rule[:patterns].any? { |pattern| blob.match?(pattern) }

      return {
        'redirect' => rule[:type],
        'load' => REDIRECT_LOAD.fetch(rule[:type])
      }
    end
    APP_RULES.each do |rule|
      next unless rule[:patterns].any? { |pattern| blob.match?(pattern) }

      return route_for(rule[:type])
    end
    nil
  end

  def template_for(app_type = 'planning')
    raise ArgumentError, "unknown appType #{app_type.inspect}; allowed: #{APP_TYPES.join(', ')}" unless
      APP_TYPES.include?(app_type)

    answers = { 'rowGrain' => nil, 'governedSource' => true, 'sparseOverrides' => true, 'loadMethod' => 'interactive' }
    case app_type
    when 'planning'
      answers['mode'] = 'scenario-planning'
      answers['filterPropagation'] = 'option-a'
      answers['rowGrain'] = 'Scenario × Period × Planning Line'
    when 'allocation'
      answers['allocationDimension'] = 'Department'
      answers['rowGrain'] = 'Period × Allocation Dimension'
    when 'approval'
      answers['allowedDecisions'] = %w[Approved Rejected Counter]
      answers['counterValue'] = true
      answers['rowGrain'] = 'one row per entity key'
    when 'exception'
      answers['override'] = true
      answers['compositeKey'] = false
      answers['rowGrain'] = 'one row per operational entity'
    end

    {
      'schemaVersion' => 1,
      'appType' => app_type,
      'recipe' => recipe_for(app_type),
      'fixture' => fixture_for(app_type),
      'answers' => answers,
      'sources' => {
        'connectionId' => nil,
        'tablePath' => nil,
        'writeConnectionId' => nil
      },
      'grain' => {
        'keys' => GRAIN_KEYS.fetch(app_type).dup,
        'expectedRows' => nil
      }
    }
  end

  TEMPLATE = template_for('planning').freeze

  def errors(manifest, strict: false)
    out = []
    unless manifest.is_a?(Hash)
      return ['root must be a JSON object']
    end

    out << 'schemaVersion must be 1' unless manifest['schemaVersion'] == 1
    app_type = manifest['appType']
    unless APP_TYPES.include?(app_type)
      out << "appType must be one of: #{APP_TYPES.join(', ')}"
      return out
    end

    expected_recipe = recipe_for(app_type)
    expected_fixture = fixture_for(app_type)
    out << "recipe must be #{expected_recipe}" unless manifest['recipe'] == expected_recipe
    out << "fixture must be #{expected_fixture}" unless manifest['fixture'] == expected_fixture

    recipe_path = File.join(SKILL_ROOT, expected_recipe)
    fixture_path = File.join(SKILL_ROOT, expected_fixture)
    out << "recipe file missing: #{expected_recipe}" unless File.file?(recipe_path)
    out << "fixture file missing: #{expected_fixture}" unless File.file?(fixture_path)

    answers = manifest['answers']
    if answers.is_a?(Hash)
      ANSWER_KEYS.fetch(app_type).each do |key|
        value = answers[key]
        out << "answers.#{key} must be present for #{app_type}" if value.nil? || (value.is_a?(String) && value.strip.empty?)
      end
    else
      out << 'answers must be an object'
    end

    sources = manifest['sources']
    if sources.is_a?(Hash)
      %w[connectionId tablePath writeConnectionId].each do |key|
        next if sources.key?(key)

        out << "sources.#{key} must be present (use null until discovery)"
      end
      if strict
        %w[connectionId writeConnectionId].each do |key|
          out << "sources.#{key} must be a non-empty string" unless
            sources[key].is_a?(String) && !sources[key].strip.empty?
        end
        path = sources['tablePath']
        out << 'sources.tablePath must be a non-empty array of path segments' unless
          path.is_a?(Array) && !path.empty? && path.all? { |segment| segment.is_a?(String) && !segment.strip.empty? }
      end
    else
      out << 'sources must be an object'
    end

    grain = manifest['grain']
    if grain.is_a?(Hash)
      keys = grain['keys']
      required = GRAIN_KEYS.fetch(app_type)
      if keys.is_a?(Array) && keys.all? { |key| key.is_a?(String) }
        missing = required - keys
        out << "grain.keys must include #{required.join(', ')} for #{app_type}" unless missing.empty?
      else
        out << 'grain.keys must be an array of strings'
      end
      if strict
        out << 'grain.expectedRows must be a positive number' unless
          grain['expectedRows'].is_a?(Numeric) && grain['expectedRows'].positive?
      end
    else
      out << 'grain must be an object'
    end

    out
  end

  def write_template(path, app_type = 'planning')
    raise ArgumentError, "#{path} already exists" if File.exist?(path)

    File.write(path, JSON.pretty_generate(template_for(app_type)) + "\n")
  end
end

if $PROGRAM_NAME == __FILE__
  command = ARGV.shift
  strict = ARGV.delete('--strict')
  path = ARGV.shift
  app_type = ARGV.shift || 'planning'

  valid_init = command == 'init' && path && (ARGV.empty? || APP_TYPES.include?(app_type) && ARGV.empty?)
  valid_validate = command == 'validate' && path && ARGV.empty?
  unless valid_init || valid_validate
    warn 'Usage: ruby scripts/lib/app_intake.rb init <manifest.json> [appType]'
    warn '   or: ruby scripts/lib/app_intake.rb validate [--strict] <manifest.json>'
    exit 2
  end

  if command == 'init'
    unless AppIntake::APP_TYPES.include?(app_type)
      warn "unknown appType #{app_type.inspect}; allowed: #{AppIntake::APP_TYPES.join(', ')}"
      exit 2
    end
    begin
      AppIntake.write_template(path, app_type)
    rescue ArgumentError => e
      warn "app-intake: #{e.message}"
      exit 1
    end
    puts "Wrote #{path}"
    exit 0
  end

  begin
    manifest = JSON.parse(File.read(path))
  rescue Errno::ENOENT, JSON::ParserError => e
    warn "app-intake: #{e.message}"
    exit 1
  end

  errors = AppIntake.errors(manifest, strict: !strict.nil?)
  if errors.empty?
    puts "OK: #{path}#{strict ? ' (strict)' : ''}"
    exit 0
  end

  errors.each { |error| warn "ERROR: #{error}" }
  exit 1
end
