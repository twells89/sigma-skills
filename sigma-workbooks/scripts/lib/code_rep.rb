# frozen_string_literal: true

# Sigma::CodeRep — adapter for the workbook-spec "document" wire wrapper.
#
# Root-cause history: live A/B testing (2026-08-04/05) found that
# POST /v2/workbooks/spec, POST /v2/workbooks/spec/verify, PUT
# /v2/workbooks/{id}/spec, and GET /v2/workbooks/{id}/spec all moved to a
# nested wire shape — non-metadata fields (`schemaVersion`, `kind`, `pages`,
# `layout`) live under a top-level `document` key instead of flat alongside
# `name`/`folderId`. POST/verify send `{ name, folderId, document: {...} }`;
# PUT sends just `{ document: {...} }` (no name/folderId — see
# reference/workflows/validate.md §1 and SKILL.md's "Sources of truth" for
# the citations). An earlier fix (`wrap_for_verify` in wb-rep.rb) covered
# ONLY the verify call; this module is the general fix, shared by every
# read/write call site in this skill and in custom-sql-to-data-model.
#
# On-disk decision: everything OTHER than the wire body — rep files
# (workbook.yaml, pages/*), snapshot.yaml, scan/audit manifests — STAYS
# FLAT. Users already have specs and reps on disk in the flat shape;
# silently migrating the on-disk format would break every existing one for
# no benefit. Call `document` right after every GET (before anything else
# touches the response) and `wrap` right before every POST/PUT (as the very
# last step before it goes over the wire); nothing in between needs to know
# the wire is nested.
module Sigma
  module CodeRep
    DOCUMENT_KEYS = %w[schemaVersion kind pages layout].freeze

    # True if `spec` is already in the nested wire shape.
    def self.wrapped?(spec)
      spec.is_a?(Hash) && spec['document'].is_a?(Hash)
    end

    # Flatten a GET response (or any spec Hash) to the legacy flat shape
    # this codebase reads/writes everywhere (`spec['pages']`,
    # `spec['layout']`, ...). Idempotent — an already-flat spec (e.g. one
    # loaded from an on-disk rep file, or a legacy fixture) passes through
    # unchanged, so it's always safe to call.
    def self.document(spec)
      return {} unless spec.is_a?(Hash)
      return spec unless wrapped?(spec)

      spec.reject { |k, _| k == 'document' }.merge(spec['document'])
    end

    # The non-document (metadata) fields of a flat spec — `name`,
    # `folderId`, `description`, and any response-only fields the caller
    # hasn't stripped yet. Accepts either shape (unwraps first).
    def self.metadata(spec)
      document(spec).reject { |k, _| DOCUMENT_KEYS.include?(k) }
    end

    # Build the wire body for a live write from a flat spec Hash:
    # `{ document: { schemaVersion, kind, pages, layout } }.merge(extra)`.
    # `kind` defaults to "workbook" when absent.
    #
    #   PUT  (update-workbook-spec) sends just `{ document: {...} }`     -> extra: {}
    #   POST (create/verify)        sends `{ name, folderId, document }` -> extra: metadata(spec).slice('name', 'folderId', ...)
    #
    # Idempotent on an already-wrapped spec (`extra` is still merged in).
    def self.wrap(spec, extra: {})
      flat = document(spec)
      doc = flat.select { |k, _| DOCUMENT_KEYS.include?(k) }
      doc['kind'] ||= 'workbook'
      extra.merge('document' => doc)
    end
  end
end
