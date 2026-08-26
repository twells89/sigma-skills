#!/usr/bin/env ruby
# frozen_string_literal: true
#
# test-gauge-plugin-static.rb — static-lint gate for the clean-room gauge
# plugin (sigma-plugin-authoring/plugins/gauge/index.html). Does NOT execute
# the plugin (no browser/JS runtime here) — it asserts the file satisfies the
# verified Sigma plugin-lifecycle contract by source inspection: loads the
# @sigmacomputing/plugin SDK, configures an editor panel, declares
# value+target bindings (the plugin_embed contract), attaches a
# ResizeObserver (redraw-on-resize — the #1 "wonky plugin" cause), and ships
# a synthetic fallback so it previews standalone.
#
# Usage:  ruby sigma-plugin-authoring/scripts/test-gauge-plugin-static.rb
require 'json'
HTML = begin
  File.read(File.expand_path('../plugins/gauge/index.html', __dir__))
rescue Errno::ENOENT
  ''
end
$f = 0
def chk(c, m)
  puts(c ? "[ok] #{m}" : "[FAIL] #{m}")
  $f += 1 unless c
end
chk(HTML.include?('@sigmacomputing/plugin'), 'loads the @sigmacomputing/plugin SDK')
chk(HTML.match?(%r{@sigmacomputing/plugin@\d+\.\d+\.\d+}), 'SDK version is PINNED (unpinned @latest crossed the 1.1.1 -> 1.2.0 React break)')
chk(HTML.include?('configureEditorPanel'),   'configures an editor panel')
chk(HTML =~ /['"]value['"]/ && HTML =~ /['"]target['"]/, 'declares value + target bindings')
chk(HTML.include?('ResizeObserver'),         'attaches a ResizeObserver (redraw-on-resize)')
chk(HTML.downcase.include?('synth') || HTML.include?('fallback'), 'has a synthetic fallback')
# Data-binding contract (verified against @sigmacomputing/plugin v1.2.0 UMD +
# dist/esm/index.d.ts). These guard the bug class that let a plugin silently
# render synthetic data forever: the wrong SDK global, and the wrong data-
# subscription path/arity.
chk(HTML.include?('SigmaPlugin'),
    'references the real SDK global window.SigmaPlugin (not the nonexistent window.Sigma)')
chk(HTML =~ /elements\s*\.\s*subscribeToElementData/,
    'reads bound data via client.elements.subscribeToElementData(sourceId, cb)')
# React peer-dep: @sigmacomputing/plugin's UMD build THROWS at load if React is
# absent, leaving window.SigmaPlugin with no `client` -> the plugin can never
# read data and silently synths. React MUST be loaded BEFORE the SDK script.
# Anchor on the actual <script src=…> tags (the SDK name also appears in prose
# comments, so a plain string index would match the wrong position).
react_idx = HTML =~ %r{<script[^>]*\bsrc=["'][^"']*react[@./][^"']*\.js}
sdk_idx   = HTML =~ %r{<script[^>]*\bsrc=["'][^"']*@sigmacomputing/plugin}
chk(react_idx && sdk_idx && react_idx < sdk_idx,
    'loads React BEFORE the @sigmacomputing/plugin SDK (UMD peer dependency)')
exit($f.zero? ? 0 : 1)
