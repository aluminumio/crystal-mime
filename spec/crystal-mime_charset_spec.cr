require "./spec_helper"

require "mime/multipart"
require "http"
require "uri"
require "time"
require "quoted_printable"

# Build raw emails with proper CRLF to avoid headers leaking into the body
private def h(line : String) : String
  line + "\r\n"
end

private def singlepart_email(ct : String, cte : String?, body : String) : String
  String.build do |s|
    s << h "From: a@example.com"
    s << h "To: b@example.com"
    s << h "Subject: charset test"
    s << h "MIME-Version: 1.0"
    s << h "Content-Type: #{ct}"
    s << h "Content-Transfer-Encoding: #{cte}" if cte
    s << "\r\n"        # header/body separator
    s << body
  end
end

private def multipart_email(boundary : String, parts : Array(String)) : String
  String.build do |s|
    s << h "From: a@example.com"
    s << h "To: b@example.com"
    s << h "Subject: multipart charset test"
    s << h "MIME-Version: 1.0"
    s << h "Content-Type: multipart/mixed; boundary=#{boundary}"
    s << "\r\n"
    s << "This is a multipart message in MIME format.\r\n"
    parts.each { |p| s << p }
    s << "--#{boundary}--\r\n"
  end
end

private def part(boundary : String, headers : Array(String), content : String) : String
  String.build do |s|
    s << "--#{boundary}\r\n"
    headers.each { |hline| s << h hline }
    s << "\r\n"
    s << content
    s << "\r\n"
  end
end

describe "MIME charset decoding" do
  it "decodes iso-8859-1 (quoted-printable) to UTF-8" do
    # café in ISO-8859-1 quoted-printable: caf=E9
    raw = singlepart_email(
      "text/plain; charset=iso-8859-1",
      "quoted-printable",
      "caf=E9"
    )

    email = MIME.mail_object_from_raw(raw)
    email.body_text.not_nil!.chomp.should eq("café")
  end

  it "decodes windows-1252 (base64) to UTF-8" do
    # bytes [0xA3, 0x20, 0x80] in CP1252 ( "£ €" ) → base64 "oyCA"
    raw = singlepart_email(
      "text/plain; charset=windows-1252",
      "base64",
      "oyCA"
    )

    email = MIME.mail_object_from_raw(raw)
    email.body_text.not_nil!.chomp.should eq("£ €")
  end

  it "passes through UTF-8 unchanged" do
    raw = singlepart_email(
      "text/plain; charset=UTF-8",
      nil,   # identity / 7bit
      "こんにちは"
    )

    email = MIME.mail_object_from_raw(raw)
    email.body_text.not_nil!.should eq("こんにちは")
  end

  it "falls back safely on unknown charset (keeps ASCII as-is)" do
    raw = singlepart_email(
      "text/plain; charset=unknown-foo",
      nil,
      "Hello"
    )

    email = MIME.mail_object_from_raw(raw)
    email.body_text.not_nil!.should eq("Hello")
  end

  it "decodes inside multipart and preserves the text/plain newline rule" do
    boundary = "xYz123"

    text_headers = [
      "Content-Type: text/plain; charset=iso-8859-1",
      "Content-Transfer-Encoding: quoted-printable"
    ]
    text_part = part(boundary, text_headers, "caf=E9")

    bin_headers = [
      "Content-Type: application/octet-stream",
      "Content-Disposition: attachment; filename=\"x.bin\"",
      "Content-Transfer-Encoding: base64"
    ]
    bin_part = part(boundary, bin_headers, "AAECAwQF")

    raw = multipart_email(boundary, [text_part, bin_part])

    email = MIME.mail_object_from_raw(raw)

    # Your existing rule: multipart text/plain gains trailing newline
    t = email.body_text.not_nil!
    t.should end_with("\n")
    t.chomp.should eq("café")
  end
end
