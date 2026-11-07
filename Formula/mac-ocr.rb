class MacOcr < Formula
  desc "Local macOS OCR command-line tool using Apple Vision"
  homepage "https://github.com/thienle99-dev/mac-ocr"
  url "https://github.com/thienle99-dev/mac-ocr/releases/download/v1.0.2/mac-ocr-macos-universal-v1.0.2.tar.gz"
  version "1.0.2"
  sha256 "5b102087a55214c471f92fb55db0c1f32359e0f1c2063f49507219f4ebba04d9"
  license :cannot_represent

  depends_on macos: :monterey

  def install
    bin.install "mac-ocr"
  end

  test do
    assert_match "Apple Vision", shell_output("#{bin}/mac-ocr --help")
  end
end
