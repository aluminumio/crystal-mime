require "mime/multipart"
require "http"
require "uri"
require "time"
require "quoted_printable"

require "./rfc2047"

# `MIME` Provides raw email parsing capabilities
module MIME
  VERSION = "0.1.17"

  struct Attachment
    getter filename : String?
    getter content_type : String
    getter content_id : String?
    getter inline : Bool
    getter data : Bytes
    def initialize(@content_type : String,
                   @data : Bytes,
                   @filename : String? = nil,
                   @content_id : String? = nil,
                   @inline : Bool = false)
    end
  end

  struct Email
    property from : String?
    property to : String?
    property subject : String?
    property datetime : Time?
    property body_html : String?
    property body_text : String?
    property attachments : Array(Attachment)
    property headers : Hash(String, String)

    def initialize(@from : String?, @to : String?, @subject : String?, @datetime : Time?,
                  @body_html : String?, @body_text : String?, @attachments : Array(Attachment),
                  @headers : Hash(String, String))
    end
  end

  # Support easy access with String
  def self.parse_raw(mime_str : String)
    self.parse_raw(IO::Memory.new(mime_str))
  end

  # Support efficient access as IO Stream
  # Mail looks like:
  # Content-Type=multipart%2Fmixed%3B+boundary%3D%22------------020601070403020003080006%22&Date=Fri%2...
  def self.parse_raw(mime_io : IO, boundary : String | Nil = nil )
    # Read headers in KEY: VAL format. RFC end is \n\n
    headers = Hash(String, String).new
    last_key = "MISSING"
    mime_io.each_line do |line|
      if line.starts_with?(/[\t ]/)        # Can have leading spaces or tabs
        if(last_key=="MISSING")
          puts "Unlikely that this is intended. Seeing line without a key:\n#{line}"
        end
        headers[last_key] += line.lstrip() # Append everything but the spaces
      elsif line.blank?
        break
      else
        k,v = line.split(": ", 2)
        last_key = k

        # Patch up subject (from =?UTF-8?q?Yo_=F0=9F=90=95?= => 🦂)
        headers[k]=RFC2047.decode(v)
      end
    end
    
    parts = Hash(String, String).new
    attachments = [] of Attachment
    body  = nil
    content_type = headers["Content-Type"]?
    if (boundary = is_multipart(content_type))
      # Should not be necessary, except that MIME::Multipart::Parser is too strict requiring CRLF
      # https://github.com/crystal-lang/crystal/blob/master/src/mime/multipart/parser.cr
      mime = mime_io.gets_to_end.gsub(/\r\n/, "\n").gsub(/\n/, "\r\n")
      # puts "MIME: #{mime.inspect}"
      mime_io = IO::Memory.new(mime)

      parser = MIME::Multipart::Parser.new(mime_io, boundary)
      while parser.has_next?
        parser.next do |headers, io|
          # Delegate to the helper (handles both leaf and nested multipart)
          process_mime_part(headers, io, parts, attachments)
        end
      end
    else
      body = mime_io.gets_to_end
      # Decode single-part content by Content-Transfer-Encoding (if present)
      if cte = headers["Content-Transfer-Encoding"]?
        case cte.downcase
        when "quoted-printable"
          body = QuotedPrintable.decode_string(body)
        when "base64"
          body = Base64.decode_string(body)
        end
      end

      # Route single-part by Content-Type:
      ctype = (headers["Content-Type"]? || "text/plain").downcase
      if ctype.starts_with?("text/html")
        parts["text/html"] = body
        body = nil
      elsif ctype.starts_with?("text/plain") || ctype.starts_with?("text/")
        parts["text/plain"] = body
        body = nil
      else
        # Non-text single-part -> treat as attachment (filename later)
        cid    = headers["Content-ID"]?
        dispo  = headers["Content-Disposition"]?
        ct_raw = headers["Content-Type"]?
        inline = (dispo || "").downcase.starts_with?("inline")
        fname  = disposition_filename(dispo) || content_type_name(ct_raw)

        attachments << Attachment.new(
          ctype,
          body.to_slice,
          fname,
          cid,
          inline
        )
        body = nil
      end
    end

    return { headers: headers, parts: parts, body: body, attachments: attachments }
  end

  def self.mail_object_from_raw(raw_mime_data)
    parsed = parse_raw(raw_mime_data)
    # return Email.new(from: "", to: "", subject: "", datetime: nil, body_html: "", body_text: "", attachments: [] of String)
    datetime  = parsed[:headers]["Date"]? ?
                  Time::Format::RFC_2822.parse(parsed[:headers]["Date"]) : nil

    # If not multipart, parsed[:body] holds the content. Route it by Content-Type.
    content_type = parsed[:headers]["Content-Type"]?
    body_is_html = content_type && content_type.downcase.starts_with?("text/html")

    Email.new(from:     parsed[:headers]["From"]?,
              to:       parsed[:headers]["To"]? || parsed[:headers]["recipient"]?,
              subject:  parsed[:headers]["Subject"]?,
              datetime: datetime,
              body_html: parsed[:parts]["text/html"]?  || (body_is_html ? parsed[:body] : nil),
              body_text: parsed[:parts]["text/plain"]? || (body_is_html ? nil : parsed[:body]),
              attachments: parsed[:attachments],
              headers:     parsed[:headers]
            )
  end

  def self.is_multipart(content_type : Nil)
    return nil
  end
  
  def self.is_multipart(content_type : String)
    if content_type =~ /^multipart/ 
        "#{MIME::Multipart.parse_boundary(content_type)}"
    else
      nil
    end
  end

  # Extract filename from Content-Disposition header.
  # Supports:
  #   filename="plain.ext"
  #   filename=plain.ext
  #   filename*=utf-8''percent-encoded.ext   (RFC 2231)
  # Also tries RFC 2047 decoding when present.
  private def self.disposition_filename(dispo : String?) : String?
    return nil unless dispo
    s = dispo

    # --- RFC 2231: filename*=<charset>''<percent-encoded> ---
    # Example: filename*=utf-8''%E2%9C%93-report.pdf
    if m = s.match(/;\s*filename\*\s*=\s*([^']*)''([^;]+)/i)
      # charset = m[1] (unused right now)
      encoded = m[2]
      begin
        decoded = URI.decode(encoded)
        begin
          return RFC2047.decode(decoded)
        rescue
          return decoded
        end
      rescue
        # If percent-decoding fails, fall through and try plain filename=
      end
    end

    # --- Plain filename=... (quoted or unquoted) ---
    # Examples:
    #   filename="report.pdf"
    #   filename=report.pdf
    if m = s.match(/;\s*filename\s*=\s*(?:"([^"]*)"|([^;\s]+))/i)
      value = m[1]? || m[2]? || ""
      return (RFC2047.decode(value) rescue value)
    end

    nil
  end

  # Extract name from Content-Type header as a fallback filename.
  # Supports:
  #   name="plain.ext"
  #   name=plain.ext
  #   name*=utf-8''percent-encoded.ext   (RFC 2231)
  # Also tries RFC 2047 decoding when present.
  private def self.content_type_name(ct_raw : String?) : String?
    return nil unless ct_raw
    s = ct_raw
  
    # RFC2231: name*=<charset>''<percent-encoded>
    if m = s.match(/;\s*name\*\s*=\s*([^']*)''([^;]+)/i)
      encoded = m[2]
      begin
        decoded = URI.decode(encoded)
        begin
          return RFC2047.decode(decoded)
        rescue
          return decoded
        end
      rescue
        # fall through to plain name=
      end
    end
  
    # Plain name=... (quoted or unquoted)
    if m = s.match(/;\s*name\s*=\s*(?:"([^"]*)"|([^;\s]+))/i)
      value = m[1]? || m[2]? || ""
      return (RFC2047.decode(value) rescue value)
    end
  
    nil
  end

  # Process a single MIME part (recurses on multipart/*) ---
  private def self.process_mime_part(headers : HTTP::Headers, io : IO, parts : Hash(String, String), attachments : Array(Attachment))
    ct_raw  = headers["Content-Type"]? || "text/plain"
    ct_main = ct_raw.split(";", 2).first.downcase

    # If this part is itself multipart/*, recurse into its boundary
    if ct_main.starts_with?("multipart/")
      # extract boundary if present
      boundary = nil
      if m = ct_raw.match(/;\s*boundary\s*=\s*(?:"([^"]+)"|([^;\s]+))/i)
        boundary = (m[1]? || m[2]?)
      end
      return unless boundary

      # Normalize line endings for stdlib parser (CRLF)
      normalized = io.gets_to_end.gsub("\r\n", "\n").gsub("\n", "\r\n")
      sub = MIME::Multipart::Parser.new(IO::Memory.new(normalized), boundary)
      while sub.has_next?
        sub.next do |sh, sio|
          process_mime_part(sh, sio, parts, attachments)
        end
      end
      return
    end

    # Leaf part: decode by CTE
    cte = headers["Content-Transfer-Encoding"]?
    content = io.gets_to_end
    case cte
    when "quoted-printable"
      content = QuotedPrintable.decode_string(content)
    when "base64"
      content = Base64.decode_string(content)
    end

    if ct_main.starts_with?("text/html")
      parts["text/html"] = content
    elsif ct_main.starts_with?("text/")
      # keep existing newline normalization for multipart text/plain
      parts["text/plain"] = content.ends_with?("\n") ? content : content + "\n"
    else
      # Non-text → attachment; get filename from Disposition or CT name
      dispo  = headers["Content-Disposition"]?
      cid    = headers["Content-ID"]?
      cid    = cid.try { |x| x.gsub(/[<>]/, "") }
      inline = (dispo || "").downcase.starts_with?("inline")
      fname  = disposition_filename(dispo) || content_type_name(ct_raw)

      attachments << Attachment.new(
        ct_main,
        content.to_slice,
        fname,
        cid,
        inline
      )
    end
  end
end
