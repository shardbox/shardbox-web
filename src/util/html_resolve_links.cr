require "xml"
require "uri"

module HTML
  def self.resolve_links(html, base_url_href, base_url_src = base_url_href)
    base_url_href = URI.parse(base_url_href) if base_url_href.is_a?(String)
    base_url_src = URI.parse(base_url_src) if base_url_src.is_a?(String)
    String.build do |io|
      resolve_links(io, html, base_url_href, base_url_src)
    end
  end

  def self.resolve_links(io : IO, html, base_url_href : URI?, base_url_src : URI? = base_url_href)
    doc = XML.parse_html(html)
    # libxml parser normalizes HTML markup and adds html and body tags which we don't need for HTML fragments
    body = doc.children[1].children.first

    resolve_links(body, base_url_href, base_url_src)

    body.children.each do |node|
      node.to_xml(io, options: XML::SaveOptions::AS_HTML | XML::SaveOptions::NO_XHTML)
    end
  end

  def self.resolve_links(doc : XML::Node, base_url_href : URI?, base_url_src : URI? = base_url_href)
    if base_url_href
      doc.xpath_nodes("//*[@href]").each do |node|
        attribute = node.attributes["href"]
        next if attribute.content.starts_with?("#")
        attribute.content = base_url_href.resolve(attribute.content).to_s
      end
    end
    if base_url_src
      doc.xpath_nodes("//*[@src]").each do |node|
        attribute = node.attributes["src"]
        next if attribute.content.starts_with?("#")
        attribute.content = base_url_src.resolve(attribute.content).to_s
      end
    end
  end
end
