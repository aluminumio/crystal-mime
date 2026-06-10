require "./spec_helper"

describe MIME do
  # [RFT1341](https://datatracker.ietf.org/doc/html/rfc1341#page-75)
  it "Ensure test mail is RFC 1341 compliant" do
    # Ensure CRLF's are present in test:
    f = File.read("spec/test-mime1.email")
    crlf = f.gsub(/\r\n/,"\n").gsub(/\n/,"\r\n")
    f.should eq(crlf)
  end

  # From [Email for Users & Programmers](https://rand-mh.sourceforge.io/book/overall/mulmes.html)
  it "Parses test1 email" do
    # Ensure CRLF's are present in test:
    f = File.read("spec/test-mime1.email")
    crlf = f.gsub(/\r\n/,"\n").gsub(/\n/,"\r\n")

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
end
