#!/usr/bin/env ruby
# frozen_string_literal: true

# sync-targets.rb — generate non-Claude-Code agent target files from SKILL.md.
#
# Usage:
#   ruby sync-targets.rb <skill-dir>
#   ruby sync-targets.rb           # if cwd is the skill dir
#
# Reads <skill-dir>/SKILL.md (Claude Code format), emits:
#   <skill-dir>/generated/codex/AGENTS.md
#   <skill-dir>/generated/cursor/rules/<name>.mdc
#   <skill-dir>/generated/cline/<name>.md
#   <skill-dir>/generated/continue/<name>.md
#
# Cortex Code is intentionally NOT generated — it reads SKILL.md natively.
#
# Markers in SKILL.md you can use:
#   <!-- agents:claude-only -->
#   ...content stripped from non-Claude outputs...
#   <!-- /agents:claude-only -->
#
#   <!-- agents:non-claude -->
#   ...content shown only in non-Claude outputs...
#   <!-- /agents:non-claude -->

require 'yaml'
require 'fileutils'

SKILL_DIR = ARGV[0] || Dir.pwd
SKILL_DIR_ABS = File.expand_path(SKILL_DIR)
SKILL_MD = File.join(SKILL_DIR_ABS, 'SKILL.md')
abort "no SKILL.md at #{SKILL_MD}" unless File.exist?(SKILL_MD)

raw = File.read(SKILL_MD)

# Parse frontmatter
unless raw =~ /\A---\s*\n(.+?)\n---\s*\n(.*)\z/m
  abort "no YAML frontmatter at top of #{SKILL_MD} — needed at minimum: name + description"
end
fm_text = $1
body    = $2

fm = YAML.safe_load(fm_text)
name = fm['name'] or abort "frontmatter missing `name`"
desc = (fm['description'] || '').to_s

# Normalise description for one-line use (Cursor / front-of-AGENTS)
desc_oneline = desc.gsub(/\s+/, ' ').strip

# ---------- Body transforms shared across non-Claude targets ----------

def strip_claude_only_blocks(s)
  # Markers are wrapped in HTML comments so they're already invisible to Claude
  # in the canonical SKILL.md. Here we strip the whole block (markers + body)
  # for non-Claude outputs.
  s.gsub(/<!--\s*agents:claude-only\s*-->.*?<!--\s*\/agents:claude-only\s*-->/m, '')
end

def reveal_non_claude_blocks(s)
  # Non-Claude content is fully inside a single HTML comment so Claude sees
  # nothing. Form expected in SKILL.md:
  #   <!-- agents:non-claude
  #   body content here
  #   agents:end -->
  # The rewriter unwraps the comment so non-Claude outputs see the body.
  s.gsub(/<!--\s*agents:non-claude\s*\n(.*?)\nagents:end\s*-->/m) { $1 }
end

CLAUDE_PHRASE_SUBS = [
  # path / config refs — do NOT auto-rewrite `~/.claude/settings.json`. Use
  # marker blocks in SKILL.md instead so the surrounding prose reads cleanly.
  [/\bClaude or the local machine\b/, 'the AI agent or the local machine'],
  [/\bin Claude Code\b/i, 'in your AI coding agent'],
  # tool primitives — keep meaning, strip Claude-specific name
  [/\bvia the `?Skill`? tool\b/i, ''],
  [/\bUse the `?Skill`? tool\b/i, 'Follow the procedure below'],
  [/\bvia the `?Bash`? tool\b/i, 'in your shell'],
  [/\bUse the `?Bash`? tool\b/i, 'In your shell'],
  [/\bvia the `?(Read|Edit|Write)`? tool\b/i, ''],
  # invocation patterns specific to Claude Code
  [/\bsubagent_type:\s*\S+/, ''],
  [/\bTaskCreate\b/, 'a TODO entry'],
  [/\bTaskUpdate\b/, 'a TODO update'],
  [/\bTaskList\b/, 'a TODO list'],
]

def apply_phrase_subs(s, subs)
  out = s.dup
  subs.each { |re, repl| out.gsub!(re, repl) }
  # collapse double blanks introduced by deletions
  out.gsub!(/[ \t]+$/, '')
  out.gsub!(/\n{3,}/, "\n\n")
  out
end

def transform_for_non_claude(body)
  s = body
  s = strip_claude_only_blocks(s)
  s = reveal_non_claude_blocks(s)
  s = apply_phrase_subs(s, CLAUDE_PHRASE_SUBS)
  s.strip + "\n"
end

# ---------- Per-target emitters ----------

PROVENANCE = <<~PROV
  <!--
  Auto-generated from SKILL.md by ~/sigma-skills/scripts/sync-targets.rb.
  Do not edit by hand — edit SKILL.md and re-run the script.
  -->
PROV

# Drop my generated H1 if the body already starts with an H1.
def header(name, desc, body_xform)
  return "> #{desc}\n\n" if body_xform.lstrip.start_with?('# ')
  "# #{name}\n\n> #{desc}\n\n"
end

def emit_codex(dir, name, desc, body_xform)
  path = File.join(dir, 'generated', 'codex', 'AGENTS.md')
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, PROVENANCE + "\n" + header(name, desc, body_xform) + body_xform)
  path
end

def emit_cursor(dir, name, desc, body_xform)
  path = File.join(dir, 'generated', 'cursor', 'rules', "#{name}.mdc")
  FileUtils.mkdir_p(File.dirname(path))
  fm = "---\ndescription: #{desc.inspect}\nalwaysApply: false\n---\n\n"
  # Cursor needs frontmatter at line 1 — provenance comment goes AFTER.
  File.write(path, fm + PROVENANCE + "\n" + header(name, desc, body_xform) + body_xform)
  path
end

def emit_cline(dir, name, desc, body_xform)
  path = File.join(dir, 'generated', 'cline', "#{name}.md")
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, PROVENANCE + "\n" + header(name, desc, body_xform) + body_xform)
  path
end

def emit_continue(dir, name, desc, body_xform)
  path = File.join(dir, 'generated', 'continue', "#{name}.md")
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, PROVENANCE + "\n" + header(name, desc, body_xform) + body_xform)
  path
end

body_xform = transform_for_non_claude(body)

written = []
written << emit_codex(SKILL_DIR_ABS, name, desc_oneline, body_xform)
written << emit_cursor(SKILL_DIR_ABS, name, desc_oneline, body_xform)
written << emit_cline(SKILL_DIR_ABS, name, desc_oneline, body_xform)
written << emit_continue(SKILL_DIR_ABS, name, desc_oneline, body_xform)

puts "skill: #{name}"
puts "  description: #{desc_oneline[0..80]}"
puts "  wrote:"
written.each { |p| puts "    #{p.sub(SKILL_DIR_ABS + '/', '')}" }
