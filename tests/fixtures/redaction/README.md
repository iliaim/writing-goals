# G06 redaction fixtures

`stream.txt` deliberately contains token-shaped credentials and absolute local roots. They are
test seeds, not credentials. `malformed-encoding.hex` is a hex encoding of an otherwise
token-bearing byte stream ending in an invalid UTF-8 byte (`ff`). The oracle decodes it at
runtime so malformed input never appears as a text fixture on the candidate output path.
`valid-json-secret.json` is valid UTF-8 JSON containing a secret field and a Windows absolute
path; it must be sanitized or rejected before persistence.
`valid-json-client-secret.json` is valid UTF-8 JSON with a `client_secret` field and a UNC
network root; it must also be sanitized or rejected before persistence.
`valid-json-escaped-keys.json` is valid UTF-8 JSON whose `client_secret` and `secret` keys use
Unicode escapes; semantic key recognition must occur before persistence.
`timestamped-embedded-escaped-key.log` prefixes embedded JSON with a timestamp, ensuring
escaped credential keys are detected record-wide rather than only when a record starts with JSON.
`valid-json-structured-credentials.json` gives `client_secret` an array and `secret` an object;
credential-shaped fields must not persist merely because their JSON values are non-strings.
`colon-delimited-credentials.log` uses line-oriented `X-Api-Key:` and `client_secret:` fields;
their values must be sanitized or rejected before persistence.

The protected redactor interface is:

```sh
bash assets/redact-stream.sh --output OUTPUT --max-bytes N --max-records N < INPUT
```

It must fail closed: an untrusted stream that cannot be transformed with certainty must return
non-zero without creating `OUTPUT` or persisting any input bytes anywhere beneath its output
directory.
