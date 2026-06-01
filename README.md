# crystal-mime

Adding support for RAW mime email parsing.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     crystal-mime:
       github: aluminumio/crystal-mime
   ```

2. Run `shards install`

## Usage

```crystal
require "crystal-mime"

email = MIME.mail_object_from_raw(raw_email_mime)
```

## Development

TODO: Write development instructions here

## References

* [Multipart RFC](https://www.w3.org/Protocols/rfc1341/7_2_Multipart.html)
* [Missing Unpack](https://forum.crystal-lang.org/t/pack-unpack-methods/1608/2)
* [Missing Unescape](https://ruby-doc.org/stdlib-2.5.1/libdoc/cgi/rdoc/CGI/Util.html#method-i-unescape)
* [SMTP Crystal](https://github.com/ray-delossantos/smtp.cr)
* [Ruby Usage](http://codebeerstartups.com/how-to-fetch-and-parse-emails-in-ruby-on-rails/)
* [mikel/mail](https://rubydoc.info/github/mikel/mail)
* [Ruby Mail Parser](https://github.com/garciadanny/email_parser)
* [Crystal Sending Email](https://github.com/arcage/crystal-email)
* [Crystal Multipart In-Progress](https://github.com/crystal-lang/crystal/blob/master/src/mime/multipart.cr) [PR12890](https://github.com/crystal-lang/crystal/pull/12890)

## Contributing

1. Fork it (<https://github.com/aluminumio/crystal-mime/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Jonathan Siegel](https://github.com/usiegj00) - creator and maintainer
- [Anton Karankevich](https://github.com/anton7c3) - some fixes from real use cases
