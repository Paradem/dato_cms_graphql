# Saved-draft preview

Optional integration. Editors save a record in DatoCMS without publishing, then
open a short-lived signed link that renders the saved draft through the host's
normal components. It is not a visual editor, not unsaved-form rendering and not
named-user authorization.

The runtime lives in `ParademCmsSite::Preview`; hosts supply routes, controllers,
templates, model construction and the per-project model list. Nothing here reads
or writes the website cache, search index or public records.

## Configuration

Per project, in the host initializer. Values may be lambdas so a missing
credential fails closed at request time instead of at boot.

```ruby
ParademCmsSite.configure do |config|
  config.preview.enabled    = true
  config.preview.site_id    = -> { ENV["DATO_PREVIEW_SITE_ID"] }
  config.preview.secret     = -> { ENV["DATO_PREVIEW_SECRET"] }
  config.preview.api_token  = -> { ENV["DATO_PREVIEW_API_TOKEN"] }
  config.preview.base_url   = -> { ENV["DATO_PREVIEW_BASE_URL"] }
  config.preview.models     = %w[article page publication message] # this project only
  config.preview.locales    = %w[en fr]
  config.preview.ttl        = 15.minutes
  config.preview.verifier   = -> { Rails.application.message_verifier("cms_preview") }
end
```

`config.preview.models` and `config.preview.locales` are the authorization scope:
anything outside them is rejected before any CMS request. `plugin_origin` defaults
to the official DatoCMS plugin CDN; change it only for a reviewed mirror.

Preview is disabled unless `enabled` is true **and** every setting validates
(secret 32–512 ASCII bytes without whitespace, distinct draft token, identifier
site/model/locale ids, positive TTL, HTTPS base URL or loopback outside
production). Invalid configuration returns 503 rather than falling back to
published content.

## Routes and controller

```ruby
get ":locale/preview/articles/:cms_id", to: "cms_previews#show",
  defaults: {model: "article"}, constraints: {locale: /en|fr/, cms_id: /[A-Za-z0-9_-]+/}
```

```ruby
class CmsPreviewsController < ApplicationController
  include ParademCmsSite::Preview::Controller
  layout "cms_preview"

  def show
    case preview_model
    when "article"
      @article = Article.new(**preview_record(model: "article", fields: ArticleQuery.fields), cms_id: preview_scope["cms_id"], locale: preview_scope["locale"])
      render "articles/show", locals: {preview: true}
    else
      render_preview_error(:invalid, :unauthorized)
    end
  end
end
```

`preview_record` returns the underscored payload for the granted record and
locale, fetched with `fallbackLocales: []` through the host's own `fields`
selection. Dropping the unsaved record into the existing view keeps preview and
published rendering identical. The concern sets `no-store`, `noindex`,
`no-referrer`, `frame-ancestors 'none'`, strips conditional-GET headers, verifies
the grant before any network call, and maps failures to 401 (invalid/expired
scope), 404 (missing record) and 503 (unconfigured or upstream failure). Override
`render_preview_error` for localized host pages.

## Plugin link issuer (optional)

```ruby
class CmsPreviewLinksController < ActionController::API
  include ParademCmsSite::Preview::LinkIssuer
end
```

```ruby
config.preview.link_builder = lambda do |model:, locale:, cms_id:, token:|
  path = case model
  when "page" then cms_page_preview_path(locale: locale, cms_id: cms_id, token: token)
  else cms_article_preview_path(locale: locale, cms_id: cms_id, token: token)
  end
  {label: I18n.t("cms_preview.link_label", locale: locale), path: path}
end
```

Routes: `post "cms/preview-links", to: "cms_preview_links#create"` and the same
path via `OPTIONS` for `preflight`. The issuer accepts only the configured plugin
origin, authenticates `X-Dato-Preview-Secret` in constant time, validates project,
locale, environment, model and record id, and binds the editor's current
environment into the grant. It never echoes submitted content.

## Credentials and limits

- `DATO_PREVIEW_API_TOKEN` must be a separate Content Delivery token with draft
  access and the Content Management API disabled, scoped by its role's
  environment access. Never reuse `DATO_API_TOKEN`; the doctor reports a
  duplicate.
- No server-side environment pin: the grant carries the environment, and the
  token's role decides which environments are readable.
- A preview link proves a scoped grant, not editor identity; anyone holding it can
  view that record until expiry. Keep query strings out of proxy/access logs.
- Unsaved previews are saved content only. Linked unpublished records resolve as
  public 404s unless the host fetches them explicitly.

## Checks

Gem tests cover configuration validation, grant scope/expiry/tampering,
draft-only headers, exact-locale document construction, payload mapping and
failure mapping (`test/site/preview_test.rb`). Hosts add request/browser tests
through their real controllers, including that public records, search rows and
snapshots are unchanged by a preview request.
