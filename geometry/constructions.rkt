#lang racket/base

;; The public standard construction library. This module is headless.
;; Use a prefix (for example c:) to keep construction names visually distinct
;; from mathematical kernel operations and native Animate Visual constructors.
(require "constructions/foundations.rkt")
(provide (all-from-out "constructions/foundations.rkt"))
