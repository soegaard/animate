#lang racket/base

;;;
;;; Unforgeable OpenGL Context Identities
;;;

;; A generation identifies a restart of one host; `token` distinguishes two
;; otherwise identical hosts.  Keeping this tiny value outside GUI code lets
;; headless resource-lifecycle tests exercise the same ownership rule.

(provide (struct-out gl-context-identity))

(struct gl-context-identity (token generation)
  #:transparent
  #:guard
  (lambda (token generation who)
    (unless token
      (raise-argument-error who "non-false context identity token" token))
    (unless (exact-nonnegative-integer? generation)
      (raise-argument-error who "exact-nonnegative-integer?" generation))
    (values token generation)))
