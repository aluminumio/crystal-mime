require "quoted_printable"

module RFC2047
  WORD = /=\?([!#$\%&'*+-\/0-9A-Z\\^\`a-z{|}~]+)\?([BbQq])\?([!->@-~]+)\?=/

  # Look for two adjacent words in the same encoding.
  ADJACENT_WORDS = /(#{WORD})[\s\r\n]+(?==\?(\2)\?([BbQq])\?)/

  # Decodes a string, +from+, containing RFC 2047 encoded words into a target
  # character set, +target+ defaulting to utf-8. See iconv_open(3) for information on the
  # supported target encodings. If one of the encoded words cannot be
  # converted to the target encoding, it is left in its encoded form.
  def self.decode(from : String, target : String = "utf-8")
    from.gsub(ADJACENT_WORDS, "\\1").gsub(WORD) do |word|
      # cs = $1
      encoding = $2
      text = $3
      # B64 or QP decode, as necessary:
      case encoding.downcase
      when "b"
        text = Base64.decode_string(text)
      when "q"
        # RFC 2047 has a variant of quoted printable where a ' ' character
        # can be represented as an '_', rather than =32, so convert
        # any of these that we find before doing the QP decoding.
        text = text.tr("_", " ")
        text = QuotedPrintable.decode_string(text)
      else
        raise Unparseable.new(from)
      end
      text
    end
  end

  class Unparseable < RuntimeError
    def initialize(@from : String)
    end
  end
end
