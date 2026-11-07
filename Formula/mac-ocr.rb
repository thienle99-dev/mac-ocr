class MacOcr < Formula
  desc "Local macOS OCR command-line tool using Apple Vision"
  homepage "https://github.com/thienle99-dev/mac-ocr"
  url "https://github.com/thienle99-dev/mac-ocr/releases/download/v1.0.1/mac-ocr-macos-universal-v1.0.1.tar.gz"
  version "1.0.1"
  sha256 "1751a72d50e5ebe4d72718abd9e7d3ba90608e5286fa3f8340b7a77258c1dc12"
  license :cannot_represent

  depends_on macos: :monterey

  def install
    bin.install "mac-ocr"
  end

  test do
    assert_match "Apple Vision", shell_output("#{bin}/mac-ocr --help")
  end
end
