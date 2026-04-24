#!/usr/bin/env ruby
# Store Sigma credentials in ~/.claude/settings.json so Claude Code loads them automatically.

require 'io/console'
require 'json'

SETTINGS_PATH = File.expand_path("~/.claude/settings.json")

puts "Sigma credential setup"
puts "Values are stored in #{SETTINGS_PATH} and loaded automatically into every Claude Code session."
puts

print "Base URL [https://aws-api.sigmacomputing.com]: "
base = $stdin.gets.chomp
base = "https://aws-api.sigmacomputing.com" if base.empty?

print "Client ID: "
cid = $stdin.noecho(&:gets).chomp
puts

print "Client Secret: "
sec = $stdin.noecho(&:gets).chomp
puts

settings = File.exist?(SETTINGS_PATH) ? JSON.parse(File.read(SETTINGS_PATH)) : {}
settings["env"] ||= {}
settings["env"]["SIGMA_BASE_URL"]      = base
settings["env"]["SIGMA_CLIENT_ID"]     = cid
settings["env"]["SIGMA_CLIENT_SECRET"] = sec

File.write(SETTINGS_PATH, JSON.pretty_generate(settings))

puts
puts "Credentials saved. Open a new Claude Code session (or run `! source ~/.claude/settings.json`) to pick them up."
