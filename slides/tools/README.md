# Auxiliary source checks

Run from the repository root:

```sh
python3 slides/tools/check-lexical.py .
python3 slides/tools/check-shapes.py .
python3 slides/tools/check-import-paths.py .
```

`check-lexical.py` recognizes a limited set of Racket lexical forms and checks
brackets, quoted strings, and escapes. `check-shapes.py` parses simple source
S-expressions and checks selected core-form/struct-constructor shapes. It also
counts named test cases occurring inside suites. `check-import-paths.py` checks
relative paths found in require forms, separating package-internal paths from
external native repository paths.

These tools **do not expand Racket macros, resolve bindings, validate contracts,
compile modules, or execute tests**. They are auxiliary source checks, not an
alternative to `raco make`, RackUnit, or native render probes.
The files are deliberately small and are not general Racket parsers.
