require "./spec_helper"

describe MIME do
  # [RFT1341](https://datatracker.ietf.org/doc/html/rfc1341#page-75)
  it "Ensure test mail is RFC 1341 compliant" do
    # Ensure CRLF's are present in test:
    f = File.read("spec/test-mime1.email")
    crlf = f.gsub(/\r\n/, "\n").gsub(/\n/, "\r\n")
    f.should eq(crlf)
  end

  # From [Email for Users & Programmers](https://rand-mh.sourceforge.io/book/overall/mulmes.html)
  it "Parses test1 email" do
    # Ensure CRLF's are present in test:
    f = File.read("spec/test-mime1.email")
    crlf = f.gsub(/\r\n/, "\n").gsub(/\n/, "\r\n")

    email = MIME.mail_object_from_raw(crlf)
    email.from.should eq("Jerry Peek <jerry@ora.com>")

    # puts email.inspect
    # puts "body: #{email.body_text}"
    body_text = email.body_text
    body_text.should be_a(String)
    body_text && body_text.should start_with("We've just released")

    true.should eq(true)
  end

  it "Follows RFC 2047" do
    str = RFC2047.decode("=?UTF-8?q?Yo_=F0=9F=90=95?=")
    str.should eq("Yo 🐕")
  end

  describe ".normalize_crlf" do
    it "returns the same object when input is already CRLF-only (no copy)" do
      input = "a\r\nb\r\nc"
      MIME.normalize_crlf(input).should be(input)
    end

    it "converts bare LF to CRLF" do
      MIME.normalize_crlf("a\nb\nc").should eq("a\r\nb\r\nc")
    end

    it "handles mixed LF and CRLF" do
      MIME.normalize_crlf("a\r\nb\nc").should eq("a\r\nb\r\nc")
    end

    it "handles LF at start of input" do
      MIME.normalize_crlf("\nabc").should eq("\r\nabc")
    end

    it "leaves lone CR untouched (matches previous gsub behavior)" do
      input = "a\rb\r\nc"
      MIME.normalize_crlf(input).should be(input)
    end

    it "matches the previous double-gsub on the test corpus" do
      f = File.read("spec/test-mime1.email")
      lf_only = f.gsub(/\r\n/, "\n")
      MIME.normalize_crlf(lf_only).should eq(lf_only.gsub(/\r\n/, "\n").gsub(/\n/, "\r\n"))
    end

    it "parses a multipart email given with LF-only line endings" do
      lf_email = File.read("spec/test-mime1.email").gsub(/\r\n/, "\n")
      email = MIME.mail_object_from_raw(lf_email)
      email.from.should eq("Jerry Peek <jerry@ora.com>")
      body_text = email.body_text
      body_text.should be_a(String)
      body_text && body_text.should start_with("We've just released")
    end
  end

  describe "header parse tolerance (RFC 5322 §2.2)" do
    it "parses a header with no space after the colon" do
      parsed = MIME.parse_raw("Auto-Submitted:auto-replied\r\nFrom: a@b.c\r\n\r\nbody")
      parsed[:headers]["Auto-Submitted"].should eq("auto-replied")
      parsed[:headers]["From"].should eq("a@b.c")
    end

    it "strips extra whitespace after the colon" do
      parsed = MIME.parse_raw("Subject:   padded\r\n\r\nbody")
      parsed[:headers]["Subject"].should eq("padded")
    end

    it "preserves colons inside the value" do
      parsed = MIME.parse_raw("Subject: Re: foo: bar\r\n\r\nbody")
      parsed[:headers]["Subject"].should eq("Re: foo: bar")
    end

    it "skips a header line with no colon instead of raising" do
      parsed = MIME.parse_raw("Garbage line without colon\r\nFrom: a@b.c\r\n\r\nbody")
      parsed[:headers]["From"].should eq("a@b.c")
    end
  end
end

# RFC 5322 §3.6 defines which header fields are mandatory and which are not.
# Only `Date:` and `From:` are required; every destination field — `To:`,
# `Cc:`, `Bcc:` — is optional. A parser that raises on an absent optional
# field rejects legal mail, and one that raises on an absent *mandatory*
# field loses a whole message to a defect it cannot fix. Parse tolerantly.
describe "MIME header requirements (RFC 5322 §3.6)" do
  it "parses a message with no To: — destination fields are optional" do
    # A Bcc-only message has no To: at all. DSNs also frequently omit it.
    raw = "From: <MAILER-DAEMON@remote.test>\r\nSubject: Undelivered\r\n\r\nfailed\r\n"
    email = MIME.mail_object_from_raw(raw)
    email.to.should eq("")
    email.from.should eq("<MAILER-DAEMON@remote.test>")
  end

  it "falls back to a `recipient` header when To: is absent" do
    raw = "From: <a@b.test>\r\nrecipient: <c@d.test>\r\nSubject: S\r\n\r\nbody\r\n"
    MIME.mail_object_from_raw(raw).to.should eq("<c@d.test>")
  end

  it "parses a message with neither To: nor recipient" do
    # The regression: this raised KeyError("recipient") — a confusing name for
    # a message whose only real oddity was having no To:.
    raw = "From: <a@b.test>\r\nSubject: S\r\n\r\nbody\r\n"
    MIME.mail_object_from_raw(raw).to.should eq("")
  end

  it "parses a message with no From:, though RFC 5322 requires one" do
    # Mandatory per the RFC, absent in the wild. Surfacing "" lets the caller
    # decide; raising here would discard the message and everything in it.
    raw = "To: <c@d.test>\r\nSubject: S\r\n\r\nbody\r\n"
    email = MIME.mail_object_from_raw(raw)
    email.from.should eq("")
    email.to.should eq("<c@d.test>")
  end

  it "parses a message with no Subject: — also optional" do
    raw = "From: <a@b.test>\r\nTo: <c@d.test>\r\n\r\nbody\r\n"
    MIME.mail_object_from_raw(raw).subject.should eq("")
  end

  it "parses a message with only the mandatory fields" do
    raw = "From: <a@b.test>\r\nDate: Fri, 14 Aug 2026 05:00:00 +0000\r\n\r\nbody\r\n"
    email = MIME.mail_object_from_raw(raw)
    email.from.should eq("<a@b.test>")
    email.datetime.should_not be_nil
    email.to.should eq("")
  end

  it "parses a message with no headers at all" do
    MIME.mail_object_from_raw("\r\nnaked body\r\n").from.should eq("")
  end

  it "defaults a Content-Type-less body part to text/plain (RFC 2045 §5.2)" do
    # A part without Content-Type is not an error; it defaults to
    # text/plain. This used to raise and abort the whole message's parse.
    raw = "From: <a@b.test>\r\nTo: <c@d.test>\r\n" \
          "Content-Type: multipart/mixed; boundary=\"zz\"\r\n\r\n" \
          "--zz\r\n\r\nbare part\r\n--zz--\r\n"
    email = MIME.mail_object_from_raw(raw)
    email.body_text.should_not be_nil
  end

  it "still keeps every header available in the headers hash" do
    raw = "From: <a@b.test>\r\nX-Custom: kept\r\n\r\nbody\r\n"
    headers = MIME.parse_raw(raw)[:headers]
    headers["X-Custom"]?.should eq("kept")
    headers["To"]?.should be_nil
  end
end
