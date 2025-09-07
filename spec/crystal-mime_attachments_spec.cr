require "./spec_helper"


describe "MIME Attachments" do
  it "single-part non-text becomes an attachment" do
    raw = <<-EML
    From: A <a@a>
    To: B <b@b>
    Subject: File
    Content-Type: application/pdf
    Content-Transfer-Encoding: base64

    #{Base64.strict_encode("PDFDATA")}
    EML

    email = MIME.mail_object_from_raw(raw)
    (email.body_text || "").should eq("")
    (email.body_html || "").should eq("")
    email.attachments.size.should eq(1)
    a = email.attachments.first
    a.content_type.should eq("application/pdf")
    String.new(a.data).should eq("PDFDATA")
  end

  it "multipart non-text becomes an attachment (current behavior)" do
    raw = <<-EML
    From: A <a@a>
    To: B <b@b>
    Subject: Mixed
    Content-Type: multipart/mixed; boundary="X"

    --X
    Content-Type: text/plain; charset=utf-8

    Hello
    --X
    Content-Type: application/pdf
    Content-Transfer-Encoding: base64
    Content-Disposition: attachment; filename="doc.pdf"

    #{Base64.strict_encode("PDFDATA")}
    --X--
    EML

    email = MIME.mail_object_from_raw(raw)
    email.body_text.should eq("Hello\n")
    # At the start of step 3, we haven't implemented multipart attachments yet:
    email.attachments.size.should eq(1)
  end

  it "single-part non-text picks up filename from Content-Disposition" do
    raw = <<-EML
    From: A <a@a>
    To: B <b@b>
    Subject: File
    Content-Type: application/pdf
    Content-Transfer-Encoding: base64
    Content-Disposition: attachment; filename="report.pdf"

    #{Base64.strict_encode("PDFDATA")}
    EML
    email = MIME.mail_object_from_raw(raw)
    email.attachments.size.should eq(1)
    a = email.attachments.first
    a.filename.should eq("report.pdf")
    a.content_type.should eq("application/pdf")
  end

  it "multipart non-text part becomes attachment and captures filename" do
    raw = <<-EML
    From: A <a@a>
    To: B <b@b>
    Subject: Mixed
    Content-Type: multipart/mixed; boundary="X"

    --X
    Content-Type: text/plain; charset=utf-8

    Hello
    --X
    Content-Type: application/pdf
    Content-Transfer-Encoding: base64
    Content-Disposition: attachment; filename="doc.pdf"

    #{Base64.strict_encode("PDFDATA")}
    --X--
    EML

    email = MIME.mail_object_from_raw(raw)
    email.body_text.should eq("Hello\n")
    email.attachments.size.should eq(1)
    a = email.attachments.first
    a.content_type.should eq("application/pdf")
    a.filename.should eq("doc.pdf")
    String.new(a.data).should eq("PDFDATA")
  end

  it "decodes RFC2231 filename* in Content-Disposition" do
    raw = <<-EML
    From: A <a@a>
    To: B <b@b>
    Subject: File
    Content-Type: application/pdf
    Content-Transfer-Encoding: base64
    Content-Disposition: attachment; filename*=utf-8''%E2%9C%93-report.pdf

    #{Base64.strict_encode("PDFDATA")}
    EML

    email = MIME.mail_object_from_raw(raw)
    email.attachments.size.should eq(1)
    a = email.attachments.first
    a.filename.should eq("✓-report.pdf")
  end

  it "uses Content-Type; name= as filename when no Content-Disposition present (multipart)" do
    raw = <<-EML
    From: A <a@a>
    To: B <b@b>
    Subject: Mixed
    Content-Type: multipart/mixed; boundary="X"

    --X
    Content-Type: text/plain; charset=utf-8

    Hello
    --X
    Content-Type: application/pdf; name="report.pdf"
    Content-Transfer-Encoding: base64

    #{Base64.strict_encode("PDFDATA")}
    --X--
    EML

    email = MIME.mail_object_from_raw(raw)
    email.attachments.size.should eq(1)
    a = email.attachments.first
    a.filename.should eq("report.pdf")
  end

  it "decodes RFC2231 name* in Content-Type as fallback filename (single-part)" do
    raw = <<-EML
    From: A <a@a>
    To: B <b@b>
    Subject: File
    Content-Type: application/pdf; name*=utf-8''%E2%9C%93-plan.pdf
    Content-Transfer-Encoding: base64

    #{Base64.strict_encode("PDFDATA")}
    EML

    email = MIME.mail_object_from_raw(raw)
    email.attachments.size.should eq(1)
    a = email.attachments.first
    a.filename.should eq("✓-plan.pdf")
  end

  it "handles nested multipart (alternative inside mixed) and still extracts attachment" do
    raw = <<-EML
    From: A <a@a>
    To: B <b@b>
    Subject: Nested
    Content-Type: multipart/mixed; boundary="outer"

    --outer
    Content-Type: multipart/alternative; boundary="alt"

    --alt
    Content-Type: text/plain; charset=utf-8

    Hello nested
    --alt
    Content-Type: text/html; charset=utf-8

    <b>Hello nested</b>
    --alt--
    --outer
    Content-Type: application/pdf
    Content-Transfer-Encoding: base64
    Content-Disposition: attachment; filename="n.pdf"

    #{Base64.strict_encode("PDFDATA")}
    --outer--
    EML

    email = MIME.mail_object_from_raw(raw)
    email.body_text.should eq("Hello nested\n")
    email.body_html.not_nil!.should contain("Hello nested")
    email.attachments.size.should eq(1)
    email.attachments.first.filename.should eq("n.pdf")
  end

  it "collapses empty filename to nil and strips path segments" do
  raw = <<-EML
    From: A <a@a>
    To: B <b@b>
    Subject: Mix
    Content-Type: multipart/mixed; boundary="X"
      
    --X
    Content-Type: text/plain; charset=utf-8
      
    Hi
    --X
    Content-Type: application/pdf; name="C:\\temp\\..\\report.pdf"
    Content-Transfer-Encoding: base64
    Content-Disposition: attachment; filename=""
      
    #{Base64.strict_encode("PDFDATA")}
    --X--
    EML
  
    email = MIME.mail_object_from_raw(raw)
    email.attachments.size.should eq(1)
    a = email.attachments.first
    a.filename.should eq("report.pdf") # from sanitized CT name (since filename="" -> nil)
  end
end
