require "markd"
require "digest"
require "sanitize"

INLINE_SANITIZER = Sanitize::Policy::HTMLSanitizer.inline

MARKD_SANITIZER = Sanitize::Policy::HTMLSanitizer.common
# Allow classes with `language-` prefix which are used for syntax highlighting.
MARKD_SANITIZER.valid_classes << /language-.+/

Crinja.filter({base_url: nil}, "markdown_inline") do
  render_markdown(target, arguments, INLINE_SANITIZER)
end

def render_markdown(target, arguments, sanitizer)
  html = Markd.to_html(target.to_s)

  if base_url = arguments["base_url"].as_s?.to_s
    sanitizer = sanitizer.dup
    sanitizer.uri_sanitizer = sanitizer.uri_sanitizer.dup
    sanitizer.uri_sanitizer.base_url = URI.parse(base_url)
  end
  sanitized = sanitizer.process(html)

  Crinja::SafeString.new(sanitized)
end

Crinja.filter({base_url: nil}, "markdown") do
  render_markdown(target, arguments, MARKD_SANITIZER)
end

Crinja.filter({repo_ref: Crinja::UNDEFINED, revision: nil}, "markdown_repo_content") do
  repo_ref = arguments["repo_ref"].raw.as(Repo::Ref)
  refname = arguments["revision"].as_s?

  sanitizer = ReadmeSanitizer.new(repo_ref.base_url_source(refname), repo_ref.base_url_raw(refname))

  html = Markd.to_html(target.to_s)
  sanitized = sanitizer.process(html)

  Crinja::SafeString.new(sanitized)
end

class ReadmeSanitizer < Sanitize::Policy::HTMLSanitizer
  property src_uri_sanitizer : Sanitize::URISanitizer?

  def self.new(base_url, src_url)
    common.tap do |instance|
      instance.uri_sanitizer.base_url = base_url
      src_sanitizer = Sanitize::URISanitizer.new
      src_sanitizer.base_url = src_url
      instance.src_uri_sanitizer = src_sanitizer
      instance.valid_classes << /language-.+/
    end
  end

  def transform_uri(tag, attributes, attribute, uri : URI) : String?
    if attribute == "src" && (src_uri_sanitizer = self.src_uri_sanitizer)
      uri = src_uri_sanitizer.sanitize(uri)

      return unless uri

      # Make sure special characters are properly encoded to avoid interpretation
      # of tweaked relative paths as "javascript:" URI (for example)
      if path = uri.path
        uri.path = URI.encode(URI.decode(path))
      end

      uri.to_s
    else
      super
    end
  end
end

Crinja.filter("gravatar_hash") do
  mail = target.as_s
  Digest::MD5.hexdigest(mail.strip.downcase)
end
