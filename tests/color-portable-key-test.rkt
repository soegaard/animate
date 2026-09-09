#lang racket/base

;;; Portable symbol identities at palette/theme serialization boundaries

(require racket/port
         rackunit
         "../colors.rkt")

(module+ test
  ;; Ordinary interned symbols remain supported, including the documented
  ;; palette aliases. They survive an actual bytes/read boundary.
  (define ordinary-key (string->symbol "portable-brand"))
  (check-equal? (color-token-key (palette-color (string->symbol "blue")))
                'blue-c)
  (check-equal? (color-token-key (role-color ordinary-key)) ordinary-key)
  (define portable-theme
    (color-theme #:id 'portable-key-roundtrip
                 #:extends animate-light-theme
                 #:roles (hash ordinary-key "#123456")
                 #:provenance 'portable-key-test))
  (define encoded
    (call-with-output-bytes
     (lambda (out) (write (theme->datum portable-theme) out))))
  (define restored
    (datum->theme (read (open-input-bytes encoded))))
  (check-equal? (theme->datum restored) (theme->datum portable-theme))
  (check-equal? (resolve-color (role-color ordinary-key) restored)
                (resolve-color (role-color ordinary-key) portable-theme))

  ;; These symbols can have a readable-looking spelling, but their identity is
  ;; process-local. Reject them before token creation, alias lookup, or hash
  ;; insertion; silently interning would merge distinct declarations.
  (for ([key (in-list (list (gensym 'brand)
                            (string->uninterned-symbol "brand")
                            (string->unreadable-symbol "brand")
                            (string->uninterned-symbol "")
                            (string->uninterned-symbol "blue")))])
    (check-exn #px"interned"
               (lambda () (palette-color key)))
    (check-exn #px"interned"
               (lambda () (role-color key)))
    (check-exn #px"interned"
               (lambda ()
                 (color-theme #:id key #:extends animate-light-theme)))
    (check-exn #px"interned"
               (lambda ()
                 (color-theme #:id 'portable-role-definition
                              #:extends animate-light-theme
                              #:roles (hash key "#123456"))))
    (check-exn #px"interned"
               (lambda ()
                 (color-palette #:id key #:extends animate-palette #:colors (hash))))
    (check-exn #px"interned"
               (lambda ()
                 (color-palette #:id 'portable-palette-definition
                                #:extends animate-palette
                                #:colors (hash key "#123456"))))
    (check-exn #px"interned"
               (lambda ()
                 (color-theme #:id 'portable-theme-provenance
                              #:extends animate-light-theme
                              #:provenance key)))
    (check-exn #px"interned"
               (lambda ()
                 (color-palette #:id 'portable-palette-provenance
                                #:extends animate-palette
                                #:colors (hash)
                                #:provenance key))))

  ;; Group identifiers are serialized palette data too, so they follow the
  ;; same rule independently of palette-entry validation.
  (check-exn #px"interned"
             (lambda ()
               (color-palette
                #:id 'portable-group
                #:extends animate-palette
                #:colors (hash 'brand "#123456")
                #:groups (append (palette-groups animate-palette)
                                  (list (list (string->uninterned-symbol "brand-group")
                                              '(brand)))))))

  ;; In particular, two same-spelling uninterned keys cannot form a theme
  ;; which would only fail later, after write/read collapses them.
  (define first-brand (string->uninterned-symbol "brand"))
  (define second-brand (string->uninterned-symbol "brand"))
  (check-false (eq? first-brand second-brand))
  (check-exn #px"interned"
             (lambda ()
               (color-theme #:id 'same-spelling-uninterned
                            #:extends animate-light-theme
                            #:roles (hash first-brand "#FF0000"
                                          second-brand "#0000FF")))))
