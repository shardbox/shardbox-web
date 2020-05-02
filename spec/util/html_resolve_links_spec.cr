require "spec"
require "../../src/util/html_resolve_links"

describe "HTML.resolve_links" do
  it "resolves relative link" do
    HTML.resolve_links(%(<a href="foo"></a>), "/base/").should eq %(<a href="/base/foo"></a>)
    HTML.resolve_links(%(<img src="foo">), "/base/").should eq %(<img src="/base/foo">)
    HTML.resolve_links(%(<a href="/foo"></a>), "/base/").should eq %(<a href="/foo"></a>)
    HTML.resolve_links(%(<img src="/foo">), "/base/").should eq %(<img src="/foo">)
    HTML.resolve_links(%(<a href="#foo"></a>), "/base/").should eq %(<a href="#foo"></a>)
    HTML.resolve_links(%(<img src="#foo">), "/base/").should eq %(<img src="#foo">)
    HTML.resolve_links(%(<img src="">), "/base/").should eq %(<img src="/base/">)
  end
end
