# shared/lib/code_rep.rb
# Shape adapter for the Sigma WORKBOOK code representation
# (POST /v2/workbooks, GET /v2/workbooks/{id}?includeContents=true,
# PUT /v2/workbooks/{id}/contents; dry-run = POST /v2/workbooks with dryRun: true).
#
# ENDPOINTS (OpenAPI 2.0.0+20261030, live-verified 2026-11-03): the /spec
# workbook and report endpoints are DEPRECATED. Their replacements carry the
# same document under `contents` instead of `document` (byte-identical on a
# live readback). Build paths and bodies with the endpoint helpers below rather
# than hand-writing them. On-disk artifacts keep the `document` wrapper that
# wrap() emits; create_body/update_body re-key it at the API boundary.
#
# Verified live 2026-08-03/04: this surface nests non-metadata fields under a top-level
# wrapper key and REJECTS the old flat body with HTTP 400 — including on dry-run.
# Sigma engineering confirmed 2026-08-03 that the DATA-MODEL code-rep surface is NOT
# changing, so this adapter is deliberately workbook-only and always writes the nested
# shape. Do NOT use it on /v2/dataModels/.../spec payloads — that API ignores `document`
# and will 400 on a missing top-level `schemaVersion`.
#
# Reads stay tolerant of the legacy flat shape because flat artifacts still exist on
# disk (committed workbook snapshots, fixtures) even though the API no longer returns them.
module Sigma
  module CodeRep
    # Every field accepted inside `document` by the live workbook OpenAPI.
    # `elements` is a required flat array; pages/overlays/panels are metadata
    # collections whose membership is established by `layout`, not by nested
    # element arrays. Keep this list complete: an omitted key is misclassified
    # as outer metadata and is then silently dropped from PUT bodies.
    DOC_KEYS = %w[
      schemaVersion kind elements pages overlays panels layout settings agents
    ].freeze

    # Envelope keys of the workbook/report responses that are never writable.
    # The /spec-era names (latestDocumentVersion, folderId) stay listed so old
    # snapshots strip the same way as live readbacks.
    RESPONSE_ONLY_KEYS = %w[
      workbookId workbookUrlId reportId reportUrlId url path documentVersion
      latestVersion latestDocumentVersion ownerId createdBy updatedBy createdAt
      updatedAt isArchived tags taggedSourceUrlId warnings dryRun valid errors
    ].freeze
    CREATE_METADATA_KEYS = %w[name folderId description ownerId].freeze

    WORKBOOKS_PATH = '/v2/workbooks'
    REPORTS_PATH = '/v2/reports'

    # REMOVED from the API. The workbook theme is now `settings.theme.name` and
    # `settings.theme.overrides` (published OpenAPI: createWorkbookSpec — there
    # are zero occurrences of themeName/themeOverrides in it). The individual
    # override keys are unchanged (categoricalScheme, colorOverrides, hasCards,
    # borderRadius, elementBorder, titleFont, tableStyles, …) — only the
    # container path moved. document() folds the legacy pair forward so specs
    # and fixtures written before the move still produce a valid body.
    LEGACY_THEME_KEYS = %w[themeName themeOverrides].freeze
    CANONICAL_LAYOUT_NODE_TAGS = %w[Element Container TabbedContainer].freeze
    LEGACY_LAYOUT_NODE_TAGS = %w[LayoutElement GridContainer].freeze
    LAYOUT_NODE_TAG_PATTERN = (
      CANONICAL_LAYOUT_NODE_TAGS + LEGACY_LAYOUT_NODE_TAGS
    ).join('|').freeze

    class << self
      # Read path: accepts the live `contents` shape, the /spec-era `document`
      # shape, OR a legacy flat artifact.
      def document(response)
        return {} unless response.is_a?(Hash)
        inner = response['contents'].is_a?(Hash) ? response['contents'] : response['document']
        doc = inner.is_a?(Hash) ? inner : response.select { |k, _| DOC_KEYS.include?(k) }
        fold_legacy_theme(doc, response)
      end

      def metadata(response)
        return {} unless response.is_a?(Hash)
        response.reject do |k, _|
          %w[document contents].include?(k) || DOC_KEYS.include?(k) || LEGACY_THEME_KEYS.include?(k)
        end
      end

      # ---- Endpoint helpers -------------------------------------------------
      # `type` is :workbook or :report. Paths are relative to SIGMA_BASE_URL.

      # POST target for create and for dry-run validation.
      def create_path(type = :workbook)
        collection_path(type)
      end

      # GET that returns the envelope plus `contents` and `documentVersion`.
      def read_path(id, type = :workbook, document_version: nil)
        path = "#{collection_path(type)}/#{id}?includeContents=true"
        document_version ? "#{path}&documentVersion=#{Integer(document_version)}" : path
      end

      # PUT target that replaces an existing document.
      def update_path(id, type = :workbook)
        "#{collection_path(type)}/#{id}/contents"
      end

      # Create (or dry-run) body. `spec` may be a bare document, a `document`-
      # or `contents`-wrapped artifact, or a flat legacy artifact; its name /
      # folderId / description / ownerId are used unless overridden in `extra`.
      # Workbook contents are flattened like wrap(); report contents are a
      # different representation and pass through untouched.
      def create_body(spec, extra: {}, dry_run: false, type: :workbook)
        meta = metadata(spec).select { |k, _| CREATE_METADATA_KEYS.include?(k) }
        body = meta.merge(extra.transform_keys(&:to_s)).merge('contents' => api_contents(spec, type))
        body['dryRun'] = true if dry_run
        body
      end

      # Update body. Pass the documentVersion you read to make the PUT fail
      # with code stale_document_settings instead of overwriting newer edits.
      def update_body(spec, document_version: nil, type: :workbook)
        body = { 'contents' => api_contents(spec, type) }
        body['documentVersion'] = document_version if document_version
        body
      end

      # Normalize a dry-run response to the /spec/verify-era shape callers
      # check: { 'valid' => bool, 'errors' => [{ 'summary' => ... }] }.
      # Success is HTTP 200 with no `valid` key; a schema failure is HTTP 400
      # with valid:false and errors; other 4xx carry only `message`.
      def dry_run_result(status, body)
        status = status.to_i
        body = body.is_a?(Hash) ? body : {}
        return { 'valid' => true, 'errors' => [], 'warnings' => Array(body['warnings']) } if status.between?(200, 299)

        errors = Array(body['errors'])
        errors = [{ 'summary' => body['message'] || "HTTP #{status}" }] if errors.empty?
        { 'valid' => false, 'errors' => errors, 'warnings' => Array(body['warnings']) }
      end

      # Strip non-writable envelope keys (live and /spec-era) from a readback.
      def strip_response_only(spec)
        return spec unless spec.is_a?(Hash)
        spec.reject { |k, _| RESPONSE_ONLY_KEYS.include?(k) }
      end

      # Emitter helper — set the workbook theme on a document hash in the CURRENT
      # shape. Builders should call this instead of assigning the removed
      # themeName/themeOverrides pair. Returns the same hash for chaining.
      def set_theme(doc, name: nil, overrides: nil)
        return doc unless name || (overrides.is_a?(Hash) && !overrides.empty?)
        settings = (doc['settings'] ||= {})
        theme    = (settings['theme'] ||= {})
        theme['name'] = name if name
        if overrides.is_a?(Hash) && !overrides.empty?
          theme['overrides'] = (theme['overrides'] || {}).merge(overrides)
        end
        doc
      end

      # Read the theme back out of either shape (nested settings.theme, or a
      # legacy flat themeName/themeOverrides artifact). Returns {name:, overrides:}.
      def theme(spec)
        d = document(spec)
        t = d.dig('settings', 'theme') || {}
        { 'name' => t['name'], 'overrides' => t['overrides'] || {} }
      end

      # Write path: every live workbook code-rep endpoint requires the wrapper
      # and flat document.elements. Flatten legacy page-nested artifacts at this
      # boundary so older artifacts remain postable during migration.
      def wrap(document_hash, extra: {})
        extra.merge('document' => flatten_elements(document_hash))
      end

      def workbook_elements(spec)
        elements = document(spec)['elements']
        elements.is_a?(Array) ? elements.select { |element| element.is_a?(Hash) } : []
      end

      # { page_id => [element_id, ...] }, in layout order.
      # Current GET specs use <Element> leaves, <Container> nested grids, and
      # <TabbedContainer> tab groups. Keep the two pre-release aliases readable
      # for old snapshots, but do not treat arbitrary XML tags carrying an
      # elementId as workbook ownership.
      def workbook_page_element_ids(spec)
        document(spec)['layout'].to_s
                       .scan(%r{<Page\b[^>]*\bid="([^"]*)"[^>]*>(.*?)</Page>}m)
                       .each_with_object({}) do |(page_id, body), out|
          nodes = body.scan(
            %r{<(?:#{LAYOUT_NODE_TAG_PATTERN})\b[^>]*\belementId="([^"]*)"}m
          )
          out[page_id] = nodes.flatten.uniq
        end
      end

      def workbook_page_by_element(spec)
        doc = document(spec)
        pages = doc['pages'].is_a?(Array) ? doc['pages'].select { |page| page.is_a?(Hash) } : []
        pages_by_id = pages.each_with_object({}) { |page, out| out[page['id']] = page if page['id'] }
        workbook_page_element_ids(doc).each_with_object({}) do |(page_id, element_ids), out|
          page = pages_by_id[page_id] || { 'id' => page_id, 'name' => page_id }
          element_ids.each { |element_id| out[element_id] ||= page }
        end
      end

      def workbook_elements_with_pages(spec)
        page_by_element = workbook_page_by_element(spec)
        workbook_elements(spec).map do |element|
          [element, page_by_element[element['id'] || element['elementId']]]
        end
      end

      private

      def api_contents(spec, type)
        collection_path(type) # validates type
        type.to_sym == :workbook ? flatten_elements(document(spec)) : document(spec)
      end

      def collection_path(type)
        case type.to_sym
        when :workbook then WORKBOOKS_PATH
        when :report then REPORTS_PATH
        else raise ArgumentError, "unknown code-rep type #{type.inspect} (want :workbook or :report)"
        end
      end

      def flatten_elements(doc)
        return doc unless doc.is_a?(Hash)
        pages = doc['pages']
        return doc unless pages.is_a?(Array)

        nested_elements = []
        flattened_pages = pages.map do |page|
          copy = page.dup
          nested_elements.concat(Array(copy.delete('elements')))
          copy
        end
        seen = {}
        elements = (Array(doc['elements']) + nested_elements).filter do |element|
          id = element.is_a?(Hash) && element['id']
          next true unless id
          next false if seen[id]

          seen[id] = true
        end
        doc.merge('pages' => flattened_pages, 'elements' => elements)
      end

      # themeName/themeOverrides -> settings.theme.{name,overrides}. Non-mutating:
      # only builds a new hash when a legacy key is actually present, so the
      # common (already-correct) path returns the input untouched.
      def fold_legacy_theme(doc, source)
        name      = doc['themeName']      || source['themeName']
        overrides = doc['themeOverrides'] || source['themeOverrides']
        has_ov    = overrides.is_a?(Hash) && !overrides.empty?
        return doc unless name || has_ov || doc.key?('themeName') || doc.key?('themeOverrides')

        out      = doc.reject { |k, _| LEGACY_THEME_KEYS.include?(k) }
        settings = (out['settings'] || {}).dup
        theme    = (settings['theme'] || {}).dup
        theme['name'] ||= name if name
        theme['overrides'] = (theme['overrides'] || {}).merge(overrides) if has_ov
        return out if theme.empty?

        settings['theme'] = theme
        out['settings'] = settings
        out
      end
    end
  end
end
