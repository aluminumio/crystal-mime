require "mime/multipart"
require "time"

# `MIME` Provides raw email parsing capabilities
module MIME
  VERSION = "0.1.10"

  struct Email
    property from
    property to
    property subject
    property datetime
    property body_html
    property body_text
    property attachments
    property headers
    def initialize(@from : String, @to : String, @subject : String, @datetime : Time | Nil, 
        @body_html : String | Nil, @body_text : String | Nil, @attachments : Array(String), @headers : Hash(String, String))
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
        headers[last_key] += line.lstrip() # Append everything but the spaces
      elsif line.blank?
        break
      else
        k,v = line.split(": ", 2)
        last_key = k
        headers[k]=v
      end
    end
    
    parts = Hash(String, String).new
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
          content_type = headers["Content-Type"].split("; ", 2).first
          parts[content_type] = io.gets_to_end
        end
      end
    else
      body = mime_io.gets_to_end
    end
    return { headers: headers, parts: parts, body: body }
  end

  def self.mail_object_from_raw(raw_mime_data)
    parsed = parse_raw(raw_mime_data)
    # return Email.new(from: "", to: "", subject: "", datetime: nil, body_html: "", body_text: "", attachments: [] of String)
    if parsed[:headers]["Date"]?
      datetime = Time::Format::RFC_2822.parse(parsed[:headers]["Date"])
    else
      datetime = nil
    end
    # puts parsed.inspect
    Email.new(from:     parsed[:headers]["From"],
              to:       parsed[:headers]["To"]? || parsed[:headers]["recipient"],
              subject:  parsed[:headers]["Subject"]? || "",    
              datetime: datetime,
              body_html: parsed[:parts]["text/html"]?,
              body_text: parsed[:parts]["text/plain"]?,
              attachments: [] of String,
              headers: parsed[:headers]
              )
  end

  def self.parse_multipart(mime_io : IO, boundary : String) Hash(String, String)
    # Manual parse:
    parts = Array(String).new
    buf   = Array(String).new
    mime_io.each_line do |line|
      if(line == "--#{boundary}")
        puts "BOUNDARY FOUND"
        self.parse_raw(mime_io, boundary)
        parts << buf.join("\n")
        buf = Array(String).new
      elsif(line == "--#{boundary}--") # Terminal boundary
        puts "TERMINAL BOUNDARY FOUND"
        parts << buf.join("\n") unless buf.empty?
        buf = Array(String).new # But really should be done
      else
        puts "LINE #{line}"
        buf << line
      end
    end
    non_mime = parts.shift # https://en.wikipedia.org/wiki/MIME#Multipart_messages
    return Hash(String, String).new
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
end
