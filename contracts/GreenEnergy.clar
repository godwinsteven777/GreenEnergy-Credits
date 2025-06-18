;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-amount (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-listing-not-found (err u103))
(define-constant err-insufficient-payment (err u104))
(define-constant err-cannot-buy-own-listing (err u105))

;; data vars
(define-data-var total-credits uint u0)
(define-data-var listing-counter uint u0)

;; data maps
(define-map credit-balances principal uint)
(define-map credit-verification principal bool)
(define-map offset-records 
    principal 
    {total-offset: uint, last-update: uint}
)
(define-map marketplace-listings
    uint
    {seller: principal, amount: uint, price-per-credit: uint, active: bool}
)
(define-map user-listings principal (list 20 uint))

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

(define-public (create-listing (amount uint) (price-per-credit uint))
    (let (
        (seller-balance (get-credit-balance tx-sender))
        (listing-id (+ (var-get listing-counter) u1))
        (current-listings (default-to (list) (map-get? user-listings tx-sender)))
    )
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (> price-per-credit u0) err-invalid-amount)
        (asserts! (>= seller-balance amount) err-insufficient-balance)
        (map-set credit-balances tx-sender (- seller-balance amount))
        (map-set marketplace-listings listing-id
            {seller: tx-sender, amount: amount, price-per-credit: price-per-credit, active: true})
        (map-set user-listings tx-sender (unwrap-panic (as-max-len? (append current-listings listing-id) u20)))
        (var-set listing-counter listing-id)
        (ok listing-id)))

(define-public (buy-credits (listing-id uint))
    (let (
        (listing (unwrap! (map-get? marketplace-listings listing-id) err-listing-not-found))
        (seller (get seller listing))
        (amount (get amount listing))
        (price-per-credit (get price-per-credit listing))
        (total-price (* amount price-per-credit))
        (buyer-balance (stx-get-balance tx-sender))
    )
        (asserts! (get active listing) err-listing-not-found)
        (asserts! (not (is-eq tx-sender seller)) err-cannot-buy-own-listing)
        (asserts! (>= buyer-balance total-price) err-insufficient-payment)
        (try! (stx-transfer? total-price tx-sender seller))
        (map-set credit-balances tx-sender 
            (+ (get-credit-balance tx-sender) amount))
        (map-set marketplace-listings listing-id
            (merge listing {active: false}))
        (ok true)))

(define-public (cancel-listing (listing-id uint))
    (let (
        (listing (unwrap! (map-get? marketplace-listings listing-id) err-listing-not-found))
        (seller (get seller listing))
        (amount (get amount listing))
    )
        (asserts! (is-eq tx-sender seller) err-owner-only)
        (asserts! (get active listing) err-listing-not-found)
        (map-set credit-balances seller 
            (+ (get-credit-balance seller) amount))
        (map-set marketplace-listings listing-id
            (merge listing {active: false}))
        (ok true)))

;; read only functions
(define-read-only (get-credit-balance (account principal))
    (default-to u0 (map-get? credit-balances account)))

(define-read-only (get-offset-total (account principal))
    (default-to u0 (get total-offset (map-get? offset-records account))))

(define-read-only (get-total-credits)
    (var-get total-credits))

(define-read-only (get-listing (listing-id uint))
    (map-get? marketplace-listings listing-id))

(define-read-only (get-user-listings (user principal))
    (default-to (list) (map-get? user-listings user)))

(define-read-only (get-listing-counter)
    (var-get listing-counter))
