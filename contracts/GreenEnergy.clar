
;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-amount (err u101))
(define-constant err-insufficient-balance (err u102))

;; data vars
(define-data-var total-credits uint u0)

;; data maps
(define-map credit-balances principal uint)
(define-map credit-verification principal bool)
(define-map offset-records 
    principal 
    {total-offset: uint, last-update: uint}
)

;; public functions
(define-public (mint-credits (amount uint) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> amount u0) err-invalid-amount)
        (map-set credit-balances recipient 
            (+ (default-to u0 (map-get? credit-balances recipient)) amount))
        (var-set total-credits (+ (var-get total-credits) amount))
        (ok true)))

(define-public (transfer-credits (amount uint) (sender principal) (recipient principal))
    (let ((sender-balance (default-to u0 (map-get? credit-balances sender))))
        (asserts! (>= sender-balance amount) err-insufficient-balance)
        (asserts! (is-eq tx-sender sender) err-owner-only)
        (map-set credit-balances sender (- sender-balance amount))
        (map-set credit-balances recipient 
            (+ (default-to u0 (map-get? credit-balances recipient)) amount))
        (ok true)))

(define-public (record-offset (amount uint))
    (let ((current-time stacks-block-height))
        (map-set offset-records tx-sender 
            {total-offset: (+ (get-offset-total tx-sender) amount),
             last-update: current-time})
        (ok true)))

;; read only functions
(define-read-only (get-credit-balance (account principal))
    (default-to u0 (map-get? credit-balances account)))

(define-read-only (get-offset-total (account principal))
    (default-to u0 (get total-offset (map-get? offset-records account))))

(define-read-only (get-total-credits)
    (var-get total-credits))
