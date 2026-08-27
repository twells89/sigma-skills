#!/usr/bin/env ruby
# frozen_string_literal: true

# Creds-free check that this repo is a valid Claude Code marketplace plugin
# without moving the skill directories Cursor / Codex / symlink installs use.

require 'json'
require 'pathname'

ROOT = File.expand_path('..', __dir__)
SKILLS = %w[
  sigma-api
  sigma-data-models
  sigma-workbooks
  sigma-reports
  sigma-plugin-authoring
  custom-sql-to-data-model
].freeze

failures = []

def check(name, failures)
  yield
  puts "PASS: #{name}"
rescue StandardError => e
  puts "FAIL: #{name} — #{e.message}"
  failures << name
end

check('marketplace.json parses and names this catalog', failures) do
  path = File.join(ROOT, '.claude-plugin', 'marketplace.json')
  raise 'missing .claude-plugin/marketplace.json' unless File.file?(path)

  catalog = JSON.parse(File.read(path))
  raise "expected marketplace name sigma-skills, got #{catalog['name'].inspect}" unless
    catalog['name'] == 'sigma-skills'
  raise 'marketplace owner.name is required' if catalog.dig('owner', 'name').to_s.strip.empty?
  raise 'marketplace must list at least one plugin' if Array(catalog['plugins']).empty?

  plugin = catalog['plugins'].find { |entry| entry['name'] == 'sigma-skills' }
  raise 'marketplace is missing the sigma-skills plugin entry' unless plugin
  raise "plugin source must be ./ so the skill tree is copied (got #{plugin['source'].inspect})" unless
    plugin['source'] == './'
end

check('plugin.json lives next to the marketplace catalog', failures) do
  path = File.join(ROOT, '.claude-plugin', 'plugin.json')
  raise 'missing .claude-plugin/plugin.json' unless File.file?(path)

  manifest = JSON.parse(File.read(path))
  raise "expected plugin name sigma-skills, got #{manifest['name'].inspect}" unless
    manifest['name'] == 'sigma-skills'
  raise "expected skills ./skills/, got #{manifest['skills'].inspect}" unless
    manifest['skills'] == './skills/'
end

check('skills/ maps every authoring skill onto its repo-root directory', failures) do
  SKILLS.each do |name|
    canonical = File.join(ROOT, name, 'SKILL.md')
    raise "canonical skill missing: #{name}/SKILL.md" unless File.file?(canonical)

    link = File.join(ROOT, 'skills', name)
    raise "skills/#{name} is not a symlink — plugin install would duplicate or miss #{name}" unless
      File.symlink?(link)

    target = File.expand_path(File.readlink(link), File.join(ROOT, 'skills'))
    expected = File.join(ROOT, name)
    raise "skills/#{name} points at #{target}, expected #{expected}" unless target == expected
    raise "skills/#{name} does not resolve to SKILL.md" unless File.file?(File.join(link, 'SKILL.md'))
  end

  extra = Dir.children(File.join(ROOT, 'skills')) - SKILLS
  raise "unexpected entries under skills/: #{extra.join(', ')}" unless extra.empty?
end

abort "#{failures.length} failure(s)" unless failures.empty?
puts 'All plugin-manifest tests passed.'
