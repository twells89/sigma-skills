# Plugin Lifecycle — Verified Gotchas

This is the canonical reference for the `@sigmacomputing/plugin` lifecycle:
**build → register → host → embed → bind → verify.** Every gotcha below was
proven against a live Sigma org (the gauge archetype shipped with this skill)
before being written down here — read this before registering or embedding a
plugin, not after hitting the failure.

The worked example throughout is the gauge plugin shipped with this skill:
`plugins/gauge/index.html` (+ `plugins/gauge/README.md`), whose emitter output
is `examples/gauge-embed.json`.

## 1. Registration: `POST /v2/plugins`

```
POST /v2/plugins
{ "name": "<unique plugin name>", "description": "<what it does>",
  "url": "<hosted index.html URL>", "type": "element" }
```

A successful register returns a `pluginId`. **Always call
`scripts/register-plugin.rb` (`PluginRegister.register_or_get`)** rather
than hand-rolling this — it already encodes the two gotchas below and is
idempotent (safe to call repeatedly for the same `name`).

### Masked 404 can accompany a *successful* register

Sigma has been observed to return a non-2xx (masked 404-shaped) response on a
`POST /v2/plugins` call that actually registered the plugin. **Never treat a
non-2xx POST response as a hard failure by itself.** Always follow up with
`GET /v2/plugins` and search the `entries` for a plugin matching the `name` you
just sent — if it's there, the register succeeded regardless of what the POST
response said. `register_or_get` does this automatically: GET-by-name first
(idempotent short-circuit), POST if not found, then re-GET-by-name before
deciding pass/fail.

### Registration may be 403 org-admin-gated

In some orgs, plugin registration requires org-admin credentials — a
non-admin token gets a real 401/403 (not the masked-404 case above; this one
is a genuine permission denial, confirmed by the follow-up GET *also* coming
up empty). **Fall back to handoff**: hand the user the built plugin bundle,
the exact hosting steps, and the exact `curl`/`register-plugin.rb` invocation
to run once they have an org-admin token. Never silently drop the viz or fake
a `pluginId`. `register_or_get` raises `PluginRegister::PermissionError` with
this message shape so callers can catch it and switch to handoff.

### `url` is set-once per registration

Once registered, a plugin's `url` cannot be edited via the same registration
call — if the hosted bundle moves (e.g. from localhost to a public host, or a
new static-deploy URL), **re-register** (a new `POST /v2/plugins`, which
mints a new `pluginId`) rather than expecting an in-place update. Downstream
workbook specs that embedded the old `pluginId` will need to be repointed to
the new one.

## 2. Hosting: localhost is dev-iteration only; a PERSISTENT public host is required for anyone else to see it render

A plugin hosted on `localhost` renders correctly in any **human's browser**
that has it open — so building, previewing, and even binding real workbook
data against it all work fine on localhost. What does **not** work on
localhost: Sigma's **server-side rendering** (headless PNG export, scheduled
PDF/email sends, any path that doesn't route through a human's browser)
cannot reach it — it needs a **publicly reachable URL**. Nor does any
*other* human — a teammate, a reviewer, an end user — who doesn't have that
same localhost open. Treat localhost as dev-iteration only: fine for the
person actively building the plugin, never sufficient for a shared or
headlessly-rendered result.

An **ephemeral tunnel** (a free-tier `ngrok`/`cloudflared` process, etc.) is
not a fix either — it dies with the process, and some free tiers inject an
interstitial page that a headless render server can't click through (no
human to send the bypass header). The requirement is **persistence**, not
just "has a public DNS name."

**This is a hosting-platform decision the customer/user owns — this skill
does not prescribe a vendor.** Ask (or use context to infer) which persistent
public static host they prefer, then register the plugin at *that* host's
URL. Common options, none of them a default:

- The customer's own static-hosting setup (an existing S3+CloudFront /
  internal CDN / corporate web server they already use for internal tools).
- GitHub Pages, Netlify, Vercel, Cloudflare Pages, or any comparable static
  host, on whichever account/org the customer controls.

The registration and embed mechanics are **entirely host-neutral** —
`register-plugin.rb` (`PluginRegister.register_or_get`) and
`plugin_embed.rb` (`PluginEmbed.build`) don't care which host served the
bundle, only that its URL is persistent and reachable. Once you have *a*
persistent public URL from *any* host, the steps in §1/§3 are identical.

Practical consequence for verification: treat **data-parity** (export the
plugin's bound element and compare the numbers) as the hard, always-provable
gate — it works regardless of host. Treat the **visual screenshot** as
depending on the host being persistent and public; on localhost or a dead/
ephemeral tunnel, skip it with an honest note rather than faking a render.

**Handoff is the default; turnkey is opt-in.** Emit the plugin bundle plus
the exact host + register steps and let the user (or their CI) host it on
their platform of choice — that's always correct and requires no new
infrastructure trust from this skill. Automating a static deploy end-to-end
is a fast-follow, not built into this skill; if the user already has an
authenticated static-host CLI available, using it to get a persistent public
URL up front makes the visual gate provable too, but never assume a
particular one is present or preferred.

*Worked example (illustrative only — not the standard):* this skill's own
live acceptance test hosts the gauge plugin at
`https://<your-org>.github.io/<repo>/gauge/`, a GitHub Pages site on a
dedicated public repo (`main` branch, `/` root), used purely to prove the
render lifecycle end-to-end during this skill's development. Substitute
the customer's actual preferred host for production use — this URL is a
demonstration, not a dependency.

## 3. Embed shape: every *binding* value is a bare string

The Sigma workbook-spec plugin element looks like:

```json
{
  "id": "<element id>",
  "kind": "plugin",
  "pluginId": "<from registration>",
  "config": {
    "source": { "kind": "element", "elementId": "<bound data element id>" },
    "<editor-panel var>": "<columnId or literal, as a STRING>"
  }
}
```

`config.source` is the **one** structured field — a fixed
`{"kind":"element","elementId":...}` object naming the data element the
plugin reads from. **Every other key in `config`** — every editor-panel
binding (`value`, `target`, or whatever variables the plugin's
`configureEditorPanel` declared) and any extra config (e.g. `format`) — **must
be a bare string**, even when the underlying value is a `columnId` or a
number. Sending a binding as a nested object (e.g. the
`{"kind":"column","columnId":"..."}` shape used elsewhere in workbook specs)
is **silently rejected**: the API does not name the offending field, it masks
the failure as a generic `Invalid kind:"plugin"` error on the whole element.
If you hit that error, the first thing to check is whether a config value
that should be a string got emitted as an object or a number.

**Don't hand-write this JSON — call the emitter:**

`PluginEmbed.build(id:, plugin_id:, source_element_id:, bindings:, extra_config: {})` — `scripts/plugin_embed.rb`

It coerces every `bindings`/`extra_config` value to a string (so a
numeric `2` becomes `"2"`) and always emits the correct `config.source` shape.
`bindings` maps editor-panel var name → `columnId` (e.g.
`{"value" => "actual", "target" => "target"}`); `extra_config` is anything
else non-binding (e.g. `{"format" => ".0%"}`). See
`examples/gauge-embed.json` for a full worked output.

## 4. The plugin's backing data element needs its own hidden page

The `source.elementId` a plugin binds to is a normal table/element in the
workbook — but if you don't want it visible to end users, **put it on a
separate hidden page**. Setting `visibleAsSource:false` on the element alone
does **not** remove it from layout / visibility — pages are the actual
visibility boundary. See the `sigma-workbooks` skill's layout reference for
how to mark a page hidden.

## 5. `ResizeObserver` is mandatory — the #1 "wonky plugin" cause

A plugin that only relies on CSS or SVG `viewBox` scaling to handle resize
ends up with illegible text or a clipped/distorted drawing at small panel
widths — this is the single most common way a hand-built plugin looks broken
in a real dashboard (where panels get resized constantly). The fix: attach a
`ResizeObserver` to the render container and, on every resize event, **fully
recompute** geometry (stroke width, font size, arc/shape dimensions) from the
container's actual current box and re-render from scratch — not an
incremental CSS-only patch. The gauge plugin
(`plugins/gauge/index.html`) does exactly this: its `ResizeObserver` callback
calls the same size-driven `render()` function used for the initial paint, so
the same code path is exercised whether the panel first loads at 1100px or
gets dragged down to 550px.

## 6. Synthetic fallback — preview standalone, without a Sigma host

Every plugin should render *something* sensible when opened directly in a
browser (no Sigma `client`) or when the bound `value`/`target` columns don't
resolve to a complete row — a `synth()` path that fabricates plausible demo
data (the gauge uses `value: 82, target: 100`). This makes the plugin file
independently previewable (open it in a browser, or screenshot it at multiple
widths) before it's ever registered or embedded, which is the fastest way to
iterate on layout/rendering without round-tripping through Sigma.

## 7. The SDK's UMD build needs React loaded BEFORE it (silent-synth trap)

`@sigmacomputing/plugin`'s UMD/CDN build — what
`<script src="https://unpkg.com/@sigmacomputing/plugin">` gives you — has
**React as a hard peer dependency**. Its factory dereferences React at load; if
React isn't already on the page it **throws before assigning `client`**, leaving
`window.SigmaPlugin` an empty object with no `client`. The plugin then has no way
to read bound data and silently falls through to its `synth()` fallback (§6) —
so it *looks* like it works (shows demo numbers) while never touching real data.
Sigma does **not** inject React into the plugin iframe, so a vanilla single-file
plugin must load React itself, **first**:

```html
<script crossorigin src="https://unpkg.com/react@18.3.1/umd/react.production.min.js"></script>
<script src="https://unpkg.com/@sigmacomputing/plugin"></script>
```

`ReactDOM` is **not** required for the vanilla `client` API — only `React`. Pin
the version. For a plugin that must render in restrictive/offline contexts, host
React and the SDK on the plugin's **own origin** instead of a CDN. This is the
single most likely reason a freshly built plugin "renders fine" but shows demo
numbers instead of your data. Verified against `@sigmacomputing/plugin` v1.2.0;
see `reference/sdk-api.md` for the full `client` shape.

## 8. Sigma's server-side PNG export does NOT hydrate plugin data

The workbook **PNG export / screenshot** API renders a plugin's page,
initializes its `client`, and fires `config.subscribe` with the correct
bindings — but it does **not** deliver the plugin's asynchronous element data
before it snapshots (the `subscribeToElementData` callback never fires in that
environment, even with the source element on the exported page). So a
server-rendered screenshot of a plugin shows its **`synth()` fallback, not live
data** — a limitation of PNG export for plugins, not a plugin bug. For
verification:

- **Do not** treat a plugin's PNG-export screenshot as proof it reads real data
  — it structurally cannot show that.
- Verify **data-parity at the element level**: export the bound
  `source.elementId` and assert its values (headless, independent of the
  plugin).
- Confirm the plugin's **live rendering** of that data only in a **live browser
  session** (interactive workbook or a signed embed), where Sigma pushes element
  data to the subscription normally.
- Watch for coincidental literals: the gauge's `synth()` fallback happens to
  use `82`/`100` as demo numbers, so a screenshot showing "82 of 100" proves
  nothing either way — it's exactly the coincidence that let the original
  silent-synth bug hide behind a correct-looking render; element-level
  data-parity is the real gate.

## 9. Emitter recap

| Concern | Tool |
|---|---|
| Register (idempotent, masked-404/403-aware) | `scripts/register-plugin.rb` (`PluginRegister.register_or_get`) |
| Emit the embed JSON (bare-string config, correct `source` shape) | `scripts/plugin_embed.rb` (`PluginEmbed.build`) |
| Worked example (plugin + emitter output) | `plugins/gauge/` + `examples/gauge-embed.json` |
