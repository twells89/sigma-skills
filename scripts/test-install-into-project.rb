#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'

INSTALLER = File.join(__dir__, 'install-into-project.sh')
failures = []

def check(failures, description)
  if yield
    puts "PASS — #{description}"
  else
    failures << description
    warn "FAIL — #{description}"
  end
end

def install(home, *args)
  Open3.capture3({ 'HOME' => home }, 'bash', INSTALLER, *args)
end

Dir.mktmpdir('sigma-skills-installer') do |tmp|
  home = File.join(tmp, 'home')
  project = File.join(tmp, 'project')
  FileUtils.mkdir_p([home, project])

  out, err, status = install(home, 'sigma-workbooks', 'cursor', project)
  check(failures, 'project Cursor install succeeds') { status.success? }
  warn "#{out}\n#{err}" unless status.success?
  check(failures, 'project Cursor rule is installed') do
    File.file?(File.join(project, '.cursor', 'rules', 'sigma-workbooks.mdc'))
  end
  check(failures, 'project runtime includes workbook scripts and references') do
    File.file?(File.join(project, '.sigma-skills', 'sigma-workbooks', 'scripts', 'validate-spec.sh')) &&
      File.directory?(File.join(project, '.sigma-skills', 'sigma-workbooks', 'reference'))
  end
  check(failures, 'API runtime is installed beside dependent skill') do
    File.file?(File.join(project, '.sigma-skills', 'sigma-api', 'scripts', 'get-token.sh'))
  end
  check(failures, 'runtime prerequisite checker is included') do
    File.file?(File.join(project, '.sigma-skills', 'check-prerequisites.sh'))
  end
  check(failures, 'generated rule explains the runtime location') do
    File.read(File.join(project, '.cursor', 'rules', 'sigma-workbooks.mdc'))
        .include?('.sigma-skills/sigma-workbooks')
  end

  _out, _err, status = install(home, 'sigma-workbooks', 'cursor', '--global')
  check(failures, 'global Cursor install succeeds') { status.success? }
  check(failures, 'global Cursor path is not double nested') do
    File.file?(File.join(home, '.cursor', 'rules', 'sigma-workbooks.mdc')) &&
      !File.exist?(File.join(home, '.cursor', '.cursor'))
  end

  _out, _err, status = install(home, 'sigma-workbooks', 'continue', '--global')
  check(failures, 'global Continue install succeeds') { status.success? }
  check(failures, 'global Continue path is not double nested') do
    File.file?(File.join(home, '.continue', 'rules', 'sigma-workbooks.md')) &&
      !File.exist?(File.join(home, '.continue', '.continue'))
  end

  codex_project = File.join(tmp, 'codex-project')
  FileUtils.mkdir_p(codex_project)
  agents = File.join(codex_project, 'AGENTS.md')
  File.write(agents, "Keep this user-authored content.\n")
  2.times do
    _out, _err, status = install(home, 'sigma-workbooks', 'codex', codex_project)
    check(failures, 'Codex install/refresh succeeds') { status.success? }
  end
  contents = File.read(agents)
  check(failures, 'Codex refresh preserves unrelated content') do
    contents.include?('Keep this user-authored content.')
  end
  check(failures, 'Codex refresh keeps one managed skill section') do
    contents.scan('<!-- BEGIN sigma-skills:sigma-workbooks -->').length == 1 &&
      contents.scan('<!-- END sigma-skills:sigma-workbooks -->').length == 1
  end

  api_project = File.join(tmp, 'api-project')
  FileUtils.mkdir_p(api_project)
  _out, _err, status = install(home, 'sigma-api', 'cursor', api_project)
  check(failures, 'sigma-api is accepted by the documented installer') do
    status.success? &&
      File.file?(File.join(api_project, '.sigma-skills', 'sigma-api', 'scripts', 'get-token.sh'))
  end
end

if failures.empty?
  puts "\nAll installer checks passed."
else
  warn "\n#{failures.length} failure(s):"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end
