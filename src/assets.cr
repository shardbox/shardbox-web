require "sass"

PUBLIC_PATH = Path.posix("public")
CSS_PATH    = Path.posix("/", "assets", "css")
STYLE_PATH  = CSS_PATH.join("style.css")

unless File.readable?(PUBLIC_PATH.join(STYLE_PATH))
  get STYLE_PATH.to_s do |context|
    context.response.headers["Content-Type"] = "text/css"
    compile_sass
  end
end

def compile_sass
  Sass.compile_file("app/sass/main.sass", is_indented_syntax_src: true, include_path: "app/sass/")
end

def assets_precompile
  Dir.mkdir_p(PUBLIC_PATH.join(CSS_PATH))
  File.write(PUBLIC_PATH.join(STYLE_PATH), compile_sass)
end
